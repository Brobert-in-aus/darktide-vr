#include "panel_renderer.h"

#include "core/xr_math.h"

#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>

using Microsoft::WRL::ComPtr;

namespace {

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) {
    throw std::runtime_error(std::string(operation) + " failed");
  }
}

void require(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

D3D12_RESOURCE_DESC texture_description(UINT width, UINT height,
                                        DXGI_FORMAT format) {
  D3D12_RESOURCE_DESC description{};
  description.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
  description.Width = width;
  description.Height = height;
  description.DepthOrArraySize = 1;
  description.MipLevels = 1;
  description.Format = format;
  description.SampleDesc.Count = 1;
  description.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
  return description;
}

ComPtr<ID3D12Resource> buffer(ID3D12Device* device, D3D12_HEAP_TYPE type,
                              UINT64 bytes, D3D12_RESOURCE_STATES state,
                              const char* operation) {
  D3D12_HEAP_PROPERTIES heap{};
  heap.Type = type;
  D3D12_RESOURCE_DESC description{};
  description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
  description.Width = bytes;
  description.Height = 1;
  description.DepthOrArraySize = 1;
  description.MipLevels = 1;
  description.SampleDesc.Count = 1;
  description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  ComPtr<ID3D12Resource> resource;
  check(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE,
                                        &description, state, nullptr,
                                        IID_PPV_ARGS(&resource)),
        operation);
  return resource;
}

// The pixel a point lands on, computed from first principles (tangents in
// the eye's own frame), not through the renderer's matrices: a transposed or
// wrong-handed matrix, a flipped V or an ignored asymmetric field of view
// would all put the quadrant colours somewhere else.
std::array<float, 2> expected_pixel(const darktidevr::math::Pose& eye,
                                    const XrFovf& fov,
                                    darktidevr::math::Vec3 world,
                                    float width, float height) {
  const auto local = darktidevr::math::transform_point(
      darktidevr::math::inverse(eye), world);
  const auto tangent_x = local.x / -local.z;
  const auto tangent_y = local.y / -local.z;
  const auto left = std::tan(fov.angleLeft);
  const auto right = std::tan(fov.angleRight);
  const auto up = std::tan(fov.angleUp);
  const auto down = std::tan(fov.angleDown);
  return {(tangent_x - left) / (right - left) * width,
          (up - tangent_y) / (up - down) * height};
}

}  // namespace

int main() {
  try {
    constexpr UINT width = 320;
    constexpr UINT height = 352;
    constexpr UINT board_width = 64;
    constexpr UINT board_height = 36;
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
    auto target_info = texture_description(width, height, format);
    target_info.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    D3D12_CLEAR_VALUE clear_value{};
    clear_value.Format = format;
    clear_value.Color[3] = 1.0F;
    ComPtr<ID3D12Resource> target;
    check(device->CreateCommittedResource(
              &default_heap, D3D12_HEAP_FLAG_NONE, &target_info,
              D3D12_RESOURCE_STATE_RENDER_TARGET, &clear_value,
              IID_PPV_ARGS(&target)),
          "CreateCommittedResource(target)");
    D3D12_DESCRIPTOR_HEAP_DESC rtv_info{};
    rtv_info.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    rtv_info.NumDescriptors = 1;
    ComPtr<ID3D12DescriptorHeap> rtv_heap;
    check(device->CreateDescriptorHeap(&rtv_info, IID_PPV_ARGS(&rtv_heap)),
          "CreateDescriptorHeap");
    const auto rtv = rtv_heap->GetCPUDescriptorHandleForHeapStart();
    device->CreateRenderTargetView(target.Get(), nullptr, rtv);
    // Not black: the renderer's own clear has to be what blackens it.
    constexpr std::array<float, 4> grey{0.5F, 0.5F, 0.5F, 1.0F};
    commands->ClearRenderTargetView(rtv, grey.data(), 0, nullptr);

    const auto board_info =
        texture_description(board_width, board_height, format);
    const auto swatch_info = texture_description(64, 64, format);
    darktidevr::harness::PanelRenderer renderer(device.Get(), format,
                                                board_info, swatch_info);

    // Quadrants: red top-left, green top-right, blue bottom-left, white
    // bottom-right, all opaque.
    UINT64 board_bytes{};
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT board_footprint{};
    device->GetCopyableFootprints(&board_info, 0, 1, 0, &board_footprint,
                                  nullptr, nullptr, &board_bytes);
    const auto board_upload =
        buffer(device.Get(), D3D12_HEAP_TYPE_UPLOAD, board_bytes,
               D3D12_RESOURCE_STATE_GENERIC_READ, "CreateCommittedResource(upload)");
    std::uint8_t* board_pixels{};
    check(board_upload->Map(0, nullptr,
                            reinterpret_cast<void**>(&board_pixels)),
          "Map(upload)");
    for (UINT y = 0; y < board_height; ++y) {
      auto* row = board_pixels + board_footprint.Offset +
                  y * board_footprint.Footprint.RowPitch;
      for (UINT x = 0; x < board_width; ++x) {
        const bool right = x >= board_width / 2;
        const bool bottom = y >= board_height / 2;
        row[x * 4 + 0] = (!right && !bottom) || (right && bottom) ? 255 : 0;
        row[x * 4 + 1] = right ? 255 : 0;
        row[x * 4 + 2] = bottom ? 255 : 0;
        row[x * 4 + 3] = 255;
      }
    }
    board_upload->Unmap(0, nullptr);
    D3D12_TEXTURE_COPY_LOCATION upload_source{};
    upload_source.pResource = board_upload.Get();
    upload_source.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    upload_source.PlacedFootprint = board_footprint;
    D3D12_TEXTURE_COPY_LOCATION board_destination{};
    board_destination.pResource = renderer.board_texture();
    board_destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    commands->CopyTextureRegion(&board_destination, 0, 0, 0, &upload_source,
                                nullptr);

    // An eye that is neither at the origin nor level, with the asymmetric
    // field of view Virtual Desktop reports at a 90 per cent FOV tangent,
    // and a board that is neither square to it nor centred.
    const darktidevr::math::Pose eye{
        darktidevr::math::multiply(
            darktidevr::math::from_axis_angle({0.0F, 1.0F, 0.0F}, 0.35F),
            darktidevr::math::from_axis_angle({1.0F, 0.0F, 0.0F}, -0.20F)),
        {0.4F, 1.6F, -0.3F}};
    const XrFovf fov{-0.893445F, 0.648593F, 0.71549F, -0.909609F};
    const auto board_pose = darktidevr::math::compose(
        eye, {darktidevr::math::from_axis_angle({0.0F, 1.0F, 0.0F}, 0.25F),
              {-0.15F, -0.10F, -2.0F}});
    XrPosef eye_pose{};
    eye_pose.orientation = {eye.orientation.x, eye.orientation.y,
                            eye.orientation.z, eye.orientation.w};
    eye_pose.position = {eye.position.x, eye.position.y, eye.position.z};
    darktidevr::harness::PanelQuad quad{};
    quad.pose.orientation = {board_pose.orientation.x,
                             board_pose.orientation.y,
                             board_pose.orientation.z,
                             board_pose.orientation.w};
    quad.pose.position = {board_pose.position.x, board_pose.position.y,
                          board_pose.position.z};
    quad.size = {2.0F, 1.125F};
    quad.texels = {{0, 0},
                   {static_cast<std::int32_t>(board_width),
                    static_cast<std::int32_t>(board_height)}};
    quad.source = darktidevr::harness::PanelQuad::Source::board;
    // A swatch quad before the swatch is uploaded must be skipped, not drawn
    // from an unwritten texture.
    auto unready = quad;
    unready.source = darktidevr::harness::PanelQuad::Source::swatch;
    const std::array<darktidevr::harness::PanelQuad, 2> quads{quad, unready};

    const XrRect2Di image_rect{{0, 0},
                               {static_cast<std::int32_t>(width),
                                static_cast<std::int32_t>(height)}};
    renderer.begin(commands.Get());
    const auto drawn =
        renderer.record(commands.Get(), rtv, image_rect, 0, eye_pose, fov,
                        quads.data(), quads.size(), true);
    renderer.end(commands.Get());
    require(drawn == 1U, "Expected the board drawn and the swatch skipped");

    UINT64 readback_bytes{};
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{};
    device->GetCopyableFootprints(&target_info, 0, 1, 0, &footprint, nullptr,
                                  nullptr, &readback_bytes);
    const auto readback =
        buffer(device.Get(), D3D12_HEAP_TYPE_READBACK, readback_bytes,
               D3D12_RESOURCE_STATE_COPY_DEST,
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
    check(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)),
          "CreateFence");
    check(queue->Signal(fence.Get(), 1), "Signal");
    const HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    require(event != nullptr, "CreateEvent failed");
    check(fence->SetEventOnCompletion(1, event), "SetEventOnCompletion");
    WaitForSingleObject(event, INFINITE);
    CloseHandle(event);

    const std::uint8_t* pixels{};
    D3D12_RANGE read_range{0, static_cast<SIZE_T>(readback_bytes)};
    check(readback->Map(0, &read_range,
                        reinterpret_cast<void**>(
                            const_cast<std::uint8_t**>(&pixels))),
          "Map(readback)");
    const auto pixel_at = [&](float x, float y) {
      const auto column = static_cast<UINT>(x);
      const auto row = static_cast<UINT>(y);
      require(column < width && row < height,
              "Expected point is outside the test image");
      const auto* pixel =
          pixels + row * footprint.Footprint.RowPitch + column * 4U;
      return std::array<int, 3>{pixel[0], pixel[1], pixel[2]};
    };
    struct Probe {
      const char* name;
      float u, v;
      std::array<int, 3> color;
    };
    const std::array<Probe, 6> probes{{
        {"top-left", 0.25F, 0.25F, {255, 0, 0}},
        {"top-right", 0.75F, 0.25F, {0, 255, 0}},
        {"bottom-left", 0.25F, 0.75F, {0, 0, 255}},
        {"bottom-right", 0.75F, 0.75F, {255, 255, 255}},
        {"left of the board", -0.15F, 0.5F, {0, 0, 0}},
        {"above the board", 0.5F, -0.25F, {0, 0, 0}},
    }};
    for (const auto& probe : probes) {
      const auto world = darktidevr::math::transform_point(
          board_pose, {(probe.u - 0.5F) * quad.size.width,
                       (0.5F - probe.v) * quad.size.height, 0.0F});
      const auto expected = expected_pixel(eye, fov, world,
                                           static_cast<float>(width),
                                           static_cast<float>(height));
      // The renderer's own clip helper must agree with first principles.
      const auto clip = darktidevr::harness::panel_point_clip(
          eye_pose, fov, quad.pose, quad.size, probe.u, probe.v);
      const auto clip_x = (clip[0] / clip[3] * 0.5F + 0.5F) * width;
      const auto clip_y = (0.5F - clip[1] / clip[3] * 0.5F) * height;
      require(std::abs(clip_x - expected[0]) < 0.05F &&
                  std::abs(clip_y - expected[1]) < 0.05F,
              std::string("Clip helper disagrees at ") + probe.name);
      const auto color = pixel_at(expected[0], expected[1]);
      for (std::size_t channel = 0; channel < 3; ++channel) {
        require(std::abs(color[channel] - probe.color[channel]) <= 2,
                std::string("Wrong colour at ") + probe.name + ": " +
                    std::to_string(color[0]) + "," +
                    std::to_string(color[1]) + "," +
                    std::to_string(color[2]) + " at " +
                    std::to_string(expected[0]) + "," +
                    std::to_string(expected[1]));
      }
    }
    // A draw that is issued is not a draw that is seen. The gameplay reticle
    // is the first panel quad placed at an arbitrary world depth -- the mod
    // publishes the aim distance up to 200 m -- and a caller that stands the
    // quad layer down when it draws has to know the quad is inside the
    // frustum (review, 18 September).
    const auto quad_at = [&](float metres) {
      XrPosef pose = quad.pose;
      const auto centre = darktidevr::math::transform_point(
          darktidevr::math::Pose{{eye_pose.orientation.x, eye_pose.orientation.y,
                                  eye_pose.orientation.z, eye_pose.orientation.w},
                                 {eye_pose.position.x, eye_pose.position.y,
                                  eye_pose.position.z}},
          {0.0F, 0.0F, -metres});
      pose.position = {centre.x, centre.y, centre.z};
      return pose;
    };
    for (const float metres : {0.5F, 5.0F, 99.0F, 200.0F, 900.0F}) {
      require(darktidevr::harness::panel_quad_centre_visible(
                  eye_pose, fov, quad_at(metres), quad.size),
              std::string("A quad ") + std::to_string(metres) +
                  " m ahead should be inside the frustum");
    }
    require(!darktidevr::harness::panel_quad_centre_visible(
                eye_pose, fov, quad_at(1200.0F), quad.size),
            "A quad past the far plane is not visible");
    require(!darktidevr::harness::panel_quad_centre_visible(
                eye_pose, fov, quad_at(-2.0F), quad.size),
            "A quad behind the eye is not visible");
    std::cout << "panel_renderer.visible_to_metres=900\n";

    D3D12_RANGE no_write{0, 0};
    readback->Unmap(0, &no_write);
    std::cout << "panel_renderer.probes=" << probes.size() << '\n';
    std::cout << "result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "panel_renderer_tests: " << error.what() << '\n';
    return 1;
  }
}
