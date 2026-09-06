#include "producer/streamline_continuous_submission.h"

namespace darktidevr::producer {
namespace sl = streamline_2_7_30;

void StreamlineContinuousSubmission::fail(const char* reason) {
  if (!stopped_ && log_) log_("STEREO_CONTINUOUS\tphase=failed\tframe=%u\treason=%s\towners_retained=1\r\n", current_ + 1, reason);
  stopped_ = true;
}

bool StreamlineContinuousSubmission::make_commands(ID3D12Device* device,
    ComPtr<ID3D12CommandAllocator>& allocator, ComPtr<ID3D12GraphicsCommandList>& commands) {
  return SUCCEEDED(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
                                                  IID_PPV_ARGS(&allocator))) &&
      SUCCEEDED(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                          allocator.Get(), nullptr, IID_PPV_ARGS(&commands)));
}

bool StreamlineContinuousSubmission::initialize(ID3D12Device* device, unsigned frames,
    const std::array<std::uint32_t, 2>& viewports,
    const std::array<std::array<D3D12_RESOURCE_DESC, 3>, 2>& descriptions, Log log) {
  if (initialized_ || stopped_) return false;
  log_ = log;
  if (!device || frames < 2 || frames > frames_.size() || !viewports[0] ||
      !viewports[1] || viewports[0] == viewports[1]) { fail("configuration"); return false; }
  width_ = static_cast<std::uint32_t>(descriptions[0][2].Width);
  height_ = descriptions[0][2].Height;
  if (!width_ || width_ > UINT_MAX / 2 || !height_ ||
      descriptions[0][2].Width != width_ || descriptions[1][2].Width != width_ ||
      descriptions[1][2].Height != height_) { fail("eye_extent"); return false; }
  viewports_ = viewports;
  count_ = frames;
  D3D12_HEAP_PROPERTIES heap{};
  heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  for (unsigned i = 0; i < count_; ++i) {
    auto& frame = frames_[i];
    for (unsigned eye = 0; eye < 2; ++eye) {
      for (unsigned role = 0; role < 3; ++role) {
        const auto& description = descriptions[eye][role];
        if (description.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D ||
            description.MipLevels != 1 || description.DepthOrArraySize != 1 ||
            description.SampleDesc.Count != 1 ||
            FAILED(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE,
                &description, D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
                IID_PPV_ARGS(&frame.textures[eye][role])))) {
          fail("input_allocation"); return false;
        }
      }
      if (!make_commands(device, frame.capture_allocators[eye], frame.capture_commands[eye]) ||
          FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                                     IID_PPV_ARGS(&frame.capture_fences[eye])))) {
        fail("capture_allocation"); return false;
      }
    }
    if (!make_commands(device, frame.stage_allocator, frame.stage_commands) ||
        !make_commands(device, frame.cleanup_allocator, frame.cleanup_commands)) {
      fail("present_allocation"); return false;
    }
  }
  initialized_ = true;
  log_("STEREO_CONTINUOUS\tphase=ready\tframes=%u\teye_width=%u\teye_height=%u\tpublication=0\r\n", count_, width_, height_);
  return true;
}

void StreamlineContinuousSubmission::capture(unsigned eye, std::uint64_t present,
    std::uint64_t pose, const sl::Constants& constants,
    const std::array<StreamlineTagInput, 3>& inputs,
    ID3D12CommandQueue* queue, Execute execute) {
  if (!initialized_ || stopped_ || staged_ || eye > 1 || !queue || !execute) return;
  auto& frame = frames_[current_];
  if (frame.captured & (1U << eye)) return;
  if (eye == 1 && frame.captured != 1) return;
  if (!pose || (eye == 1 && (frame.source_present != present || frame.pose != pose))) {
    fail("pair_identity"); return;
  }
  for (unsigned role = 0; role < 3; ++role) {
    const auto& input = inputs[role];
    const auto target = frame.textures[eye][role]->GetDesc();
    if (!input.native || input.state == UINT_MAX || input.width != target.Width ||
        input.height != target.Height || input.format != static_cast<unsigned>(target.Format)) {
      fail("capture_extent"); return;
    }
  }
  auto* commands = frame.capture_commands[eye].Get();
  for (unsigned role = 0; role < 3; ++role) {
    const auto& input = inputs[role];
    auto* source = static_cast<ID3D12Resource*>(input.native);
    frame.sources[eye][role] = source;
    D3D12_RESOURCE_BARRIER barrier{};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition = {source, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        static_cast<D3D12_RESOURCE_STATES>(input.state), D3D12_RESOURCE_STATE_COPY_SOURCE};
    if (barrier.Transition.StateBefore != barrier.Transition.StateAfter) commands->ResourceBarrier(1, &barrier);
    commands->CopyResource(frame.textures[eye][role].Get(), source);
    std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
    if (barrier.Transition.StateBefore != barrier.Transition.StateAfter) commands->ResourceBarrier(1, &barrier);
  }
  if (FAILED(commands->Close())) { fail("capture_close"); return; }
  ID3D12CommandList* lists[]{commands};
  execute(queue, 1, lists);
  if (FAILED(queue->Signal(frame.capture_fences[eye].Get(), 1))) { fail("capture_signal"); return; }
  frame.constants[eye] = constants;
  frame.source_present = present;
  frame.pose = pose;
  frame.captured |= 1U << eye;
}

void StreamlineContinuousSubmission::before_present(IDXGISwapChain3* swapchain,
    ID3D12CommandQueue* queue, std::uint64_t present,
    const std::array<core::StreamlinePresentEyeBinding, 2>& bindings,
    StreamlineSubmissionApi api, StreamlineSubmission::Tagging tagging, Execute execute) {
  if (!initialized_ || stopped_ || staged_) return;
  auto& frame = frames_[current_];
  if (!frame.captured) return;
  if (!swapchain || !queue || !execute || frame.captured != 3 ||
      frame.source_present + 1 != present ||
      !core::streamline_present_binding_matches(present, viewports_, bindings) ||
      bindings[0].pose != frame.pose ||
      (current_ && frames_[current_ - 1].present + 1 != present)) {
    fail("present_binding_or_gap"); return;
  }
  ComPtr<ID3D12Resource> backbuffer;
  if (FAILED(swapchain->GetBuffer(swapchain->GetCurrentBackBufferIndex(), IID_PPV_ARGS(&backbuffer)))) {
    fail("backbuffer"); return;
  }
  const auto description = backbuffer->GetDesc();
  const auto color_copy_compatible = [&](DXGI_FORMAT format) {
    // Darktide's HUDless backing texture is typeless RGBA8 with an UNORM
    // view. D3D12 permits a bitwise copy within that format family.
    return description.Format == DXGI_FORMAT_R8G8B8A8_UNORM &&
        (format == DXGI_FORMAT_R8G8B8A8_TYPELESS || format == DXGI_FORMAT_R8G8B8A8_UNORM);
  };
  if (description.Width != width_ * 2ULL || description.Height != height_ ||
      !color_copy_compatible(frame.textures[0][2]->GetDesc().Format) ||
      !color_copy_compatible(frame.textures[1][2]->GetDesc().Format)) {
    fail("backbuffer_extent"); return;
  }
  StreamlineStereoTags::Inputs inputs{};
  auto* commands = frame.stage_commands.Get();
  for (unsigned eye = 0; eye < 2; ++eye) {
    if (FAILED(queue->Wait(frame.capture_fences[eye].Get(), 1))) { fail("capture_wait"); return; }
    for (unsigned role = 0; role < 3; ++role) {
      const auto source = frame.textures[eye][role]->GetDesc();
      inputs[eye][role] = {frame.textures[eye][role].Get(), static_cast<unsigned>(source.Width),
          source.Height, D3D12_RESOURCE_STATE_COPY_DEST, static_cast<unsigned>(source.Format)};
    }
  }
  D3D12_RESOURCE_BARRIER destination{};
  destination.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  destination.Transition = {backbuffer.Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                            D3D12_RESOURCE_STATE_PRESENT, D3D12_RESOURCE_STATE_COPY_DEST};
  commands->ResourceBarrier(1, &destination);
  for (unsigned eye = 0; eye < 2; ++eye) {
    D3D12_RESOURCE_BARRIER source{};
    source.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    source.Transition = {frame.textures[eye][2].Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                         D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_COPY_SOURCE};
    commands->ResourceBarrier(1, &source);
    D3D12_TEXTURE_COPY_LOCATION from{}, to{};
    from.pResource = frame.textures[eye][2].Get();
    from.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    to.pResource = backbuffer.Get();
    to.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    commands->CopyTextureRegion(&to, eye * width_, 0, 0, &from, nullptr);
    std::swap(source.Transition.StateBefore, source.Transition.StateAfter);
    commands->ResourceBarrier(1, &source);
  }
  std::swap(destination.Transition.StateBefore, destination.Transition.StateAfter);
  commands->ResourceBarrier(1, &destination);
  if (!frame.submission.prepare(current_ + 1, width_, height_, viewports_, frame.constants, inputs) ||
      !frame.submission.stage(api, reinterpret_cast<void*>(bindings[0].token), commands,
          tagging, StreamlineSubmission::ConstantsMode::already_supplied)) {
    fail("tag_stage"); return;
  }
  if (current_ && !frames_[current_ - 1].submission.replace_tags_with(frame.submission)) {
    fail("tag_replacement"); return;
  }
  if (FAILED(commands->Close())) { fail("stage_close"); return; }
  ID3D12CommandList* lists[]{commands};
  execute(queue, 1, lists);
  if (!frame.submission.begin_present()) { fail("begin_present"); return; }
  frame.present = present;
  staged_ = true;
  log_("STEREO_CONTINUOUS\tphase=present\tframe=%u\tpresent_frame=%llu\tpose=%llu\tpublication=0\r\n",
       current_ + 1, present, frame.pose);
}

void StreamlineContinuousSubmission::after_present(ID3D12CommandQueue* queue,
    GetState get_state, Execute execute) {
  if (!queue || !execute) return;
  if (stopped_ && !staged_) { clear_bindings(queue, execute); return; }
  if (!staged_) return;
  if (!get_state) { fail("missing_state_api"); clear_bindings(queue, execute); return; }
  auto& frame = frames_[current_];
  for (unsigned eye = 0; eye < 2; ++eye) {
    const auto viewport = sl::make_viewport(viewports_[eye]);
    auto state = sl::make_dlssg_state();
    const auto result = get_state(&viewport, &state, nullptr);
    if (result != 0 || state.base.struct_version < 3 || !state.inputs_processing_completion_fence ||
        FAILED(static_cast<IUnknown*>(state.inputs_processing_completion_fence)->QueryInterface(
            IID_PPV_ARGS(&frame.input_fences[eye])))) {
      fail("input_ticket"); break;
    }
    frame.submission.record_ticket(current_ + 1, eye,
        reinterpret_cast<std::uintptr_t>(frame.input_fences[eye].Get()),
        state.last_present_inputs_processing_completion_fence_value);
    log_("STEREO_CONTINUOUS\tphase=ticket\tframe=%u\teye=%u\tframes_presented=%u\tvalue=%llu\r\n",
        current_ + 1, eye, state.num_frames_actually_presented,
        state.last_present_inputs_processing_completion_fence_value);
  }
  frame.presented = true;
  staged_ = false;
  if (stopped_ || current_ + 1 == count_) {
    clear_bindings(queue, execute);
    stopped_ = true;
  } else ++current_;
}

void StreamlineContinuousSubmission::clear_bindings(ID3D12CommandQueue* queue, Execute execute) {
  if (cleanup_submitted_ || !initialized_) return;
  cleanup_submitted_ = true;
  auto& frame = frames_[current_];
  bool cleared = true;
  for (unsigned i = 0; i <= current_; ++i) {
    auto& submission = frames_[i].submission;
    if (submission.phase() != StreamlineSubmission::Phase::idle)
      cleared = submission.clear_tags(frame.cleanup_commands.Get()) && cleared;
  }
  const auto closed = SUCCEEDED(frame.cleanup_commands->Close());
  if (closed) {
    ID3D12CommandList* lists[]{frame.cleanup_commands.Get()};
    execute(queue, 1, lists);
  }
  if (!closed || !cleared) fail("cleanup");
  log_("STEREO_CONTINUOUS\tphase=stopped\tframes=%u\ttags_cleared=%u\towners_retained=1\tpublication=0\r\n",
      current_ + 1, cleared && closed ? 1U : 0U);
}
} // namespace darktidevr::producer
