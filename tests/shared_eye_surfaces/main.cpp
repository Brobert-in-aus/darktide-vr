#include "bridge/shared_eye_surfaces.h"
#include "core/shared_surface_policy.h"

#include <Windows.h>
#include <d3d12.h>
#include <wrl/client.h>

#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

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
    if (!darktidevr::bridge::shared_fence_values_healthy(0, 0) ||
        !darktidevr::bridge::shared_fence_values_healthy(42, 41) ||
        darktidevr::bridge::shared_fence_values_healthy(UINT64_MAX, 0) ||
        darktidevr::bridge::shared_fence_values_healthy(0, UINT64_MAX)) {
      throw std::runtime_error(
          "Shared fence health must reject either device-removed sentinel");
    }
    if (!darktidevr::core::shared_mailbox_writable(0, 0) ||
        !darktidevr::core::shared_mailbox_writable(42, 42) ||
        !darktidevr::core::shared_mailbox_writable(42, 43) ||
        darktidevr::core::shared_mailbox_writable(42, 41) ||
        darktidevr::core::shared_mailbox_writable(UINT64_MAX, UINT64_MAX)) {
      throw std::runtime_error(
          "One-slot shared mailbox must not be overwritten before consume");
    }
    if (darktidevr::core::canonical_shared_render_target_format(
            DXGI_FORMAT_R8G8B8A8_TYPELESS,
            DXGI_FORMAT_R8G8B8A8_UNORM) != DXGI_FORMAT_R8G8B8A8_UNORM ||
        darktidevr::core::canonical_shared_copy_format(
            DXGI_FORMAT_R8G8B8A8_TYPELESS) !=
            DXGI_FORMAT_R8G8B8A8_UNORM ||
        darktidevr::core::canonical_shared_copy_format(
            DXGI_FORMAT_R16G16B16A16_FLOAT) !=
            DXGI_FORMAT_R16G16B16A16_FLOAT ||
        !darktidevr::core::shared_render_target_description_matches(
            2496, 2688, DXGI_FORMAT_R8G8B8A8_UNORM, 2496, 2688,
            DXGI_FORMAT_R8G8B8A8_TYPELESS, DXGI_FORMAT_R8G8B8A8_UNORM) ||
        !darktidevr::core::shared_render_target_description_matches(
            2496, 2688, DXGI_FORMAT_R8G8B8A8_UNORM, 2496, 2688,
            DXGI_FORMAT_R8G8B8A8_UNORM, DXGI_FORMAT_R8G8B8A8_UNORM) ||
        darktidevr::core::shared_render_target_description_matches(
            2496, 2688, DXGI_FORMAT_R8G8B8A8_UNORM, 2496, 2688,
            DXGI_FORMAT_R8G8B8A8_TYPELESS,
            DXGI_FORMAT_R8G8B8A8_UNORM_SRGB)) {
      throw std::runtime_error(
          "Shared render target identity must canonicalize typed/typeless "
          "backing resources to the typed RTV format");
    }
    if (!darktidevr::core::menu_capture_extent_matches(2496, 2688, 2496, 2688) ||
        darktidevr::core::menu_capture_extent_matches(2496, 1404, 2496, 2688) ||
        darktidevr::core::menu_capture_extent_matches(1920, 1080, 2496, 2688) ||
        darktidevr::core::menu_capture_extent_matches(0, 0, 0, 0)) {
      throw std::runtime_error(
          "Menu capture must reject HUD and mismatched canvases before alias routing");
    }
    ComPtr<ID3D12Device> device;
    check(D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_12_0,
                            IID_PPV_ARGS(&device)),
          "D3D12CreateDevice");

    const bool live_dump = argc == 3 &&
                           (std::string(argv[1]) == "--live-dump" ||
                            std::string(argv[1]) == "--live-dump-native" ||
                            std::string(argv[1]) == "--live-dump-medium");
    if ((argc == 2 && (std::string(argv[1]) == "--live" ||
                       std::string(argv[1]) == "--live-full")) ||
        live_dump) {
      const bool full_width = !live_dump &&
                              std::string(argv[1]) == "--live-full";
      const bool native_dump = live_dump &&
                               std::string(argv[1]) == "--live-dump-native";
      const bool medium_dump = live_dump &&
                               std::string(argv[1]) == "--live-dump-medium";
      const std::uint32_t width =
          (native_dump || medium_dump) ? 2112U
                                       : (full_width ? 3840U : 1920U);
      const std::uint32_t height =
          (native_dump || medium_dump) ? 2304U : 2160U;
      const auto format = native_dump ? DXGI_FORMAT_R8G8B8A8_TYPELESS
                                      : DXGI_FORMAT_R8G8B8A8_UNORM;
      const darktidevr::bridge::SharedEyeSurfaceNames live_names{
          {L"Local\\DarktideVR-eye-left", L"Local\\DarktideVR-eye-right"},
          L"Local\\DarktideVR-eye-ready",
          L"Local\\DarktideVR-eye-consumed"};
      const auto opened = darktidevr::bridge::open_shared_eye_surfaces(
          device.Get(), live_names,
          {{width, height}, format});
      const auto first = opened.ready_fence->GetCompletedValue();
      if (live_dump) {
        ComPtr<ID3D12CommandQueue> queue;
        D3D12_COMMAND_QUEUE_DESC queue_description{};
        queue_description.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
        check(device->CreateCommandQueue(&queue_description,
                                         IID_PPV_ARGS(&queue)),
              "CreateCommandQueue(live dump)");
        ComPtr<ID3D12CommandAllocator> allocator;
        ComPtr<ID3D12GraphicsCommandList> commands;
        check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
                                              IID_PPV_ARGS(&allocator)),
              "CreateCommandAllocator(live dump)");
        check(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                        allocator.Get(), nullptr,
                                        IID_PPV_ARGS(&commands)),
              "CreateCommandList(live dump)");

        std::array<ComPtr<ID3D12Resource>, 2> readbacks;
        std::array<D3D12_PLACED_SUBRESOURCE_FOOTPRINT, 2> footprints{};
        std::array<UINT64, 2> readback_bytes{};
        D3D12_HEAP_PROPERTIES readback_heap{};
        readback_heap.Type = D3D12_HEAP_TYPE_READBACK;
        for (std::size_t eye = 0; eye < opened.eyes.size(); ++eye) {
          const auto description = opened.eyes[eye]->GetDesc();
          device->GetCopyableFootprints(&description, 0, 1, 0,
                                        &footprints[eye], nullptr, nullptr,
                                        &readback_bytes[eye]);
          D3D12_RESOURCE_DESC buffer{};
          buffer.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
          buffer.Width = readback_bytes[eye];
          buffer.Height = 1;
          buffer.DepthOrArraySize = 1;
          buffer.MipLevels = 1;
          buffer.SampleDesc.Count = 1;
          buffer.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
          check(device->CreateCommittedResource(
                    &readback_heap, D3D12_HEAP_FLAG_NONE, &buffer,
                    D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
                    IID_PPV_ARGS(&readbacks[eye])),
                "CreateCommittedResource(live dump)");

          D3D12_RESOURCE_BARRIER barrier{};
          barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
          barrier.Transition.pResource = opened.eyes[eye].Get();
          barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
          barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
          barrier.Transition.Subresource =
              D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
          commands->ResourceBarrier(1, &barrier);
          D3D12_TEXTURE_COPY_LOCATION destination{};
          destination.pResource = readbacks[eye].Get();
          destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
          destination.PlacedFootprint = footprints[eye];
          D3D12_TEXTURE_COPY_LOCATION source{};
          source.pResource = opened.eyes[eye].Get();
          source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
          commands->CopyTextureRegion(&destination, 0, 0, 0, &source,
                                      nullptr);
          std::swap(barrier.Transition.StateBefore,
                    barrier.Transition.StateAfter);
          commands->ResourceBarrier(1, &barrier);
        }
        check(commands->Close(), "Close(live dump)");
        const auto producer_value = opened.ready_fence->GetCompletedValue();
        check(queue->Wait(opened.ready_fence.Get(), producer_value),
              "Wait(live dump producer)");
        ID3D12CommandList* lists[]{commands.Get()};
        queue->ExecuteCommandLists(1, lists);
        check(queue->Signal(opened.consumed_fence.Get(), producer_value),
              "Signal(live dump consumed)");
        ComPtr<ID3D12Fence> completion;
        check(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                                  IID_PPV_ARGS(&completion)),
              "CreateFence(live dump)");
        check(queue->Signal(completion.Get(), 1), "Signal(live dump)");
        UniqueHandle event(CreateEventW(nullptr, FALSE, FALSE, nullptr));
        if (!event) {
          throw std::runtime_error("CreateEvent(live dump) failed");
        }
        check(completion->SetEventOnCompletion(1, event.get()),
              "SetEventOnCompletion(live dump)");
        WaitForSingleObject(event.get(), INFINITE);

        const std::filesystem::path output_directory(argv[2]);
        std::filesystem::create_directories(output_directory);
        const std::array<const char*, 2> filenames{"left.ppm", "right.ppm"};
        for (std::size_t eye = 0; eye < readbacks.size(); ++eye) {
          void* mapped{};
          const D3D12_RANGE read_range{
              0, static_cast<SIZE_T>(readback_bytes[eye])};
          check(readbacks[eye]->Map(0, &read_range, &mapped),
                "Map(live dump)");
          const auto path = output_directory / filenames[eye];
          std::ofstream output(path, std::ios::binary);
          if (!output) {
            throw std::runtime_error("Open output image failed");
          }
          output << "P6\n" << width << ' ' << height << "\n255\n";
          std::vector<unsigned char> row(static_cast<std::size_t>(width) * 3);
          for (std::uint32_t y = 0; y < height; ++y) {
            const auto* source = static_cast<const unsigned char*>(mapped) +
                                 footprints[eye].Offset +
                                 static_cast<std::size_t>(y) *
                                     footprints[eye].Footprint.RowPitch;
            for (std::uint32_t x = 0; x < width; ++x) {
              row[x * 3] = source[x * 4];
              row[x * 3 + 1] = source[x * 4 + 1];
              row[x * 3 + 2] = source[x * 4 + 2];
            }
            output.write(reinterpret_cast<const char*>(row.data()),
                         static_cast<std::streamsize>(row.size()));
          }
          const D3D12_RANGE written_range{0, 0};
          readbacks[eye]->Unmap(0, &written_range);
          std::cout << "shared_eye_surfaces.dump.eye" << eye << '='
                    << path.string() << '\n';
        }
        std::cout << "shared_eye_surfaces.dump.fence=" << producer_value
                  << '\n';
        return 0;
      }
      check(opened.consumed_fence->Signal(first),
            "Signal(live consumed)");
      Sleep(1000);
      const auto second = opened.ready_fence->GetCompletedValue();
      if (first == 0 || second <= first) {
        throw std::runtime_error("Live producer fence is not advancing: " +
                                 std::to_string(first) + "->" +
                                 std::to_string(second));
      }
      std::cout << "shared_eye_surfaces.live=pass width=" << width
                << " height=" << height << " fence=" << first << "->"
                << second << '\n';
      return 0;
    }

    const darktidevr::bridge::SharedEyeSurfaceDescription description{
        {64, 64}, DXGI_FORMAT_R8G8B8A8_UNORM};
    const auto prefix = L"Local\\DarktideVR-SharedEye-Test-" +
                        std::to_wstring(GetCurrentProcessId());
    const darktidevr::bridge::SharedEyeSurfaceNames names{
        {prefix + L"-left", prefix + L"-right"}, prefix + L"-ready",
        prefix + L"-consumed"};

    D3D12_HEAP_PROPERTIES heap{};
    heap.Type = D3D12_HEAP_TYPE_DEFAULT;
    D3D12_RESOURCE_DESC resource{};
    resource.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    resource.Width = description.extent.width;
    resource.Height = description.extent.height;
    resource.DepthOrArraySize = 1;
    resource.MipLevels = 1;
    resource.Format = description.format;
    resource.SampleDesc.Count = 1;
    resource.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
    resource.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;

    std::array<ComPtr<ID3D12Resource>, 2> producer_eyes;
    std::array<UniqueHandle, 2> producer_handles;
    for (std::size_t eye = 0; eye < producer_eyes.size(); ++eye) {
      check(device->CreateCommittedResource(
                &heap, D3D12_HEAP_FLAG_SHARED, &resource,
                D3D12_RESOURCE_STATE_COMMON, nullptr,
                IID_PPV_ARGS(&producer_eyes[eye])),
            "CreateCommittedResource(shared eye)");
      HANDLE handle{};
      check(device->CreateSharedHandle(producer_eyes[eye].Get(), nullptr,
                                       GENERIC_ALL, names.eyes[eye].c_str(),
                                       &handle),
            "CreateSharedHandle(eye)");
      producer_handles[eye].reset(handle);
    }

    ComPtr<ID3D12Fence> producer_fence;
    check(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED,
                              IID_PPV_ARGS(&producer_fence)),
          "CreateFence(shared)");
    HANDLE fence_handle{};
    check(device->CreateSharedHandle(producer_fence.Get(), nullptr, GENERIC_ALL,
                                     names.ready_fence.c_str(), &fence_handle),
          "CreateSharedHandle(fence)");
    UniqueHandle producer_fence_handle(fence_handle);

    ComPtr<ID3D12Fence> producer_consumed_fence;
    check(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED,
                              IID_PPV_ARGS(&producer_consumed_fence)),
          "CreateFence(consumed shared)");
    HANDLE consumed_fence_handle{};
    check(device->CreateSharedHandle(
              producer_consumed_fence.Get(), nullptr, GENERIC_ALL,
              names.consumed_fence.c_str(), &consumed_fence_handle),
          "CreateSharedHandle(consumed fence)");
    UniqueHandle producer_consumed_fence_handle(consumed_fence_handle);

    const auto opened = darktidevr::bridge::open_shared_eye_surfaces(
        device.Get(), names, description);
    if (!opened.eyes[0] || !opened.eyes[1] || !opened.ready_fence ||
        !opened.consumed_fence ||
        opened.eyes[0]->GetDesc().Width != 64 ||
        opened.eyes[1]->GetDesc().Height != 64) {
      throw std::runtime_error("Receiver did not open both eye surfaces");
    }
    bool mismatch_rejected{};
    try {
      (void)darktidevr::bridge::open_shared_eye_surfaces(
          device.Get(), names, {{65, 64}, description.format});
    } catch (const std::runtime_error&) {
      mismatch_rejected = true;
    }
    if (!mismatch_rejected) {
      throw std::runtime_error("Receiver accepted a mismatched eye extent");
    }

    const darktidevr::bridge::SharedTextureNames texture_names{
        prefix + L"-menu", prefix + L"-menu-ready",
        prefix + L"-menu-consumed"};
    ComPtr<ID3D12Resource> producer_texture;
    check(device->CreateCommittedResource(
              &heap, D3D12_HEAP_FLAG_SHARED, &resource,
              D3D12_RESOURCE_STATE_COMMON, nullptr,
              IID_PPV_ARGS(&producer_texture)),
          "CreateCommittedResource(shared texture)");
    HANDLE texture_handle{};
    check(device->CreateSharedHandle(
              producer_texture.Get(), nullptr, GENERIC_ALL,
              texture_names.texture.c_str(), &texture_handle),
          "CreateSharedHandle(texture)");
    UniqueHandle producer_texture_handle(texture_handle);
    ComPtr<ID3D12Fence> texture_ready;
    ComPtr<ID3D12Fence> texture_consumed;
    check(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED,
                              IID_PPV_ARGS(&texture_ready)),
          "CreateFence(texture ready)");
    check(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED,
                              IID_PPV_ARGS(&texture_consumed)),
          "CreateFence(texture consumed)");
    HANDLE texture_ready_handle{};
    HANDLE texture_consumed_handle{};
    check(device->CreateSharedHandle(
              texture_ready.Get(), nullptr, GENERIC_ALL,
              texture_names.ready_fence.c_str(), &texture_ready_handle),
          "CreateSharedHandle(texture ready)");
    check(device->CreateSharedHandle(
              texture_consumed.Get(), nullptr, GENERIC_ALL,
              texture_names.consumed_fence.c_str(),
              &texture_consumed_handle),
          "CreateSharedHandle(texture consumed)");
    UniqueHandle producer_texture_ready_handle(texture_ready_handle);
    UniqueHandle producer_texture_consumed_handle(texture_consumed_handle);

    const auto opened_texture = darktidevr::bridge::open_shared_texture(
        device.Get(), texture_names, description);
    if (!opened_texture.texture || !opened_texture.ready_fence ||
        !opened_texture.consumed_fence ||
        opened_texture.texture->GetDesc().Width != 64) {
      throw std::runtime_error("Receiver did not open shared texture");
    }

    const darktidevr::bridge::SharedGeneratedSurfaceNames generated_names{
        {prefix + L"-generated-0", prefix + L"-generated-1",
         prefix + L"-generated-2"},
        prefix + L"-generated-ready",
        prefix + L"-generated-consumed"};
    std::array<ComPtr<ID3D12Resource>,
               darktidevr::core::kSharedGeneratedFrameSlotCount>
        producer_generated;
    std::array<UniqueHandle,
               darktidevr::core::kSharedGeneratedFrameSlotCount>
        producer_generated_handles;
    for (std::size_t index = 0; index < producer_generated.size(); ++index) {
      check(device->CreateCommittedResource(
                &heap, D3D12_HEAP_FLAG_SHARED, &resource,
                D3D12_RESOURCE_STATE_COMMON, nullptr,
                IID_PPV_ARGS(&producer_generated[index])),
            "CreateCommittedResource(generated texture)");
      HANDLE handle{};
      check(device->CreateSharedHandle(
                producer_generated[index].Get(), nullptr, GENERIC_ALL,
                generated_names.textures[index].c_str(), &handle),
            "CreateSharedHandle(generated texture)");
      producer_generated_handles[index].reset(handle);
    }
    ComPtr<ID3D12Fence> generated_ready;
    ComPtr<ID3D12Fence> generated_consumed;
    check(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED,
                              IID_PPV_ARGS(&generated_ready)),
          "CreateFence(generated ready)");
    check(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED,
                              IID_PPV_ARGS(&generated_consumed)),
          "CreateFence(generated consumed)");
    HANDLE generated_ready_handle{};
    HANDLE generated_consumed_handle{};
    check(device->CreateSharedHandle(
              generated_ready.Get(), nullptr, GENERIC_ALL,
              generated_names.ready_fence.c_str(), &generated_ready_handle),
          "CreateSharedHandle(generated ready)");
    check(device->CreateSharedHandle(
              generated_consumed.Get(), nullptr, GENERIC_ALL,
              generated_names.consumed_fence.c_str(),
              &generated_consumed_handle),
          "CreateSharedHandle(generated consumed)");
    UniqueHandle producer_generated_ready_handle(generated_ready_handle);
    UniqueHandle producer_generated_consumed_handle(generated_consumed_handle);

    const auto opened_generated =
        darktidevr::bridge::open_shared_generated_surfaces(
            device.Get(), generated_names, description);
    if (!opened_generated.ready_fence || !opened_generated.consumed_fence) {
      throw std::runtime_error("Receiver did not open generated fences");
    }
    for (const auto& texture : opened_generated.textures) {
      if (!texture || texture->GetDesc().Width != 64 ||
          texture->GetDesc().Height != 64) {
        throw std::runtime_error(
            "Receiver did not open every generated texture");
      }
    }

    std::cout << "shared_eye_surfaces.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "shared_eye_surfaces: " << error.what() << '\n';
    return 1;
  }
}
