#include "bridge/shared_eye_surfaces.h"
#include "core/shared_generated_frame_state.h"

#include <Windows.h>
#include <d3d12.h>
#include <wrl/client.h>

#include <chrono>
#include <cstdint>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>

using Microsoft::WRL::ComPtr;

namespace {

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) {
    throw std::runtime_error(std::string(operation) + " failed");
  }
}

struct HandleCloser {
  void operator()(void* handle) const noexcept {
    if (handle) {
      CloseHandle(handle);
    }
  }
};

using UniqueHandle = std::unique_ptr<void, HandleCloser>;

}  // namespace

int main(int argc, char** argv) {
  try {
    const auto count = argc >= 2 ? std::stoul(argv[1]) : 120UL;
    const auto timeout_seconds = argc >= 3 ? std::stoul(argv[2]) : 600UL;
    if (count == 0 || count > 10000 || timeout_seconds == 0) {
      throw std::invalid_argument("Invalid count or timeout");
    }
    ComPtr<ID3D12Device> device;
    check(D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_12_0,
                            IID_PPV_ARGS(&device)),
          "D3D12CreateDevice");
    darktidevr::core::SharedGeneratedFrameStateReader state_reader;
    darktidevr::core::SharedGeneratedFrameState state{};
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(timeout_seconds);
    while (!state_reader.read(state)) {
      if (std::chrono::steady_clock::now() >= deadline) {
        throw std::runtime_error("Timed out waiting for generated metadata");
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    const darktidevr::bridge::SharedGeneratedSurfaceNames names{
        {L"Local\\DarktideVR-generated-frame-0",
         L"Local\\DarktideVR-generated-frame-1",
         L"Local\\DarktideVR-generated-frame-2"},
        L"Local\\DarktideVR-generated-frame-ready",
        L"Local\\DarktideVR-generated-frame-consumed"};
    auto opened = darktidevr::bridge::open_shared_generated_surfaces(
        device.Get(), names,
        {{state.width, state.height}, static_cast<DXGI_FORMAT>(state.format)});

    D3D12_COMMAND_QUEUE_DESC queue_description{};
    queue_description.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    ComPtr<ID3D12CommandQueue> queue;
    ComPtr<ID3D12CommandAllocator> allocator;
    ComPtr<ID3D12GraphicsCommandList> commands;
    ComPtr<ID3D12Fence> completion;
    check(device->CreateCommandQueue(&queue_description,
                                     IID_PPV_ARGS(&queue)),
          "CreateCommandQueue");
    check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
                                          IID_PPV_ARGS(&allocator)),
          "CreateCommandAllocator");
    check(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                    allocator.Get(), nullptr,
                                    IID_PPV_ARGS(&commands)),
          "CreateCommandList");
    check(commands->Close(), "Close(initial)");
    check(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                              IID_PPV_ARGS(&completion)),
          "CreateFence(completion)");
    D3D12_HEAP_PROPERTIES readback_heap{};
    readback_heap.Type = D3D12_HEAP_TYPE_READBACK;
    D3D12_RESOURCE_DESC readback_description{};
    readback_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    readback_description.Width = 256;
    readback_description.Height = 1;
    readback_description.DepthOrArraySize = 1;
    readback_description.MipLevels = 1;
    readback_description.SampleDesc.Count = 1;
    readback_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    ComPtr<ID3D12Resource> readback;
    check(device->CreateCommittedResource(
              &readback_heap, D3D12_HEAP_FLAG_NONE, &readback_description,
              D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
              IID_PPV_ARGS(&readback)),
          "CreateCommittedResource(readback)");
    UniqueHandle completion_event(CreateEventW(nullptr, FALSE, FALSE, nullptr));
    if (!completion_event) {
      throw std::runtime_error("CreateEvent failed");
    }

    const auto generation = state.transport_generation;
    std::uint64_t nonzero_samples{};
    for (std::uint64_t sequence = 1; sequence <= count; ++sequence) {
      const auto index = darktidevr::core::generated_frame_slot(sequence);
      while (!state_reader.read(state) ||
             state.transport_generation != generation ||
             state.slots[index].sequence != sequence) {
        if (state.transport_generation != 0 &&
            state.transport_generation != generation) {
          throw std::runtime_error("Generated producer restarted");
        }
        if (std::chrono::steady_clock::now() >= deadline) {
          throw std::runtime_error("Timed out waiting for generated frame");
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
      }
      check(allocator->Reset(), "Reset(allocator)");
      check(commands->Reset(allocator.Get(), nullptr), "Reset(commands)");
      auto* texture = opened.textures[index].Get();
      D3D12_RESOURCE_BARRIER barrier{};
      barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      barrier.Transition.pResource = texture;
      barrier.Transition.Subresource =
          D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
      barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
      barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
      commands->ResourceBarrier(1, &barrier);
      D3D12_TEXTURE_COPY_LOCATION destination{};
      destination.pResource = readback.Get();
      destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
      destination.PlacedFootprint.Footprint.Format =
          static_cast<DXGI_FORMAT>(state.format);
      destination.PlacedFootprint.Footprint.Width = 1;
      destination.PlacedFootprint.Footprint.Height = 1;
      destination.PlacedFootprint.Footprint.Depth = 1;
      destination.PlacedFootprint.Footprint.RowPitch = 256;
      D3D12_TEXTURE_COPY_LOCATION source{};
      source.pResource = texture;
      source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
      const D3D12_BOX box{state.width / 2, state.height / 2, 0,
                          state.width / 2 + 1, state.height / 2 + 1, 1};
      commands->CopyTextureRegion(&destination, 0, 0, 0, &source, &box);
      std::swap(barrier.Transition.StateBefore,
                barrier.Transition.StateAfter);
      commands->ResourceBarrier(1, &barrier);
      check(commands->Close(), "Close(commands)");
      check(queue->Wait(opened.ready_fence.Get(), sequence),
            "Wait(generated ready)");
      ID3D12CommandList* lists[]{commands.Get()};
      queue->ExecuteCommandLists(1, lists);
      check(queue->Signal(opened.consumed_fence.Get(), sequence),
            "Signal(generated consumed)");
      check(queue->Signal(completion.Get(), sequence),
            "Signal(completion)");
      check(completion->SetEventOnCompletion(sequence, completion_event.get()),
            "SetEventOnCompletion");
      if (WaitForSingleObject(completion_event.get(), 30000) != WAIT_OBJECT_0) {
        throw std::runtime_error("Timed out reading generated texture");
      }
      void* mapped{};
      const D3D12_RANGE read_range{0, 4};
      check(readback->Map(0, &read_range, &mapped), "Map(readback)");
      const auto* pixel = static_cast<const std::uint8_t*>(mapped);
      nonzero_samples +=
          (pixel[0] | pixel[1] | pixel[2] | pixel[3]) != 0 ? 1U : 0U;
      const D3D12_RANGE written_range{};
      readback->Unmap(0, &written_range);
    }
    std::cout << "generated_frame_consumer=pass consumed=" << count
              << " generation=" << generation
              << " nonzero_samples=" << nonzero_samples << '\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "generated_frame_consumer: " << error.what() << '\n';
    return 1;
  }
}
