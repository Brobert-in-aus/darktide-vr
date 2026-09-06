#include "ui_projection_layer.h"
#include <stdexcept>
#include <string>
#include <utility>

namespace darktidevr::harness {
namespace {
void check(XrResult result, const char* operation) {
  if (XR_FAILED(result)) throw std::runtime_error(std::string(operation) + ": " + std::to_string(result));
}
}

UiProjectionLayer::UiProjectionLayer(XrSession session, XrSpace space,
    std::int64_t format, std::uint32_t width, std::uint32_t height)
    : width_(width), height_(height) {
  if (!session || !space || !width || !height || width > INT32_MAX || height > INT32_MAX ||
      (format != DXGI_FORMAT_R8G8B8A8_UNORM && format != DXGI_FORMAT_R8G8B8A8_UNORM_SRGB))
    throw std::runtime_error("Invalid UI projection configuration");
  layer_.space = space;
  // Captures are premultiplied; deliberately omit UNPREMULTIPLIED_ALPHA.
  layer_.layerFlags = XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;
  layer_.viewCount = static_cast<std::uint32_t>(views_.size());
  layer_.views = views_.data();
  XrSwapchainCreateInfo create{XR_TYPE_SWAPCHAIN_CREATE_INFO};
  create.usageFlags = XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT | XR_SWAPCHAIN_USAGE_TRANSFER_DST_BIT;
  create.format = format;
  create.sampleCount = create.faceCount = create.arraySize = create.mipCount = 1;
  create.width = width; create.height = height;
  try {
    for (unsigned eye = 0; eye < 2; ++eye) {
      check(xrCreateSwapchain(session, &create, &swapchains_[eye]), "Create UI projection swapchain");
      std::uint32_t count{};
      check(xrEnumerateSwapchainImages(swapchains_[eye], 0, &count, nullptr), "Count UI projection images");
      images_[eye].assign(count, {XR_TYPE_SWAPCHAIN_IMAGE_D3D12_KHR});
      check(xrEnumerateSwapchainImages(swapchains_[eye], count, &count,
          reinterpret_cast<XrSwapchainImageBaseHeader*>(images_[eye].data())), "Get UI projection images");
      views_[eye] = {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW};
      views_[eye].subImage.swapchain = swapchains_[eye];
      views_[eye].subImage.imageRect.extent = {static_cast<std::int32_t>(width), static_cast<std::int32_t>(height)};
    }
  } catch (...) { destroy(); throw; }
}

UiProjectionLayer::~UiProjectionLayer() { destroy(); }
void UiProjectionLayer::destroy() noexcept {
  for (unsigned eye = 0; eye < 2; ++eye) {
    if (acquired_[eye]) {
      const XrSwapchainImageReleaseInfo release{XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
      xrReleaseSwapchainImage(swapchains_[eye], &release);
      acquired_[eye] = false;
    }
    if (swapchains_[eye]) xrDestroySwapchain(swapchains_[eye]);
    swapchains_[eye] = XR_NULL_HANDLE;
  }
}

void UiProjectionLayer::record(ID3D12GraphicsCommandList* commands,
    const std::array<ID3D12Resource*, 2>& sources,
    const std::array<XrPosef, 2>& source_poses,
    const std::array<XrFovf, 2>& source_fovs) {
  if (!commands || acquired_[0] || acquired_[1]) throw std::runtime_error("UI projection copy lifecycle");
  for (auto* source : sources) {
    if (!source) throw std::runtime_error("UI projection source missing");
    const auto desc = source->GetDesc();
    if (desc.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D || desc.Width != width_ || desc.Height != height_ ||
        desc.DepthOrArraySize != 1 || desc.MipLevels != 1 || desc.SampleDesc.Count != 1 ||
        (desc.Format != DXGI_FORMAT_R8G8B8A8_UNORM && desc.Format != DXGI_FORMAT_R8G8B8A8_TYPELESS))
      throw std::runtime_error("UI projection source extent or format mismatch");
  }
  for (unsigned eye = 0; eye < 2; ++eye) {
    std::uint32_t index{};
    const XrSwapchainImageAcquireInfo acquire{XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
    check(xrAcquireSwapchainImage(swapchains_[eye], &acquire, &index), "Acquire UI projection image");
    const XrSwapchainImageWaitInfo wait{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO, nullptr, XR_INFINITE_DURATION};
    check(xrWaitSwapchainImage(swapchains_[eye], &wait), "Wait UI projection image");
    acquired_[eye] = true;
    if (index >= images_[eye].size()) throw std::runtime_error("UI projection image index");
    auto* target = images_[eye][index].texture;
    std::array<D3D12_RESOURCE_BARRIER, 2> barriers{};
    for (auto& barrier : barriers) barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barriers[0].Transition = {sources[eye], D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_COPY_SOURCE};
    barriers[1].Transition = {target, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        D3D12_RESOURCE_STATE_RENDER_TARGET, D3D12_RESOURCE_STATE_COPY_DEST};
    commands->ResourceBarrier(static_cast<UINT>(barriers.size()), barriers.data());
    commands->CopyResource(target, sources[eye]);
    for (auto& barrier : barriers) std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
    commands->ResourceBarrier(static_cast<UINT>(barriers.size()), barriers.data());
    views_[eye].pose = source_poses[eye];
    views_[eye].fov = source_fovs[eye];
  }
}

void UiProjectionLayer::release() {
  for (unsigned eye = 0; eye < 2; ++eye) {
    if (!acquired_[eye]) continue;
    const XrSwapchainImageReleaseInfo release{XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
    check(xrReleaseSwapchainImage(swapchains_[eye], &release), "Release UI projection image");
    acquired_[eye] = false;
  }
}
}
