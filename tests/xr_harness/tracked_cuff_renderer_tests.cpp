#include "tracked_cuff_renderer.h"

#include "core/head_tracking.h"
#include "core/xr_math.h"

#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
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

}  // namespace

int main() {
  try {
    constexpr UINT width = 256;
    constexpr UINT height = 256;
    constexpr DXGI_FORMAT format = DXGI_FORMAT_R8G8B8A8_UNORM;

    ComPtr<ID3D12Device> device;
    check(D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_11_0,
                            IID_PPV_ARGS(&device)),
          "D3D12CreateDevice");
    D3D12_COMMAND_QUEUE_DESC queue_info{};
    ComPtr<ID3D12CommandQueue> queue;
    check(device->CreateCommandQueue(&queue_info, IID_PPV_ARGS(&queue)),
          "CreateCommandQueue");
    ComPtr<ID3D12CommandAllocator> allocator;
    check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
                                         IID_PPV_ARGS(&allocator)),
          "CreateCommandAllocator");
    ComPtr<ID3D12GraphicsCommandList> commands;
    check(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                    allocator.Get(), nullptr,
                                    IID_PPV_ARGS(&commands)),
          "CreateCommandList");

    D3D12_HEAP_PROPERTIES default_heap{};
    default_heap.Type = D3D12_HEAP_TYPE_DEFAULT;
    D3D12_RESOURCE_DESC texture_info{};
    texture_info.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    texture_info.Width = width;
    texture_info.Height = height;
    texture_info.DepthOrArraySize = 1;
    texture_info.MipLevels = 1;
    texture_info.Format = format;
    texture_info.SampleDesc.Count = 1;
    texture_info.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
    texture_info.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    D3D12_CLEAR_VALUE clear_value{};
    clear_value.Format = format;
    clear_value.Color[3] = 1.0F;
    ComPtr<ID3D12Resource> target;
    check(device->CreateCommittedResource(
              &default_heap, D3D12_HEAP_FLAG_NONE, &texture_info,
              D3D12_RESOURCE_STATE_RENDER_TARGET, &clear_value,
              IID_PPV_ARGS(&target)),
          "CreateCommittedResource(target)");

    D3D12_DESCRIPTOR_HEAP_DESC rtv_info{};
    rtv_info.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    rtv_info.NumDescriptors = 1;
    ComPtr<ID3D12DescriptorHeap> clear_rtv_heap;
    check(device->CreateDescriptorHeap(&rtv_info,
                                       IID_PPV_ARGS(&clear_rtv_heap)),
          "CreateDescriptorHeap");
    const auto clear_rtv =
        clear_rtv_heap->GetCPUDescriptorHandleForHeapStart();
    device->CreateRenderTargetView(target.Get(), nullptr, clear_rtv);
    constexpr std::array<float, 4> black{0.0F, 0.0F, 0.0F, 1.0F};
    commands->ClearRenderTargetView(clear_rtv, black.data(), 0, nullptr);

    std::vector<std::vector<XrSwapchainImageD3D12KHR>> images(1);
    images[0].push_back(
        {XR_TYPE_SWAPCHAIN_IMAGE_D3D12_KHR, nullptr, target.Get()});
    std::vector<XrViewConfigurationView> configurations(
        1, {XR_TYPE_VIEW_CONFIGURATION_VIEW});
    configurations[0].recommendedImageRectWidth = width;
    configurations[0].recommendedImageRectHeight = height;
    darktidevr::harness::TrackedCuffRenderer renderer(
        device.Get(), format, images, configurations);

    // Exercise the same translated, rotated recenter/body conversion used by
    // unattended controller paths. An identity-only render would not catch a
    // transposed or wrong-space view/model matrix.
    const darktidevr::math::Pose recenter_pose{
        darktidevr::math::from_axis_angle({1.0F, 0.0F, 0.0F}, -0.65F),
        {1.2F, 1.65F, -0.8F}};
    XrPosef eye_pose{};
    eye_pose.orientation = {recenter_pose.orientation.x,
                            recenter_pose.orientation.y,
                            recenter_pose.orientation.z,
                            recenter_pose.orientation.w};
    eye_pose.position = {recenter_pose.position.x, recenter_pose.position.y,
                         recenter_pose.position.z};
    const XrFovf fov{-0.78F, 0.78F, 0.78F, -0.78F};
    std::array<darktidevr::core::ControllerHandState, 2> hands{};
    const darktidevr::math::Pose body_grip{{}, {0.0F, 0.45F, -0.25F}};
    hands[0].grip_pose = darktidevr::core::anchored_controller_pose(
        recenter_pose, body_grip);
    hands[0].grip_tracking_flags =
        darktidevr::core::controller_orientation_valid |
        darktidevr::core::controller_position_valid;
    const auto clip = darktidevr::harness::tracked_cuff_clip_center(
        eye_pose, fov, hands[0]);
    if (!(clip[3] > 0.0F) || std::abs(clip[0] / clip[3]) > 1.0F ||
        std::abs(clip[1] / clip[3]) > 1.0F || clip[2] < 0.0F ||
        clip[2] > clip[3]) {
      throw std::runtime_error("Tracked cuff centre is outside test frustum");
    }
    if (renderer.record(commands.Get(), 0, 0, eye_pose, fov, hands) != 1U) {
      throw std::runtime_error("Expected exactly one tracked cuff draw");
    }

    UINT64 readback_bytes{};
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{};
    device->GetCopyableFootprints(&texture_info, 0, 1, 0, &footprint,
                                  nullptr, nullptr, &readback_bytes);
    D3D12_HEAP_PROPERTIES readback_heap{};
    readback_heap.Type = D3D12_HEAP_TYPE_READBACK;
    D3D12_RESOURCE_DESC buffer_info{};
    buffer_info.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    buffer_info.Width = readback_bytes;
    buffer_info.Height = 1;
    buffer_info.DepthOrArraySize = 1;
    buffer_info.MipLevels = 1;
    buffer_info.SampleDesc.Count = 1;
    buffer_info.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    ComPtr<ID3D12Resource> readback;
    check(device->CreateCommittedResource(
              &readback_heap, D3D12_HEAP_FLAG_NONE, &buffer_info,
              D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
              IID_PPV_ARGS(&readback)),
          "CreateCommittedResource(readback)");
    D3D12_RESOURCE_BARRIER barrier{};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition.pResource = target.Get();
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    commands->ResourceBarrier(1, &barrier);
    D3D12_TEXTURE_COPY_LOCATION source{};
    source.pResource = target.Get();
    source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    D3D12_TEXTURE_COPY_LOCATION destination{};
    destination.pResource = readback.Get();
    destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    destination.PlacedFootprint = footprint;
    commands->CopyTextureRegion(&destination, 0, 0, 0, &source, nullptr);
    check(commands->Close(), "Close");
    ID3D12CommandList* lists[]{commands.Get()};
    queue->ExecuteCommandLists(1, lists);

    ComPtr<ID3D12Fence> fence;
    check(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                              IID_PPV_ARGS(&fence)),
          "CreateFence");
    check(queue->Signal(fence.Get(), 1), "Signal");
    const HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!event) {
      throw std::runtime_error("CreateEvent failed");
    }
    check(fence->SetEventOnCompletion(1, event), "SetEventOnCompletion");
    WaitForSingleObject(event, INFINITE);
    CloseHandle(event);

    const std::byte* pixels{};
    D3D12_RANGE read_range{0, static_cast<SIZE_T>(readback_bytes)};
    check(readback->Map(0, &read_range,
                        reinterpret_cast<void**>(
                            const_cast<std::byte**>(&pixels))),
          "Map(readback)");
    std::size_t changed_pixels{};
    for (UINT y = 0; y < height; ++y) {
      const auto* row = pixels + y * footprint.Footprint.RowPitch;
      for (UINT x = 0; x < width; ++x) {
        const auto* pixel = row + x * 4U;
        if (pixel[0] != std::byte{} || pixel[1] != std::byte{} ||
            pixel[2] != std::byte{}) {
          ++changed_pixels;
        }
      }
    }
    D3D12_RANGE no_write{0, 0};
    readback->Unmap(0, &no_write);
    if (changed_pixels == 0U || changed_pixels >= width * height) {
      throw std::runtime_error("Tracked cuff produced no bounded pixels");
    }
    std::cout << "tracked_cuff.changed_pixels=" << changed_pixels << '\n';
    std::cout << "result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "tracked_cuff_renderer_tests: " << error.what() << '\n';
    return 1;
  }
}
