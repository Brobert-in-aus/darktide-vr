#include "../isolated_transports.h"
#include "producer/native_original_ring.h"
#include "bridge/shared_eye_surfaces.h"
#include "core/shared_generated_frame_state.h"
#include "core/shared_object_name.h"
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <array>
#include <iostream>
#include <stdexcept>
#include <string_view>

using Microsoft::WRL::ComPtr;
using Ring = darktidevr::producer::NativeOriginalRing;
void check(HRESULT value) { if (FAILED(value)) throw std::runtime_error("D3D12 operation failed"); }
void expect(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
void STDMETHODCALLTYPE execute(ID3D12CommandQueue* queue, UINT count, ID3D12CommandList* const* lists) {
  queue->ExecuteCommandLists(count, lists);
}
int main(int argc, char** argv) {
  try {
    const bool typeless = argc == 2 && std::string_view(argv[1]) == "typeless";
    darktidevr::tests::isolate_transports();
    ComPtr<IDXGIFactory4> factory;
    check(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
    ComPtr<IDXGIAdapter> warp;
    check(factory->EnumWarpAdapter(IID_PPV_ARGS(&warp)));
    ComPtr<ID3D12Device> device;
    check(D3D12CreateDevice(warp.Get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&device)));
    D3D12_COMMAND_QUEUE_DESC queue_description{};
    ComPtr<ID3D12CommandQueue> queue, other_queue;
    check(device->CreateCommandQueue(&queue_description, IID_PPV_ARGS(&queue)));
    check(device->CreateCommandQueue(&queue_description, IID_PPV_ARGS(&other_queue)));
    ComPtr<ID3D12Fence> finished, gate;
    check(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&finished)));
    check(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&gate)));
    const auto event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    expect(event != nullptr, "CreateEvent failed");
    std::uint64_t fence_value{};
    const auto flush = [&] {
      check(queue->Signal(finished.Get(), ++fence_value));
      check(finished->SetEventOnCompletion(fence_value, event));
      expect(WaitForSingleObject(event, 10000) == WAIT_OBJECT_0, "GPU completion timeout");
    };
    D3D12_HEAP_PROPERTIES heap{};
    heap.Type = D3D12_HEAP_TYPE_DEFAULT;
    D3D12_RESOURCE_DESC description{};
    description.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    description.Width = 4; description.Height = 4;
    description.DepthOrArraySize = 1; description.MipLevels = 1;
    description.Format = typeless ? DXGI_FORMAT_R8G8B8A8_TYPELESS : DXGI_FORMAT_R8G8B8A8_UNORM;
    description.SampleDesc.Count = 1;
    description.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    std::array<ComPtr<ID3D12Resource>, 2> eyes;
    D3D12_DESCRIPTOR_HEAP_DESC rtv_description{};
    rtv_description.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    rtv_description.NumDescriptors = 2;
    ComPtr<ID3D12DescriptorHeap> rtvs;
    check(device->CreateDescriptorHeap(&rtv_description, IID_PPV_ARGS(&rtvs)));
    const auto increment = device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    for (unsigned eye = 0; eye < 2; ++eye) {
      check(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &description,
          D3D12_RESOURCE_STATE_COMMON, nullptr, IID_PPV_ARGS(&eyes[eye])));
      const D3D12_CPU_DESCRIPTOR_HANDLE handle{rtvs->GetCPUDescriptorHandleForHeapStart().ptr + SIZE_T(eye) * increment};
      D3D12_RENDER_TARGET_VIEW_DESC view{};
      view.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
      view.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
      device->CreateRenderTargetView(eyes[eye].Get(), &view, handle);
    }
    ComPtr<ID3D12CommandAllocator> allocator;
    ComPtr<ID3D12GraphicsCommandList> commands;
    check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocator)));
    check(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator.Get(), nullptr, IID_PPV_ARGS(&commands)));
    check(commands->Close());
    Ring ring;
    const auto capture = [&](unsigned eye, std::uint64_t pose, std::uint64_t generation = 9) {
      return ring.capture(queue.Get(), execute, eyes[eye].Get(), D3D12_RESOURCE_STATE_COMMON,
                          eye, {pose, pose, generation});
    };
    expect(capture(1, 101) == Ring::Result::invalid, "Right eye published without left");
    expect(capture(0, 0) == Ring::Result::invalid, "Zero pose accepted");
    for (std::uint64_t frame = 1; frame <= 3; ++frame) {
      check(allocator->Reset()); check(commands->Reset(allocator.Get(), nullptr));
      for (unsigned eye = 0; eye < 2; ++eye) {
        D3D12_RESOURCE_BARRIER barrier{};
        barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        barrier.Transition = {eyes[eye].Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
            D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_RENDER_TARGET};
        commands->ResourceBarrier(1, &barrier);
        const float colour[]{eye == 0 ? float(frame) / 255.0F : 0.0F,
                             eye == 1 ? float(frame + 10) / 255.0F : 0.0F, 1, 1};
        const D3D12_CPU_DESCRIPTOR_HANDLE handle{rtvs->GetCPUDescriptorHandleForHeapStart().ptr + SIZE_T(eye) * increment};
        commands->ClearRenderTargetView(handle, colour, 0, nullptr);
        std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
        commands->ResourceBarrier(1, &barrier);
      }
      check(commands->Close());
      ID3D12CommandList* lists[]{commands.Get()}; execute(queue.Get(), 1, lists);
      expect(capture(0, 100 + frame) == Ring::Result::staged, "Left eye did not stage");
      expect(capture(1, 100 + frame) == Ring::Result::published, "Pair did not publish");
      flush();
    }
    using namespace darktidevr;
    core::SharedGeneratedFrameStateReader reader{L"Local\\DarktideVR-original-frame-state-v1"};
    core::SharedGeneratedFrameState metadata;
    expect(reader.read(metadata) && metadata.latest_sequence == 3, "Missing complete ring metadata");
    expect(metadata.width == 8 && metadata.height == 4 && metadata.slots[1].current_pose == 102 &&
           metadata.slots[1].gameplay_generation == 9, "Incorrect dimensions or pose tag");
    bridge::SharedGeneratedSurfaceNames names{{L"Local\\DarktideVR-original-stereo-0",
        L"Local\\DarktideVR-original-stereo-1", L"Local\\DarktideVR-original-stereo-2"},
        L"Local\\DarktideVR-original-stereo-ready", L"Local\\DarktideVR-original-stereo-consumed"};
    for (auto& name : names.textures) name = core::shared_object_name(name.c_str());
    names.ready_fence = core::shared_object_name(names.ready_fence.c_str());
    names.consumed_fence = core::shared_object_name(names.consumed_fence.c_str());
    auto opened = bridge::open_shared_generated_surfaces(device.Get(), names, {{8, 4}, DXGI_FORMAT_R8G8B8A8_UNORM});
    expect(capture(0, 104) == Ring::Result::busy, "Overwrote unconsumed slot");
    check(opened.consumed_fence->Signal(1));
    expect(capture(0, 104) == Ring::Result::staged, "Acknowledged slot not reusable");
    expect(capture(1, 105) == Ring::Result::invalid, "Mismatched poses published");
    flush();
    expect(reader.read(metadata) && metadata.latest_sequence == 3, "Partial pair became visible");
    expect(capture(0, 104) == Ring::Result::staged, "Partial pair did not recover");
    expect(capture(1, 104) == Ring::Result::published, "Recovered pair did not publish");
    flush();
    expect(reader.read(metadata) && metadata.latest_sequence == 4, "Sequence did not advance once");
    expect(ring.capture(other_queue.Get(), execute, eyes[0].Get(), D3D12_RESOURCE_STATE_COMMON,
                        0, {105, 105, 9}) == Ring::Result::invalid, "Queue change accepted");

    // Read the untouched second slot after slot zero has been recycled.
    auto packed_description = opened.textures[1]->GetDesc();
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{};
    UINT rows{}; UINT64 row_bytes{}, bytes{};
    device->GetCopyableFootprints(&packed_description, 0, 1, 0, &footprint, &rows, &row_bytes, &bytes);
    D3D12_RESOURCE_DESC buffer{};
    buffer.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER; buffer.Width = bytes;
    buffer.Height = 1; buffer.DepthOrArraySize = 1; buffer.MipLevels = 1;
    buffer.SampleDesc.Count = 1; buffer.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    D3D12_HEAP_PROPERTIES readback_heap{}; readback_heap.Type = D3D12_HEAP_TYPE_READBACK;
    ComPtr<ID3D12Resource> readback;
    check(device->CreateCommittedResource(&readback_heap, D3D12_HEAP_FLAG_NONE, &buffer,
        D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&readback)));
    check(allocator->Reset()); check(commands->Reset(allocator.Get(), nullptr));
    D3D12_RESOURCE_BARRIER barrier{}; barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition = {opened.textures[1].Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_COPY_SOURCE};
    commands->ResourceBarrier(1, &barrier);
    D3D12_TEXTURE_COPY_LOCATION from{}, to{};
    from.pResource = opened.textures[1].Get(); from.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    to.pResource = readback.Get(); to.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; to.PlacedFootprint = footprint;
    commands->CopyTextureRegion(&to, 0, 0, 0, &from, nullptr);
    std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
    commands->ResourceBarrier(1, &barrier); check(commands->Close());
    ID3D12CommandList* lists[]{commands.Get()}; execute(queue.Get(), 1, lists); flush();
    void* mapped{}; D3D12_RANGE range{0, SIZE_T(bytes)};
    check(readback->Map(0, &range, &mapped));
    const auto* pixels = static_cast<const unsigned char*>(mapped);
    bool correct = true;
    for (unsigned y = 0; y < 4; ++y) for (unsigned x = 0; x < 8; ++x) {
      const auto* pixel = pixels + footprint.Offset + y * footprint.Footprint.RowPitch + x * 4;
      correct = correct && pixel[0] == (x < 4 ? 2 : 0) && pixel[1] == (x < 4 ? 0 : 12) && pixel[2] == 255 && pixel[3] == 255;
    }
    const D3D12_RANGE no_writes{0, 0}; readback->Unmap(0, &no_writes);
    expect(correct, "Ring pixels lost eye identity or unconsumed content");

    // Hold the GPU: a second left eye must not reset an in-flight allocator.
    check(opened.consumed_fence->Signal(2));
    check(queue->Wait(gate.Get(), 1));
    const auto first = capture(0, 105);
    const auto blocked = capture(0, 106);
    check(gate->Signal(1)); flush();
    expect(first == Ring::Result::staged && blocked == Ring::Result::busy, "In-flight allocator was reused");
    expect(capture(0, 106) == Ring::Result::staged, "GPU-completed partial did not recover");
    expect(capture(1, 106, 10) == Ring::Result::invalid, "Mixed generations published");
    flush();
    expect(reader.read(metadata) && metadata.latest_sequence == 4, "Invalid generation advanced sequence");
    check(opened.consumed_fence->Signal(UINT64_MAX));
    expect(capture(0, 107) == Ring::Result::failed, "Poisoned acknowledgement accepted");
    flush(); CloseHandle(event);
    std::cout << "native_original_ring=pass pixels=both_eyes slots=3 partial_pairs=rejected gpu_reuse=guarded\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
