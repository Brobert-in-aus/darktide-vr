#include <Windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>

#define XR_USE_PLATFORM_WIN32
#define XR_USE_GRAPHICS_API_D3D12
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>

#include "synthetic_scene.h"
#include "menu_input_injector.h"
#include "synthetic_controller_path.h"
#include "window_capture.h"
#include "bridge/shared_eye_surfaces.h"
#include "core/head_tracking.h"
#include "core/menu_pointer_input.h"
#include "core/panel_pointer.h"
#include "core/presentation_policy.h"
#include "core/shared_controller_state.h"
#include "core/shared_head_pose.h"
#include "core/shared_presentation_state.h"

#include <algorithm>
#include <atomic>
#include <array>
#include <chrono>
#include <cmath>
#include <cstring>
#include <cstdint>
#include <deque>
#include <iostream>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

constexpr UINT kBufferCount = 2;
constexpr UINT kWidth = 960;
constexpr UINT kHeight = 540;

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) {
    throw std::runtime_error(std::string(operation) + " failed (HRESULT " +
                             std::to_string(static_cast<std::uint32_t>(result)) +
                             ")");
  }
}

std::wstring registry_string(HKEY root, const wchar_t* subkey,
                             const wchar_t* value_name) {
  DWORD bytes{};
  const auto flags = RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY;
  if (RegGetValueW(root, subkey, value_name, flags, nullptr, nullptr, &bytes) !=
      ERROR_SUCCESS) {
    return {};
  }
  std::wstring value(bytes / sizeof(wchar_t), L'\0');
  if (RegGetValueW(root, subkey, value_name, flags, nullptr, value.data(),
                   &bytes) != ERROR_SUCCESS) {
    return {};
  }
  while (!value.empty() && value.back() == L'\0') {
    value.pop_back();
  }
  return value;
}

class OpenXrProbe {
 public:
  OpenXrProbe() {
    constexpr auto key = L"SOFTWARE\\Khronos\\OpenXR\\1";
    auto runtime = registry_string(HKEY_CURRENT_USER, key, L"ActiveRuntime");
    if (runtime.empty()) {
      runtime = registry_string(HKEY_LOCAL_MACHINE, key, L"ActiveRuntime");
    }
    std::wcout << L"openxr.active_runtime="
               << (runtime.empty() ? L"<not registered>" : runtime) << L'\n';
    std::cout << "openxr.loader=Khronos-1.1.61-app-local\n";

    std::uint32_t extension_count{};
    const auto enumerate_result = xrEnumerateInstanceExtensionProperties(
        nullptr, 0, &extension_count, nullptr);
    if (enumerate_result == XR_ERROR_RUNTIME_UNAVAILABLE) {
      std::cout << "openxr.extension.XR_KHR_D3D12_enable=unknown\n"
                << "openxr.instance=runtime-unavailable\n";
      return;
    }
    check_xr(enumerate_result,
             "xrEnumerateInstanceExtensionProperties(count)");
    std::vector<XrExtensionProperties> extensions(
        extension_count, {XR_TYPE_EXTENSION_PROPERTIES});
    check_xr(xrEnumerateInstanceExtensionProperties(
                 nullptr, extension_count, &extension_count, extensions.data()),
             "xrEnumerateInstanceExtensionProperties(list)");
    d3d12_extension_ = std::any_of(
        extensions.begin(), extensions.end(), [](const auto& extension) {
          return std::strcmp(extension.extensionName,
                             XR_KHR_D3D12_ENABLE_EXTENSION_NAME) == 0;
        });
    std::cout << "openxr.extension.XR_KHR_D3D12_enable="
              << (d3d12_extension_ ? "available" : "unavailable") << '\n';

    const char* enabled_extensions[] = {XR_KHR_D3D12_ENABLE_EXTENSION_NAME};
    XrInstanceCreateInfo create_info{XR_TYPE_INSTANCE_CREATE_INFO};
    strcpy_s(create_info.applicationInfo.applicationName, "DarktideVR Harness");
    create_info.applicationInfo.applicationVersion = 1;
    strcpy_s(create_info.applicationInfo.engineName, "DarktideVR Synthetic");
    create_info.applicationInfo.engineVersion = 1;
    create_info.applicationInfo.apiVersion = XR_CURRENT_API_VERSION;
    if (d3d12_extension_) {
      create_info.enabledExtensionCount = 1;
      create_info.enabledExtensionNames = enabled_extensions;
    }

    auto create_result = xrCreateInstance(&create_info, &instance_);
    if (create_result == XR_ERROR_API_VERSION_UNSUPPORTED ||
        create_result == XR_ERROR_INITIALIZATION_FAILED) {
      create_info.applicationInfo.apiVersion = XR_MAKE_VERSION(1, 0, 0);
      std::cout << "openxr.api_retry=1.0\n";
      create_result = xrCreateInstance(&create_info, &instance_);
    }
    if (create_result == XR_ERROR_RUNTIME_UNAVAILABLE ||
        create_result == XR_ERROR_INITIALIZATION_FAILED) {
      std::cout << "openxr.instance="
                << (create_result == XR_ERROR_RUNTIME_UNAVAILABLE
                        ? "runtime-unavailable"
                        : "runtime-initialization-failed")
                << '\n';
      instance_ = XR_NULL_HANDLE;
      return;
    }
    check_xr(create_result, "xrCreateInstance");

    XrInstanceProperties properties{XR_TYPE_INSTANCE_PROPERTIES};
    check_xr(xrGetInstanceProperties(instance_, &properties),
             "xrGetInstanceProperties");
    std::cout << "openxr.instance=created\n"
              << "openxr.runtime_name=" << properties.runtimeName << '\n'
              << "openxr.runtime_version="
              << XR_VERSION_MAJOR(properties.runtimeVersion) << '.'
              << XR_VERSION_MINOR(properties.runtimeVersion) << '.'
              << XR_VERSION_PATCH(properties.runtimeVersion) << '\n';

    XrSystemGetInfo system_info{XR_TYPE_SYSTEM_GET_INFO};
    system_info.formFactor = XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
    const auto system_result = xrGetSystem(instance_, &system_info, &system_id_);
    if (system_result == XR_ERROR_FORM_FACTOR_UNAVAILABLE) {
      std::cout << "openxr.system=hmd-unavailable\n";
      system_id_ = XR_NULL_SYSTEM_ID;
      return;
    }
    check_xr(system_result, "xrGetSystem");
    std::cout << "openxr.system=hmd-available\n";

    std::uint32_t view_count{};
    check_xr(xrEnumerateViewConfigurationViews(
                 instance_, system_id_, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,
                 0, &view_count, nullptr),
             "xrEnumerateViewConfigurationViews(count)");
    views_.assign(
        view_count, {XR_TYPE_VIEW_CONFIGURATION_VIEW});
    check_xr(xrEnumerateViewConfigurationViews(
                 instance_, system_id_, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,
                 view_count, &view_count, views_.data()),
             "xrEnumerateViewConfigurationViews(list)");
    std::cout << "openxr.stereo_views=" << view_count << '\n';
    if (!views_.empty()) {
      std::cout << "openxr.recommended_size="
                << views_.front().recommendedImageRectWidth << 'x'
                << views_.front().recommendedImageRectHeight << '\n';
    }

    if (!d3d12_extension_) {
      return;
    }
    PFN_xrGetD3D12GraphicsRequirementsKHR get_requirements{};
    check_xr(xrGetInstanceProcAddr(
                 instance_, "xrGetD3D12GraphicsRequirementsKHR",
                 reinterpret_cast<PFN_xrVoidFunction*>(&get_requirements)),
             "xrGetInstanceProcAddr(xrGetD3D12GraphicsRequirementsKHR)");
    requirements_ = {XR_TYPE_GRAPHICS_REQUIREMENTS_D3D12_KHR};
    check_xr(get_requirements(instance_, system_id_, &*requirements_),
             "xrGetD3D12GraphicsRequirementsKHR");
    std::cout << "openxr.d3d12_min_feature_level=0x" << std::hex
              << static_cast<unsigned int>(requirements_->minFeatureLevel)
              << std::dec << '\n';
  }

  ~OpenXrProbe() noexcept {
    try {
      destroy_session();
    } catch (...) {
      force_destroy_session();
    }
    if (controller_action_set_ != XR_NULL_HANDLE) {
      xrDestroyActionSet(controller_action_set_);
      controller_action_set_ = XR_NULL_HANDLE;
    }
    if (instance_ != XR_NULL_HANDLE) {
      xrDestroyInstance(instance_);
    }
  }

  std::optional<LUID> adapter_luid() const {
    if (!requirements_) {
      return std::nullopt;
    }
    return requirements_->adapterLuid;
  }

  D3D_FEATURE_LEVEL minimum_feature_level() const {
    return requirements_ ? requirements_->minFeatureLevel
                         : D3D_FEATURE_LEVEL_12_0;
  }

  void create_session(ID3D12Device* device, ID3D12CommandQueue* queue,
                      bool create_projection_swapchains = true) {
    if (instance_ == XR_NULL_HANDLE || system_id_ == XR_NULL_SYSTEM_ID ||
        !requirements_) {
      std::cout << "openxr.session=skipped\n";
      return;
    }
    XrGraphicsBindingD3D12KHR binding{XR_TYPE_GRAPHICS_BINDING_D3D12_KHR};
    binding.device = device;
    binding.queue = queue;
    XrSessionCreateInfo session_info{XR_TYPE_SESSION_CREATE_INFO};
    session_info.next = &binding;
    session_info.systemId = system_id_;
    check_xr(xrCreateSession(instance_, &session_info, &session_),
             "xrCreateSession");

    XrReferenceSpaceCreateInfo space_info{XR_TYPE_REFERENCE_SPACE_CREATE_INFO};
    space_info.referenceSpaceType = XR_REFERENCE_SPACE_TYPE_LOCAL;
    space_info.poseInReferenceSpace.orientation.w = 1.0F;
    check_xr(xrCreateReferenceSpace(session_, &space_info, &local_space_),
             "xrCreateReferenceSpace(LOCAL)");
    space_info.referenceSpaceType = XR_REFERENCE_SPACE_TYPE_VIEW;
    check_xr(xrCreateReferenceSpace(session_, &space_info, &view_space_),
             "xrCreateReferenceSpace(VIEW)");
    create_controller_actions();

    std::uint32_t format_count{};
    check_xr(xrEnumerateSwapchainFormats(session_, 0, &format_count, nullptr),
             "xrEnumerateSwapchainFormats(count)");
    std::vector<std::int64_t> formats(format_count);
    check_xr(xrEnumerateSwapchainFormats(session_, format_count, &format_count,
                                         formats.data()),
             "xrEnumerateSwapchainFormats(list)");
    std::cout << "openxr.session=created\n"
              << "openxr.swapchain_formats=" << format_count << '\n';
    for (std::size_t index = 0; index < formats.size(); ++index) {
      std::cout << "openxr.swapchain_format[" << index
                << "]=" << formats[index] << '\n';
    }
    create_swapchains(formats, create_projection_swapchains);
  }

  void run_frame_lifecycle(std::uint32_t frame_count, ID3D12Device* device,
                           ID3D12CommandQueue* queue, bool require_rendering) {
    if (session_ == XR_NULL_HANDLE) {
      throw std::runtime_error("OpenXR frame loop requires a session");
    }

    darktidevr::harness::SyntheticScene scene(
        device, static_cast<DXGI_FORMAT>(swapchain_format_), swapchain_images_,
        views_);
    std::cout << "openxr.synthetic_triangles=" << scene.triangle_count() << '\n';

    ComPtr<ID3D12CommandAllocator> allocator;
    ComPtr<ID3D12GraphicsCommandList> command_list;
    ComPtr<ID3D12Fence> fence;
    check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
                                         IID_PPV_ARGS(&allocator)),
          "ID3D12Device::CreateCommandAllocator(XR)");
    check(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                    allocator.Get(), nullptr,
                                    IID_PPV_ARGS(&command_list)),
          "ID3D12Device::CreateCommandList(XR)");
    check(command_list->Close(), "ID3D12GraphicsCommandList::Close(XR init)");
    check(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)),
          "ID3D12Device::CreateFence(XR)");
    const auto fence_event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!fence_event) {
      throw std::runtime_error("CreateEventW(XR) failed");
    }
    UINT64 fence_value{};

    wait_until_ready();

    XrSessionBeginInfo begin_info{XR_TYPE_SESSION_BEGIN_INFO};
    begin_info.primaryViewConfigurationType =
        XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
    check_xr(xrBeginSession(session_, &begin_info), "xrBeginSession");
    session_running_ = true;
    std::cout << "openxr.lifecycle=running\n";

    std::vector<XrView> located_views(views_.size(), {XR_TYPE_VIEW});
    std::vector<XrCompositionLayerProjectionView> projection_views(
        views_.size(), {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW});
    std::uint32_t submitted_frames{};
    std::uint32_t not_rendered_frames{};
    const auto xr_start = std::chrono::steady_clock::now();
    for (std::uint32_t frame = 0; frame < frame_count; ++frame) {
      poll_session_events();
      XrFrameWaitInfo wait_info{XR_TYPE_FRAME_WAIT_INFO};
      XrFrameState frame_state{XR_TYPE_FRAME_STATE};
      check_xr(xrWaitFrame(session_, &wait_info, &frame_state), "xrWaitFrame");
      XrFrameBeginInfo frame_begin{XR_TYPE_FRAME_BEGIN_INFO};
      check_xr(xrBeginFrame(session_, &frame_begin), "xrBeginFrame");

      bool submit_layer = frame_state.shouldRender == XR_TRUE;
      XrViewState view_state{XR_TYPE_VIEW_STATE};
      std::uint32_t located_count{};
      if (submit_layer) {
        XrViewLocateInfo locate_info{XR_TYPE_VIEW_LOCATE_INFO};
        locate_info.viewConfigurationType =
            XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
        locate_info.displayTime = frame_state.predictedDisplayTime;
        locate_info.space = local_space_;
        check_xr(xrLocateViews(session_, &locate_info, &view_state,
                               static_cast<std::uint32_t>(located_views.size()),
                               &located_count, located_views.data()),
                 "xrLocateViews");
        const auto valid_flags = XR_VIEW_STATE_POSITION_VALID_BIT |
                                 XR_VIEW_STATE_ORIENTATION_VALID_BIT;
        submit_layer = located_count == located_views.size() &&
                       (view_state.viewStateFlags & valid_flags) == valid_flags;
      }

      std::vector<std::uint32_t> acquired_indices(swapchains_.size());
      if (submit_layer) {
        check(allocator->Reset(), "ID3D12CommandAllocator::Reset(XR)");
        check(command_list->Reset(allocator.Get(), nullptr),
              "ID3D12GraphicsCommandList::Reset(XR)");
        for (std::size_t eye = 0; eye < swapchains_.size(); ++eye) {
          XrSwapchainImageAcquireInfo acquire_info{
              XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
          check_xr(xrAcquireSwapchainImage(swapchains_[eye], &acquire_info,
                                           &acquired_indices[eye]),
                   "xrAcquireSwapchainImage");
          XrSwapchainImageWaitInfo image_wait{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};
          image_wait.timeout = XR_INFINITE_DURATION;
          check_xr(xrWaitSwapchainImage(swapchains_[eye], &image_wait),
                   "xrWaitSwapchainImage");

          auto* resource = swapchain_images_[eye][acquired_indices[eye]].texture;
          D3D12_RESOURCE_BARRIER to_render{};
          to_render.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
          to_render.Transition.pResource = resource;
          to_render.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
          to_render.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
          to_render.Transition.Subresource =
              D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
          command_list->ResourceBarrier(1, &to_render);

          scene.record(command_list.Get(), eye, acquired_indices[eye],
                       located_views[eye], frame);

          std::swap(to_render.Transition.StateBefore,
                    to_render.Transition.StateAfter);
          command_list->ResourceBarrier(1, &to_render);

          projection_views[eye] = {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW};
          projection_views[eye].pose = located_views[eye].pose;
          projection_views[eye].fov = located_views[eye].fov;
          projection_views[eye].subImage.swapchain = swapchains_[eye];
          projection_views[eye].subImage.imageRect.extent = {
              static_cast<std::int32_t>(views_[eye].recommendedImageRectWidth),
              static_cast<std::int32_t>(views_[eye].recommendedImageRectHeight)};
          projection_views[eye].subImage.imageArrayIndex = 0;
        }
        check(command_list->Close(), "ID3D12GraphicsCommandList::Close(XR)");
        ID3D12CommandList* lists[]{command_list.Get()};
        queue->ExecuteCommandLists(1, lists);
        const auto signal_value = ++fence_value;
        check(queue->Signal(fence.Get(), signal_value),
              "ID3D12CommandQueue::Signal(XR)");
        if (fence->GetCompletedValue() < signal_value) {
          check(fence->SetEventOnCompletion(signal_value, fence_event),
                "ID3D12Fence::SetEventOnCompletion(XR)");
          WaitForSingleObject(fence_event, INFINITE);
        }
        for (const auto swapchain : swapchains_) {
          XrSwapchainImageReleaseInfo release_info{
              XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
          check_xr(xrReleaseSwapchainImage(swapchain, &release_info),
                   "xrReleaseSwapchainImage");
        }
        ++submitted_frames;
      } else {
        ++not_rendered_frames;
      }

      XrCompositionLayerProjection projection{
          XR_TYPE_COMPOSITION_LAYER_PROJECTION};
      projection.space = local_space_;
      projection.viewCount = static_cast<std::uint32_t>(projection_views.size());
      projection.views = projection_views.data();
      const auto* layer = reinterpret_cast<const XrCompositionLayerBaseHeader*>(
          &projection);
      XrFrameEndInfo frame_end{XR_TYPE_FRAME_END_INFO};
      frame_end.displayTime = frame_state.predictedDisplayTime;
      frame_end.environmentBlendMode = environment_blend_mode_;
      frame_end.layerCount = submit_layer ? 1U : 0U;
      frame_end.layers = submit_layer ? &layer : nullptr;
      check_xr(xrEndFrame(session_, &frame_end), "xrEndFrame");
      poll_session_events();
    }
    CloseHandle(fence_event);
    const auto xr_elapsed = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - xr_start);
    std::cout << "openxr.frames=" << frame_count << '\n';
    std::cout << "openxr.submitted_frames=" << submitted_frames << '\n';
    std::cout << "openxr.not_rendered_frames=" << not_rendered_frames << '\n';
    std::cout << "openxr.elapsed_ms=" << xr_elapsed.count() << '\n';
    std::cout << "openxr.submit_hz="
              << (xr_elapsed.count() > 0.0
                      ? static_cast<double>(frame_count) * 1000.0 /
                            xr_elapsed.count()
                      : 0.0)
              << '\n';
    std::cout << "openxr.projection=synthetic-depth-scene\n";
    if (require_rendering && submitted_frames == 0) {
      request_clean_exit();
      throw std::runtime_error(
          "Runtime completed the frame loop without allowing projection submission");
    }
    request_clean_exit();
  }

  void run_theatre_lifecycle(std::uint32_t frame_count, ID3D12Device* device,
                             ID3D12CommandQueue* queue,
                              bool require_rendering,
                              std::optional<std::chrono::seconds> duration,
                              const std::optional<std::wstring>& capture_title,
                               bool stereo_sbs, bool stereo_top_bottom,
                               bool shared_eyes,
                               std::int64_t shared_pose_sequence_offset,
                               bool pair_driven_shared,
                               bool separate_shared_eye_swapchains,
                               bool enable_menu_input,
                               const std::wstring& menu_input_title,
                               bool synthetic_controller_path,
                               bool synthetic_gameplay_input) {
    if (session_ == XR_NULL_HANDLE || view_space_ == XR_NULL_HANDLE) {
      throw std::runtime_error("OpenXR theatre loop requires a session and VIEW space");
    }

    // Preserve the native 4K SBS source for stereo. The earlier 1920x1080
    // bridge reduced each eye to only 960x1080 before OpenXR sampled it.
    // Theatre mode keeps its lower-cost 1080p surface.
    separate_shared_eye_swapchains =
        shared_eyes && separate_shared_eye_swapchains;
    const bool stereo_top_bottom_layout =
        stereo_top_bottom ||
        (shared_eyes && !separate_shared_eye_swapchains);
    const bool stereo = stereo_sbs || stereo_top_bottom_layout || shared_eyes;
    // The application render and OpenXR swapchain extents follow the runtime's
    // exact recommendation. Lens distortion and hidden-area sampling belong to
    // the runtime; the game must supply the corresponding asymmetric frusta.
    const std::uint32_t shared_eye_width =
        views_.front().recommendedImageRectWidth;
    const std::uint32_t shared_eye_height =
        views_.front().recommendedImageRectHeight;
    const std::uint32_t width = stereo_top_bottom_layout
                                    ? (shared_eyes ? shared_eye_width : 2160U)
                                    : (separate_shared_eye_swapchains
                                           ? shared_eye_width
                                           : (stereo ? 3840U : 1920U));
    const std::uint32_t height = stereo_top_bottom_layout
                                     ? (shared_eyes ? shared_eye_height * 2U
                                                    : 4320U)
                                     : (separate_shared_eye_swapchains
                                            ? shared_eye_height
                                            : (stereo ? 2160U : 1080U));
    const std::uint32_t flat_capture_height =
        shared_eyes
            ? (separate_shared_eye_swapchains ? height : height / 2)
            : height;
    XrSwapchainCreateInfo swapchain_info{XR_TYPE_SWAPCHAIN_CREATE_INFO};
    swapchain_info.usageFlags = XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT |
                                XR_SWAPCHAIN_USAGE_SAMPLED_BIT;
    swapchain_info.format = swapchain_format_;
    swapchain_info.sampleCount = 1;
    swapchain_info.width = width;
    swapchain_info.height = height;
    swapchain_info.faceCount = 1;
    swapchain_info.arraySize = 1;
    swapchain_info.mipCount = 1;
    const std::size_t theatre_swapchain_count =
        separate_shared_eye_swapchains ? 2U : 1U;
    std::vector<XrSwapchain> theatre_swapchains(
        theatre_swapchain_count, XR_NULL_HANDLE);
    std::vector<std::vector<XrSwapchainImageD3D12KHR>> theatre_images(
        theatre_swapchain_count);
    std::vector<std::size_t> rtv_base_offsets(theatre_swapchain_count);
    std::uint32_t total_image_count{};
    for (std::size_t eye = 0; eye < theatre_swapchain_count; ++eye) {
      check_xr(xrCreateSwapchain(session_, &swapchain_info,
                                 &theatre_swapchains[eye]),
               "xrCreateSwapchain(theatre)");
      std::uint32_t image_count{};
      check_xr(xrEnumerateSwapchainImages(theatre_swapchains[eye], 0,
                                          &image_count, nullptr),
               "xrEnumerateSwapchainImages(theatre count)");
      theatre_images[eye].assign(
          image_count, {XR_TYPE_SWAPCHAIN_IMAGE_D3D12_KHR});
      check_xr(xrEnumerateSwapchainImages(
                   theatre_swapchains[eye], image_count, &image_count,
                   reinterpret_cast<XrSwapchainImageBaseHeader*>(
                       theatre_images[eye].data())),
               "xrEnumerateSwapchainImages(theatre list)");
      rtv_base_offsets[eye] = total_image_count;
      total_image_count += image_count;
    }

    D3D12_DESCRIPTOR_HEAP_DESC heap_info{};
    heap_info.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    heap_info.NumDescriptors = total_image_count;
    ComPtr<ID3D12DescriptorHeap> rtv_heap;
    check(device->CreateDescriptorHeap(&heap_info, IID_PPV_ARGS(&rtv_heap)),
          "ID3D12Device::CreateDescriptorHeap(theatre)");
    const auto rtv_increment = device->GetDescriptorHandleIncrementSize(
        D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    auto rtv = rtv_heap->GetCPUDescriptorHandleForHeapStart();
    D3D12_RENDER_TARGET_VIEW_DESC rtv_view{};
    rtv_view.Format = static_cast<DXGI_FORMAT>(swapchain_format_);
    rtv_view.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
    for (const auto& eye_images : theatre_images) {
      for (const auto& image : eye_images) {
        device->CreateRenderTargetView(image.texture, &rtv_view, rtv);
        rtv.ptr += rtv_increment;
      }
    }

    std::unique_ptr<darktidevr::harness::WindowCapture> window_capture;
    ComPtr<ID3D12Resource> upload;
    std::byte* upload_pixels{};
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT upload_footprint{};
    using CapturePixels = std::vector<std::byte>;
    std::atomic<std::shared_ptr<const CapturePixels>> latest_capture;
    std::atomic<std::shared_ptr<const std::string>> capture_error;
    std::atomic<std::uint64_t> capture_failures_total{0};
    std::shared_ptr<const CapturePixels> consumed_capture;
    std::jthread capture_thread;
    if (capture_title) {
      window_capture = std::make_unique<darktidevr::harness::WindowCapture>(
          *capture_title, width, flat_capture_height);
      const auto texture_description =
          theatre_images.front().front().texture->GetDesc();
      UINT64 upload_bytes{};
      device->GetCopyableFootprints(&texture_description, 0, 1, 0,
                                    &upload_footprint, nullptr, nullptr,
                                    &upload_bytes);
      D3D12_HEAP_PROPERTIES upload_heap{};
      upload_heap.Type = D3D12_HEAP_TYPE_UPLOAD;
      upload_heap.CreationNodeMask = 1;
      upload_heap.VisibleNodeMask = 1;
      D3D12_RESOURCE_DESC upload_description{};
      upload_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
      upload_description.Width = upload_bytes;
      upload_description.Height = 1;
      upload_description.DepthOrArraySize = 1;
      upload_description.MipLevels = 1;
      upload_description.SampleDesc.Count = 1;
      upload_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
      check(device->CreateCommittedResource(
                &upload_heap, D3D12_HEAP_FLAG_NONE, &upload_description,
                D3D12_RESOURCE_STATE_GENERIC_READ, nullptr,
                IID_PPV_ARGS(&upload)),
            "ID3D12Device::CreateCommittedResource(theatre upload)");
      check(upload->Map(0, nullptr,
                        reinterpret_cast<void**>(&upload_pixels)),
            "ID3D12Resource::Map(theatre upload)");

      const auto capture_rgba =
          [&window_capture, width, flat_capture_height] {
        const auto captured = window_capture->capture();
        auto converted =
            std::make_shared<CapturePixels>(static_cast<std::size_t>(width) *
                                            flat_capture_height * 4);
        for (std::uint32_t y = 0; y < captured.height; ++y) {
          const auto* source = captured.bgra_pixels +
                               static_cast<std::size_t>(y) *
                                   captured.row_pitch;
          auto* destination = converted->data() +
                              static_cast<std::size_t>(y) * width * 4;
          for (std::uint32_t x = 0; x < captured.width; ++x) {
            destination[x * 4] = source[x * 4 + 2];
            destination[x * 4 + 1] = source[x * 4 + 1];
            destination[x * 4 + 2] = source[x * 4];
            destination[x * 4 + 3] = source[x * 4 + 3];
          }
        }
        return std::shared_ptr<const CapturePixels>(std::move(converted));
      };
      latest_capture.store(capture_rgba(), std::memory_order_release);
      capture_thread = std::jthread(
          [capture_rgba, &latest_capture,
           &capture_error,
           &capture_failures_total](std::stop_token stop_token) {
            auto next_capture = std::chrono::steady_clock::now();
            while (!stop_token.stop_requested()) {
              next_capture += std::chrono::milliseconds(33);
              try {
                latest_capture.store(capture_rgba(),
                                     std::memory_order_release);
                capture_error.store(nullptr, std::memory_order_release);
              } catch (const std::exception& error) {
                capture_failures_total.fetch_add(1, std::memory_order_relaxed);
                capture_error.store(
                    std::make_shared<const std::string>(error.what()),
                    std::memory_order_release);
              }
              std::this_thread::sleep_until(next_capture);
            }
          });
    }

    std::optional<darktidevr::bridge::OpenedEyeSurfaces> opened_eyes;
    std::unique_ptr<darktidevr::core::SharedHeadPoseWriter> head_pose_writer;
    const darktidevr::bridge::SharedEyeSurfaceNames shared_eye_names{
        {L"Local\\DarktideVR-eye-left", L"Local\\DarktideVR-eye-right"},
        L"Local\\DarktideVR-eye-ready",
        L"Local\\DarktideVR-eye-consumed"};
    UINT64 shared_last_ready_value{};
    auto shared_last_advance = std::chrono::steady_clock::now();
    auto next_shared_open_attempt = std::chrono::steady_clock::now();
    HANDLE projection_active_event{};
    darktidevr::core::SharedPresentationStateReader presentation_state_reader;
    darktidevr::core::SharedPresentationState presentation_state{};
    std::uint64_t presentation_sequence{};
    darktidevr::core::MenuPointerInputState menu_pointer_state;
    std::unique_ptr<darktidevr::harness::MenuInputInjector>
        menu_input_injector;
    std::uint64_t menu_input_events{};
    std::uint64_t menu_input_dispatched{};
    if (enable_menu_input) {
      menu_input_injector =
          std::make_unique<darktidevr::harness::MenuInputInjector>(
              menu_input_title);
      std::cout << "openxr.menu_input=enabled\n";
    } else {
      std::cout << "openxr.menu_input=disabled\n";
    }
    if (shared_eyes) {
      head_pose_writer =
          std::make_unique<darktidevr::core::SharedHeadPoseWriter>();
    }

    ComPtr<ID3D12CommandAllocator> allocator;
    ComPtr<ID3D12GraphicsCommandList> command_list;
    ComPtr<ID3D12Fence> fence;
    check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
                                         IID_PPV_ARGS(&allocator)),
          "ID3D12Device::CreateCommandAllocator(theatre)");
    check(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                    allocator.Get(), nullptr,
                                    IID_PPV_ARGS(&command_list)),
          "ID3D12Device::CreateCommandList(theatre)");
    check(command_list->Close(),
          "ID3D12GraphicsCommandList::Close(theatre init)");
    check(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                              IID_PPV_ARGS(&fence)),
          "ID3D12Device::CreateFence(theatre)");
    const auto fence_event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!fence_event) {
      for (const auto swapchain : theatre_swapchains) {
        if (swapchain != XR_NULL_HANDLE) {
          xrDestroySwapchain(swapchain);
        }
      }
      throw std::runtime_error("CreateEventW(theatre) failed");
    }
    UINT64 fence_value{};

    wait_until_ready();
    XrSessionBeginInfo begin_info{XR_TYPE_SESSION_BEGIN_INFO};
    begin_info.primaryViewConfigurationType =
        XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
    check_xr(xrBeginSession(session_, &begin_info), "xrBeginSession(theatre)");
    session_running_ = true;
    std::uint32_t submitted_frames{};
    std::uint32_t not_rendered_frames{};
    std::uint32_t capture_updates{};
    std::uint32_t capture_stale_frames{};
    std::uint32_t flat_fallback_frames{};
    std::uint32_t flat_fallback_transitions{};
    bool flat_fallback_active{};
    std::uint64_t flat_fallback_anchored_sequence{};
    XrPosef flat_fallback_pose{{0.0F, 0.0F, 0.0F, 1.0F},
                               {0.0F, 0.0F, -2.0F}};
    bool flat_fallback_pose_valid{};
    std::vector<XrView> located_views(views_.size(), {XR_TYPE_VIEW});
    std::vector<XrCompositionLayerProjectionView> projection_views(
        views_.size(), {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW});
    bool stereo_fov_logged{};
    std::optional<darktidevr::math::Pose> head_recenter_pose;
    controller_recenter_pose_.reset();
    std::uint64_t head_pose_sequence{};
    std::array<XrPosef, 2> recentered_view_poses{};
    bool recentered_view_poses_valid{};
    std::deque<std::pair<std::uint64_t, std::array<XrPosef, 2>>>
        head_pose_history;
    std::array<XrPosef, 2> rendered_pair_view_poses{};
    std::uint64_t rendered_pair_pose_ready_value{};
    std::uint64_t last_pair_pose_checked_ready_value{};
    std::uint64_t last_submitted_shared_value{};
    std::uint64_t fresh_shared_pairs{};
    std::uint64_t reused_shared_frames{};
    std::uint64_t pair_pose_mismatches{};
    std::uint64_t pair_pose_sequence_lag_sum{};
    std::uint64_t pair_pose_sequence_lag_samples{};
    std::uint64_t pair_pose_sequence_lag_max{};
    double pair_pose_angle_lag_degrees_sum{};
    double pair_pose_angle_lag_degrees_max{};
    std::uint64_t pair_driven_waits{};
    std::uint64_t pair_driven_timeouts{};
    const auto start = std::chrono::steady_clock::now();
    auto last_live_report = start;
    std::uint32_t last_live_submitted_frames{};
    std::uint64_t last_live_fresh_shared_pairs{};
    std::uint32_t last_live_fallback_frames{};
    std::uint32_t processed_frames{};
    constexpr auto shared_stale_after = std::chrono::milliseconds(500);
    const float render_aspect_ratio =
        separate_shared_eye_swapchains
            ? static_cast<float>(width) / static_cast<float>(height)
            : (stereo_top_bottom_layout
                   ? static_cast<float>(width) /
                         static_cast<float>(height / 2)
                   : static_cast<float>(width / 2) /
                         static_cast<float>(height));
    XrFovf rendered_symmetric_fov{};
    std::vector<std::uint32_t> image_indices(theatre_swapchain_count);
    std::vector<ID3D12Resource*> resources(theatre_swapchain_count);
    std::vector<D3D12_RESOURCE_BARRIER> destination_barriers(
        theatre_swapchain_count);

    for (std::uint32_t frame = 0; frame < frame_count; ++frame) {
      if (duration && std::chrono::steady_clock::now() - start >= *duration) {
        break;
      }
      const auto frame_start = std::chrono::steady_clock::now();
      if (shared_eyes && !projection_active_event) {
        projection_active_event = OpenEventW(
            SYNCHRONIZE, FALSE,
            L"Local\\DarktideVR-projection-active-v1");
      }
      const bool projection_active =
          !shared_eyes || [&] {
            darktidevr::core::SharedPresentationState newest{};
            if (presentation_state_reader.read(newest)) {
              presentation_state = newest;
              presentation_sequence = newest.sequence;
              return newest.mode == darktidevr::core::
                                        SharedPresentationMode::stereo_world;
            }
            return projection_active_event &&
                   WaitForSingleObject(projection_active_event, 0) ==
                       WAIT_OBJECT_0;
          }();
      if (shared_eyes && !opened_eyes &&
          frame_start >= next_shared_open_attempt) {
        next_shared_open_attempt = frame_start + std::chrono::milliseconds(250);
        try {
          opened_eyes = darktidevr::bridge::open_shared_eye_surfaces(
              device, shared_eye_names,
              {{shared_eye_width, shared_eye_height},
               DXGI_FORMAT_R8G8B8A8_UNORM});
          shared_last_ready_value =
              opened_eyes->ready_fence->GetCompletedValue();
          shared_last_advance = frame_start;
          if (shared_last_ready_value != 0) {
            // A pair published before attachment has no bridge-side pose
            // history. Acknowledge it so the producer can publish a pair
            // associated with the live XR pose stream.
            check(opened_eyes->consumed_fence->Signal(
                      shared_last_ready_value),
                  "ID3D12Fence::Signal(initial untagged pair consumed)");
          }
          std::cout << "openxr.shared_eyes=attached\n";
        } catch (const std::exception&) {
          // The title and loading screens legitimately precede the game's
          // producer-owned eye surfaces. Keep publishing XR state and retry
          // while the spatial flat fallback remains visible.
        }
      }
      if (pair_driven_shared && projection_active && opened_eyes &&
          last_pair_pose_checked_ready_value != 0) {
        ++pair_driven_waits;
        const auto now = std::chrono::steady_clock::now();
        // Follow the producer at its real cadence, including rates below
        // 30 Hz. Once no pair has arrived for the same 500 ms interval used by
        // flat fallback, wake at 30 Hz so loading/error presentation remains
        // responsive without pretending those are fresh game frames.
        const auto deadline =
            now - shared_last_advance < shared_stale_after
                ? shared_last_advance + shared_stale_after
                : now + std::chrono::milliseconds(33);
        while (opened_eyes->ready_fence->GetCompletedValue() <=
                   last_pair_pose_checked_ready_value &&
               std::chrono::steady_clock::now() < deadline) {
          std::this_thread::sleep_for(std::chrono::microseconds(500));
        }
        if (opened_eyes->ready_fence->GetCompletedValue() <=
            last_pair_pose_checked_ready_value) {
          ++pair_driven_timeouts;
        }
      }
      poll_session_events();
      XrFrameWaitInfo wait_info{XR_TYPE_FRAME_WAIT_INFO};
      XrFrameState frame_state{XR_TYPE_FRAME_STATE};
      check_xr(xrWaitFrame(session_, &wait_info, &frame_state),
               "xrWaitFrame(theatre)");
      XrFrameBeginInfo frame_begin{XR_TYPE_FRAME_BEGIN_INFO};
      check_xr(xrBeginFrame(session_, &frame_begin), "xrBeginFrame(theatre)");
      if (!synthetic_controller_path) {
        sync_controller_actions(frame_state.predictedDisplayTime);
      }

      bool submit_layer = frame_state.shouldRender == XR_TRUE;
      darktidevr::math::Pose current_head{};
      bool current_head_valid{};
      if (stereo && submit_layer) {
        XrViewState view_state{XR_TYPE_VIEW_STATE};
        XrViewLocateInfo locate_info{XR_TYPE_VIEW_LOCATE_INFO};
        locate_info.viewConfigurationType =
            XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
        locate_info.displayTime = frame_state.predictedDisplayTime;
        locate_info.space = local_space_;
        std::uint32_t located_count{};
        check_xr(xrLocateViews(session_, &locate_info, &view_state,
                               static_cast<std::uint32_t>(located_views.size()),
                               &located_count, located_views.data()),
                 "xrLocateViews(theatre stereo)");
        const auto valid_flags = XR_VIEW_STATE_POSITION_VALID_BIT |
                                 XR_VIEW_STATE_ORIENTATION_VALID_BIT;
        submit_layer = located_count == located_views.size() &&
                       (view_state.viewStateFlags & valid_flags) == valid_flags;
        if (submit_layer) {
          const float average_vertical_span =
              ((located_views[0].fov.angleUp -
                located_views[0].fov.angleDown) +
               (located_views[1].fov.angleUp -
                located_views[1].fov.angleDown)) *
              0.5F;
          rendered_symmetric_fov =
              {0.0F, 0.0F, average_vertical_span * 0.5F,
               average_vertical_span * -0.5F};
          current_head.position = {
              (located_views[0].pose.position.x +
               located_views[1].pose.position.x) *
                  0.5F,
              (located_views[0].pose.position.y +
               located_views[1].pose.position.y) *
                  0.5F,
              (located_views[0].pose.position.z +
               located_views[1].pose.position.z) *
                  0.5F};
          current_head.orientation = {
              located_views[0].pose.orientation.x,
              located_views[0].pose.orientation.y,
              located_views[0].pose.orientation.z,
              located_views[0].pose.orientation.w};
          current_head_valid = true;
        }
        if (submit_layer && head_pose_writer) {
          if (!head_recenter_pose) {
            head_recenter_pose = current_head;
            controller_recenter_pose_ = current_head;
          }
          const auto delta = darktidevr::core::recentered_head_delta(
              *head_recenter_pose, current_head, {0.25F, 0.18F});
          darktidevr::core::SharedHeadPoseSample pose_sample{};
          pose_sample.sequence = ++head_pose_sequence;
          pose_sample.pose = delta;
          pose_sample.render_vertical_fov_radians =
              rendered_symmetric_fov.angleUp -
              rendered_symmetric_fov.angleDown;
          pose_sample.render_aspect_ratio = render_aspect_ratio;
          pose_sample.render_width =
              views_.front().recommendedImageRectWidth;
          pose_sample.render_height =
              views_.front().recommendedImageRectHeight;
          const auto eye_dx = located_views[1].pose.position.x -
                              located_views[0].pose.position.x;
          const auto eye_dy = located_views[1].pose.position.y -
                              located_views[0].pose.position.y;
          const auto eye_dz = located_views[1].pose.position.z -
                              located_views[0].pose.position.z;
          pose_sample.ipd_metres =
              std::sqrt(eye_dx * eye_dx + eye_dy * eye_dy + eye_dz * eye_dz);
          runtime_ipd_metres_ = pose_sample.ipd_metres;
          for (std::size_t eye = 0; eye < located_views.size(); ++eye) {
            pose_sample.render_frusta[eye] = {
                located_views[eye].fov.angleLeft,
                located_views[eye].fov.angleRight,
                located_views[eye].fov.angleDown,
                located_views[eye].fov.angleUp};
          }
          if (!head_pose_writer->publish(pose_sample)) {
            throw std::runtime_error("Shared head-pose publication failed");
          }
          for (std::size_t eye = 0; eye < located_views.size(); ++eye) {
            const darktidevr::math::Pose current_eye{
                {located_views[eye].pose.orientation.x,
                 located_views[eye].pose.orientation.y,
                 located_views[eye].pose.orientation.z,
                 located_views[eye].pose.orientation.w},
                {located_views[eye].pose.position.x,
                 located_views[eye].pose.position.y,
                 located_views[eye].pose.position.z}};
            // Projection layers are submitted in absolute LOCAL space. The
            // game camera consumes a delta from the first tracked head pose,
            // so anchor that same full 6DoF delta back onto the exact pose
            // which established the baseline. The helper also preserves the
            // runtime eye-from-head transform (including physical IPD).
            const auto anchored_eye =
                darktidevr::core::anchored_recentered_eye_pose(
                    *head_recenter_pose, delta, current_head, current_eye);
            recentered_view_poses[eye].orientation = {
                anchored_eye.orientation.x, anchored_eye.orientation.y,
                anchored_eye.orientation.z, anchored_eye.orientation.w};
            recentered_view_poses[eye].position = {
                anchored_eye.position.x, anchored_eye.position.y,
                anchored_eye.position.z};
          }
          recentered_view_poses_valid = true;
          head_pose_history.emplace_back(head_pose_sequence,
                                         recentered_view_poses);
          while (head_pose_history.size() > 512) {
            head_pose_history.pop_front();
          }
        }
      }
      bool submitted_shared_pair_this_frame{};
      bool submitted_flat_fallback_this_frame{};
      if (submit_layer) {
        XrSwapchainImageAcquireInfo acquire_info{
            XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
        XrSwapchainImageWaitInfo image_wait{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};
        image_wait.timeout = XR_INFINITE_DURATION;
        for (std::size_t eye = 0; eye < theatre_swapchain_count; ++eye) {
          check_xr(xrAcquireSwapchainImage(theatre_swapchains[eye],
                                           &acquire_info,
                                           &image_indices[eye]),
                   "xrAcquireSwapchainImage(theatre)");
          check_xr(xrWaitSwapchainImage(theatre_swapchains[eye], &image_wait),
                   "xrWaitSwapchainImage(theatre)");
          resources[eye] = theatre_images[eye][image_indices[eye]].texture;
        }

        check(allocator->Reset(),
              "ID3D12CommandAllocator::Reset(theatre)");
        check(command_list->Reset(allocator.Get(), nullptr),
              "ID3D12GraphicsCommandList::Reset(theatre)");
        UINT64 shared_ready_for_frame{};
        bool discard_shared_pair_this_frame =
            opened_eyes && !projection_active;
        if (opened_eyes) {
          shared_ready_for_frame =
              opened_eyes->ready_fence->GetCompletedValue();
          if (shared_ready_for_frame > shared_last_ready_value) {
            shared_last_ready_value = shared_ready_for_frame;
            shared_last_advance = std::chrono::steady_clock::now();
          }
        }
        if (head_pose_writer && shared_ready_for_frame != 0 &&
            shared_ready_for_frame != last_pair_pose_checked_ready_value) {
          last_pair_pose_checked_ready_value = shared_ready_for_frame;
          darktidevr::core::SharedRenderedEyePairPose rendered_pair{};
          const auto tag_available =
              head_pose_writer->read_rendered_pair(rendered_pair);
          const auto tag_matches =
              tag_available &&
              rendered_pair.ready_value == shared_ready_for_frame &&
              rendered_pair.eye_pose_sequences[0] ==
                  rendered_pair.eye_pose_sequences[1];
          bool history_match{};
          if (tag_matches) {
            const auto tagged_sequence =
                rendered_pair.eye_pose_sequences[0];
            const auto target_sequence_signed =
                static_cast<std::int64_t>(tagged_sequence) +
                shared_pose_sequence_offset;
            for (auto entry = head_pose_history.rbegin();
                 entry != head_pose_history.rend(); ++entry) {
              if (target_sequence_signed > 0 &&
                  entry->first ==
                      static_cast<std::uint64_t>(target_sequence_signed)) {
                rendered_pair_view_poses = entry->second;
                rendered_pair_pose_ready_value = shared_ready_for_frame;
                history_match = true;
                if (head_pose_sequence >=
                    rendered_pair.eye_pose_sequences[0]) {
                  const auto sequence_lag = head_pose_sequence -
                                            rendered_pair.eye_pose_sequences[0];
                  pair_pose_sequence_lag_sum += sequence_lag;
                  ++pair_pose_sequence_lag_samples;
                  pair_pose_sequence_lag_max = std::max(
                      pair_pose_sequence_lag_max, sequence_lag);

                  const auto& rendered_orientation =
                      rendered_pair_view_poses[0].orientation;
                  const auto& current_orientation =
                      recentered_view_poses[0].orientation;
                  const auto dot = std::clamp(std::abs(
                      static_cast<double>(rendered_orientation.x) *
                          current_orientation.x +
                      static_cast<double>(rendered_orientation.y) *
                          current_orientation.y +
                      static_cast<double>(rendered_orientation.z) *
                          current_orientation.z +
                      static_cast<double>(rendered_orientation.w) *
                          current_orientation.w), 0.0, 1.0);
                  constexpr double radians_to_degrees =
                      57.295779513082320876;
                  const auto angle_lag_degrees =
                      2.0 * std::acos(dot) * radians_to_degrees;
                  pair_pose_angle_lag_degrees_sum += angle_lag_degrees;
                  pair_pose_angle_lag_degrees_max = std::max(
                      pair_pose_angle_lag_degrees_max,
                      angle_lag_degrees);
                }
                break;
              }
            }
          }
          if (!tag_matches || !history_match) {
            ++pair_pose_mismatches;
            discard_shared_pair_this_frame = true;
          }
        }
        const bool shared_pair_fresh =
            opened_eyes &&
            std::chrono::steady_clock::now() - shared_last_advance <=
                shared_stale_after;
        const bool shared_pair_pose_synced =
            rendered_pair_pose_ready_value == shared_ready_for_frame;
        const bool use_shared_pair =
            projection_active && opened_eyes &&
            (!window_capture ||
             (shared_pair_fresh && shared_pair_pose_synced));
        submitted_shared_pair_this_frame = use_shared_pair;
        const bool use_flat_capture = window_capture && !use_shared_pair;
        submitted_flat_fallback_this_frame = use_flat_capture;
        if (window_capture) {
          const auto flat_presentation_changed =
              use_flat_capture && presentation_sequence != 0 &&
              presentation_sequence != flat_fallback_anchored_sequence;
          if (use_flat_capture != flat_fallback_active ||
              flat_presentation_changed) {
            flat_fallback_active = use_flat_capture;
            ++flat_fallback_transitions;
            if (flat_fallback_active && current_head_valid) {
              const auto world_anchored =
                  presentation_state.mode == darktidevr::core::
                                                 SharedPresentationMode::
                                                     world_anchored_menu &&
                  presentation_state.body_panel_pose_valid &&
                  controller_recenter_pose_.has_value();
              const auto anchored = world_anchored
                                        ? darktidevr::core::
                                              anchored_body_panel_pose(
                                                  *controller_recenter_pose_,
                                                  presentation_state.
                                                      body_panel_pose)
                                        : darktidevr::core::
                                              horizon_locked_panel_pose(
                                                  current_head, 2.0F);
              flat_fallback_pose.orientation = {
                  anchored.orientation.x, anchored.orientation.y,
                  anchored.orientation.z, anchored.orientation.w};
              flat_fallback_pose.position = {
                  anchored.position.x, anchored.position.y,
                  anchored.position.z};
              flat_fallback_pose_valid = true;
              flat_fallback_anchored_sequence = presentation_sequence;
            } else if (!flat_fallback_active) {
              flat_fallback_pose_valid = false;
              flat_fallback_anchored_sequence = 0;
            }
          }
          if (use_flat_capture) {
            ++flat_fallback_frames;
          }
        }
        for (std::size_t eye = 0; eye < theatre_swapchain_count; ++eye) {
          auto& barrier = destination_barriers[eye];
          barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
          barrier.Transition.pResource = resources[eye];
          barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
          barrier.Transition.StateAfter =
              (window_capture || opened_eyes)
                  ? D3D12_RESOURCE_STATE_COPY_DEST
                  : D3D12_RESOURCE_STATE_RENDER_TARGET;
          barrier.Transition.Subresource =
              D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        }
        command_list->ResourceBarrier(
            static_cast<UINT>(destination_barriers.size()),
            destination_barriers.data());
        if (use_flat_capture) {
          const auto newest = latest_capture.load(std::memory_order_acquire);
          if (newest && newest != consumed_capture) {
            for (std::uint32_t y = 0; y < height; ++y) {
              const auto* source = newest->data() +
                                   static_cast<std::size_t>(
                                       y % flat_capture_height) *
                                       width * 4;
              auto* destination = upload_pixels + upload_footprint.Offset +
                                  static_cast<std::size_t>(y) *
                                      upload_footprint.Footprint.RowPitch;
              std::memcpy(destination, source,
                          static_cast<std::size_t>(width) * 4);
            }
            consumed_capture = newest;
            ++capture_updates;
          } else if (capture_error.load(std::memory_order_acquire)) {
            ++capture_stale_frames;
          }
          D3D12_TEXTURE_COPY_LOCATION source{};
          source.pResource = upload.Get();
          source.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
          source.PlacedFootprint = upload_footprint;
          for (auto* destination_resource : resources) {
            D3D12_TEXTURE_COPY_LOCATION destination{};
            destination.pResource = destination_resource;
            destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            destination.SubresourceIndex = 0;
            command_list->CopyTextureRegion(&destination, 0, 0, 0, &source,
                                            nullptr);
          }
        } else if (use_shared_pair) {
          if (shared_ready_for_frame != last_submitted_shared_value) {
            last_submitted_shared_value = shared_ready_for_frame;
            ++fresh_shared_pairs;
          } else {
            ++reused_shared_frames;
          }
          for (std::size_t eye = 0; eye < opened_eyes->eyes.size(); ++eye) {
            D3D12_RESOURCE_BARRIER eye_barrier{};
            eye_barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
            eye_barrier.Transition.pResource = opened_eyes->eyes[eye].Get();
            eye_barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
            eye_barrier.Transition.StateAfter =
                D3D12_RESOURCE_STATE_COPY_SOURCE;
            eye_barrier.Transition.Subresource =
                D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
            command_list->ResourceBarrier(1, &eye_barrier);
            D3D12_TEXTURE_COPY_LOCATION destination{};
            destination.pResource =
                resources[separate_shared_eye_swapchains ? eye : 0U];
            destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            D3D12_TEXTURE_COPY_LOCATION source{};
            source.pResource = opened_eyes->eyes[eye].Get();
            source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            command_list->CopyTextureRegion(
                &destination, 0,
                separate_shared_eye_swapchains
                    ? 0U
                    : static_cast<UINT>(eye * shared_eye_height),
                0, &source, nullptr);
            std::swap(eye_barrier.Transition.StateBefore,
                      eye_barrier.Transition.StateAfter);
            command_list->ResourceBarrier(1, &eye_barrier);
          }
        } else {
          const std::array<D3D12_RECT, 4> quadrants{{
              {0, 0, static_cast<LONG>(width / 2),
               static_cast<LONG>(height / 2)},
              {static_cast<LONG>(width / 2), 0, static_cast<LONG>(width),
               static_cast<LONG>(height / 2)},
              {0, static_cast<LONG>(height / 2),
               static_cast<LONG>(width / 2), static_cast<LONG>(height)},
              {static_cast<LONG>(width / 2), static_cast<LONG>(height / 2),
               static_cast<LONG>(width), static_cast<LONG>(height)},
          }};
          const float pulse =
              0.15F + 0.10F * static_cast<float>(frame % 120) / 119.0F;
          const std::array<std::array<float, 4>, 4> colors{{
              {0.04F, 0.07F, pulse, 1.0F},
              {0.18F, 0.05F, 0.04F, 1.0F},
              {0.04F, 0.16F, 0.08F, 1.0F},
              {0.20F, 0.16F, 0.04F, 1.0F},
          }};
          for (std::size_t eye = 0; eye < theatre_swapchain_count; ++eye) {
            const D3D12_CPU_DESCRIPTOR_HANDLE target{
                rtv_heap->GetCPUDescriptorHandleForHeapStart().ptr +
                static_cast<SIZE_T>(rtv_base_offsets[eye] +
                                    image_indices[eye]) *
                    rtv_increment};
            for (std::size_t index = 0; index < quadrants.size(); ++index) {
              command_list->ClearRenderTargetView(
                  target, colors[index].data(), 1, &quadrants[index]);
            }
          }
        }
        for (auto& barrier : destination_barriers) {
          std::swap(barrier.Transition.StateBefore,
                    barrier.Transition.StateAfter);
        }
        command_list->ResourceBarrier(
            static_cast<UINT>(destination_barriers.size()),
            destination_barriers.data());
        check(command_list->Close(),
              "ID3D12GraphicsCommandList::Close(theatre)");
        ID3D12CommandList* lists[]{command_list.Get()};
        if (use_shared_pair) {
          check(queue->Wait(opened_eyes->ready_fence.Get(),
                            shared_ready_for_frame),
                "ID3D12CommandQueue::Wait(shared eyes)");
        }
        queue->ExecuteCommandLists(1, lists);
        if (use_shared_pair) {
          check(queue->Signal(opened_eyes->consumed_fence.Get(),
                              shared_ready_for_frame),
                "ID3D12CommandQueue::Signal(shared eyes consumed)");
        } else if (discard_shared_pair_this_frame) {
          // A rejected pair was never copied by this command list, so it can be
          // acknowledged immediately. Leaving it unacknowledged would pin the
          // producer's single shared slot forever and prevent recovery on a
          // subsequent pose-associated pair.
          check(opened_eyes->consumed_fence->Signal(shared_ready_for_frame),
                "ID3D12Fence::Signal(discarded shared eyes consumed)");
        }
        const auto signal_value = ++fence_value;
        check(queue->Signal(fence.Get(), signal_value),
              "ID3D12CommandQueue::Signal(theatre)");
        if (fence->GetCompletedValue() < signal_value) {
          check(fence->SetEventOnCompletion(signal_value, fence_event),
                "ID3D12Fence::SetEventOnCompletion(theatre)");
          WaitForSingleObject(fence_event, INFINITE);
        }
        XrSwapchainImageReleaseInfo release_info{
            XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
        for (const auto swapchain : theatre_swapchains) {
          check_xr(xrReleaseSwapchainImage(swapchain, &release_info),
                   "xrReleaseSwapchainImage(theatre)");
        }
        ++submitted_frames;
      } else {
        ++not_rendered_frames;
      }

      std::array<XrCompositionLayerQuad, 2> quads{{
          {XR_TYPE_COMPOSITION_LAYER_QUAD},
          {XR_TYPE_COMPOSITION_LAYER_QUAD},
      }};
      const auto configure_quad = [&](XrCompositionLayerQuad& quad,
                                      XrEyeVisibility visibility,
                                      std::int32_t offset_x,
                                      std::int32_t extent_width) {
        quad.space = view_space_;
        quad.eyeVisibility = visibility;
        quad.subImage.swapchain = theatre_swapchains.front();
        quad.subImage.imageRect.offset = {offset_x, 0};
        quad.subImage.imageRect.extent = {
            extent_width, static_cast<std::int32_t>(height)};
        quad.pose.orientation.w = 1.0F;
        quad.pose.position.z = -2.0F;
        quad.size = stereo ? XrExtent2Df{1.1F, 1.2375F}
                               : XrExtent2Df{2.2F, 1.2375F};
      };
      configure_quad(quads[0], stereo ? XR_EYE_VISIBILITY_LEFT
                                           : XR_EYE_VISIBILITY_BOTH,
                     0, stereo ? static_cast<std::int32_t>(width / 2)
                                    : static_cast<std::int32_t>(width));
      if (stereo) {
        configure_quad(quads[1], XR_EYE_VISIBILITY_RIGHT,
                       static_cast<std::int32_t>(width / 2),
                       static_cast<std::int32_t>(width / 2));
      }
      XrCompositionLayerQuad flat_fallback_quad{
          XR_TYPE_COMPOSITION_LAYER_QUAD};
      flat_fallback_quad.space =
          flat_fallback_pose_valid ? local_space_ : view_space_;
      flat_fallback_quad.eyeVisibility = XR_EYE_VISIBILITY_BOTH;
      flat_fallback_quad.subImage.swapchain = theatre_swapchains.front();
      flat_fallback_quad.subImage.imageRect.offset = {0, 0};
      flat_fallback_quad.subImage.imageRect.extent = {
          static_cast<std::int32_t>(width),
          static_cast<std::int32_t>(flat_capture_height)};
      flat_fallback_quad.pose = flat_fallback_pose;
      const auto panel_source_width =
          presentation_sequence != 0 ? presentation_state.crop_width : width;
      const auto panel_source_height = presentation_sequence != 0
                                           ? presentation_state.crop_height
                                           : flat_capture_height;
      const auto panel_max_width = presentation_sequence != 0
                                       ? presentation_state
                                             .maximum_panel_width_metres
                                       : 2.0F;
      const auto panel_max_height = presentation_sequence != 0
                                        ? presentation_state
                                              .maximum_panel_height_metres
                                        : 2.0F;
      const auto panel_extent = darktidevr::core::fit_panel_extent(
          panel_source_width, panel_source_height, panel_max_width,
          panel_max_height);
      std::optional<std::pair<std::uint32_t, std::uint32_t>>
          menu_pointer_position;
      flat_fallback_quad.size = {panel_extent.width_metres,
                                 panel_extent.height_metres};
      const darktidevr::math::Pose panel_pose{
          {flat_fallback_pose.orientation.x, flat_fallback_pose.orientation.y,
           flat_fallback_pose.orientation.z, flat_fallback_pose.orientation.w},
          {flat_fallback_pose.position.x, flat_fallback_pose.position.y,
           flat_fallback_pose.position.z}};
      // The deterministic controller provider models controller tracking, not
      // menu visibility. Keep publishing it in immersive stereo so gameplay
      // consumers can be exercised while the physical controllers are idle.
      if (synthetic_controller_path) {
        const auto timestamp_ns = static_cast<std::uint64_t>(
            std::chrono::duration_cast<std::chrono::nanoseconds>(
                std::chrono::steady_clock::now().time_since_epoch())
                .count());
        auto synthetic =
            darktidevr::harness::synthetic_controller_path_sample(
                synthetic_controller_frames_++, ++controller_sequence_,
                timestamp_ns, panel_pose, panel_extent.width_metres,
                panel_extent.height_metres, synthetic_gameplay_input);
        populate_body_local_controller_poses(synthetic.state);
        if (!controller_writer_->publish(synthetic.state)) {
          throw std::runtime_error(
              "Shared controller state rejected synthetic sample");
        }
        latest_controller_sample_ = synthetic.state;
        ++controller_samples_;
        for (std::size_t hand = 0; hand < 2; ++hand) {
          if ((synthetic.state.hands[hand].aim_tracking_flags &
               darktidevr::core::controller_orientation_tracked) != 0) {
            ++controller_aim_tracked_frames_[hand];
          }
        }
        ++synthetic_controller_phase_frames_[
            static_cast<std::size_t>(synthetic.phase)];
      }
      if (submitted_flat_fallback_this_frame && latest_controller_sample_) {
        const auto& right = latest_controller_sample_->hands[1];
        const auto required =
            darktidevr::core::controller_orientation_valid |
            darktidevr::core::controller_position_valid;
        if ((right.aim_tracking_flags & required) == required &&
            current_head_valid &&
            darktidevr::core::pointer_origin_within_reach(
                right.aim_pose.position, current_head.position, 1.5F)) {
          const auto direction = darktidevr::math::rotate(
              right.aim_pose.orientation, {0.0F, 0.0F, -1.0F});
          ++controller_pointer_rays_;
          const auto pointer = darktidevr::core::map_pointer_to_panel(
              {right.aim_pose.position, direction}, panel_pose,
              panel_extent.width_metres, panel_extent.height_metres,
              presentation_sequence != 0 ? presentation_state.source_width
                                         : width,
              presentation_sequence != 0 ? presentation_state.source_height
                                         : flat_capture_height,
              presentation_sequence != 0 ? presentation_state.crop_x : 0,
              presentation_sequence != 0 ? presentation_state.crop_y : 0,
              panel_source_width, panel_source_height);
          if (pointer) {
            ++controller_pointer_hits_;
            controller_pointer_x_ = pointer->source_x;
            controller_pointer_y_ = pointer->source_y;
            menu_pointer_position =
                std::pair{pointer->source_x, pointer->source_y};
          }
        }
      }
      if (menu_input_injector) {
        const auto menu_mode =
            presentation_sequence != 0 &&
            (presentation_state.mode == darktidevr::core::
                                            SharedPresentationMode::flat_menu ||
             presentation_state.mode ==
                 darktidevr::core::SharedPresentationMode::world_anchored_menu);
        darktidevr::core::MenuPointerInput input{};
        input.active = menu_mode && submitted_flat_fallback_this_frame;
        input.source_position = menu_pointer_position;
        input.time_seconds =
            std::chrono::duration<double>(frame_start - start).count();
        if (window_capture) {
          window_capture->set_pointer_overlay(
              input.active ? menu_pointer_position : std::nullopt,
              presentation_sequence != 0
                  ? presentation_state.source_width
                  : width,
              presentation_sequence != 0
                  ? presentation_state.source_height
                  : flat_capture_height);
        }
        if (latest_controller_sample_) {
          const auto& left = latest_controller_sample_->hands[0];
          const auto& right = latest_controller_sample_->hands[1];
          input.trigger = right.trigger;
          input.thumbstick_y = right.thumbstick_y;
          input.back =
              (right.buttons & darktidevr::core::controller_secondary) != 0 ||
              (left.buttons & darktidevr::core::controller_menu) != 0;
        }
        for (const auto& event : menu_pointer_state.update(input)) {
          ++menu_input_events;
          if (menu_input_injector->dispatch(
                  event,
                  presentation_sequence != 0
                      ? presentation_state.source_width
                      : width,
                  presentation_sequence != 0
                      ? presentation_state.source_height
                      : flat_capture_height)) {
            ++menu_input_dispatched;
          }
        }
      }
      XrCompositionLayerProjection projection{
          XR_TYPE_COMPOSITION_LAYER_PROJECTION};
      if (stereo) {
        if (!stereo_fov_logged) {
          for (std::size_t eye = 0; eye < located_views.size(); ++eye) {
            const auto& runtime_fov = located_views[eye].fov;
            std::cout << "openxr.runtime_fov.eye" << eye << '='
                      << runtime_fov.angleLeft << ','
                      << runtime_fov.angleRight << ','
                      << runtime_fov.angleUp << ','
                      << runtime_fov.angleDown << '\n';
          }
          std::cout << "openxr.render_projection=recentered-symmetric\n";
          stereo_fov_logged = true;
        }
        for (std::size_t eye = 0; eye < projection_views.size(); ++eye) {
          auto& projection_view = projection_views[eye];
          projection_view = {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW};
          const auto base_pose =
              submitted_shared_pair_this_frame &&
                      rendered_pair_pose_ready_value != 0
                  ? rendered_pair_view_poses[eye]
                  : (recentered_view_poses_valid
                         ? recentered_view_poses[eye]
                         : located_views[eye].pose);
          const darktidevr::math::Fov runtime_fov{
              located_views[eye].fov.angleLeft,
              located_views[eye].fov.angleRight,
              located_views[eye].fov.angleUp,
              located_views[eye].fov.angleDown};
          const auto recentered =
              darktidevr::math::recentered_symmetric_projection(
                  runtime_fov, render_aspect_ratio);
          const darktidevr::math::Pose base{
              {base_pose.orientation.x, base_pose.orientation.y,
               base_pose.orientation.z, base_pose.orientation.w},
              {base_pose.position.x, base_pose.position.y,
               base_pose.position.z}};
          const auto submitted = darktidevr::math::compose(
              base, {recentered.orientation_offset, {0.0F, 0.0F, 0.0F}});
          projection_view.pose.orientation = {
              submitted.orientation.x, submitted.orientation.y,
              submitted.orientation.z, submitted.orientation.w};
          projection_view.pose.position = {
              submitted.position.x, submitted.position.y,
              submitted.position.z};
          projection_view.fov = {
              recentered.symmetric_fov.angle_left,
              recentered.symmetric_fov.angle_right,
              recentered.symmetric_fov.angle_up,
              recentered.symmetric_fov.angle_down};
          projection_view.subImage.swapchain =
              theatre_swapchains[separate_shared_eye_swapchains ? eye : 0U];
          if (separate_shared_eye_swapchains) {
            projection_view.subImage.imageRect.offset = {0, 0};
            projection_view.subImage.imageRect.extent = {
                static_cast<std::int32_t>(width),
                static_cast<std::int32_t>(height)};
          } else {
            projection_view.subImage.imageRect.offset =
                stereo_top_bottom_layout
                    ? XrOffset2Di{
                          0, static_cast<std::int32_t>(eye * (height / 2))}
                    : XrOffset2Di{
                          static_cast<std::int32_t>(eye * (width / 2)), 0};
            projection_view.subImage.imageRect.extent =
                stereo_top_bottom_layout
                    ? XrExtent2Di{static_cast<std::int32_t>(width),
                                  static_cast<std::int32_t>(height / 2)}
                    : XrExtent2Di{static_cast<std::int32_t>(width / 2),
                                  static_cast<std::int32_t>(height)};
          }
          projection_view.subImage.imageArrayIndex = 0;
        }
        projection.space = local_space_;
        projection.viewCount =
            static_cast<std::uint32_t>(projection_views.size());
        projection.views = projection_views.data();
      }
      const auto* layer = submitted_flat_fallback_this_frame
                              ? reinterpret_cast<const XrCompositionLayerBaseHeader*>(
                                    &flat_fallback_quad)
                          : stereo
                              ? reinterpret_cast<const XrCompositionLayerBaseHeader*>(
                                    &projection)
                              : reinterpret_cast<const XrCompositionLayerBaseHeader*>(
                                    &quads[0]);
      XrFrameEndInfo frame_end{XR_TYPE_FRAME_END_INFO};
      frame_end.displayTime = frame_state.predictedDisplayTime;
      frame_end.environmentBlendMode = environment_blend_mode_;
      frame_end.layerCount = submit_layer ? 1U : 0U;
      frame_end.layers = submit_layer ? &layer : nullptr;
      check_xr(xrEndFrame(session_, &frame_end), "xrEndFrame(theatre)");
      ++processed_frames;
      poll_session_events();
      if ((frame + 1) % 120 == 0) {
        const auto report_time = std::chrono::steady_clock::now();
        const auto live_seconds =
            std::chrono::duration<double>(report_time - start).count();
        const auto interval_seconds = std::chrono::duration<double>(
            report_time - last_live_report).count();
        const auto interval_submissions =
            submitted_frames - last_live_submitted_frames;
        const auto interval_fresh_pairs =
            fresh_shared_pairs - last_live_fresh_shared_pairs;
        const auto interval_fallback_frames =
            flat_fallback_frames - last_live_fallback_frames;
        std::cout << "openxr.live.submission_fps="
                  << submitted_frames / live_seconds
                  << " fresh_pair_fps=" << fresh_shared_pairs / live_seconds
                  << " interval_submission_fps="
                  << interval_submissions / interval_seconds
                  << " interval_fresh_pair_fps="
                  << interval_fresh_pairs / interval_seconds
                  << " interval_fallback_fps="
                  << interval_fallback_frames / interval_seconds
                  << " reused_frames=" << reused_shared_frames
                  << " pair_pose_mismatches=" << pair_pose_mismatches
                  << std::endl;
        last_live_report = report_time;
        last_live_submitted_frames = submitted_frames;
        last_live_fresh_shared_pairs = fresh_shared_pairs;
        last_live_fallback_frames = flat_fallback_frames;
      }
    }

    const auto elapsed = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - start);
    if (capture_thread.joinable()) {
      capture_thread.request_stop();
      capture_thread.join();
    }
    if (menu_input_injector) {
      for (const auto& event : menu_pointer_state.update({})) {
        ++menu_input_events;
        if (menu_input_injector->dispatch(
                event,
                presentation_sequence != 0 ? presentation_state.source_width
                                           : width,
                presentation_sequence != 0 ? presentation_state.source_height
                                           : flat_capture_height)) {
          ++menu_input_dispatched;
        }
      }
      menu_input_injector->release();
    }
    std::cout << "openxr.frames=" << processed_frames << '\n'
              << "openxr.submitted_frames=" << submitted_frames << '\n'
              << "openxr.not_rendered_frames=" << not_rendered_frames << '\n'
              << "openxr.elapsed_ms=" << elapsed.count() << '\n'
              << "openxr.presentation="
              << (shared_eyes ? "shared-eye-projection"
                              : (stereo_top_bottom ? "stereo-top-bottom-projection"
                                    : (stereo_sbs ? "stereo-sbs-projection"
                                                  : "theatre-quad")))
              << '\n'
              << "openxr.theatre_source="
              << (shared_eyes
                      ? "shared-eyes"
                      : (window_capture ? "window-capture"
                                        : "diagnostic-pattern"))
              << '\n'
              << "openxr.theatre_capture_updates=" << capture_updates << '\n'
              << "openxr.theatre_capture_failures="
              << capture_failures_total.load(std::memory_order_relaxed) << '\n'
              << "openxr.theatre_stale_frames=" << capture_stale_frames
              << '\n'
              << "openxr.flat_fallback_frames=" << flat_fallback_frames
              << '\n'
              << "openxr.flat_fallback_transitions="
              << flat_fallback_transitions << '\n'
              << "openxr.fresh_shared_pairs=" << fresh_shared_pairs << '\n'
              << "openxr.reused_shared_frames=" << reused_shared_frames
              << '\n'
              << "openxr.pair_pose_mismatches=" << pair_pose_mismatches
              << '\n'
              << "openxr.shared_pose_sequence_offset="
              << shared_pose_sequence_offset << '\n'
              << "openxr.pair_driven_shared=" << pair_driven_shared << '\n'
              << "openxr.pair_driven_waits=" << pair_driven_waits << '\n'
              << "openxr.pair_driven_timeouts=" << pair_driven_timeouts
              << '\n'
              << "openxr.pair_pose_sequence_lag_average="
              << (pair_pose_sequence_lag_samples == 0
                      ? 0.0
                      : static_cast<double>(pair_pose_sequence_lag_sum) /
                            pair_pose_sequence_lag_samples)
              << '\n'
              << "openxr.pair_pose_sequence_lag_max="
              << pair_pose_sequence_lag_max << '\n'
              << "openxr.pair_pose_angle_lag_degrees_average="
              << (pair_pose_sequence_lag_samples == 0
                      ? 0.0
                      : pair_pose_angle_lag_degrees_sum /
                            pair_pose_sequence_lag_samples)
              << '\n'
              << "openxr.pair_pose_angle_lag_degrees_max="
              << pair_pose_angle_lag_degrees_max << '\n'
              << "openxr.controller_samples=" << controller_samples_ << '\n'
              << "openxr.runtime_ipd_metres=" << runtime_ipd_metres_ << '\n'
              << "openxr.controller_left_aim_tracked_frames="
              << controller_aim_tracked_frames_[0] << '\n'
              << "openxr.controller_right_aim_tracked_frames="
              << controller_aim_tracked_frames_[1] << '\n'
              << "openxr.controller_pointer_rays=" << controller_pointer_rays_
              << '\n'
              << "openxr.controller_pointer_hits=" << controller_pointer_hits_
              << '\n'
              << "openxr.controller_pointer_last_source="
              << controller_pointer_x_ << ',' << controller_pointer_y_ << '\n'
              << "openxr.menu_input_events=" << menu_input_events << '\n'
              << "openxr.menu_input_dispatched=" << menu_input_dispatched
              << '\n'
              << "openxr.synthetic_controller_frames="
              << synthetic_controller_frames_ << '\n'
              << "openxr.synthetic_controller_phase_frames=";
    for (std::size_t index = 0;
         index < synthetic_controller_phase_frames_.size(); ++index) {
      std::cout << (index == 0 ? "" : ",")
                << synthetic_controller_phase_frames_[index];
    }
    std::cout << '\n';
    if (upload) {
      upload->Unmap(0, nullptr);
      upload_pixels = nullptr;
    }
    CloseHandle(fence_event);
    for (const auto swapchain : theatre_swapchains) {
      check_xr(xrDestroySwapchain(swapchain), "xrDestroySwapchain(theatre)");
    }
    if (require_rendering && submitted_frames == 0) {
      request_clean_exit();
      throw std::runtime_error(
          "Runtime completed theatre loop without layer submission");
    }
    request_clean_exit();
  }

  void destroy_session() {
    if (session_ != XR_NULL_HANDLE) {
      if (session_running_) {
        request_clean_exit();
      }
      for (const auto swapchain : swapchains_) {
        xrDestroySwapchain(swapchain);
      }
      swapchains_.clear();
      swapchain_images_.clear();
      destroy_controller_spaces();
      if (local_space_ != XR_NULL_HANDLE) {
        xrDestroySpace(local_space_);
        local_space_ = XR_NULL_HANDLE;
      }
      if (view_space_ != XR_NULL_HANDLE) {
        xrDestroySpace(view_space_);
        view_space_ = XR_NULL_HANDLE;
      }
      xrDestroySession(session_);
      session_ = XR_NULL_HANDLE;
      std::cout << "openxr.session=destroyed\n";
    }
  }

  bool session_created() const { return session_ != XR_NULL_HANDLE; }

 private:
  XrPath path(const char* value) const {
    XrPath result{XR_NULL_PATH};
    check_xr(xrStringToPath(instance_, value, &result), "xrStringToPath");
    return result;
  }

  void create_controller_actions() {
    if (controller_action_set_ == XR_NULL_HANDLE) {
      XrActionSetCreateInfo set_info{XR_TYPE_ACTION_SET_CREATE_INFO};
      strcpy_s(set_info.actionSetName, "gameplay");
      strcpy_s(set_info.localizedActionSetName, "Darktide VR gameplay");
      check_xr(xrCreateActionSet(instance_, &set_info, &controller_action_set_),
               "xrCreateActionSet(gameplay)");

      hand_paths_[0] = path("/user/hand/left");
      hand_paths_[1] = path("/user/hand/right");
      const auto create_action = [&](XrActionType type, const char* name,
                                     const char* localized,
                                     XrAction& action) {
        XrActionCreateInfo info{XR_TYPE_ACTION_CREATE_INFO};
        info.actionType = type;
        strcpy_s(info.actionName, name);
        strcpy_s(info.localizedActionName, localized);
        info.countSubactionPaths =
            static_cast<std::uint32_t>(hand_paths_.size());
        info.subactionPaths = hand_paths_.data();
        check_xr(xrCreateAction(controller_action_set_, &info, &action),
                 "xrCreateAction");
      };
      create_action(XR_ACTION_TYPE_POSE_INPUT, "aim_pose", "Aim pose",
                    aim_action_);
      create_action(XR_ACTION_TYPE_POSE_INPUT, "grip_pose", "Grip pose",
                    grip_action_);
      create_action(XR_ACTION_TYPE_FLOAT_INPUT, "trigger", "Trigger",
                    trigger_action_);
      create_action(XR_ACTION_TYPE_FLOAT_INPUT, "squeeze", "Squeeze",
                    squeeze_action_);
      create_action(XR_ACTION_TYPE_VECTOR2F_INPUT, "thumbstick", "Thumbstick",
                    thumbstick_action_);
      create_action(XR_ACTION_TYPE_BOOLEAN_INPUT, "primary", "Primary",
                    primary_action_);
      create_action(XR_ACTION_TYPE_BOOLEAN_INPUT, "secondary", "Secondary",
                    secondary_action_);
      create_action(XR_ACTION_TYPE_BOOLEAN_INPUT, "stick_click", "Stick click",
                    stick_click_action_);
      create_action(XR_ACTION_TYPE_BOOLEAN_INPUT, "menu", "Menu",
                    menu_action_);
      create_action(XR_ACTION_TYPE_VIBRATION_OUTPUT, "haptic", "Haptic",
                    haptic_action_);

      const std::array<XrActionSuggestedBinding, 18> touch_bindings{{
          {aim_action_, path("/user/hand/left/input/aim/pose")},
          {aim_action_, path("/user/hand/right/input/aim/pose")},
          {grip_action_, path("/user/hand/left/input/grip/pose")},
          {grip_action_, path("/user/hand/right/input/grip/pose")},
          {trigger_action_, path("/user/hand/left/input/trigger/value")},
          {trigger_action_, path("/user/hand/right/input/trigger/value")},
          {squeeze_action_, path("/user/hand/left/input/squeeze/value")},
          {squeeze_action_, path("/user/hand/right/input/squeeze/value")},
          {thumbstick_action_, path("/user/hand/left/input/thumbstick")},
          {thumbstick_action_, path("/user/hand/right/input/thumbstick")},
          {primary_action_, path("/user/hand/left/input/x/click")},
          {primary_action_, path("/user/hand/right/input/a/click")},
          {secondary_action_, path("/user/hand/left/input/y/click")},
          {secondary_action_, path("/user/hand/right/input/b/click")},
          {stick_click_action_,
           path("/user/hand/left/input/thumbstick/click")},
          {stick_click_action_,
           path("/user/hand/right/input/thumbstick/click")},
          {menu_action_, path("/user/hand/left/input/menu/click")},
          {haptic_action_, path("/user/hand/right/output/haptic")},
      }};
      XrInteractionProfileSuggestedBinding touch{
          XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
      touch.interactionProfile =
          path("/interaction_profiles/oculus/touch_controller");
      touch.suggestedBindings = touch_bindings.data();
      touch.countSuggestedBindings =
          static_cast<std::uint32_t>(touch_bindings.size());
      check_xr(xrSuggestInteractionProfileBindings(instance_, &touch),
               "xrSuggestInteractionProfileBindings(Touch)");

      const std::array<XrActionSuggestedBinding, 6> simple_bindings{{
          {grip_action_, path("/user/hand/left/input/grip/pose")},
          {grip_action_, path("/user/hand/right/input/grip/pose")},
          {primary_action_, path("/user/hand/left/input/select/click")},
          {primary_action_, path("/user/hand/right/input/select/click")},
          {menu_action_, path("/user/hand/left/input/menu/click")},
          {haptic_action_, path("/user/hand/right/output/haptic")},
      }};
      XrInteractionProfileSuggestedBinding simple{
          XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
      simple.interactionProfile =
          path("/interaction_profiles/khr/simple_controller");
      simple.suggestedBindings = simple_bindings.data();
      simple.countSuggestedBindings =
          static_cast<std::uint32_t>(simple_bindings.size());
      check_xr(xrSuggestInteractionProfileBindings(instance_, &simple),
               "xrSuggestInteractionProfileBindings(simple)");
      controller_writer_ =
          std::make_unique<darktidevr::core::SharedControllerStateWriter>();
      std::cout << "openxr.controller_actions=created\n";
    }

    XrSessionActionSetsAttachInfo attach{
        XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO};
    attach.countActionSets = 1;
    attach.actionSets = &controller_action_set_;
    check_xr(xrAttachSessionActionSets(session_, &attach),
             "xrAttachSessionActionSets");
    for (std::size_t hand = 0; hand < hand_paths_.size(); ++hand) {
      XrActionSpaceCreateInfo info{XR_TYPE_ACTION_SPACE_CREATE_INFO};
      info.poseInActionSpace.orientation.w = 1.0F;
      info.subactionPath = hand_paths_[hand];
      info.action = aim_action_;
      check_xr(xrCreateActionSpace(session_, &info, &aim_spaces_[hand]),
               "xrCreateActionSpace(aim)");
      info.action = grip_action_;
      check_xr(xrCreateActionSpace(session_, &info, &grip_spaces_[hand]),
               "xrCreateActionSpace(grip)");
    }
  }

  void destroy_controller_spaces() noexcept {
    for (auto& space : aim_spaces_) {
      if (space != XR_NULL_HANDLE) {
        xrDestroySpace(space);
        space = XR_NULL_HANDLE;
      }
    }
    for (auto& space : grip_spaces_) {
      if (space != XR_NULL_HANDLE) {
        xrDestroySpace(space);
        space = XR_NULL_HANDLE;
      }
    }
  }

  void sync_controller_actions(XrTime display_time) {
    if (!controller_writer_) {
      return;
    }
    XrActiveActionSet active_set{controller_action_set_, XR_NULL_PATH};
    XrActionsSyncInfo sync_info{XR_TYPE_ACTIONS_SYNC_INFO};
    sync_info.countActiveActionSets = 1;
    sync_info.activeActionSets = &active_set;
    const auto sync_result = xrSyncActions(session_, &sync_info);

    darktidevr::core::SharedControllerState sample{};
    sample.sequence = ++controller_sequence_;
    sample.timestamp_ns = static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now().time_since_epoch())
            .count());
    for (auto& hand : sample.hands) {
      hand.aim_pose.orientation.w = 1.0F;
      hand.grip_pose.orientation.w = 1.0F;
      hand.body_aim_pose.orientation.w = 1.0F;
      hand.body_grip_pose.orientation.w = 1.0F;
    }
    if (sync_result == XR_SESSION_NOT_FOCUSED) {
      controller_writer_->publish(sample);
      latest_controller_sample_ = sample;
      ++controller_samples_;
      return;
    }
    check_xr(sync_result, "xrSyncActions");

    const auto get_info = [&](XrAction action, std::size_t hand) {
      XrActionStateGetInfo info{XR_TYPE_ACTION_STATE_GET_INFO};
      info.action = action;
      info.subactionPath = hand_paths_[hand];
      return info;
    };
    const auto read_float = [&](XrAction action, std::size_t hand) {
      auto info = get_info(action, hand);
      XrActionStateFloat state{XR_TYPE_ACTION_STATE_FLOAT};
      check_xr(xrGetActionStateFloat(session_, &info, &state),
               "xrGetActionStateFloat");
      return state.isActive ? std::clamp(state.currentState, 0.0F, 1.0F) : 0.0F;
    };
    const auto read_bool = [&](XrAction action, std::size_t hand) {
      auto info = get_info(action, hand);
      XrActionStateBoolean state{XR_TYPE_ACTION_STATE_BOOLEAN};
      check_xr(xrGetActionStateBoolean(session_, &info, &state),
               "xrGetActionStateBoolean");
      return state.isActive && state.currentState == XR_TRUE;
    };
    const auto locate_pose = [&](XrAction action, XrSpace space,
                                 darktidevr::math::Pose& pose,
                                 std::uint32_t& flags, std::size_t hand) {
      auto info = get_info(action, hand);
      XrActionStatePose state{XR_TYPE_ACTION_STATE_POSE};
      check_xr(xrGetActionStatePose(session_, &info, &state),
               "xrGetActionStatePose");
      if (!state.isActive) {
        return;
      }
      XrSpaceLocation location{XR_TYPE_SPACE_LOCATION};
      check_xr(xrLocateSpace(space, local_space_, display_time, &location),
               "xrLocateSpace(controller)");
      pose.orientation = {location.pose.orientation.x,
                          location.pose.orientation.y,
                          location.pose.orientation.z,
                          location.pose.orientation.w};
      pose.position = {location.pose.position.x, location.pose.position.y,
                       location.pose.position.z};
      if ((location.locationFlags &
           XR_SPACE_LOCATION_ORIENTATION_VALID_BIT) != 0) {
        flags |= darktidevr::core::controller_orientation_valid;
      }
      if ((location.locationFlags & XR_SPACE_LOCATION_POSITION_VALID_BIT) != 0) {
        flags |= darktidevr::core::controller_position_valid;
      }
      if ((location.locationFlags &
           XR_SPACE_LOCATION_ORIENTATION_TRACKED_BIT) != 0) {
        flags |= darktidevr::core::controller_orientation_tracked;
      }
      if ((location.locationFlags &
           XR_SPACE_LOCATION_POSITION_TRACKED_BIT) != 0) {
        flags |= darktidevr::core::controller_position_tracked;
      }
    };

    for (std::size_t hand = 0; hand < hand_paths_.size(); ++hand) {
      auto& destination = sample.hands[hand];
      locate_pose(aim_action_, aim_spaces_[hand], destination.aim_pose,
                  destination.aim_tracking_flags, hand);
      locate_pose(grip_action_, grip_spaces_[hand], destination.grip_pose,
                  destination.grip_tracking_flags, hand);
      destination.trigger = read_float(trigger_action_, hand);
      destination.squeeze = read_float(squeeze_action_, hand);
      auto stick_info = get_info(thumbstick_action_, hand);
      XrActionStateVector2f stick{XR_TYPE_ACTION_STATE_VECTOR2F};
      check_xr(xrGetActionStateVector2f(session_, &stick_info, &stick),
               "xrGetActionStateVector2f");
      if (stick.isActive) {
        destination.thumbstick_x =
            std::clamp(stick.currentState.x, -1.0F, 1.0F);
        destination.thumbstick_y =
            std::clamp(stick.currentState.y, -1.0F, 1.0F);
      }
      destination.buttons =
          (read_bool(primary_action_, hand)
               ? darktidevr::core::controller_primary
               : 0U) |
          (read_bool(secondary_action_, hand)
               ? darktidevr::core::controller_secondary
               : 0U) |
          (read_bool(stick_click_action_, hand)
               ? darktidevr::core::controller_stick_click
               : 0U) |
          (read_bool(menu_action_, hand) ? darktidevr::core::controller_menu
                                         : 0U);
    }
    populate_body_local_controller_poses(sample);
    if (!controller_writer_->publish(sample)) {
      throw std::runtime_error("Shared controller state rejected live sample");
    }
    latest_controller_sample_ = sample;
    ++controller_samples_;
    for (std::size_t hand = 0; hand < hand_paths_.size(); ++hand) {
      if ((sample.hands[hand].aim_tracking_flags &
           darktidevr::core::controller_orientation_tracked) != 0) {
        ++controller_aim_tracked_frames_[hand];
      }
    }
  }

  void populate_body_local_controller_poses(
      darktidevr::core::SharedControllerState& sample) const {
    if (!controller_recenter_pose_) {
      return;
    }
    for (auto& hand : sample.hands) {
      hand.body_aim_pose = darktidevr::core::recentered_controller_pose(
          *controller_recenter_pose_, hand.aim_pose);
      hand.body_grip_pose = darktidevr::core::recentered_controller_pose(
          *controller_recenter_pose_, hand.grip_pose);
      hand.body_aim_tracking_flags = hand.aim_tracking_flags;
      hand.body_grip_tracking_flags = hand.grip_tracking_flags;
    }
  }

  void force_destroy_session() noexcept {
    for (const auto swapchain : swapchains_) {
      if (swapchain != XR_NULL_HANDLE) {
        xrDestroySwapchain(swapchain);
      }
    }
    swapchains_.clear();
    swapchain_images_.clear();
    destroy_controller_spaces();
    if (local_space_ != XR_NULL_HANDLE) {
      xrDestroySpace(local_space_);
      local_space_ = XR_NULL_HANDLE;
    }
    if (view_space_ != XR_NULL_HANDLE) {
      xrDestroySpace(view_space_);
      view_space_ = XR_NULL_HANDLE;
    }
    if (session_ != XR_NULL_HANDLE) {
      xrDestroySession(session_);
      session_ = XR_NULL_HANDLE;
    }
    session_running_ = false;
  }

  void create_swapchains(const std::vector<std::int64_t>& formats,
                         bool create_projection_swapchains) {
    const std::array<std::int64_t, 4> preferred_formats{
        DXGI_FORMAT_R8G8B8A8_UNORM_SRGB, DXGI_FORMAT_B8G8R8A8_UNORM_SRGB,
        DXGI_FORMAT_R8G8B8A8_UNORM, DXGI_FORMAT_B8G8R8A8_UNORM};
    const auto selected = std::find_first_of(
        preferred_formats.begin(), preferred_formats.end(), formats.begin(),
        formats.end());
    if (selected == preferred_formats.end()) {
      throw std::runtime_error("Runtime exposes no supported harness color format");
    }
    swapchain_format_ = *selected;

    if (create_projection_swapchains) {
      swapchains_.reserve(views_.size());
      swapchain_images_.reserve(views_.size());
    }
    for (const auto& view :
         create_projection_swapchains
             ? views_
             : std::vector<XrViewConfigurationView>{}) {
      XrSwapchainCreateInfo create_info{XR_TYPE_SWAPCHAIN_CREATE_INFO};
      create_info.usageFlags = XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT |
                               XR_SWAPCHAIN_USAGE_SAMPLED_BIT;
      create_info.format = swapchain_format_;
      create_info.sampleCount = view.recommendedSwapchainSampleCount;
      create_info.width = view.recommendedImageRectWidth;
      create_info.height = view.recommendedImageRectHeight;
      create_info.faceCount = 1;
      create_info.arraySize = 1;
      create_info.mipCount = 1;
      XrSwapchain swapchain{XR_NULL_HANDLE};
      check_xr(xrCreateSwapchain(session_, &create_info, &swapchain),
               "xrCreateSwapchain");
      swapchains_.push_back(swapchain);

      std::uint32_t image_count{};
      check_xr(xrEnumerateSwapchainImages(swapchain, 0, &image_count, nullptr),
               "xrEnumerateSwapchainImages(count)");
      std::vector<XrSwapchainImageD3D12KHR> images(
          image_count, {XR_TYPE_SWAPCHAIN_IMAGE_D3D12_KHR});
      check_xr(xrEnumerateSwapchainImages(
                   swapchain, image_count, &image_count,
                   reinterpret_cast<XrSwapchainImageBaseHeader*>(images.data())),
               "xrEnumerateSwapchainImages(list)");
      swapchain_images_.push_back(std::move(images));
    }

    std::cout << "openxr.swapchains=" << swapchains_.size() << '\n'
              << "openxr.swapchain_format=" << swapchain_format_ << '\n';
    for (std::size_t eye = 0; eye < swapchain_images_.size(); ++eye) {
      std::cout << "openxr.swapchain[" << eye
                << "].images=" << swapchain_images_[eye].size() << '\n';
    }

    std::uint32_t blend_mode_count{};
    check_xr(xrEnumerateEnvironmentBlendModes(
                 instance_, system_id_, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,
                 0, &blend_mode_count, nullptr),
             "xrEnumerateEnvironmentBlendModes(count)");
    std::vector<XrEnvironmentBlendMode> blend_modes(blend_mode_count);
    check_xr(xrEnumerateEnvironmentBlendModes(
                 instance_, system_id_, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,
                 blend_mode_count, &blend_mode_count, blend_modes.data()),
             "xrEnumerateEnvironmentBlendModes(list)");
    if (blend_modes.empty()) {
      throw std::runtime_error("Runtime exposes no environment blend mode");
    }
    environment_blend_mode_ = blend_modes.front();
  }

  void poll_session_events() {
    XrEventDataBuffer event{XR_TYPE_EVENT_DATA_BUFFER};
    while (xrPollEvent(instance_, &event) == XR_SUCCESS) {
      if (event.type == XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED) {
        const auto* changed =
            reinterpret_cast<const XrEventDataSessionStateChanged*>(&event);
        if (changed->session == session_) {
          session_state_ = changed->state;
          std::cout << "openxr.session_state="
                    << static_cast<int>(session_state_) << '\n';
        }
      } else if (event.type == XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING) {
        throw std::runtime_error("OpenXR runtime reported instance loss pending");
      }
      event = {XR_TYPE_EVENT_DATA_BUFFER};
    }
  }

  void wait_until_ready() {
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(5);
    while (std::chrono::steady_clock::now() < deadline) {
      poll_session_events();
      if (session_state_ == XR_SESSION_STATE_READY) {
        return;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    throw std::runtime_error("Timed out waiting for XR_SESSION_STATE_READY");
  }

  void request_clean_exit() {
    if (!session_running_) {
      return;
    }
    check_xr(xrRequestExitSession(session_), "xrRequestExitSession");
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(5);
    while (std::chrono::steady_clock::now() < deadline) {
      poll_session_events();
      if (session_state_ == XR_SESSION_STATE_STOPPING) {
        check_xr(xrEndSession(session_), "xrEndSession");
        session_running_ = false;
        std::cout << "openxr.lifecycle=stopped\n";
        return;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    throw std::runtime_error("Timed out waiting for XR_SESSION_STATE_STOPPING");
  }

  void check_xr(XrResult result, const char* operation) const {
    if (XR_SUCCEEDED(result)) {
      return;
    }
    char result_text[XR_MAX_RESULT_STRING_SIZE]{};
    if (instance_ != XR_NULL_HANDLE &&
        XR_SUCCEEDED(xrResultToString(instance_, result, result_text))) {
      throw std::runtime_error(std::string(operation) + " failed (" +
                               result_text + ")");
    }
    throw std::runtime_error(std::string(operation) + " failed (XrResult " +
                             std::to_string(result) + ")");
  }

  XrInstance instance_{XR_NULL_HANDLE};
  XrSystemId system_id_{XR_NULL_SYSTEM_ID};
  XrSession session_{XR_NULL_HANDLE};
  XrSpace local_space_{XR_NULL_HANDLE};
  XrSpace view_space_{XR_NULL_HANDLE};
  XrActionSet controller_action_set_{XR_NULL_HANDLE};
  std::array<XrPath, 2> hand_paths_{XR_NULL_PATH, XR_NULL_PATH};
  XrAction aim_action_{XR_NULL_HANDLE};
  XrAction grip_action_{XR_NULL_HANDLE};
  XrAction trigger_action_{XR_NULL_HANDLE};
  XrAction squeeze_action_{XR_NULL_HANDLE};
  XrAction thumbstick_action_{XR_NULL_HANDLE};
  XrAction primary_action_{XR_NULL_HANDLE};
  XrAction secondary_action_{XR_NULL_HANDLE};
  XrAction stick_click_action_{XR_NULL_HANDLE};
  XrAction menu_action_{XR_NULL_HANDLE};
  XrAction haptic_action_{XR_NULL_HANDLE};
  std::array<XrSpace, 2> aim_spaces_{XR_NULL_HANDLE, XR_NULL_HANDLE};
  std::array<XrSpace, 2> grip_spaces_{XR_NULL_HANDLE, XR_NULL_HANDLE};
  std::unique_ptr<darktidevr::core::SharedControllerStateWriter>
      controller_writer_;
  std::uint64_t controller_sequence_{};
  std::optional<darktidevr::core::SharedControllerState>
      latest_controller_sample_;
  std::optional<darktidevr::math::Pose> controller_recenter_pose_;
  std::uint64_t controller_samples_{};
  float runtime_ipd_metres_{};
  std::array<std::uint64_t, 2> controller_aim_tracked_frames_{};
  std::uint64_t controller_pointer_rays_{};
  std::uint64_t controller_pointer_hits_{};
  std::uint32_t controller_pointer_x_{};
  std::uint32_t controller_pointer_y_{};
  std::uint64_t synthetic_controller_frames_{};
  std::array<std::uint64_t, 6> synthetic_controller_phase_frames_{};
  bool d3d12_extension_{};
  std::optional<XrGraphicsRequirementsD3D12KHR> requirements_;
  std::vector<XrViewConfigurationView> views_;
  std::vector<XrSwapchain> swapchains_;
  std::vector<std::vector<XrSwapchainImageD3D12KHR>> swapchain_images_;
  std::int64_t swapchain_format_{};
  XrEnvironmentBlendMode environment_blend_mode_{XR_ENVIRONMENT_BLEND_MODE_OPAQUE};
  XrSessionState session_state_{XR_SESSION_STATE_UNKNOWN};
  bool session_running_{};
};

LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam,
                             LPARAM lparam) {
  if (message == WM_CLOSE) {
    DestroyWindow(window);
    return 0;
  }
  if (message == WM_DESTROY) {
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

class Harness {
 public:
  Harness(bool show_window, bool debug_layer,
          const std::optional<LUID>& required_adapter,
          D3D_FEATURE_LEVEL minimum_feature_level) {
    create_window(show_window);
    create_device(debug_layer, required_adapter, minimum_feature_level);
    create_swapchain();
    create_render_targets();
    create_commands();
  }

  ~Harness() {
    if (queue_ && fence_ && fence_event_) {
      try {
        wait_for_gpu();
      } catch (...) {
      }
    }
    if (fence_event_) {
      CloseHandle(fence_event_);
    }
    if (window_) {
      DestroyWindow(window_);
    }
  }

  void render(UINT frame_number) {
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }

    const auto index = swapchain_->GetCurrentBackBufferIndex();
    check(allocator_->Reset(), "ID3D12CommandAllocator::Reset");
    check(command_list_->Reset(allocator_.Get(), nullptr),
          "ID3D12GraphicsCommandList::Reset");

    const auto to_render = CD3DX12_RESOURCE_BARRIER::transition(
        render_targets_[index].Get(), D3D12_RESOURCE_STATE_PRESENT,
        D3D12_RESOURCE_STATE_RENDER_TARGET);
    command_list_->ResourceBarrier(1, &to_render);
    const auto target = CD3DX12_CPU_DESCRIPTOR_HANDLE(
        rtv_heap_->GetCPUDescriptorHandleForHeapStart(),
        static_cast<INT>(index), rtv_increment_);
    const float phase = static_cast<float>(frame_number % 120) / 119.0F;
    const std::array<float, 4> color{0.03F + phase * 0.12F, 0.02F,
                                     0.08F + (1.0F - phase) * 0.2F, 1.0F};
    command_list_->ClearRenderTargetView(target, color.data(), 0, nullptr);

    const auto to_present = CD3DX12_RESOURCE_BARRIER::transition(
        render_targets_[index].Get(), D3D12_RESOURCE_STATE_RENDER_TARGET,
        D3D12_RESOURCE_STATE_PRESENT);
    command_list_->ResourceBarrier(1, &to_present);
    check(command_list_->Close(), "ID3D12GraphicsCommandList::Close");
    ID3D12CommandList* lists[]{command_list_.Get()};
    queue_->ExecuteCommandLists(1, lists);
    check(swapchain_->Present(0, DXGI_PRESENT_ALLOW_TEARING),
          "IDXGISwapChain::Present");
    // Phase 0 favors an unambiguous lifetime proof over throughput. A frame
    // ring with per-slot allocators/fences replaces this serialization later.
    wait_for_gpu();
  }

  void resize(UINT width, UINT height) {
    wait_for_gpu();
    for (auto& target : render_targets_) {
      target.Reset();
    }
    check(swapchain_->ResizeBuffers(kBufferCount, width, height,
                                    DXGI_FORMAT_R8G8B8A8_UNORM,
                                    DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING),
          "IDXGISwapChain::ResizeBuffers");
    create_render_targets();
    ++resize_count_;
  }

  void finish() {
    wait_for_gpu();
    check(device_->GetDeviceRemovedReason(),
          "ID3D12Device::GetDeviceRemovedReason");
    validate_debug_messages();
  }

  const DXGI_ADAPTER_DESC3& adapter_description() const { return adapter_desc_; }
  D3D12_VIEW_INSTANCING_TIER view_instancing_tier() const {
    return view_instancing_tier_;
  }
  ID3D12Device* device() const { return device_.Get(); }
  ID3D12CommandQueue* queue() const { return queue_.Get(); }
  UINT resize_count() const { return resize_count_; }

 private:
  // Small local equivalents avoid taking a helper-header dependency.
  struct CD3DX12_RESOURCE_BARRIER : D3D12_RESOURCE_BARRIER {
    static CD3DX12_RESOURCE_BARRIER transition(
        ID3D12Resource* resource, D3D12_RESOURCE_STATES before,
        D3D12_RESOURCE_STATES after) {
      CD3DX12_RESOURCE_BARRIER barrier{};
      barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      barrier.Transition.pResource = resource;
      barrier.Transition.StateBefore = before;
      barrier.Transition.StateAfter = after;
      barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
      return barrier;
    }
  };

  struct CD3DX12_CPU_DESCRIPTOR_HANDLE : D3D12_CPU_DESCRIPTOR_HANDLE {
    CD3DX12_CPU_DESCRIPTOR_HANDLE(D3D12_CPU_DESCRIPTOR_HANDLE base, INT offset,
                                  UINT increment) {
      ptr = base.ptr + static_cast<SIZE_T>(offset) * increment;
    }
  };

  void create_window(bool show_window) {
    WNDCLASSEXW window_class{sizeof(WNDCLASSEXW)};
    window_class.lpfnWndProc = window_proc;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.lpszClassName = L"DarktideVRSyntheticHarness";
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    if (!RegisterClassExW(&window_class) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      throw std::runtime_error("RegisterClassExW failed");
    }

    window_ = CreateWindowExW(0, window_class.lpszClassName,
                              L"DarktideVR Phase 0 synthetic harness",
                              WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
                              kWidth, kHeight, nullptr, nullptr,
                              window_class.hInstance, nullptr);
    if (!window_) {
      throw std::runtime_error("CreateWindowExW failed");
    }
    ShowWindow(window_, show_window ? SW_SHOW : SW_HIDE);
  }

  void create_device(bool debug_layer, const std::optional<LUID>& required_adapter,
                     D3D_FEATURE_LEVEL minimum_feature_level) {
    UINT factory_flags{};
    if (debug_layer) {
      ComPtr<ID3D12Debug> debug;
      check(D3D12GetDebugInterface(IID_PPV_ARGS(&debug)),
            "D3D12GetDebugInterface");
      debug->EnableDebugLayer();
      factory_flags |= DXGI_CREATE_FACTORY_DEBUG;
    }
    check(CreateDXGIFactory2(factory_flags, IID_PPV_ARGS(&factory_)),
          "CreateDXGIFactory2");

    ComPtr<IDXGIAdapter1> adapter;
    for (UINT index = 0;
         factory_->EnumAdapterByGpuPreference(
             index, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE,
             IID_PPV_ARGS(&adapter)) != DXGI_ERROR_NOT_FOUND;
         ++index) {
      DXGI_ADAPTER_DESC1 candidate{};
      check(adapter->GetDesc1(&candidate), "IDXGIAdapter1::GetDesc1");
      const bool luid_matches =
          !required_adapter ||
          std::memcmp(&candidate.AdapterLuid, &*required_adapter, sizeof(LUID)) == 0;
      const auto requested_level = std::max(D3D_FEATURE_LEVEL_12_0,
                                            minimum_feature_level);
      if (luid_matches && (candidate.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) == 0 &&
          SUCCEEDED(D3D12CreateDevice(adapter.Get(), requested_level,
                                     IID_PPV_ARGS(&device_)))) {
        check(adapter.As(&adapter3_), "Query IDXGIAdapter4");
        check(adapter3_->GetDesc3(&adapter_desc_), "IDXGIAdapter4::GetDesc3");
        break;
      }
      adapter.Reset();
    }
    if (!device_) {
      throw std::runtime_error(
          "No matching hardware D3D12 feature-level 12.0 adapter");
    }

    D3D12_FEATURE_DATA_D3D12_OPTIONS3 options3{};
    if (SUCCEEDED(device_->CheckFeatureSupport(
            D3D12_FEATURE_D3D12_OPTIONS3, &options3, sizeof(options3)))) {
      view_instancing_tier_ = options3.ViewInstancingTier;
    }

    if (debug_layer) {
      check(device_.As(&info_queue_), "Query ID3D12InfoQueue");
      std::array<D3D12_MESSAGE_SEVERITY, 2> severities{
          D3D12_MESSAGE_SEVERITY_CORRUPTION, D3D12_MESSAGE_SEVERITY_ERROR};
      D3D12_INFO_QUEUE_FILTER filter{};
      filter.AllowList.NumSeverities = static_cast<UINT>(severities.size());
      filter.AllowList.pSeverityList = severities.data();
      check(info_queue_->PushStorageFilter(&filter),
            "ID3D12InfoQueue::PushStorageFilter");
    }

    D3D12_COMMAND_QUEUE_DESC queue_desc{};
    queue_desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    check(device_->CreateCommandQueue(&queue_desc, IID_PPV_ARGS(&queue_)),
          "ID3D12Device::CreateCommandQueue");
  }

  void create_swapchain() {
    DXGI_SWAP_CHAIN_DESC1 description{};
    description.Width = kWidth;
    description.Height = kHeight;
    description.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    description.SampleDesc.Count = 1;
    description.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    description.BufferCount = kBufferCount;
    description.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    description.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING;

    ComPtr<IDXGISwapChain1> swapchain;
    check(factory_->CreateSwapChainForHwnd(queue_.Get(), window_, &description,
                                           nullptr, nullptr, &swapchain),
          "IDXGIFactory::CreateSwapChainForHwnd");
    check(swapchain.As(&swapchain_), "Query IDXGISwapChain4");
  }

  void create_render_targets() {
    if (!rtv_heap_) {
      D3D12_DESCRIPTOR_HEAP_DESC heap_desc{};
      heap_desc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
      heap_desc.NumDescriptors = kBufferCount;
      check(device_->CreateDescriptorHeap(&heap_desc, IID_PPV_ARGS(&rtv_heap_)),
            "ID3D12Device::CreateDescriptorHeap");
      rtv_increment_ = device_->GetDescriptorHandleIncrementSize(
          D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    }
    for (UINT index = 0; index < kBufferCount; ++index) {
      check(swapchain_->GetBuffer(index, IID_PPV_ARGS(&render_targets_[index])),
            "IDXGISwapChain::GetBuffer");
      const CD3DX12_CPU_DESCRIPTOR_HANDLE target(
          rtv_heap_->GetCPUDescriptorHandleForHeapStart(),
          static_cast<INT>(index), rtv_increment_);
      device_->CreateRenderTargetView(render_targets_[index].Get(), nullptr,
                                      target);
    }
  }

  void create_commands() {
    check(device_->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
                                          IID_PPV_ARGS(&allocator_)),
          "ID3D12Device::CreateCommandAllocator");
    check(device_->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                     allocator_.Get(), nullptr,
                                     IID_PPV_ARGS(&command_list_)),
          "ID3D12Device::CreateCommandList");
    check(command_list_->Close(), "ID3D12GraphicsCommandList::Close");
    check(device_->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                               IID_PPV_ARGS(&fence_)),
          "ID3D12Device::CreateFence");
    fence_event_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!fence_event_) {
      throw std::runtime_error("CreateEventW failed");
    }
  }

  void wait_for_gpu() {
    const auto value = ++fence_value_;
    check(queue_->Signal(fence_.Get(), value), "ID3D12CommandQueue::Signal");
    if (fence_->GetCompletedValue() < value) {
      check(fence_->SetEventOnCompletion(value, fence_event_),
            "ID3D12Fence::SetEventOnCompletion");
      WaitForSingleObject(fence_event_, INFINITE);
    }
  }

  void validate_debug_messages() {
    if (!info_queue_) {
      return;
    }
    const auto count = info_queue_->GetNumStoredMessagesAllowedByRetrievalFilter();
    if (count == 0) {
      return;
    }
    std::string descriptions;
    for (UINT64 index = 0; index < count; ++index) {
      SIZE_T bytes{};
      info_queue_->GetMessage(index, nullptr, &bytes);
      std::vector<std::byte> storage(bytes);
      auto* message = reinterpret_cast<D3D12_MESSAGE*>(storage.data());
      if (SUCCEEDED(info_queue_->GetMessage(index, message, &bytes))) {
        if (!descriptions.empty()) {
          descriptions += "; ";
        }
        descriptions.append(message->pDescription, message->DescriptionByteLength);
      }
    }
    throw std::runtime_error("D3D12 debug layer reported " +
                             std::to_string(count) + " error(s): " +
                             descriptions);
  }

  HWND window_{};
  ComPtr<IDXGIFactory6> factory_;
  ComPtr<IDXGIAdapter4> adapter3_;
  DXGI_ADAPTER_DESC3 adapter_desc_{};
  D3D12_VIEW_INSTANCING_TIER view_instancing_tier_{
      D3D12_VIEW_INSTANCING_TIER_NOT_SUPPORTED};
  ComPtr<ID3D12Device> device_;
  ComPtr<ID3D12InfoQueue> info_queue_;
  ComPtr<ID3D12CommandQueue> queue_;
  ComPtr<IDXGISwapChain4> swapchain_;
  ComPtr<ID3D12DescriptorHeap> rtv_heap_;
  UINT rtv_increment_{};
  std::array<ComPtr<ID3D12Resource>, kBufferCount> render_targets_;
  ComPtr<ID3D12CommandAllocator> allocator_;
  ComPtr<ID3D12GraphicsCommandList> command_list_;
  ComPtr<ID3D12Fence> fence_;
  HANDLE fence_event_{};
  UINT64 fence_value_{};
  UINT resize_count_{};
};

void usage() {
  std::cout << "DarktideVR Phase 0 synthetic graphics harness\n\n"
            << "Usage: darktidevr-xr-harness [--frames N] [--show] "
               "[--debug-layer] [--require-openxr] [--require-rendering] "
               "[--xr-frames N | --xr-seconds N] [--theatre] "
               "[--stereo-sbs] [--stereo-tb] "
                "[--capture-window-title TEXT] [--shared-eyes] "
                "[--enable-menu-input [--menu-input-window-title TEXT]] "
                "[--synthetic-controller-path] "
                "[--synthetic-gameplay-input] "
                "[--shared-pose-sequence-offset N] "
               "[--pair-driven-shared | --continuous-shared] "
               "[--resize-at N]\n\n"
            << "Creates an independent D3D12 swapchain and reports OpenXR "
               "discovery.\n"
            << "It never loads or modifies Darktide.\n";
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  try {
    UINT frames = 120;
    bool show = false;
    bool debug_layer = false;
    bool require_openxr = false;
    bool require_rendering = false;
    bool theatre = false;
    bool stereo_sbs = false;
    bool stereo_top_bottom = false;
    bool shared_eyes = false;
    std::int64_t shared_pose_sequence_offset{};
    // Shared-eye projection follows complete producer pairs by default so the
    // runtime sees the real application cadence. Continuous compositor-rate
    // submission remains available only as an explicit diagnostic control.
    bool pair_driven_shared = true;
    bool enable_menu_input = false;
    bool synthetic_controller_path = false;
    bool synthetic_gameplay_input = false;
    std::wstring menu_input_title = L"Warhammer 40,000: Darktide";
    std::optional<std::wstring> capture_window_title;
    std::uint32_t xr_frames{};
    std::optional<std::chrono::seconds> xr_duration;
    std::optional<UINT> resize_at;
    for (int index = 1; index < argc; ++index) {
      const std::wstring argument = argv[index];
      if (argument == L"--help" || argument == L"-h") {
        usage();
        return 0;
      }
      if (argument == L"--show") {
        show = true;
      } else if (argument == L"--debug-layer") {
        debug_layer = true;
      } else if (argument == L"--require-openxr") {
        require_openxr = true;
      } else if (argument == L"--require-rendering") {
        require_openxr = true;
        require_rendering = true;
      } else if (argument == L"--theatre") {
        require_openxr = true;
        theatre = true;
      } else if (argument == L"--stereo-sbs") {
        require_openxr = true;
        theatre = true;
        stereo_sbs = true;
      } else if (argument == L"--stereo-tb") {
        require_openxr = true;
        theatre = true;
        stereo_top_bottom = true;
      } else if (argument == L"--shared-eyes") {
        require_openxr = true;
        theatre = true;
        shared_eyes = true;
      } else if (argument == L"--capture-window-title" && index + 1 < argc) {
        require_openxr = true;
        theatre = true;
        capture_window_title = argv[++index];
      } else if (argument == L"--enable-menu-input") {
        enable_menu_input = true;
      } else if (argument == L"--synthetic-controller-path") {
        synthetic_controller_path = true;
      } else if (argument == L"--synthetic-gameplay-input") {
        synthetic_gameplay_input = true;
      } else if (argument == L"--menu-input-window-title" &&
                 index + 1 < argc) {
        menu_input_title = argv[++index];
      } else if (argument == L"--shared-pose-sequence-offset" &&
                 index + 1 < argc) {
        shared_pose_sequence_offset = std::stoll(argv[++index]);
      } else if (argument == L"--pair-driven-shared") {
        pair_driven_shared = true;
      } else if (argument == L"--continuous-shared") {
        pair_driven_shared = false;
      } else if (argument == L"--resize-at" && index + 1 < argc) {
        resize_at = static_cast<UINT>(std::stoul(argv[++index]));
      } else if (argument == L"--xr-frames" && index + 1 < argc) {
        xr_frames = static_cast<std::uint32_t>(std::stoul(argv[++index]));
      } else if (argument == L"--xr-seconds" && index + 1 < argc) {
        xr_duration = std::chrono::seconds(std::stoul(argv[++index]));
      } else if (argument == L"--frames" && index + 1 < argc) {
        frames = static_cast<UINT>(std::stoul(argv[++index]));
      } else {
        throw std::invalid_argument("Unknown or incomplete argument");
      }
    }
    if (resize_at && *resize_at >= frames) {
      throw std::invalid_argument("--resize-at must be less than --frames");
    }
    if (xr_frames > 0 && xr_duration) {
      throw std::invalid_argument(
          "--xr-frames and --xr-seconds are mutually exclusive");
    }
    if (xr_duration && !theatre) {
      throw std::invalid_argument("--xr-seconds requires a theatre mode");
    }
    if (enable_menu_input && !shared_eyes) {
      throw std::invalid_argument(
          "--enable-menu-input requires --shared-eyes");
    }
    if (synthetic_controller_path && !shared_eyes) {
      throw std::invalid_argument(
          "--synthetic-controller-path requires --shared-eyes");
    }
    if (synthetic_gameplay_input && !synthetic_controller_path) {
      throw std::invalid_argument(
          "--synthetic-gameplay-input requires --synthetic-controller-path");
    }
    if (xr_duration && xr_duration->count() == 0) {
      throw std::invalid_argument("--xr-seconds must be greater than zero");
    }
    pair_driven_shared = shared_eyes && pair_driven_shared;

    OpenXrProbe openxr;
    Harness harness(show, debug_layer, openxr.adapter_luid(),
                    openxr.minimum_feature_level());
    openxr.create_session(harness.device(), harness.queue(), !theatre);
    if (require_openxr && !openxr.session_created()) {
      throw std::runtime_error(
          "OpenXR session required, but no usable HMD system is available");
    }
    if (xr_frames > 0 || xr_duration) {
      if (theatre) {
        openxr.run_theatre_lifecycle(
                                     xr_duration
                                         ? std::numeric_limits<std::uint32_t>::max()
                                         : xr_frames,
                                     harness.device(), harness.queue(),
                                     require_rendering, xr_duration,
                                     capture_window_title, stereo_sbs,
                                     stereo_top_bottom, shared_eyes,
                                     shared_pose_sequence_offset,
                                     pair_driven_shared,
                                     true, enable_menu_input,
                                     menu_input_title,
                                     synthetic_controller_path,
                                     synthetic_gameplay_input);
      } else {
        openxr.run_frame_lifecycle(xr_frames, harness.device(), harness.queue(),
                                   require_rendering);
      }
    } else if (require_rendering) {
      throw std::invalid_argument(
          "--require-rendering requires --xr-frames N or --xr-seconds N");
    }
    const auto start = std::chrono::steady_clock::now();
    std::vector<double> frame_times;
    frame_times.reserve(frames);
    for (UINT frame = 0; frame < frames; ++frame) {
      if (resize_at && frame == *resize_at) {
        harness.resize(1280, 720);
      }
      const auto frame_start = std::chrono::steady_clock::now();
      harness.render(frame);
      frame_times.push_back(std::chrono::duration<double, std::milli>(
                                std::chrono::steady_clock::now() - frame_start)
                                .count());
    }
    harness.finish();
    const auto elapsed = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - start);
    const auto& adapter = harness.adapter_description();
    std::sort(frame_times.begin(), frame_times.end());
    const auto percentile = [&frame_times](double fraction) {
      if (frame_times.empty()) {
        return 0.0;
      }
      const auto rank = static_cast<std::size_t>(
          std::ceil(fraction * static_cast<double>(frame_times.size())));
      return frame_times[std::max<std::size_t>(1, rank) - 1];
    };
    std::wcout << L"d3d12.adapter=" << adapter.Description << L'\n';
    std::cout << "d3d12.feature_level=12_0\n"
              << "d3d12.view_instancing_tier="
              << static_cast<unsigned>(harness.view_instancing_tier()) << '\n'
              << "present.frames=" << frames << '\n'
              << "present.resize_count=" << harness.resize_count() << '\n'
              << "present.elapsed_ms=" << elapsed.count() << '\n'
              << "present.cpu_ms_p50=" << percentile(0.50) << '\n'
              << "present.cpu_ms_p95=" << percentile(0.95) << '\n'
              << "present.cpu_ms_p99=" << percentile(0.99) << '\n'
              << "result=pass\n";
    openxr.destroy_session();
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "darktidevr-xr-harness: " << error.what() << '\n';
    return 1;
  }
}
