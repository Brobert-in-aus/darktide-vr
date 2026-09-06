#include "producer/streamline_continuous_submission.h"
#include "producer/generated_stereo.h"
#include "producer/stereo_ui_readback.h"

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
    const std::array<std::array<D3D12_RESOURCE_DESC, 3>, 2>& descriptions, Log log, bool persistent, bool profile) {
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
  persistent_ = persistent;
  if (!make_commands(device, pause_allocator_, pause_commands_) ||
      FAILED(pause_commands_->Close()) ||
      FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&pause_fence_)))) {
    fail("pause_allocation"); return false;
  }
  D3D12_HEAP_PROPERTIES heap{};
  heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  for (unsigned i = 0; i < count_; ++i) {
    auto& frame = frames_[i];
    if (profile) {
      D3D12_QUERY_HEAP_DESC queries{};
      queries.Type = D3D12_QUERY_HEAP_TYPE_TIMESTAMP;
      queries.Count = 6;
      D3D12_HEAP_PROPERTIES readback_heap{};
      readback_heap.Type = D3D12_HEAP_TYPE_READBACK;
      D3D12_RESOURCE_DESC buffer{};
      buffer.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
      buffer.Width = 6 * sizeof(std::uint64_t);
      buffer.Height = buffer.DepthOrArraySize = buffer.MipLevels = 1;
      buffer.SampleDesc.Count = 1;
      buffer.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
      // Profiling failure must not disable rendering. No timestamps are emitted
      // unless both resources exist; completed input-owner fences govern reuse.
      if (FAILED(device->CreateQueryHeap(&queries, IID_PPV_ARGS(&frame.timing_queries))) ||
          FAILED(device->CreateCommittedResource(&readback_heap, D3D12_HEAP_FLAG_NONE,
              &buffer, D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
              IID_PPV_ARGS(&frame.timing_readback)))) {
        frame.timing_queries.Reset(); frame.timing_readback.Reset();
      }
    }
    for (unsigned eye = 0; eye < 2; ++eye) {
      for (unsigned role = 0; role < 4; ++role) {
        const auto& description = descriptions[eye][role==3 ? 2 : role];
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
        !make_commands(device, frame.cleanup_allocator, frame.cleanup_commands) ||
        FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&frame.stage_done)))) {
      fail("present_allocation"); return false;
    }
  }
  initialized_ = true;
  log_("STEREO_CONTINUOUS\tphase=ready\tframes=%u\teye_width=%u\teye_height=%u\tpublication=0\r\n", count_, width_, height_);
  return true;
}

void StreamlineContinuousSubmission::harvest_timing(Frame& frame) {
  if (!frame.timing_readback || !frame.timing_frequencies[0] ||
      !frame.timing_frequencies[1] || !frame.timing_frequencies[2]) return;
  // Called only after the existing owner completion checks. Never wait for
  // profiling, and do not infer NVIDIA's async compute time from these spans.
  D3D12_RANGE read{0, 6 * sizeof(std::uint64_t)};
  std::uint64_t* ticks{};
  if (FAILED(frame.timing_readback->Map(0, &read, reinterpret_cast<void**>(&ticks)))) return;
  std::array<double, 3> milliseconds{};
  bool valid = true;
  for (unsigned i = 0; i < 3; ++i) {
    valid = valid && ticks[i*2+1] >= ticks[i*2];
    milliseconds[i] = double(ticks[i*2+1] - ticks[i*2]) * 1000.0 / frame.timing_frequencies[i];
  }
  D3D12_RANGE written{0, 0};
  frame.timing_readback->Unmap(0, &written);
  if (!valid) return;
  for (unsigned i = 0; i < 3; ++i) timing_totals_[i] += milliseconds[i];
  if (++timing_samples_ == 120) {
    log_("STEREO_CONTINUOUS\tphase=timing\tsamples=%u\tcapture_left_gpu_ms=%.4f\tcapture_right_gpu_ms=%.4f\tpack_publish_gpu_ms=%.4f\r\n",
        timing_samples_, timing_totals_[0]/timing_samples_, timing_totals_[1]/timing_samples_,
        timing_totals_[2]/timing_samples_);
    timing_totals_ = {}; timing_samples_ = 0;
  }
}

bool StreamlineContinuousSubmission::recycle(Frame& frame) {
  if (!frame.presented) return true;
  const auto stage_done = frame.stage_done->GetCompletedValue();
  if (stage_done == UINT64_MAX || stage_done < frame.reuse_value) return false;
  for (unsigned eye = 0; eye < 2; ++eye) {
    if (!frame.input_fences[eye] ||
        !frame.submission.observe_completion(frame.submission_id, eye,
            reinterpret_cast<std::uintptr_t>(frame.input_fences[eye].Get()),
            frame.input_fences[eye]->GetCompletedValue())) return false;
  }
  if (!frame.submission.retire()) return false;
  harvest_timing(frame);
  for (unsigned eye = 0; eye < 2; ++eye) {
    const auto captured = frame.capture_fences[eye]->GetCompletedValue();
    if (captured == UINT64_MAX || captured < frame.reuse_value ||
        FAILED(frame.capture_allocators[eye]->Reset()) ||
        FAILED(frame.capture_commands[eye]->Reset(frame.capture_allocators[eye].Get(), nullptr))) return false;
    frame.input_fences[eye].Reset();
  }
  if (FAILED(frame.stage_allocator->Reset()) ||
      FAILED(frame.stage_commands->Reset(frame.stage_allocator.Get(), nullptr))) return false;
  ++frame.reuse_value;
  frame.captured = 0; frame.presented = false;
  return true;
}

void StreamlineContinuousSubmission::pause(ID3D12CommandQueue* queue, Execute execute, const char* reason) {
  if (!initialized_ || stopped_ || staged_ || paused_ || !queue || !execute) return;
  if (!persistent_) { fail(reason); return; }
  if (pause_fence_->GetCompletedValue() < pause_value_ ||
      FAILED(pause_allocator_->Reset()) ||
      FAILED(pause_commands_->Reset(pause_allocator_.Get(), nullptr))) {
    fail("pause_reset"); return;
  }
  if (previous_tags_active_ && !frames_[(current_-1)%count_].submission.clear_tags(pause_commands_.Get())) {
    fail("pause_tags"); return;
  }
  if (FAILED(pause_commands_->Close())) { fail("pause_close"); return; }
  ID3D12CommandList* lists[]{pause_commands_.Get()};
  execute(queue, 1, lists);
  if (FAILED(queue->Signal(pause_fence_.Get(), ++pause_value_))) { fail("pause_signal"); return; }
  previous_tags_active_ = false;
  previous_pose_ = previous_present_ = original_ready_ = 0;
  paused_ = true;
  log_("STEREO_CONTINUOUS\tphase=paused\tframe=%u\treason=%s\r\n", current_+1, reason);
}

bool StreamlineContinuousSubmission::resume_capture() {
  if (!paused_) return true;
  const auto completed = pause_fence_->GetCompletedValue();
  if (completed == UINT64_MAX) { fail("pause_device_removed"); return false; }
  if (completed < pause_value_) return false;
  auto& frame = frames_[current_%count_];
  // A rejected pair was copied but never tagged/presented. Its capture lists
  // have independent completion fences; do not reset them while on the GPU.
  if (!frame.presented) {
    for (unsigned eye=0; eye<2; ++eye) if (frame.captured & (1U<<eye)) {
      const auto captured = frame.capture_fences[eye]->GetCompletedValue();
      if (captured == UINT64_MAX) { fail("capture_device_removed"); return false; }
      if (captured < frame.reuse_value) return false;
    }
    for (unsigned eye=0; eye<2; ++eye) if (frame.captured & (1U<<eye)) {
      if (FAILED(frame.capture_allocators[eye]->Reset()) ||
          FAILED(frame.capture_commands[eye]->Reset(frame.capture_allocators[eye].Get(), nullptr))) {
        fail("capture_discard_reset"); return false;
      }
    }
    if (frame.captured) ++frame.reuse_value;
    frame.captured = 0;
  }
  paused_ = false;
  log_("STEREO_CONTINUOUS\tphase=resumed\tframe=%u\r\n", current_+1);
  return true;
}

void StreamlineContinuousSubmission::capture(unsigned eye, std::uint64_t present,
    std::uint64_t pose, const sl::Constants& constants,
    const std::array<StreamlineTagInput, 4>& inputs,
    ID3D12CommandQueue* queue, Execute execute) {
  if (!initialized_ || stopped_ || staged_ || eye > 1 || !queue || !execute) return;
  if (!resume_capture()) return;
  auto& frame = frames_[current_ % count_];
  if (eye == 0 && !recycle(frame)) { fail("ring_completion"); return; }
  if (frame.captured & (1U << eye)) return;
  if (eye == 1 && frame.captured != 1) return;
  if (!pose || (eye == 1 && (frame.source_present != present || frame.pose != pose))) {
    fail("pair_identity"); return;
  }
  for (unsigned role = 0; role < 4; ++role) {
    const auto& input = inputs[role];
    const auto target = frame.textures[eye][role]->GetDesc();
    if (!input.native || input.state == UINT_MAX || input.width != target.Width ||
        input.height != target.Height || (input.format != static_cast<unsigned>(target.Format) &&
        !(role==3 && target.Format==DXGI_FORMAT_R8G8B8A8_TYPELESS && input.format==DXGI_FORMAT_R8G8B8A8_UNORM))) {
      fail("capture_extent"); return;
    }
  }
  auto* commands = frame.capture_commands[eye].Get();
  frame.timing_frequencies[eye] = 0;
  if (frame.timing_queries && SUCCEEDED(queue->GetTimestampFrequency(&frame.timing_frequencies[eye])))
    commands->EndQuery(frame.timing_queries.Get(), D3D12_QUERY_TYPE_TIMESTAMP, eye * 2);
  for (unsigned role = 0; role < 4; ++role) {
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
  if (frame.timing_queries && frame.timing_frequencies[eye]) {
    commands->EndQuery(frame.timing_queries.Get(), D3D12_QUERY_TYPE_TIMESTAMP, eye * 2 + 1);
    commands->ResolveQueryData(frame.timing_queries.Get(), D3D12_QUERY_TYPE_TIMESTAMP,
        eye * 2, 2, frame.timing_readback.Get(), eye * 2 * sizeof(std::uint64_t));
  }
  if (FAILED(commands->Close())) { fail("capture_close"); return; }
  ID3D12CommandList* lists[]{commands};
  execute(queue, 1, lists);
  if (FAILED(queue->Signal(frame.capture_fences[eye].Get(), frame.reuse_value))) { fail("capture_signal"); return; }
  frame.constants[eye] = constants;
  frame.source_present = present;
  frame.pose = pose;
  frame.captured |= 1U << eye;
}

void StreamlineContinuousSubmission::before_present(IDXGISwapChain3* swapchain,
    ID3D12CommandQueue* queue, std::uint64_t present,
    const std::array<core::StreamlinePresentEyeBinding, 2>& bindings,
    StreamlineSubmissionApi api, StreamlineSubmission::Tagging tagging, Execute execute, std::uint64_t generation) {
  if (!initialized_ || stopped_ || staged_ || paused_) return;
  auto& frame = frames_[current_ % count_];
  if (!frame.captured) return;
  if (!swapchain || !queue || !execute || frame.captured != 3 ||
      frame.source_present + 1 != present ||
      !core::streamline_present_binding_matches(present, viewports_, bindings) ||
      bindings[0].pose != frame.pose ||
      (previous_present_ && previous_present_ + 1 != present)) {
    log_("STEREO_CONTINUOUS\tphase=binding_rejection\tcaptured=%u\tsource_present=%llu\tpresent=%llu\tprevious_present=%llu\tpose=%llu\tbound_pose=%llu\tbindings_match=%u\r\n",
        frame.captured,frame.source_present,present,current_ ? frames_[(current_-1)%count_].present : 0,
        frame.pose,bindings[0].pose,core::streamline_present_binding_matches(present,viewports_,bindings) ? 1U : 0U);
    pause(queue, execute, "present_binding_or_gap"); return;
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
  frame.timing_frequencies[2] = 0;
  if (frame.timing_queries && SUCCEEDED(queue->GetTimestampFrequency(&frame.timing_frequencies[2])))
    commands->EndQuery(frame.timing_queries.Get(), D3D12_QUERY_TYPE_TIMESTAMP, 4);
  for (unsigned eye = 0; eye < 2; ++eye) {
    if (FAILED(queue->Wait(frame.capture_fences[eye].Get(), frame.reuse_value))) { fail("capture_wait"); return; }
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
    source.Transition = {frame.textures[eye][3].Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                         D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_COPY_SOURCE};
    commands->ResourceBarrier(1, &source);
    D3D12_TEXTURE_COPY_LOCATION from{}, to{};
    from.pResource = frame.textures[eye][3].Get();
    from.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    to.pResource = backbuffer.Get();
    to.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    commands->CopyTextureRegion(&to, eye * width_, 0, 0, &from, nullptr);
    std::swap(source.Transition.StateBefore, source.Transition.StateAfter);
    commands->ResourceBarrier(1, &source);
  }
  std::swap(destination.Transition.StateBefore, destination.Transition.StateAfter);
  commands->ResourceBarrier(1, &destination);
  original_ready_=persistent_ ? stage_original_stereo(commands,backbuffer.Get(),present,frame.pose,generation) : 0;
  if(persistent_) stage_stereo_ui_readback(commands,frame.textures[0][2].Get(),frame.textures[0][3].Get(),
      frame.textures[1][2].Get(),frame.textures[1][3].Get());
  if (!frame.submission.prepare(current_ + 1, width_, height_, viewports_, frame.constants, inputs) ||
      !frame.submission.stage(api, reinterpret_cast<void*>(bindings[0].token), commands,
          tagging, StreamlineSubmission::ConstantsMode::already_supplied)) {
    fail("tag_stage"); return;
  }
  if (previous_tags_active_ && !frames_[(current_ - 1) % count_].submission.replace_tags_with(frame.submission)) {
    fail("tag_replacement"); return;
  }
  if (frame.timing_queries && frame.timing_frequencies[2]) {
    commands->EndQuery(frame.timing_queries.Get(), D3D12_QUERY_TYPE_TIMESTAMP, 5);
    commands->ResolveQueryData(frame.timing_queries.Get(), D3D12_QUERY_TYPE_TIMESTAMP,
        4, 2, frame.timing_readback.Get(), 4 * sizeof(std::uint64_t));
  }
  if (FAILED(commands->Close())) { fail("stage_close"); return; }
  ID3D12CommandList* lists[]{commands};
  execute(queue, 1, lists);
  if(original_ready_ && !submit_original_stereo(queue,original_ready_)) { fail("original_publish"); return; }
  finish_stereo_ui_readback(queue);
  if (!frame.submission.begin_present()) { fail("begin_present"); return; }
  frame.present = present;
  frame.submission_id = current_ + 1;
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
  auto& frame = frames_[current_ % count_];
  for (unsigned eye = 0; eye < 2; ++eye) {
    const auto viewport = sl::make_viewport(viewports_[eye]);
    auto state = sl::make_dlssg_state();
    const auto result = get_state(&viewport, &state, nullptr);
    log_("STEREO_CONTINUOUS\tphase=state\tframe=%u\teye=%u\tresult=%u\tstatus=%u\tversion=%u\r\n",
         current_ + 1, eye, result, state.status, state.base.struct_version);
    if (result != 0 || state.status != 0 || state.base.struct_version < 3 || !state.inputs_processing_completion_fence ||
        FAILED(static_cast<IUnknown*>(state.inputs_processing_completion_fence)->QueryInterface(
            IID_PPV_ARGS(&frame.input_fences[eye])))) {
      fail("input_ticket"); break;
    }
    if (!frame.submission.record_ticket(current_ + 1, eye,
        reinterpret_cast<std::uintptr_t>(frame.input_fences[eye].Get()),
        state.last_present_inputs_processing_completion_fence_value)) {
      fail("rejected_input_ticket"); break;
    }
    log_("STEREO_CONTINUOUS\tphase=ticket\tframe=%u\teye=%u\tframes_presented=%u\tvalue=%llu\r\n",
        current_ + 1, eye, state.num_frames_actually_presented,
        state.last_present_inputs_processing_completion_fence_value);
  }
  frame.presented = true;
  if (FAILED(queue->Signal(frame.stage_done.Get(), frame.reuse_value))) fail("stage_fence");
  previous_pose_ = frame.pose;
  previous_present_ = frame.present;
  previous_tags_active_ = true;
  staged_ = false;
  if (stopped_ || (!persistent_ && current_ + 1 == count_)) {
    clear_bindings(queue, execute);
    stopped_ = true;
  } else ++current_;
}

void StreamlineContinuousSubmission::clear_bindings(ID3D12CommandQueue* queue, Execute execute) {
  if (cleanup_submitted_ || !initialized_) return;
  cleanup_submitted_ = true;
  auto& frame = frames_[current_ % count_];
  bool cleared = true;
  for (unsigned i = 0; i < count_; ++i) {
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
