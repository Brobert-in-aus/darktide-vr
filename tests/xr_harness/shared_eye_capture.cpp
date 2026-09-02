#include "bridge/shared_eye_surfaces.h"

#include <Windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>

#include <array>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) {
    throw std::runtime_error(std::string(operation) + " failed (HRESULT " +
                             std::to_string(
                                 static_cast<std::uint32_t>(result)) +
                             ")");
  }
}

struct AttachedEyes {
  ComPtr<ID3D12Device> device;
  darktidevr::bridge::OpenedEyeSurfaces surfaces;
  std::wstring adapter_name;
};

std::optional<AttachedEyes> try_attach(
    IDXGIFactory6* factory,
    darktidevr::bridge::SharedEyeSurfaceDescription expected) {
  for (UINT index = 0;; ++index) {
    ComPtr<IDXGIAdapter1> adapter;
    const auto result = factory->EnumAdapters1(index, &adapter);
    if (result == DXGI_ERROR_NOT_FOUND) {
      break;
    }
    check(result, "IDXGIFactory6::EnumAdapters1");
    DXGI_ADAPTER_DESC1 description{};
    check(adapter->GetDesc1(&description), "IDXGIAdapter1::GetDesc1");
    if ((description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) != 0) {
      continue;
    }
    ComPtr<ID3D12Device> device;
    if (FAILED(D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_11_0,
                                 IID_PPV_ARGS(&device)))) {
      continue;
    }
    try {
      auto surfaces = darktidevr::bridge::open_shared_eye_surfaces(
          device.Get(),
          {{{L"Local\\DarktideVR-eye-left",
             L"Local\\DarktideVR-eye-right"}},
           L"Local\\DarktideVR-eye-ready",
           L"Local\\DarktideVR-eye-consumed"},
          expected);
      return AttachedEyes{std::move(device), std::move(surfaces),
                          description.Description};
    } catch (const std::exception&) {
      // Named resources either do not exist yet or belong to another adapter.
    }
  }
  return std::nullopt;
}

void write_ppm(const std::filesystem::path& path,
               ID3D12Resource* readback,
               const D3D12_PLACED_SUBRESOURCE_FOOTPRINT& footprint,
               std::uint32_t width, std::uint32_t height) {
  void* mapped{};
  const auto byte_count =
      static_cast<SIZE_T>(footprint.Footprint.RowPitch) * height;
  const D3D12_RANGE read_range{0, byte_count};
  check(readback->Map(0, &read_range, &mapped),
        "ID3D12Resource::Map(shared eye readback)");
  std::ofstream output(path, std::ios::binary);
  if (!output) {
    readback->Unmap(0, nullptr);
    throw std::runtime_error("Could not create shared-eye PPM");
  }
  output << "P6\n" << width << ' ' << height << "\n255\n";
  std::vector<std::uint8_t> rgb(static_cast<std::size_t>(width) * 3);
  const auto* pixels = static_cast<const std::uint8_t*>(mapped);
  for (std::uint32_t y = 0; y < height; ++y) {
    const auto* source_row =
        pixels + static_cast<std::size_t>(y) * footprint.Footprint.RowPitch;
    for (std::uint32_t x = 0; x < width; ++x) {
      const auto* source = source_row + static_cast<std::size_t>(x) * 4;
      auto* destination = rgb.data() + static_cast<std::size_t>(x) * 3;
      destination[0] = source[0];
      destination[1] = source[1];
      destination[2] = source[2];
    }
    output.write(reinterpret_cast<const char*>(rgb.data()),
                 static_cast<std::streamsize>(rgb.size()));
  }
  readback->Unmap(0, nullptr);
  if (!output) {
    throw std::runtime_error("Could not finish shared-eye PPM");
  }
}

std::uint32_t parse_positive(const wchar_t* value, const char* label,
                             std::uint32_t maximum) {
  const auto parsed = std::stoul(value);
  if (parsed == 0 || parsed > maximum) {
    throw std::invalid_argument(std::string(label) + " is out of range");
  }
  return static_cast<std::uint32_t>(parsed);
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  try {
    if (argc == 2 && std::wstring(argv[1]) == L"--help") {
      std::wcout << L"Usage: darktidevr-shared-eye-capture OUTPUT_DIRECTORY "
                    L"[PAIR_COUNT] [WIDTH] [HEIGHT]\n";
      return 0;
    }
    if (argc < 2 || argc > 5) {
      std::wcerr << L"Usage: darktidevr-shared-eye-capture OUTPUT_DIRECTORY "
                    L"[PAIR_COUNT] [WIDTH] [HEIGHT]\n";
      return 2;
    }
    const std::filesystem::path output_directory(argv[1]);
    const auto pair_count =
        argc >= 3 ? parse_positive(argv[2], "PAIR_COUNT", 120) : 1U;
    const auto width =
        argc >= 4 ? parse_positive(argv[3], "WIDTH", 7680) : 2112U;
    const auto height =
        argc >= 5 ? parse_positive(argv[4], "HEIGHT", 7680) : 2304U;
    std::filesystem::create_directories(output_directory);

    ComPtr<IDXGIFactory6> factory;
    check(CreateDXGIFactory2(0, IID_PPV_ARGS(&factory)),
          "CreateDXGIFactory2");
    const darktidevr::bridge::SharedEyeSurfaceDescription expected{
        {width, height}, DXGI_FORMAT_R8G8B8A8_UNORM};
    std::optional<AttachedEyes> attached;
    const auto attach_deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(90);
    while (!attached && std::chrono::steady_clock::now() < attach_deadline) {
      attached = try_attach(factory.Get(), expected);
      if (!attached) {
        std::this_thread::sleep_for(std::chrono::milliseconds(250));
      }
    }
    if (!attached) {
      throw std::runtime_error(
          "Timed out waiting for producer-owned shared eye surfaces");
    }
    auto& device = attached->device;
    auto& surfaces = attached->surfaces;
    const auto initial_ready = surfaces.ready_fence->GetCompletedValue();
    const auto initial_consumed = surfaces.consumed_fence->GetCompletedValue();
    if (!darktidevr::bridge::shared_fence_values_healthy(
            initial_ready, initial_consumed)) {
      throw std::runtime_error("Shared eye fence generation is poisoned");
    }
    if (initial_ready != 0 && initial_consumed < initial_ready) {
      check(surfaces.consumed_fence->Signal(initial_ready),
            "ID3D12Fence::Signal(initial pair consumed)");
    }

    D3D12_COMMAND_QUEUE_DESC queue_description{};
    queue_description.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    ComPtr<ID3D12CommandQueue> queue;
    check(device->CreateCommandQueue(&queue_description,
                                     IID_PPV_ARGS(&queue)),
          "ID3D12Device::CreateCommandQueue");
    ComPtr<ID3D12CommandAllocator> allocator;
    check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
                                         IID_PPV_ARGS(&allocator)),
          "ID3D12Device::CreateCommandAllocator");
    ComPtr<ID3D12GraphicsCommandList> commands;
    check(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                    allocator.Get(), nullptr,
                                    IID_PPV_ARGS(&commands)),
          "ID3D12Device::CreateCommandList");
    check(commands->Close(), "ID3D12GraphicsCommandList::Close(init)");
    ComPtr<ID3D12Fence> local_fence;
    check(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                              IID_PPV_ARGS(&local_fence)),
          "ID3D12Device::CreateFence(local)");
    const auto fence_event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    const auto ready_event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!fence_event || !ready_event) {
      throw std::runtime_error("CreateEventW failed");
    }

    const auto eye_description = surfaces.eyes[0]->GetDesc();
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{};
    UINT rows{};
    UINT64 row_bytes{};
    UINT64 total_bytes{};
    device->GetCopyableFootprints(&eye_description, 0, 1, 0, &footprint,
                                  &rows, &row_bytes, &total_bytes);
    D3D12_HEAP_PROPERTIES readback_heap{};
    readback_heap.Type = D3D12_HEAP_TYPE_READBACK;
    D3D12_RESOURCE_DESC readback_description{};
    readback_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    readback_description.Width = total_bytes;
    readback_description.Height = 1;
    readback_description.DepthOrArraySize = 1;
    readback_description.MipLevels = 1;
    readback_description.SampleDesc.Count = 1;
    readback_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    std::array<ComPtr<ID3D12Resource>, 2> readbacks;
    for (auto& readback : readbacks) {
      check(device->CreateCommittedResource(
                &readback_heap, D3D12_HEAP_FLAG_NONE,
                &readback_description, D3D12_RESOURCE_STATE_COPY_DEST,
                nullptr, IID_PPV_ARGS(&readback)),
            "ID3D12Device::CreateCommittedResource(readback)");
    }

    auto last_ready = initial_ready;
    UINT64 local_fence_value{};
    for (std::uint32_t pair = 0; pair < pair_count; ++pair) {
      const auto target_ready = last_ready + 1;
      check(surfaces.ready_fence->SetEventOnCompletion(target_ready,
                                                       ready_event),
            "ID3D12Fence::SetEventOnCompletion(shared ready)");
      if (WaitForSingleObject(ready_event, 30000) != WAIT_OBJECT_0) {
        throw std::runtime_error("Timed out waiting for a fresh eye pair");
      }
      const auto ready = surfaces.ready_fence->GetCompletedValue();
      if (!darktidevr::bridge::shared_fence_values_healthy(
              ready, surfaces.consumed_fence->GetCompletedValue()) ||
          ready < target_ready) {
        throw std::runtime_error("Shared ready fence became invalid");
      }
      check(allocator->Reset(), "ID3D12CommandAllocator::Reset");
      check(commands->Reset(allocator.Get(), nullptr),
            "ID3D12GraphicsCommandList::Reset");
      for (std::size_t eye = 0; eye < surfaces.eyes.size(); ++eye) {
        D3D12_RESOURCE_BARRIER barrier{};
        barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        barrier.Transition.pResource = surfaces.eyes[eye].Get();
        barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
        barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
        barrier.Transition.Subresource =
            D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        commands->ResourceBarrier(1, &barrier);
        D3D12_TEXTURE_COPY_LOCATION destination{};
        destination.pResource = readbacks[eye].Get();
        destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
        destination.PlacedFootprint = footprint;
        D3D12_TEXTURE_COPY_LOCATION source{};
        source.pResource = surfaces.eyes[eye].Get();
        source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        commands->CopyTextureRegion(&destination, 0, 0, 0, &source, nullptr);
        std::swap(barrier.Transition.StateBefore,
                  barrier.Transition.StateAfter);
        commands->ResourceBarrier(1, &barrier);
      }
      check(commands->Close(), "ID3D12GraphicsCommandList::Close(capture)");
      check(queue->Wait(surfaces.ready_fence.Get(), ready),
            "ID3D12CommandQueue::Wait(shared ready)");
      ID3D12CommandList* lists[]{commands.Get()};
      queue->ExecuteCommandLists(1, lists);
      check(queue->Signal(surfaces.consumed_fence.Get(), ready),
            "ID3D12CommandQueue::Signal(shared consumed)");
      const auto completed = ++local_fence_value;
      check(queue->Signal(local_fence.Get(), completed),
            "ID3D12CommandQueue::Signal(local)");
      check(local_fence->SetEventOnCompletion(completed, fence_event),
            "ID3D12Fence::SetEventOnCompletion(local)");
      if (WaitForSingleObject(fence_event, 30000) != WAIT_OBJECT_0) {
        throw std::runtime_error("Timed out waiting for eye readback");
      }
      const auto local_completed = local_fence->GetCompletedValue();
      if (local_completed == UINT64_MAX || local_completed < completed) {
        throw std::runtime_error(
            "Local eye-readback fence became invalid");
      }
      const std::array<const wchar_t*, 2> labels{L"left", L"right"};
      for (std::size_t eye = 0; eye < readbacks.size(); ++eye) {
        const auto filename = L"pair-" + std::to_wstring(ready) + L"-" +
                              labels[eye] + L".ppm";
        const auto path = output_directory / filename;
        write_ppm(path, readbacks[eye].Get(), footprint, width, height);
        std::wcout << L"shared_eye_capture=" << path.wstring() << L'\n';
      }
      last_ready = ready;
    }
    CloseHandle(fence_event);
    CloseHandle(ready_event);
    std::wcout << L"shared_eye_capture.result=pass adapter="
               << attached->adapter_name << L" pairs=" << pair_count
               << L" initial_ready=" << initial_ready
               << L" final_ready=" << last_ready << L'\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "shared_eye_capture: " << error.what() << '\n';
    return 1;
  }
}
