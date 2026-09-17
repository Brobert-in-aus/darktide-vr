#include <Windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>

#define XR_USE_PLATFORM_WIN32
#define XR_USE_GRAPHICS_API_D3D12
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>

#include "synthetic_scene.h"
#include "runtime_d3d11_diagnostics.h"
#include "menu_input_injector.h"
#include "synthetic_controller_path.h"
#include "synthetic_head_path.h"
#include "panel_renderer.h"
#include "tracked_cuff_renderer.h"
#include "window_capture.h"
#include "capture_worker.h"
#include "bridge/shared_eye_surfaces.h"
#include "core/head_tracking.h"
#include "core/menu_pointer_input.h"
#include "core/aim_stabilization.h"
#include "core/panel_pointer.h"
#include "core/presentation_policy.h"
#include "core/reticle_atlas.h"
#include "core/shared_controller_state.h"
#include "core/shared_gameplay_aim_state.h"
#include "core/shared_head_pose.h"
#include "core/shared_menu_pointer_state.h"
#include "core/shared_presentation_state.h"
#include "core/shared_generated_frame_state.h"
#include "core/generated_frame_cadence.h"
#include "core/frame_stage_timing.h"
#include "core/delivery_cadence.h"
#include "pair_poll_wait.h"
#include "packed_original_copy.h"

#include <algorithm>
#include <atomic>
#include <array>
#include <chrono>
#include <cmath>
#include <cstring>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <memory>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

constexpr UINT kBufferCount = 2;
constexpr UINT kWidth = 960;
constexpr UINT kHeight = 540;
constexpr auto kMenuTestPrimaryEvent =
    L"Local\\DarktideVR-menu-test-primary";
constexpr auto kMenuTestPrimaryDownEvent =
    L"Local\\DarktideVR-menu-test-primary-down";
constexpr auto kMenuTestPrimaryUpEvent =
    L"Local\\DarktideVR-menu-test-primary-up";
constexpr auto kMenuTestBackEvent = L"Local\\DarktideVR-menu-test-back";
constexpr auto kMenuTestScrollUpEvent =
    L"Local\\DarktideVR-menu-test-scroll-up";
constexpr auto kMenuTestScrollDownEvent =
    L"Local\\DarktideVR-menu-test-scroll-down";

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) {
    throw std::runtime_error(std::string(operation) + " failed (HRESULT " +
                             std::to_string(static_cast<std::uint32_t>(result)) +
                             ")");
  }
}

// Close reports only E_INVALIDARG for an invalid recorded command. With the
// debug layer (--debug-layer) the device's info queue names it: print the last
// messages before failing (intermittent theatre failure, 14 September).
void check_command_list_close(ID3D12GraphicsCommandList* list,
                              ID3D12Device* device, std::uint64_t frame,
                              const char* operation,
                              const std::function<std::string()>& describe = {}) {
  const auto result = list->Close();
  if (SUCCEEDED(result)) {
    return;
  }
  std::cerr << "openxr.command_list_close_failure frame=" << frame
            << " result=" << static_cast<std::uint32_t>(result)
            << (describe ? " " + describe() : std::string()) << '\n';
  Microsoft::WRL::ComPtr<ID3D12InfoQueue> messages;
  if (device && SUCCEEDED(device->QueryInterface(IID_PPV_ARGS(&messages)))) {
    const auto count = messages->GetNumStoredMessagesAllowedByRetrievalFilter();
    std::cerr << "openxr.command_list_close_failure.d3d12_messages=" << count << '\n';
    const auto first = count > 12 ? count - 12 : 0;
    for (auto index = first; index < count; ++index) {
      SIZE_T bytes{};
      if (FAILED(messages->GetMessage(index, nullptr, &bytes)) ||
          bytes < sizeof(D3D12_MESSAGE) || bytes > 1024 * 1024) {
        continue;
      }
      std::vector<std::byte> storage(bytes);
      auto* message = reinterpret_cast<D3D12_MESSAGE*>(storage.data());
      if (SUCCEEDED(messages->GetMessage(index, message, &bytes))) {
        std::cerr << "openxr.command_list_close_failure.d3d12 id=" << message->ID
                  << " severity=" << message->Severity << " text="
                  << (message->pDescription ? message->pDescription : "unavailable")
                  << '\n';
      }
    }
  } else {
    std::cerr << "openxr.command_list_close_failure.d3d12_messages=unavailable"
                 " (run the viewer with --debug-layer)\n";
  }
  std::cerr.flush();
  check(result, operation);
}

void wait_for_fence(ID3D12Fence* fence, std::uint64_t value, HANDLE event,
                    const char* operation) {
  constexpr DWORD timeout_ms = 10000;
  const auto before = fence->GetCompletedValue();
  if (before == UINT64_MAX) {
    throw std::runtime_error(std::string(operation) +
                             " failed: D3D12 fence is poisoned");
  }
  if (before >= value) {
    return;
  }
  check(fence->SetEventOnCompletion(value, event), operation);
  const auto wait_result = WaitForSingleObject(event, timeout_ms);
  if (wait_result != WAIT_OBJECT_0) {
    const auto after = fence->GetCompletedValue();
    throw std::runtime_error(
        std::string(operation) + " failed: wait_result=" +
        std::to_string(wait_result) + " completed=" + std::to_string(after) +
        " target=" + std::to_string(value));
  }
  if (fence->GetCompletedValue() == UINT64_MAX) {
    throw std::runtime_error(std::string(operation) +
                             " failed: D3D12 fence became poisoned");
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
  explicit OpenXrProbe(bool enabled = true) {
    if (!enabled) {
      std::cout << "openxr.discovery=disabled\n";
      return;
    }
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
                << "openxr.extension.XR_EXT_frame_synthesis=unknown\n"
                << "openxr.extension.XR_FB_space_warp=unknown\n"
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
    const auto extension_version = [&](const char* name) {
      const auto found = std::find_if(
          extensions.begin(), extensions.end(), [&](const auto& extension) {
            return std::strcmp(extension.extensionName, name) == 0;
          });
      return found == extensions.end() ? 0U : found->extensionVersion;
    };
    d3d12_extension_ =
        extension_version(XR_KHR_D3D12_ENABLE_EXTENSION_NAME) != 0U;
    std::cout << "openxr.extension.XR_KHR_D3D12_enable="
              << (d3d12_extension_ ? "available" : "unavailable") << '\n';
    const auto frame_synthesis_version =
        extension_version(XR_EXT_FRAME_SYNTHESIS_EXTENSION_NAME);
    const auto space_warp_version =
        extension_version(XR_FB_SPACE_WARP_EXTENSION_NAME);
    std::cout << "openxr.extension.XR_EXT_frame_synthesis="
              << (frame_synthesis_version != 0U ? "available" : "unavailable")
              << " spec_version=" << frame_synthesis_version << '\n'
              << "openxr.extension.XR_FB_space_warp="
              << (space_warp_version != 0U ? "available" : "unavailable")
              << " spec_version=" << space_warp_version << '\n';

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
    // The shared pose ABI currently carries one common eye extent. Reject an
    // unsupported asymmetric runtime rather than allocating the right eye from
    // the left recommendation and silently stretching or clipping its image.
    if (views_.size() != 2 ||
        views_[0].recommendedImageRectWidth == 0 ||
        views_[0].recommendedImageRectHeight == 0 ||
        views_[0].recommendedImageRectWidth != views_[1].recommendedImageRectWidth ||
        views_[0].recommendedImageRectHeight != views_[1].recommendedImageRectHeight) {
      throw std::runtime_error("OpenXR requires two equal, nonzero recommended eye extents");
    }
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
    std::uint32_t reference_space_count{};
    check_xr(xrEnumerateReferenceSpaces(
                 session_, 0, &reference_space_count, nullptr),
             "xrEnumerateReferenceSpaces(count)");
    std::vector<XrReferenceSpaceType> reference_spaces(reference_space_count);
    check_xr(xrEnumerateReferenceSpaces(
                 session_, reference_space_count, &reference_space_count,
                 reference_spaces.data()),
             "xrEnumerateReferenceSpaces(list)");
    if (std::find(reference_spaces.begin(), reference_spaces.end(),
                  XR_REFERENCE_SPACE_TYPE_STAGE) != reference_spaces.end()) {
      space_info.referenceSpaceType = XR_REFERENCE_SPACE_TYPE_STAGE;
      check_xr(xrCreateReferenceSpace(session_, &space_info, &stage_space_),
               "xrCreateReferenceSpace(STAGE)");
      std::cout << "openxr.floor_space=stage\n";
    } else {
      std::cout << "openxr.floor_space=unavailable\n";
    }
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
    create_swapchains(formats, create_projection_swapchains, device);
  }

  void run_frame_lifecycle(std::uint32_t frame_count, ID3D12Device* device,
                           ID3D12CommandQueue* queue, bool require_rendering,
                           bool synthetic_billboard_sweep) {
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
    ComPtr<ID3D12Resource> billboard_readback;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT billboard_readback_footprint{};
    UINT64 billboard_readback_bytes{};
    if (synthetic_billboard_sweep) {
      const auto description = swapchain_images_[0][0].texture->GetDesc();
      UINT rows{};
      UINT64 row_bytes{};
      device->GetCopyableFootprints(
          &description, 0, 1, 0, &billboard_readback_footprint, &rows,
          &row_bytes, &billboard_readback_bytes);
      D3D12_HEAP_PROPERTIES heap{};
      heap.Type = D3D12_HEAP_TYPE_READBACK;
      D3D12_RESOURCE_DESC readback_description{};
      readback_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
      readback_description.Width = billboard_readback_bytes;
      readback_description.Height = 1;
      readback_description.DepthOrArraySize = 1;
      readback_description.MipLevels = 1;
      readback_description.SampleDesc.Count = 1;
      readback_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
      check(device->CreateCommittedResource(
                &heap, D3D12_HEAP_FLAG_NONE, &readback_description,
                D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
                IID_PPV_ARGS(&billboard_readback)),
            "ID3D12Device::CreateCommittedResource(billboard readback)");
    }

    wait_until_ready();

    XrSessionBeginInfo begin_info{XR_TYPE_SESSION_BEGIN_INFO};
    begin_info.primaryViewConfigurationType =
        XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
    check_xr(xrBeginSession(session_, &begin_info), "xrBeginSession");
    session_running_ = true;
    std::cout << "openxr.lifecycle=running\n";

    std::vector<XrView> located_views(views_.size(), {XR_TYPE_VIEW});
    // Views with valid pose flags can still carry an unusable (all-zero) field
    // of view while the runtime is not streaming; such a frame submits no
    // projection layer instead of stopping the viewer.
    const auto located_views_have_usable_fov = [&located_views]() {
      for (const auto& view : located_views) {
        if (!darktidevr::math::fov_usable({view.fov.angleLeft, view.fov.angleRight,
                                           view.fov.angleUp, view.fov.angleDown})) {
          return false;
        }
      }
      return true;
    };
    std::vector<XrCompositionLayerProjectionView> projection_views(
        views_.size(), {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW});
    std::uint32_t submitted_frames{};
    std::uint32_t not_rendered_frames{};
    const auto xr_start = std::chrono::steady_clock::now();
    for (std::uint32_t frame = 0; frame < frame_count; ++frame) {
      const char* billboard_capture_label = nullptr;
      if (synthetic_billboard_sweep) {
        constexpr auto phase =
            darktidevr::harness::kSyntheticHeadPhaseFrames;
        if (frame == 0) {
          billboard_capture_label = "neutral";
        } else if (frame == phase + phase / 4) {
          billboard_capture_label = "pitch";
        } else if (frame == phase * 2 + phase / 4) {
          billboard_capture_label = "roll";
        } else if (frame == phase * 3 + phase / 4) {
          billboard_capture_label = "combined";
        }
      }
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
                       (view_state.viewStateFlags & valid_flags) == valid_flags &&
                       located_views_have_usable_fov();
        if (submit_layer && synthetic_billboard_sweep) {
          const auto synthetic =
              darktidevr::harness::synthetic_head_path_sample(frame, {});
          // The authored A/B must not depend on where or at what angle the
          // unattended headset happens to be resting. Preserve only the
          // runtime's inter-eye displacement, recentered around the scene
          // origin, and drive the common camera orientation entirely from the
          // deterministic sweep.
          const XrVector3f eye_midpoint{
              (located_views[0].pose.position.x +
               located_views[1].pose.position.x) * 0.5F,
              (located_views[0].pose.position.y +
               located_views[1].pose.position.y) * 0.5F,
              (located_views[0].pose.position.z +
               located_views[1].pose.position.z) * 0.5F};
          for (auto& located_view : located_views) {
            located_view.pose.orientation = {
                synthetic.delta.orientation.x,
                synthetic.delta.orientation.y,
                synthetic.delta.orientation.z,
                synthetic.delta.orientation.w};
            located_view.pose.position.x -= eye_midpoint.x;
            located_view.pose.position.y -= eye_midpoint.y;
            located_view.pose.position.z -= eye_midpoint.z;
          }
        }
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
          // XR_KHR_D3D12_enable acquires and releases color images in
          // RENDER_TARGET. Direct rendering needs no state transition.
          scene.record(command_list.Get(), eye, acquired_indices[eye],
                       located_views[eye], frame);

          if (eye == 0 && billboard_capture_label) {
            D3D12_RESOURCE_BARRIER to_copy{};
            to_copy.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
            to_copy.Transition.pResource = resource;
            to_copy.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
            to_copy.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
            to_copy.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
            command_list->ResourceBarrier(1, &to_copy);
            D3D12_TEXTURE_COPY_LOCATION destination{};
            destination.pResource = billboard_readback.Get();
            destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
            destination.PlacedFootprint = billboard_readback_footprint;
            D3D12_TEXTURE_COPY_LOCATION source{};
            source.pResource = resource;
            source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            source.SubresourceIndex = 0;
            command_list->CopyTextureRegion(&destination, 0, 0, 0, &source,
                                            nullptr);
            std::swap(to_copy.Transition.StateBefore,
                      to_copy.Transition.StateAfter);
            command_list->ResourceBarrier(1, &to_copy);
          }

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
        wait_for_fence(fence.Get(), signal_value, fence_event,
                       "ID3D12Fence::SetEventOnCompletion(XR)");
        if (billboard_capture_label) {
          void* mapped{};
          D3D12_RANGE read_range{0, billboard_readback_bytes};
          check(billboard_readback->Map(0, &read_range, &mapped),
                "ID3D12Resource::Map(billboard readback)");
          const auto width = views_[0].recommendedImageRectWidth;
          const auto height = views_[0].recommendedImageRectHeight;
          const auto path = std::filesystem::temp_directory_path() /
              (std::string("darktidevr-billboard-") +
               billboard_capture_label + ".ppm");
          std::ofstream output(path, std::ios::binary);
          if (!output) {
            billboard_readback->Unmap(0, nullptr);
            throw std::runtime_error("Could not open billboard capture output");
          }
          output << "P6\n" << width << ' ' << height << "\n255\n";
          const auto* pixels = static_cast<const std::uint8_t*>(mapped);
          const bool bgra =
              swapchain_format_ == DXGI_FORMAT_B8G8R8A8_UNORM ||
              swapchain_format_ == DXGI_FORMAT_B8G8R8A8_UNORM_SRGB;
          std::vector<std::uint8_t> row(static_cast<std::size_t>(width) * 3);
          for (std::uint32_t y = 0; y < height; ++y) {
            const auto* source_row = pixels +
                static_cast<std::size_t>(y) *
                    billboard_readback_footprint.Footprint.RowPitch;
            for (std::uint32_t x = 0; x < width; ++x) {
              const auto* source = source_row + static_cast<std::size_t>(x) * 4;
              row[static_cast<std::size_t>(x) * 3] = source[bgra ? 2 : 0];
              row[static_cast<std::size_t>(x) * 3 + 1] = source[1];
              row[static_cast<std::size_t>(x) * 3 + 2] = source[bgra ? 0 : 2];
            }
            output.write(reinterpret_cast<const char*>(row.data()),
                         static_cast<std::streamsize>(row.size()));
          }
          billboard_readback->Unmap(0, nullptr);
          std::cout << "openxr.synthetic_billboard_capture=" << path.string()
                    << '\n';
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
    std::cout << "openxr.synthetic_billboard_sweep="
              << (synthetic_billboard_sweep ? 1 : 0) << '\n';
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
                              bool capture_window_deferred,
                              bool capture_window_always,
                               bool stereo_sbs, bool stereo_top_bottom,
                               bool shared_eyes,
                               std::int64_t shared_pose_sequence_offset,
                               bool pair_driven_shared,
                               bool separate_shared_eye_swapchains,
                               bool enable_menu_input,
                               bool enable_menu_test_controls,
                               bool menu_aim_stabilization,
                               const std::wstring& menu_input_title,
                               bool synthetic_controller_path,
                               bool synthetic_body_path,
                               bool synthetic_gameplay_input,
                               bool synthetic_weapon_aim_matrix,
                               bool synthetic_movement_reference_path,
                               bool synthetic_holster_once,
                               bool enable_gameplay_reticle,
                               bool tracked_cuff_overlay,
                               bool synthetic_head_sweep,
                               bool synthetic_body_inspection,
                               bool synthetic_neck_pivot_path,
                               bool synthetic_roomscale_path,
                               bool synthetic_crouch_path,
                               float projection_translation_scale,
                               const std::optional<std::wstring>& stop_file) {
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
    std::cout << "openxr.projection_translation="
              << projection_translation_scale
              << '\n';
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
    // The game renders a runtime-sized portrait eye target but presents only
    // its 16:9 landscape content region at the top. Window chrome/non-content
    // accounts for the taller observed client capture; the native producer's
    // cropped shared resource is exactly 2112x1188 at this runtime setting.
    const std::uint32_t flat_capture_width = shared_eye_width;
    const std::uint32_t flat_capture_height =
        (flat_capture_width * 9U + 8U) / 16U;
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

    // Flat loading/menu presentation has a different lifetime from immersive
    // projection. Keep it on an independent swapchain so transitional desktop
    // frames cannot overwrite either eye while the first new stereo pair is
    // being produced.
    XrSwapchain flat_swapchain{XR_NULL_HANDLE};
    std::vector<XrSwapchainImageD3D12KHR> flat_images;
    if (capture_title) {
      auto flat_swapchain_info = swapchain_info;
      flat_swapchain_info.width = flat_capture_width;
      flat_swapchain_info.height = flat_capture_height;
      check_xr(xrCreateSwapchain(session_, &flat_swapchain_info,
                                 &flat_swapchain),
               "xrCreateSwapchain(flat capture)");
      std::uint32_t flat_image_count{};
      check_xr(xrEnumerateSwapchainImages(flat_swapchain, 0,
                                          &flat_image_count, nullptr),
               "xrEnumerateSwapchainImages(flat capture count)");
      flat_images.assign(flat_image_count,
                         {XR_TYPE_SWAPCHAIN_IMAGE_D3D12_KHR});
      check_xr(xrEnumerateSwapchainImages(
                   flat_swapchain, flat_image_count, &flat_image_count,
                   reinterpret_cast<XrSwapchainImageBaseHeader*>(
                       flat_images.data())),
                "xrEnumerateSwapchainImages(flat capture list)");
    }

    // The laser strips and the hit target sample one static swapchain. A
    // quad layer can only sample a swapchain image, and the flat texture is
    // rewritten on every menu update, so the pointer owns a swapchain that
    // is filled once and never written again: no capture or canvas pixel can
    // tint or hide it. Layout of the 64x64 image: a solid dark green block
    // in the top-left 16x16 (the strips sample its 8x8 interior so filtering
    // never reaches another texel) and the 48x48 target sprite at (16,16).
    XrSwapchain pointer_swapchain{XR_NULL_HANDLE};
    std::vector<XrSwapchainImageD3D12KHR> pointer_images;
    // The sprite is staged in its own upload buffer. Staging it in a corner
    // of the flat capture's upload buffer raced the window-capture memcpy
    // that runs later in the same frame, before the command list executes,
    // so the swapchain received captured title-screen pixels instead.
    ComPtr<ID3D12Resource> pointer_upload;
    std::byte* pointer_upload_pixels{};
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT pointer_upload_footprint{};
    constexpr std::uint32_t pointer_swatch_extent = 64;
    constexpr std::uint32_t pointer_ray_block_extent = 16;
    constexpr XrRect2Di pointer_ray_texels{{4, 4}, {8, 8}};
    constexpr XrRect2Di pointer_target_texels{
        {16, 16},
        {darktidevr::core::kPointerTargetExtent,
         darktidevr::core::kPointerTargetExtent}};
    if (capture_title) {
      auto pointer_swapchain_info = swapchain_info;
      pointer_swapchain_info.createFlags |=
          XR_SWAPCHAIN_CREATE_STATIC_IMAGE_BIT;
      pointer_swapchain_info.width = pointer_swatch_extent;
      pointer_swapchain_info.height = pointer_swatch_extent;
      check_xr(xrCreateSwapchain(session_, &pointer_swapchain_info,
                                 &pointer_swapchain),
               "xrCreateSwapchain(pointer swatch)");
      std::uint32_t pointer_image_count{};
      check_xr(xrEnumerateSwapchainImages(pointer_swapchain, 0,
                                          &pointer_image_count, nullptr),
               "xrEnumerateSwapchainImages(pointer swatch count)");
      pointer_images.assign(pointer_image_count,
                            {XR_TYPE_SWAPCHAIN_IMAGE_D3D12_KHR});
      check_xr(xrEnumerateSwapchainImages(
                   pointer_swapchain, pointer_image_count, &pointer_image_count,
                   reinterpret_cast<XrSwapchainImageBaseHeader*>(
                       pointer_images.data())),
               "xrEnumerateSwapchainImages(pointer swatch list)");
      const auto pointer_description =
          pointer_images.front().texture->GetDesc();
      UINT64 pointer_upload_bytes{};
      device->GetCopyableFootprints(&pointer_description, 0, 1, 0,
                                    &pointer_upload_footprint, nullptr,
                                    nullptr, &pointer_upload_bytes);
      D3D12_HEAP_PROPERTIES pointer_heap{};
      pointer_heap.Type = D3D12_HEAP_TYPE_UPLOAD;
      pointer_heap.CreationNodeMask = 1;
      pointer_heap.VisibleNodeMask = 1;
      D3D12_RESOURCE_DESC pointer_upload_description{};
      pointer_upload_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
      pointer_upload_description.Width = pointer_upload_bytes;
      pointer_upload_description.Height = 1;
      pointer_upload_description.DepthOrArraySize = 1;
      pointer_upload_description.MipLevels = 1;
      pointer_upload_description.SampleDesc.Count = 1;
      pointer_upload_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
      check(device->CreateCommittedResource(
                &pointer_heap, D3D12_HEAP_FLAG_NONE,
                &pointer_upload_description,
                D3D12_RESOURCE_STATE_GENERIC_READ, nullptr,
                IID_PPV_ARGS(&pointer_upload)),
            "ID3D12Device::CreateCommittedResource(pointer upload)");
      check(pointer_upload->Map(
                0, nullptr, reinterpret_cast<void**>(&pointer_upload_pixels)),
            "ID3D12Resource::Map(pointer upload)");
    }

    // Preserve the last complete stereo pair independently of the producer's
    // single shared slot. Fullscreen menus can then be a live 2 m spatial quad
    // over a stable stereo world, and closing one never exposes the engine's
    // transient blur/mono frames while a new pair is being produced.
    std::array<ComPtr<ID3D12Resource>, 2> cached_eye_resources;
    if (shared_eyes) {
      D3D12_HEAP_PROPERTIES cache_heap{};
      cache_heap.Type = D3D12_HEAP_TYPE_DEFAULT;
      cache_heap.CreationNodeMask = 1;
      cache_heap.VisibleNodeMask = 1;
      D3D12_RESOURCE_DESC cache_description{};
      cache_description.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
      cache_description.Width = shared_eye_width;
      cache_description.Height = shared_eye_height;
      cache_description.DepthOrArraySize = 1;
      cache_description.MipLevels = 1;
      cache_description.Format = static_cast<DXGI_FORMAT>(swapchain_format_);
      cache_description.SampleDesc.Count = 1;
      cache_description.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
      for (auto& cached_eye : cached_eye_resources) {
        check(device->CreateCommittedResource(
                  &cache_heap, D3D12_HEAP_FLAG_NONE, &cache_description,
                  D3D12_RESOURCE_STATE_COMMON, nullptr,
                  IID_PPV_ARGS(&cached_eye)),
              "ID3D12Device::CreateCommittedResource(cached eye)");
      }
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

    std::unique_ptr<darktidevr::harness::TrackedCuffRenderer>
        tracked_cuff_renderer;
    if (tracked_cuff_overlay) {
      tracked_cuff_renderer =
          std::make_unique<darktidevr::harness::TrackedCuffRenderer>(
              device, static_cast<DXGI_FORMAT>(swapchain_format_),
              theatre_images, views_);
      std::cout << "openxr.tracked_cuff_overlay=enabled depth_policy=overlay\n";
    }

    // Play default: the flat board (loading screens, menus) and the menu
    // pointer are drawn by the viewer into a projection layer of their own
    // instead of being handed to the runtime as quad layers (see
    // panel_renderer.h: Virtual Desktop draws quad layers wrongly with its
    // FOV tangent below 100 per cent). DTVR_XR_BOARD_PROJECTION=0 restores
    // the quad layers (a development override).
    wchar_t board_projection_value[2]{};
    const bool board_projection_requested = !(GetEnvironmentVariableW(
        L"DTVR_XR_BOARD_PROJECTION", board_projection_value, 2) == 1 &&
        board_projection_value[0] == L'0');
    // The gameplay reticle is a world-locked quad layer, and Virtual Desktop
    // draws quad layers with a projection that does not match a cropped
    // display -- the same fault that moved the boards, about a degree at ten
    // degrees off centre and swimming as the head turns against the aim. Drawn
    // into the eye images instead it is exactly as right as the world, and an
    // eye readback can finally see it. Off until it has been worn:
    // DTVR_XR_RETICLE_IN_EYES=1 turns it on.
    wchar_t reticle_in_eyes_value[2]{};
    const bool reticle_in_eyes_environment =
        GetEnvironmentVariableW(L"DTVR_XR_RETICLE_IN_EYES",
                                reticle_in_eyes_value, 2) == 1 &&
        reticle_in_eyes_value[0] == L'1';
    // Polled from the flag file below as well, so a run can turn it on and
    // off while the game is up.
    bool reticle_in_eyes_requested = reticle_in_eyes_environment;
    std::unique_ptr<darktidevr::harness::PanelRenderer> panel_renderer;
    std::array<XrSwapchain, 2> board_swapchains{XR_NULL_HANDLE, XR_NULL_HANDLE};
    std::array<std::vector<XrSwapchainImageD3D12KHR>, 2> board_images;
    std::array<std::size_t, 2> board_rtv_base_offsets{};
    ComPtr<ID3D12DescriptorHeap> board_rtv_heap;
    ComPtr<ID3D12CommandAllocator> board_allocator;
    ComPtr<ID3D12GraphicsCommandList> board_command_list;
    XrExtent2Di board_eye_extent{};
    if (board_projection_requested && stereo && views_.size() == 2 &&
        flat_swapchain != XR_NULL_HANDLE &&
        pointer_swapchain != XR_NULL_HANDLE) {
      panel_renderer = std::make_unique<darktidevr::harness::PanelRenderer>(
          device, static_cast<DXGI_FORMAT>(swapchain_format_),
          flat_images.front().texture->GetDesc(),
          pointer_images.front().texture->GetDesc());
      board_eye_extent = {
          static_cast<std::int32_t>(views_.front().recommendedImageRectWidth),
          static_cast<std::int32_t>(views_.front().recommendedImageRectHeight)};
      auto board_swapchain_info = swapchain_info;
      board_swapchain_info.width =
          static_cast<std::uint32_t>(board_eye_extent.width);
      board_swapchain_info.height =
          static_cast<std::uint32_t>(board_eye_extent.height);
      std::size_t board_image_total{};
      for (std::size_t eye = 0; eye < board_swapchains.size(); ++eye) {
        check_xr(xrCreateSwapchain(session_, &board_swapchain_info,
                                   &board_swapchains[eye]),
                 "xrCreateSwapchain(board)");
        std::uint32_t image_count{};
        check_xr(xrEnumerateSwapchainImages(board_swapchains[eye], 0,
                                            &image_count, nullptr),
                 "xrEnumerateSwapchainImages(board count)");
        board_images[eye].assign(image_count,
                                 {XR_TYPE_SWAPCHAIN_IMAGE_D3D12_KHR});
        check_xr(xrEnumerateSwapchainImages(
                     board_swapchains[eye], image_count, &image_count,
                     reinterpret_cast<XrSwapchainImageBaseHeader*>(
                         board_images[eye].data())),
                 "xrEnumerateSwapchainImages(board list)");
        board_rtv_base_offsets[eye] = board_image_total;
        board_image_total += image_count;
      }
      D3D12_DESCRIPTOR_HEAP_DESC board_heap_info{};
      board_heap_info.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
      board_heap_info.NumDescriptors = static_cast<UINT>(board_image_total);
      check(device->CreateDescriptorHeap(&board_heap_info,
                                         IID_PPV_ARGS(&board_rtv_heap)),
            "ID3D12Device::CreateDescriptorHeap(board)");
      auto board_rtv = board_rtv_heap->GetCPUDescriptorHandleForHeapStart();
      for (const auto& eye_images : board_images) {
        for (const auto& image : eye_images) {
          device->CreateRenderTargetView(image.texture, &rtv_view, board_rtv);
          board_rtv.ptr += rtv_increment;
        }
      }
      check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
                                           IID_PPV_ARGS(&board_allocator)),
            "ID3D12Device::CreateCommandAllocator(board)");
      check(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                      board_allocator.Get(), nullptr,
                                      IID_PPV_ARGS(&board_command_list)),
            "ID3D12Device::CreateCommandList(board)");
      check(board_command_list->Close(),
            "ID3D12GraphicsCommandList::Close(board init)");
    }
    std::cout << "openxr.board_projection requested="
              << board_projection_requested
              << " enabled=" << (panel_renderer != nullptr) << '\n';
    std::uint64_t board_projection_frames{};
    // The renderer's board texture is drawn only once pixels have been
    // copied into it; until then the quad layer carries the board.
    bool board_texture_written{};
    // The reticle sprite is copied into the board texture by the atlas branch;
    // until it has been, there is nothing to draw and the quad layer stands.
    bool reticle_sprite_in_board_texture{};
    bool gameplay_reticle_layer_logged{};

    std::unique_ptr<darktidevr::harness::WindowCapture> window_capture;
    ComPtr<ID3D12Resource> upload;
    std::byte* upload_pixels{};
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT upload_footprint{};
    using CapturePixels = std::vector<std::byte>;
    std::atomic<std::shared_ptr<const CapturePixels>> latest_capture;
    std::atomic<std::shared_ptr<const std::string>> capture_error;
    std::atomic<std::uint64_t> capture_failures_total{0};
    std::shared_ptr<const CapturePixels> consumed_capture;
    std::atomic<std::uint64_t> capture_attempts{0};
    bool capture_requested = true;
    std::unique_ptr<darktidevr::harness::CaptureWorker> capture_worker;
    // The on-demand policy pauses captures while stereo or native UI supplies
    // the image. The explicit always policy keeps the legacy 30 Hz capture
    // loop running for controlled cost comparisons only.
    const bool capture_on_demand = !capture_window_always;
    std::function<void()> acquire_capture_source;
    if (capture_title) {
      const auto texture_description = flat_images.front().texture->GetDesc();
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
          [&window_capture, &capture_attempts, flat_capture_width, flat_capture_height] {
        capture_attempts.fetch_add(1, std::memory_order_relaxed);
        const auto captured = window_capture->capture();
        auto converted = std::make_shared<CapturePixels>(
            static_cast<std::size_t>(flat_capture_width) *
            flat_capture_height * 4);
        for (std::uint32_t y = 0; y < captured.height; ++y) {
          const auto* source = captured.bgra_pixels +
                               static_cast<std::size_t>(y) *
                                   captured.row_pitch;
          auto* destination = converted->data() +
                              static_cast<std::size_t>(y) *
                                  flat_capture_width * 4;
          for (std::uint32_t x = 0; x < captured.width; ++x) {
            destination[x * 4] = source[x * 4 + 2];
            destination[x * 4 + 1] = source[x * 4 + 1];
            destination[x * 4 + 2] = source[x * 4];
            destination[x * 4 + 3] = source[x * 4 + 3];
          }
        }
        return std::shared_ptr<const CapturePixels>(std::move(converted));
      };
      acquire_capture_source = [&window_capture, &capture_worker, &latest_capture,
                                &capture_error, &capture_failures_total, capture_rgba,
                                &capture_title, flat_capture_width, flat_capture_height,
                                capture_on_demand] {
        try {
          window_capture = std::make_unique<darktidevr::harness::WindowCapture>(
              *capture_title, flat_capture_width, flat_capture_height);
          latest_capture.store(capture_rgba(), std::memory_order_release);
          capture_worker = std::make_unique<darktidevr::harness::CaptureWorker>(
              [capture_rgba, &latest_capture, &capture_error, &capture_failures_total] {
                try {
                  latest_capture.store(capture_rgba(), std::memory_order_release);
                  capture_error.store(nullptr, std::memory_order_release);
                } catch (const std::exception& error) {
                  capture_failures_total.fetch_add(1, std::memory_order_relaxed);
                  capture_error.store(std::make_shared<const std::string>(error.what()),
                                      std::memory_order_release);
                }
              });
          capture_worker->set_enabled(true);
        } catch (...) {
          // A partially acquired source must not survive a failed attempt. The
          // worker joins before the window object it captures from is released.
          capture_worker.reset();
          window_capture.reset();
          throw;
        }
        std::cout << "openxr.theatre_capture_policy="
                  << (capture_on_demand ? "on_demand" : "always") << '\n';
      };
      if (!capture_window_deferred) {
        acquire_capture_source();
      } else {
        try {
          acquire_capture_source();
        } catch (const std::exception& error) {
          // The simulator benchmark starts this consumer before the game window
          // exists. Keep the session running and retry from the frame loop.
          std::cout << "openxr.capture_window=pending reason=" << error.what()
                    << '\n';
        }
      }
    }

    std::optional<darktidevr::bridge::OpenedEyeSurfaces> opened_eyes;
    std::optional<darktidevr::bridge::OpenedSharedTexture> opened_menu;
    bool shared_menu_unavailable_logged = false;
    // Interactive UI is an additional compositor layer over uninterrupted
    // stereo projection. It never replaces either eye and therefore cannot
    // turn the world mono, freeze it, or expose the desktop behind the game.
    bool shared_menu_projection_enabled = true;
    std::unique_ptr<darktidevr::core::SharedHeadPoseWriter> head_pose_writer;
    const darktidevr::bridge::SharedEyeSurfaceNames shared_eye_names{
        {L"Local\\DarktideVR-eye-left", L"Local\\DarktideVR-eye-right"},
        L"Local\\DarktideVR-eye-ready",
        L"Local\\DarktideVR-eye-consumed"};
    const darktidevr::bridge::SharedTextureNames shared_menu_names{
        L"Local\\DarktideVR-menu-ui",
        L"Local\\DarktideVR-menu-ui-ready",
        L"Local\\DarktideVR-menu-ui-consumed"};
    UINT64 shared_last_ready_value{};
    auto shared_last_advance = std::chrono::steady_clock::now();
    auto next_shared_open_attempt = std::chrono::steady_clock::now();
    std::uint64_t shared_eye_generation{};
    auto next_shared_open_error_log = std::chrono::steady_clock::now();
    auto next_menu_open_attempt = std::chrono::steady_clock::now();
    std::uint64_t shared_menu_generation{};
    HANDLE projection_active_event{};
    darktidevr::core::SharedPresentationStateReader presentation_state_reader;
    darktidevr::core::RecenterRequestTracker recenter_request_tracker;
    darktidevr::core::HapticRequestTracker haptic_request_tracker;
    darktidevr::core::SharedPresentationState presentation_state{};
    std::uint64_t presentation_sequence{};
    std::uint64_t presentation_transport_generation{};
    darktidevr::core::SharedGameplayAimStateReader gameplay_aim_state_reader;
    darktidevr::core::SharedGameplayAimState gameplay_aim_state{};
    std::uint64_t gameplay_aim_sequence{};
    std::uint64_t gameplay_aim_transport_generation{};
    darktidevr::core::MenuPointerInputState menu_pointer_state;
    darktidevr::core::AimStabilization menu_aim_filter;
    std::uint64_t menu_filter_presentation_generation{};
    std::uint64_t menu_filter_samples{};
    std::uint64_t menu_filter_trace_samples{};
    std::cout << "openxr.menu_aim_stabilization=" << menu_aim_stabilization << '\n';
    darktidevr::core::SharedMenuPointerStateWriter menu_pointer_writer;
    std::uint64_t menu_pointer_sequence{};
    std::uint32_t menu_primary_press_sequence{};
    std::uint32_t menu_secondary_press_sequence{};
    std::uint32_t menu_back_press_sequence{};
    std::uint32_t menu_scroll_sequence{};
    int last_shared_menu_scroll_steps{};
    darktidevr::core::MenuPrimaryInputState menu_primary_state;
    darktidevr::core::MenuPrimaryInputState menu_secondary_state;
    std::unique_ptr<darktidevr::harness::MenuInputInjector>
        menu_input_injector;
    std::uint64_t menu_input_events{};
    std::uint64_t menu_input_dispatched{};
    HANDLE menu_test_primary_event{};
    HANDLE menu_test_primary_down_event{};
    HANDLE menu_test_primary_up_event{};
    HANDLE menu_test_back_event{};
    HANDLE menu_test_scroll_up_event{};
    HANDLE menu_test_scroll_down_event{};
    bool menu_test_primary_held{};
    menu_input_injector =
        std::make_unique<darktidevr::harness::MenuInputInjector>(
            menu_input_title);
    if (enable_menu_input) {
      std::cout << "openxr.menu_input=enabled\n";
    } else {
      std::cout << "openxr.menu_input=native-ui-service\n";
    }
    if (enable_menu_test_controls) {
      menu_test_primary_event =
          CreateEventW(nullptr, FALSE, FALSE, kMenuTestPrimaryEvent);
      menu_test_primary_down_event =
          CreateEventW(nullptr, FALSE, FALSE, kMenuTestPrimaryDownEvent);
      menu_test_primary_up_event =
          CreateEventW(nullptr, FALSE, FALSE, kMenuTestPrimaryUpEvent);
      menu_test_back_event =
          CreateEventW(nullptr, FALSE, FALSE, kMenuTestBackEvent);
      menu_test_scroll_up_event =
          CreateEventW(nullptr, FALSE, FALSE, kMenuTestScrollUpEvent);
      menu_test_scroll_down_event =
          CreateEventW(nullptr, FALSE, FALSE, kMenuTestScrollDownEvent);
      if (!menu_test_primary_event || !menu_test_primary_down_event ||
          !menu_test_primary_up_event || !menu_test_back_event ||
          !menu_test_scroll_up_event ||
          !menu_test_scroll_down_event) {
        if (menu_test_primary_event) {
          CloseHandle(menu_test_primary_event);
        }
        if (menu_test_primary_down_event) {
          CloseHandle(menu_test_primary_down_event);
        }
        if (menu_test_primary_up_event) {
          CloseHandle(menu_test_primary_up_event);
        }
        if (menu_test_back_event) {
          CloseHandle(menu_test_back_event);
        }
        if (menu_test_scroll_up_event) {
          CloseHandle(menu_test_scroll_up_event);
        }
        if (menu_test_scroll_down_event) {
          CloseHandle(menu_test_scroll_down_event);
        }
        throw std::runtime_error("CreateEventW(menu test controls) failed");
      }
      std::cout << "openxr.menu_test_controls=enabled\n";
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
      if (flat_swapchain != XR_NULL_HANDLE) {
        xrDestroySwapchain(flat_swapchain);
      }
      if (pointer_swapchain != XR_NULL_HANDLE) {
        xrDestroySwapchain(pointer_swapchain);
      }
      for (const auto swapchain : board_swapchains) {
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
    std::uint64_t menu_crop_clamped_frames{};
    bool menu_crop_clamp_logged{};
    std::uint32_t flat_fallback_transitions{};
    bool flat_fallback_active{};
    std::optional<darktidevr::core::SharedPresentationState>
        flat_fallback_anchor_state;
    XrPosef flat_fallback_pose{{0.0F, 0.0F, 0.0F, 1.0F},
                               {0.0F, 0.0F, -2.0F}};
    bool flat_fallback_pose_valid{};
    std::vector<XrView> located_views(views_.size(), {XR_TYPE_VIEW});
    // Views with valid pose flags can still carry an unusable (all-zero) field
    // of view while the runtime is not streaming; such a frame submits no
    // projection layer instead of stopping the viewer.
    const auto located_views_have_usable_fov = [&located_views]() {
      for (const auto& view : located_views) {
        if (!darktidevr::math::fov_usable({view.fov.angleLeft, view.fov.angleRight,
                                           view.fov.angleUp, view.fov.angleDown})) {
          return false;
        }
      }
      return true;
    };
    std::vector<XrCompositionLayerProjectionView> projection_views(
        views_.size(), {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW});
    bool stereo_fov_logged{};
    std::optional<darktidevr::math::Pose> head_recenter_pose;
    std::optional<darktidevr::math::Pose> synthetic_roomscale_origin;
    darktidevr::math::Vec3 body_follow_offset{};
    controller_recenter_pose_.reset();
    std::uint64_t head_pose_sequence{};
    std::uint32_t head_recenter_generation{};
    std::array<XrPosef, 2> recentered_view_poses{};
    bool recentered_view_poses_valid{};
    std::deque<std::pair<std::uint64_t, std::array<XrPosef, 2>>>
        head_pose_history;
    std::deque<std::pair<std::uint64_t, darktidevr::math::Pose>>
        gameplay_aim_origin_history;
    std::array<XrPosef, 2> rendered_pair_view_poses{};
    std::array<XrPosef, 2> generated_view_poses{};
    darktidevr::core::SharedGeneratedFrameStateReader generated_reader;
    darktidevr::core::SharedGeneratedFrameStateReader original_reader{L"Local\\DarktideVR-original-frame-state-v1"};
    darktidevr::core::SharedGeneratedFrameState original_state{};
    std::optional<darktidevr::bridge::OpenedGeneratedSurfaces> original_surfaces;
    std::optional<darktidevr::bridge::OpenedGeneratedSurfaces> generated_surfaces;
    darktidevr::core::SharedGeneratedFrameState generated_state{};
    std::uint64_t generated_last_consumed{}, generated_submitted{}, last_original_ready{}, last_original_pose{};
    std::uint64_t generated_displayed_before_original{};
    darktidevr::core::GeneratedFrameCadence generated_cadence;
    // Per-report selection outcomes; observation only, no scheduling changes.
    std::array<std::uint64_t,7> generated_selection_outcomes{};
    std::uint64_t generated_reserved_original_frames{};
    struct PendingOriginal {
      std::array<ComPtr<ID3D12Resource>,2> eyes;
      std::array<XrPosef,2> poses{};
      std::uint64_t ready{},pose{},generation{},tick{};
    };
    std::array<PendingOriginal,3> pending_originals;
    // Play defaults: direct native originals and the precise pair wait are on
    // unless the environment sets the variable to 0 (a development override).
    wchar_t direct_original_value[2]{};
    const bool direct_original_requested = !(GetEnvironmentVariableW(
        L"DTVR_XR_NATIVE_ORIGINAL_DIRECT", direct_original_value, 2) == 1 &&
        direct_original_value[0] == L'0');
    std::uint64_t direct_original_submitted{};
    std::cout << "openxr.native_original_direct requested=" << direct_original_requested << '\n';
    std::uint64_t ingested_original_ready{};
    std::array<XrPosef,2> submitted_original_view_poses{};
    std::uint64_t rendered_pair_pose_sequence{};
    auto next_generated_open = std::chrono::steady_clock::now();
    std::array<XrPosef, 2> cached_pair_view_poses{};
    bool cached_pair_valid{};
    std::uint64_t rendered_pair_pose_ready_value{};
    std::uint64_t rendered_pair_gameplay_generation{};
    std::uint64_t last_pair_pose_checked_ready_value{};
    std::uint64_t last_submitted_shared_value{};
    std::uint64_t fresh_shared_pairs{};
    std::uint64_t reused_shared_frames{};
    std::uint64_t tracked_cuff_frames{};
    std::uint64_t tracked_cuff_draws{};
    std::uint64_t pair_pose_mismatches{};
    std::uint64_t pair_pose_sequence_lag_sum{};
    std::uint64_t pair_pose_sequence_lag_samples{};
    std::uint64_t pair_pose_sequence_lag_max{};
    double pair_pose_angle_lag_degrees_sum{};
    double pair_pose_angle_lag_degrees_max{};
    std::uint64_t pair_driven_waits{};
    std::uint64_t pair_driven_timeouts{};
    std::uint64_t last_pose_publish_tick{};
    unsigned pose_timing_reports{};
    darktidevr::core::FrameStageTiming frame_stage_timing;
    darktidevr::core::DeliveryCadence delivery_cadence;
    std::uint64_t cadence_distinct_total{}, cadence_generation{};
    wchar_t precise_pair_wait_value[2]{};
    const bool precise_pair_wait_requested = !(GetEnvironmentVariableW(
        L"DTVR_XR_PRECISE_PAIR_WAIT", precise_pair_wait_value, 2) == 1 &&
        precise_pair_wait_value[0] == L'0');
    darktidevr::xr::PairPollWait pair_poll_wait(precise_pair_wait_requested);
    auto previous_pair_wait_failures = pair_poll_wait.failures();
    std::cout << "openxr.pair_poll_wait requested=" << precise_pair_wait_requested
              << " precise=" << pair_poll_wait.precise()
              << " failures=" << pair_poll_wait.failures() << '\n';
    using FrameStage = darktidevr::core::FrameStage;
    auto report_pose_wait = [&](const char* stage, ULONGLONG began) {
      const auto ended = GetTickCount64();
      if (ended - began >= 100 && pose_timing_reports++ < 256) {
        std::cout << "openxr.pose_wait stage=" << stage
                  << " tick_ms=" << ended << " duration_ms=" << ended - began
                  << " last_publish_ms=" << last_pose_publish_tick << '\n';
      }
    };

    std::optional<std::chrono::steady_clock::time_point>
        projection_resume_started;
    std::uint64_t projection_resume_ready_value{};
    std::uint64_t projection_resume_gameplay_generation{};
    const auto start = std::chrono::steady_clock::now();
    // The gate's flag file lives in the same folder: an unattended run starts
    // the game through Steam, so the viewer never sees the runner's
    // environment and an environment-only switch could not be proved without
    // a head on (18 September).
    std::wstring reticle_in_eyes_flag;
    wchar_t reticle_scale_file[32768]{};
    const auto reticle_scale_path_length = GetEnvironmentVariableW(
        L"DTVR_RETICLE_SCALE_FILE", reticle_scale_file, 32768);
    if (reticle_scale_path_length >= 32768) reticle_scale_file[0] = L'\0';
    if (reticle_scale_path_length == 0) {
      // Installed beside the mod's bin directory: the Lua crosshair feedback
      // writes the scale one level above this executable.
      std::wstring executable_directory(32768, L'\0');
      const auto executable_length = GetModuleFileNameW(
          nullptr, executable_directory.data(), 32768);
      const auto separator = executable_length != 0 && executable_length < 32768
          ? executable_directory.find_last_of(L"\\/") : std::wstring::npos;
      if (separator != std::wstring::npos) {
        executable_directory.resize(separator + 1);
        const auto candidate = executable_directory +
            L"..\\darktidevr_crosshair_scale.flag";
        if (candidate.size() < 32768) {
          std::copy(candidate.begin(), candidate.end(), reticle_scale_file);
          reticle_scale_file[candidate.size()] = L'\0';
        }
        reticle_in_eyes_flag = executable_directory +
            L"..\\darktidevr_reticle_in_eyes.flag";
      }
    }
    float reticle_scale = 0.7F;
    auto next_reticle_scale_poll = start;
    // Aim-down-sights focus: eased from the published aim state; tightens the
    // reticle and drives the vignette sprite alpha.
    float ads_blend = 0.0F;
    // The painted strength of each flat swapchain image. The sprite lives in
    // a corner of that shared texture and every image keeps whatever was last
    // written into it, so painting only when the strength changed wrote one
    // image and left the rest holding stale pixels: the vignette showed, at
    // best, on one frame in as many as the runtime has images (built 12
    // September, never seen worn).
    std::vector<float> ads_painted_blend(
        flat_images.empty() ? std::size_t{1} : flat_images.size(), -1.0F);
    bool ads_vignette_logged{};
    auto ads_last_tick = start;
    auto last_live_report = start;
    auto next_cached_pair_report = start;
    std::uint32_t last_live_submitted_frames{};
    std::uint64_t last_live_fresh_shared_pairs{};
    std::uint64_t cached_original_submissions{}, last_live_cached_original_submissions{}, last_live_generated_submissions{};
    std::uint32_t last_live_fallback_frames{};
    std::uint32_t processed_frames{};
    std::uint64_t synthetic_head_frames{};
    std::uint64_t synthetic_body_inspection_frames{};
    std::uint64_t synthetic_roomscale_frames{};
    std::uint64_t synthetic_crouch_frames{};
    darktidevr::math::Vec3 latest_camera_translation{};
    darktidevr::math::Vec3 latest_body_follow_offset{};
    std::array<std::uint64_t, 4> synthetic_head_phase_frames{};
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
    std::uint32_t flat_image_index{};
    ID3D12Resource* flat_resource{};
    bool pointer_swatch_uploaded{};
    bool pointer_swatch_release_pending{};
    ComPtr<ID3D12Resource> menu_readback;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT menu_readback_footprint{};
    std::uint64_t menu_readback_total_bytes{};
    std::uint32_t menu_readback_copies{};
    // True while no menu readback is pending. The readback request file arms
    // one; it no longer runs on every menu attach (two large PPM writes, and
    // the source of a level-load crash when the crop exceeded the texture).
    bool menu_readback_logged{true};
    const auto menu_readback_request_path =
        std::filesystem::temp_directory_path() /
        "darktidevr-menu-readback.request";
    auto next_menu_readback_request_poll = start;
    std::array<ComPtr<ID3D12Resource>, 2> shared_eye_readbacks;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT shared_eye_readback_footprint{};
    std::uint64_t shared_eye_readback_total_bytes{};
    bool shared_eye_readback_requested{};
    bool shared_eye_readback_copied_this_frame{};
    const auto shared_eye_readback_request_path =
        std::filesystem::temp_directory_path() /
        "darktidevr-shared-eye-readback.request";
    auto next_shared_eye_readback_request_poll = start;
    std::array<ComPtr<ID3D12Resource>, 2> projected_eye_readbacks;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT projected_eye_readback_footprint{};
    std::uint64_t projected_eye_readback_total_bytes{};
    bool projected_eye_readback_requested{};
    bool projected_eye_readback_copied_this_frame{};
    const auto projected_eye_readback_request_path =
        std::filesystem::temp_directory_path() /
        "darktidevr-projected-eye-readback.request";
    auto next_projected_eye_readback_request_poll = start;
    auto detach_shared_eyes =
        [&](const char* reason, UINT64 ready, UINT64 consumed,
            std::chrono::steady_clock::time_point now) {
          std::cerr << "openxr.shared_eyes=detached reason=" << reason
                    << " ready=" << ready << " consumed=" << consumed
                    << '\n';
          opened_eyes.reset();
          original_surfaces.reset();
          generated_surfaces.reset();
          shared_eye_readbacks = {};
          shared_eye_readback_footprint = {};
          shared_eye_readback_total_bytes = 0;
          shared_eye_readback_copied_this_frame = false;
          shared_last_ready_value = 0;
          shared_last_advance = now;
          last_pair_pose_checked_ready_value = 0;
          rendered_pair_pose_ready_value = 0;
          rendered_pair_gameplay_generation = 0;
          last_submitted_shared_value = 0;
          ingested_original_ready=last_original_ready=last_original_pose=generated_displayed_before_original=0;
          generated_cadence={};
          for(auto& original:pending_originals) original.ready=0;
          next_shared_open_attempt = now;
        };
    auto detach_shared_menu =
        [&](const char* reason, UINT64 ready, UINT64 consumed,
            std::chrono::steady_clock::time_point now) {
          std::cerr << "openxr.shared_menu=detached reason=" << reason
                    << " ready=" << ready << " consumed=" << consumed
                    << '\n';
          opened_menu.reset();
          menu_readback.Reset();
          menu_readback_footprint = {};
          menu_readback_total_bytes = 0;
          menu_readback_copies = 0;
          menu_readback_logged = true;
          next_menu_open_attempt = now;
        };

    XrTime last_tracking_prediction{};
    XrDuration tracking_period{};
    std::chrono::steady_clock::time_point last_tracking_prediction_at{};
    auto next_wait_tracking_update = std::chrono::steady_clock::now();
    auto update_tracking = [&](XrTime display_time, bool render_allowed,
                               darktidevr::math::Pose& current_head,
                               bool& current_head_valid) {
      bool head_recenter_requested = reference_space_recenter_pending_;
      reference_space_recenter_pending_ = false;
      if (!synthetic_controller_path) {
        sync_controller_actions(display_time);
      }

      bool submit_layer = render_allowed;
      current_head = {};
      current_head_valid = false;
      if (stereo && submit_layer) {
        XrViewState view_state{XR_TYPE_VIEW_STATE};
        XrViewLocateInfo locate_info{XR_TYPE_VIEW_LOCATE_INFO};
        locate_info.viewConfigurationType =
            XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
        locate_info.displayTime = display_time;
        locate_info.space = local_space_;
        std::uint32_t located_count{};
        check_xr(xrLocateViews(session_, &locate_info, &view_state,
                               static_cast<std::uint32_t>(located_views.size()),
                               &located_count, located_views.data()),
                 "xrLocateViews(theatre stereo)");
        const auto valid_flags = XR_VIEW_STATE_POSITION_VALID_BIT |
                                 XR_VIEW_STATE_ORIENTATION_VALID_BIT;
        submit_layer = located_count == located_views.size() &&
                       (view_state.viewStateFlags & valid_flags) == valid_flags &&
                       located_views_have_usable_fov();
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
          if (head_recenter_requested) {
            head_recenter_pose =
                darktidevr::core::horizon_locked_recenter_pose(current_head);
            synthetic_roomscale_origin = *head_recenter_pose;
            controller_recenter_pose_ = *head_recenter_pose;
            // Recentring changes the tracking-space reference, not the game
            // character's already-applied world displacement. Keep the
            // cumulative root target continuous so reset-view cannot teleport
            // the collision capsule back toward its spawn point.
            recentered_view_poses_valid = false;
            rendered_pair_pose_ready_value = 0;
            head_pose_history.clear();
            gameplay_aim_origin_history.clear();
            // A flat panel is anchored independently in LOCAL space. Force the
            // active presentation state to rebuild it from this same leveled
            // centre-head pose, otherwise a recenter corrects the world while
            // leaving a loading board at its old yaw.
            flat_fallback_anchor_state.reset();
            ++head_recenter_generation;
            std::cout << "openxr.head_recenter=applied\n";
          }
          if (!head_recenter_pose) {
            head_recenter_pose =
                darktidevr::core::horizon_locked_recenter_pose(current_head);
            synthetic_roomscale_origin = *head_recenter_pose;
            controller_recenter_pose_ = *head_recenter_pose;
            ++head_recenter_generation;
          }
          if (synthetic_roomscale_path) {
            if (!synthetic_roomscale_origin) {
              synthetic_roomscale_origin = *head_recenter_pose;
            }
            const auto synthetic_position =
                darktidevr::harness::synthetic_roomscale_position(
                    synthetic_roomscale_frames++);
            current_head.position = {
                synthetic_roomscale_origin->position.x + synthetic_position.x,
                synthetic_roomscale_origin->position.y + synthetic_position.y,
                synthetic_roomscale_origin->position.z + synthetic_position.z};
          }
          if (synthetic_crouch_path) {
            if (!synthetic_roomscale_origin) {
              synthetic_roomscale_origin = *head_recenter_pose;
            }
            const auto synthetic_position =
                darktidevr::harness::synthetic_crouch_position(
                    synthetic_crouch_frames++);
            current_head.position = {
                synthetic_roomscale_origin->position.x + synthetic_position.x,
                synthetic_roomscale_origin->position.y + synthetic_position.y,
                synthetic_roomscale_origin->position.z + synthetic_position.z};
          }
          const auto head_translation =
              darktidevr::core::sliding_head_translation(
                  *head_recenter_pose, current_head, {0.0F, 1.2F});
          auto delta = head_translation.camera_delta;
          body_follow_offset.x += head_translation.body_follow_delta.x;
          body_follow_offset.y += head_translation.body_follow_delta.y;
          body_follow_offset.z += head_translation.body_follow_delta.z;
          latest_camera_translation = delta.position;
          latest_body_follow_offset = body_follow_offset;
          controller_recenter_pose_ = *head_recenter_pose;
          if (synthetic_head_sweep) {
            const auto synthetic =
                darktidevr::harness::synthetic_head_path_sample(
                    synthetic_head_frames++, delta.position);
            delta = synthetic.delta;
            ++synthetic_head_phase_frames[
                static_cast<std::size_t>(synthetic.phase)];
          }
          if (synthetic_body_inspection) {
            delta = darktidevr::harness::synthetic_body_inspection_pose(
                delta.position);
            ++synthetic_body_inspection_frames;
          }
          if (synthetic_neck_pivot_path) {
            delta = darktidevr::harness::synthetic_neck_pivot_path_sample(
                synthetic_head_frames++, delta.position);
          }
          darktidevr::core::SharedHeadPoseSample pose_sample{};
          pose_sample.sequence = ++head_pose_sequence;
          pose_sample.recenter_generation = head_recenter_generation;
          pose_sample.pose = delta;
          pose_sample.body_follow_offset = body_follow_offset;
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
          if (stage_space_ != XR_NULL_HANDLE) {
            XrSpaceLocation stage_head{XR_TYPE_SPACE_LOCATION};
            check_xr(xrLocateSpace(view_space_, stage_space_,
                                   display_time,
                                   &stage_head),
                     "xrLocateSpace(VIEW in STAGE)");
            const auto floor_flags = XR_SPACE_LOCATION_POSITION_VALID_BIT |
                                     XR_SPACE_LOCATION_POSITION_TRACKED_BIT;
            if ((stage_head.locationFlags & floor_flags) == floor_flags) {
              pose_sample.floor_eye_height_metres =
                  stage_head.pose.position.y;
            }
          }
          runtime_ipd_metres_ = pose_sample.ipd_metres;
          const darktidevr::math::Pose submitted_head_delta{
              delta.orientation,
              {delta.position.x * projection_translation_scale,
               delta.position.y * projection_translation_scale,
               delta.position.z * projection_translation_scale}};
          for (std::size_t eye = 0; eye < located_views.size(); ++eye) {
            pose_sample.render_frusta[eye] = {
                located_views[eye].fov.angleLeft,
                located_views[eye].fov.angleRight,
                located_views[eye].fov.angleDown,
                located_views[eye].fov.angleUp};
          }
          if (last_pose_publish_tick) report_pose_wait("publication_gap", last_pose_publish_tick);
          if (!head_pose_writer->publish(pose_sample)) {
            throw std::runtime_error("Shared head-pose publication failed");
          }
          last_pose_publish_tick = GetTickCount64();
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
                    *head_recenter_pose, submitted_head_delta, current_head,
                    current_eye);
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
          gameplay_aim_origin_history.emplace_back(head_pose_sequence,
                                                   *head_recenter_pose);
          while (gameplay_aim_origin_history.size() > 512) {
            gameplay_aim_origin_history.pop_front();
          }
          while (head_pose_history.size() > 512) {
            head_pose_history.pop_front();
          }
        }
      }
      return submit_layer;
    };
    auto next_stop_file_poll = start;
    auto next_capture_source_poll = start;
    std::uint32_t runtime_stop_pauses{};
    runtime_stop_resumable_ = true;
    for (std::uint32_t frame = 0; frame < frame_count; ++frame) {
      if (duration && std::chrono::steady_clock::now() - start >= *duration) {
        break;
      }
      if (stop_file && std::chrono::steady_clock::now() >= next_stop_file_poll) {
        next_stop_file_poll = std::chrono::steady_clock::now() + std::chrono::milliseconds(250);
        if (GetFileAttributesW(stop_file->c_str()) != INVALID_FILE_ATTRIBUTES) {
          std::cout << "openxr.stop_file=requested\n";
          break;
        }
      }
      if (window_capture && !window_capture->source_window_alive()) {
        std::cout << "openxr.capture_window=closed session_exit=clean\n";
        break;
      }
      // A runtime-initiated stop must end the loop through the normal
      // cleanup instead of failing the next frame call.
      if (runtime_stop_pending_ && !runtime_exit_requested_) {
        // Headset asleep: end the session, keep the swapchains and wait for
        // READY, still honouring the stop file, the game window and the
        // duration; then begin again and carry on with the next frame.
        runtime_stop_pending_ = false;
        check_xr(xrEndSession(session_), "xrEndSession(runtime stop)");
        session_running_ = false;
        ++runtime_stop_pauses;
        std::cout << "openxr.session_pause=runtime_stop count="
                  << runtime_stop_pauses << " frame=" << frame << '\n';
        const auto pause_start = std::chrono::steady_clock::now();
        bool resume{};
        while (!runtime_exit_requested_) {
          poll_session_events();
          if (session_state_ == XR_SESSION_STATE_READY) {
            resume = true;
            break;
          }
          if (stop_file &&
              GetFileAttributesW(stop_file->c_str()) != INVALID_FILE_ATTRIBUTES) {
            std::cout << "openxr.stop_file=requested\n";
            break;
          }
          if (window_capture && !window_capture->source_window_alive()) {
            std::cout << "openxr.capture_window=closed session_exit=clean\n";
            break;
          }
          if (duration && std::chrono::steady_clock::now() - start >= *duration) {
            break;
          }
          std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        if (!resume) {
          std::cout << "openxr.session_exit=paused state="
                    << static_cast<int>(session_state_) << '\n';
          break;
        }
        XrSessionBeginInfo resume_info{XR_TYPE_SESSION_BEGIN_INFO};
        resume_info.primaryViewConfigurationType =
            XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
        check_xr(xrBeginSession(session_, &resume_info),
                 "xrBeginSession(theatre resume)");
        session_running_ = true;
        std::cout << "openxr.session_resume=ready paused_ms="
                  << std::chrono::duration_cast<std::chrono::milliseconds>(
                         std::chrono::steady_clock::now() - pause_start).count()
                  << '\n';
      }
      if (runtime_exit_requested_) {
        std::cout << "openxr.session_exit=runtime state="
                  << static_cast<int>(session_state_) << '\n';
        break;
      }
      if (acquire_capture_source && !window_capture &&
          std::chrono::steady_clock::now() >= next_capture_source_poll) {
        next_capture_source_poll =
            std::chrono::steady_clock::now() + std::chrono::milliseconds(500);
        try {
          acquire_capture_source();
          std::cout << "openxr.capture_window=acquired frame=" << frame << '\n';
        } catch (const std::exception&) {
          // Still pending; the next poll retries without repeating the log.
        }
      }
      const auto frame_start = std::chrono::steady_clock::now();
      if (frame_start >= next_menu_readback_request_poll) {
        next_menu_readback_request_poll =
            frame_start + std::chrono::milliseconds(250);
        std::error_code request_error;
        if (std::filesystem::remove(menu_readback_request_path,
                                    request_error)) {
          menu_readback_copies = 0;
          menu_readback_logged = false;
          std::cout << "openxr.shared_menu_readback=requested\n";
        } else if (request_error) {
          std::cerr << "warning: menu readback request poll failed: "
                    << request_error.message() << '\n';
        }
      }
      if (frame_start >= next_shared_eye_readback_request_poll) {
        next_shared_eye_readback_request_poll =
            frame_start + std::chrono::milliseconds(250);
        std::error_code request_error;
        if (std::filesystem::remove(shared_eye_readback_request_path,
                                    request_error)) {
          shared_eye_readback_requested = true;
          std::cout << "openxr.shared_eye_readback=requested\n";
        } else if (request_error) {
          std::cerr << "warning: shared-eye readback request poll failed: "
                    << request_error.message() << '\n';
        }
      }
      if ((tracked_cuff_renderer || panel_renderer) &&
          frame_start >= next_projected_eye_readback_request_poll) {
        next_projected_eye_readback_request_poll =
            frame_start + std::chrono::milliseconds(250);
        std::error_code request_error;
        if (std::filesystem::remove(projected_eye_readback_request_path,
                                    request_error)) {
          if (!projected_eye_readbacks[0]) {
            const auto eye_description =
                theatre_images[0][0].texture->GetDesc();
            device->GetCopyableFootprints(
                &eye_description, 0, 1, 0,
                &projected_eye_readback_footprint, nullptr, nullptr,
                &projected_eye_readback_total_bytes);
            D3D12_HEAP_PROPERTIES readback_heap{};
            readback_heap.Type = D3D12_HEAP_TYPE_READBACK;
            D3D12_RESOURCE_DESC readback_description{};
            readback_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
            readback_description.Width = projected_eye_readback_total_bytes;
            readback_description.Height = 1;
            readback_description.DepthOrArraySize = 1;
            readback_description.MipLevels = 1;
            readback_description.SampleDesc.Count = 1;
            readback_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
            for (std::size_t eye = 0; eye < theatre_swapchain_count; ++eye) {
              check(device->CreateCommittedResource(
                        &readback_heap, D3D12_HEAP_FLAG_NONE,
                        &readback_description,
                        D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
                        IID_PPV_ARGS(&projected_eye_readbacks[eye])),
                    "CreateCommittedResource(projected-eye readback)");
            }
          }
          projected_eye_readback_requested = true;
          std::cout << "openxr.projected_eye_readback=requested\n";
        } else if (request_error) {
          std::cerr << "warning: projected-eye readback request poll failed: "
                    << request_error.message() << '\n';
        }
      }
      if (opened_eyes) {
        const auto ready = opened_eyes->ready_fence->GetCompletedValue();
        const auto consumed =
            opened_eyes->consumed_fence->GetCompletedValue();
        if (!darktidevr::bridge::shared_fence_values_healthy(ready,
                                                             consumed)) {
          detach_shared_eyes(
              "poisoned_fence", ready, consumed, frame_start);
        }
      }
      if (shared_eyes && !projection_active_event) {
        projection_active_event = OpenEventW(
            SYNCHRONIZE, FALSE,
            L"Local\\DarktideVR-projection-active-v1");
      }
      const bool projection_active =
          !shared_eyes || [&] {
            constexpr std::uint64_t kPresentationMaximumAgeMs = 1500;
            const auto presentation_now_ms = GetTickCount64();
            darktidevr::core::SharedPresentationState newest{};
            if (presentation_state_reader.read(newest) &&
                darktidevr::core::presentation_state_fresh(
                    newest, presentation_now_ms,
                    kPresentationMaximumAgeMs)) {
              if (newest.transport_generation !=
                      presentation_transport_generation ||
                  newest.sequence != presentation_sequence) {
                const bool was_projection_active =
                    darktidevr::core::immersive_projection_active(
                        presentation_state.mode);
                const bool will_be_projection_active =
                    darktidevr::core::immersive_projection_active(newest.mode);
                const auto panel_extent =
                    darktidevr::core::fit_panel_extent(
                        newest.crop_width, newest.crop_height,
                        newest.maximum_panel_width_metres,
                        newest.maximum_panel_height_metres);
                std::cout << "openxr.presentation mode="
                          << static_cast<std::uint32_t>(newest.mode)
                          << " generation=" << newest.transport_generation
                          << " sequence=" << newest.sequence << " source="
                          << newest.source_width << 'x' << newest.source_height
                          << " crop=" << newest.crop_x << ',' << newest.crop_y
                          << ',' << newest.crop_width << 'x'
                          << newest.crop_height << " panel_metres="
                          << panel_extent.width_metres << 'x'
                          << panel_extent.height_metres << '\n';
                if (!was_projection_active && will_be_projection_active) {
                  projection_resume_started = frame_start;
                  projection_resume_ready_value = shared_last_ready_value;
                } else if (!will_be_projection_active) {
                  // Capture the outgoing generation when entering the menu.
                  // On exit Lua may already have committed its restored pose
                  // before we observe the mode change; sampling it there would
                  // wait forever for a second commit that is not required.
                  if (was_projection_active) {
                    projection_resume_gameplay_generation =
                        head_pose_writer
                            ? head_pose_writer->read_gameplay_generation()
                            : 0;
                  }
                  projection_resume_started.reset();
                }
              }
              // The game's recentre-view keybind takes the same path as a
              // runtime recentre: the next tracking update rebases on the
              // current head and advances the recenter generation.
              if (recenter_request_tracker.observe(newest)) {
                reference_space_recenter_pending_ = true;
                flat_reanchor_pending_ = true;
                flat_reanchor_after_ = 0;
                std::cout << "openxr.head_recenter=game-request count="
                          << newest.recenter_request << '\n';
              }
              darktidevr::core::HapticPulse haptic_pulse{};
              if (haptic_request_tracker.observe(newest, haptic_pulse)) {
                apply_haptic_pulse(haptic_pulse, newest.haptic_request);
              }
              presentation_state = newest;
              presentation_sequence = newest.sequence;
              presentation_transport_generation =
                  newest.transport_generation;
              return darktidevr::core::immersive_projection_active(
                  newest.mode);
            }
            // A four-attempt seqlock read can transiently collide with a
            // heartbeat. Reuse only a still-fresh cached packet. Once the
            // transport has been established, an expired publisher must not
            // fall back to a permanently signalled legacy event.
            if (presentation_transport_generation != 0 &&
                darktidevr::core::presentation_state_fresh(
                    presentation_state, presentation_now_ms,
                    kPresentationMaximumAgeMs)) {
              return darktidevr::core::immersive_projection_active(
                  presentation_state.mode);
            }
            return presentation_transport_generation == 0 &&
                   projection_active_event &&
                    WaitForSingleObject(projection_active_event, 0) ==
                        WAIT_OBJECT_0;
          }();
      if (window_capture) {
        window_capture->set_gameplay_reticle_atlas_enabled(
            enable_gameplay_reticle && presentation_sequence != 0 &&
            presentation_state.mode == darktidevr::core::
                                           SharedPresentationMode::stereo_world);
      }
      if (opened_eyes && head_pose_writer) {
        const auto current_generation =
            head_pose_writer->read_eye_surface_generation();
        if (current_generation != shared_eye_generation) {
          const auto old_ready =
              opened_eyes->ready_fence->GetCompletedValue();
          const auto old_consumed =
              opened_eyes->consumed_fence->GetCompletedValue();
          detach_shared_eyes("replaced_generation", old_ready,
                             old_consumed, frame_start);
        }
      }
      if (window_capture && presentation_sequence != 0) {
        // PrintWindow captures the already-scaled desktop client, not the
        // producer's 2112x2304 render target. Applying the render-target crop
        // here retained only 1080/2304 of the physical client and visibly cut
        // off the lower half of every menu. Capture the complete client; the
        // producer-space crop remains useful for panel/input coordinates.
        window_capture->set_source_crop(
            presentation_state.source_width,
            presentation_state.source_height, 0, 0,
            presentation_state.source_width,
            presentation_state.source_height);
      }
      if (shared_eyes && !opened_eyes &&
          frame_start >= next_shared_open_attempt) {
        next_shared_open_attempt = frame_start + std::chrono::milliseconds(250);
        try {
          auto candidate_eyes = darktidevr::bridge::open_shared_eye_surfaces(
              device, shared_eye_names,
              {{shared_eye_width, shared_eye_height},
               DXGI_FORMAT_R8G8B8A8_UNORM});
          shared_last_ready_value =
              candidate_eyes.ready_fence->GetCompletedValue();
          const auto initial_consumed_value =
              candidate_eyes.consumed_fence->GetCompletedValue();
          if (!darktidevr::bridge::shared_fence_values_healthy(
                  shared_last_ready_value, initial_consumed_value)) {
            throw std::runtime_error("Shared eye fence generation is poisoned");
          }
          opened_eyes = std::move(candidate_eyes);
          const auto eye_description = opened_eyes->eyes[0]->GetDesc();
          UINT eye_rows{};
          UINT64 eye_row_bytes{};
          device->GetCopyableFootprints(
              &eye_description, 0, 1, 0, &shared_eye_readback_footprint,
              &eye_rows, &eye_row_bytes, &shared_eye_readback_total_bytes);
          D3D12_HEAP_PROPERTIES readback_heap{};
          readback_heap.Type = D3D12_HEAP_TYPE_READBACK;
          D3D12_RESOURCE_DESC readback_description{};
          readback_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
          readback_description.Width = shared_eye_readback_total_bytes;
          readback_description.Height = 1;
          readback_description.DepthOrArraySize = 1;
          readback_description.MipLevels = 1;
          readback_description.SampleDesc.Count = 1;
          readback_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
          for (auto& readback : shared_eye_readbacks) {
            check(device->CreateCommittedResource(
                      &readback_heap, D3D12_HEAP_FLAG_NONE,
                      &readback_description, D3D12_RESOURCE_STATE_COPY_DEST,
                      nullptr, IID_PPV_ARGS(&readback)),
                  "ID3D12Device::CreateCommittedResource(shared-eye readback)");
          }
          shared_last_advance = frame_start;
          shared_eye_generation =
              head_pose_writer
                  ? head_pose_writer->read_eye_surface_generation()
                  : 0;
          if (shared_last_ready_value != 0) {
            // A pair published before attachment has no bridge-side pose
            // history. Acknowledge it so the producer can publish a pair
            // associated with the live XR pose stream.
            check(opened_eyes->consumed_fence->Signal(
                      shared_last_ready_value),
                  "ID3D12Fence::Signal(initial untagged pair consumed)");
          }
          std::cout << "openxr.shared_eyes=attached initial_ready="
                    << shared_last_ready_value << " initial_consumed="
                    << initial_consumed_value << '\n';
        } catch (const std::exception& error) {
          // The title and loading screens legitimately precede the game's
          // producer-owned eye surfaces. Keep publishing XR state and retry
          // while the spatial flat fallback remains visible.
          if (frame_start >= next_shared_open_error_log) {
            std::cerr << "openxr.shared_eyes=waiting reason=" << error.what()
                      << '\n';
            next_shared_open_error_log =
                frame_start + std::chrono::seconds(2);
          }
        }
      }
      // Direct-render menus (3, 4), the in-game interactive menus (5, 6) and
      // the loading and cutscene boards (2), which the producer publishes
      // from its private canvas at the presentation extent; the window
      // capture remains the fallback while no shared menu can be opened
      // (character select, title). Mode 2 takes the texture only: menu_mode
      // and the pointer stay off for it.
      const bool interactive_menu_projection =
          presentation_sequence != 0 &&
          (presentation_state.mode == darktidevr::core::
                                          SharedPresentationMode::flat_menu ||
           presentation_state.mode == darktidevr::core::
                                          SharedPresentationMode::
                                              world_anchored_menu ||
           presentation_state.mode == darktidevr::core::
                                          SharedPresentationMode::
                                              flat_loading_or_cinematic ||
           darktidevr::core::flat_interactive_active(presentation_state.mode));
      if (opened_menu) {
        const auto menu_ready =
            opened_menu->ready_fence->GetCompletedValue();
        const auto menu_consumed =
            opened_menu->consumed_fence->GetCompletedValue();
        if (!darktidevr::bridge::shared_fence_values_healthy(
                menu_ready, menu_consumed)) {
          detach_shared_menu("poisoned_fence", menu_ready, menu_consumed,
                             frame_start);
        }
      }
      if (opened_menu && head_pose_writer) {
        const auto current_generation =
            head_pose_writer->read_menu_surface_generation();
        if (current_generation != shared_menu_generation) {
          const auto old_ready =
              opened_menu->ready_fence->GetCompletedValue();
          const auto old_consumed =
              opened_menu->consumed_fence->GetCompletedValue();
          detach_shared_menu("replaced_generation", old_ready,
                             old_consumed, frame_start);
        }
      }
      // The shared menu is presented through the flat capture swapchain,
      // which exists only with a capture window title. Without it the menu
      // must stay detached rather than submit a null swapchain.
      if (shared_menu_projection_enabled && interactive_menu_projection &&
          !opened_menu && flat_swapchain == XR_NULL_HANDLE &&
          !shared_menu_unavailable_logged) {
        shared_menu_unavailable_logged = true;
        std::cout << "openxr.shared_menu=unavailable reason=no_flat_swapchain\n";
      }
      if (shared_menu_projection_enabled && interactive_menu_projection &&
          !opened_menu && flat_swapchain != XR_NULL_HANDLE &&
          frame_start >= next_menu_open_attempt) {
        next_menu_open_attempt = frame_start + std::chrono::milliseconds(250);
        try {
          opened_menu = darktidevr::bridge::open_shared_texture(
              device, shared_menu_names,
              {{presentation_state.source_width,
                presentation_state.source_height},
               DXGI_FORMAT_R8G8B8A8_UNORM});
          const auto initial =
              opened_menu->ready_fence->GetCompletedValue();
          const auto initial_consumed =
              opened_menu->consumed_fence->GetCompletedValue();
          if (!darktidevr::bridge::shared_fence_values_healthy(
                  initial, initial_consumed)) {
            throw std::runtime_error(
                "Shared menu fence generation is poisoned");
          }
          if (initial != 0) {
            check(opened_menu->consumed_fence->Signal(initial),
                  "ID3D12Fence::Signal(initial menu consumed)");
          }
          shared_menu_generation =
              head_pose_writer
                  ? head_pose_writer->read_menu_surface_generation()
                  : 0;
          std::cout << "openxr.shared_menu=attached source="
                    << presentation_state.source_width << 'x'
                    << presentation_state.source_height << " crop="
                    << presentation_state.crop_x << ','
                    << presentation_state.crop_y << ','
                    << presentation_state.crop_width << 'x'
                    << presentation_state.crop_height << '\n';
          const auto menu_description = opened_menu->texture->GetDesc();
          UINT menu_rows{};
          UINT64 menu_row_bytes{};
          device->GetCopyableFootprints(
              &menu_description, 0, 1, 0, &menu_readback_footprint,
              &menu_rows, &menu_row_bytes, &menu_readback_total_bytes);
          D3D12_HEAP_PROPERTIES readback_heap{};
          readback_heap.Type = D3D12_HEAP_TYPE_READBACK;
          D3D12_RESOURCE_DESC readback_description{};
          readback_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
          readback_description.Width = menu_readback_total_bytes;
          readback_description.Height = 1;
          readback_description.DepthOrArraySize = 1;
          readback_description.MipLevels = 1;
          readback_description.SampleDesc.Count = 1;
          readback_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
          check(device->CreateCommittedResource(
                    &readback_heap, D3D12_HEAP_FLAG_NONE,
                    &readback_description, D3D12_RESOURCE_STATE_COPY_DEST,
                    nullptr, IID_PPV_ARGS(&menu_readback)),
                "ID3D12Device::CreateCommittedResource(menu readback)");
        } catch (const std::exception& error) {
          // The resource is created lazily by the first interactive menu
          // draw. Keep the stereo world live and retry without surfacing the
          // desktop mirror as an apparently-mono substitute.
          std::cout << "openxr.shared_menu=waiting reason=" << error.what()
                    << '\n';
        }
      }
      const auto pair_wait_tick = GetTickCount64();
      const auto pair_wait_start = std::chrono::steady_clock::now();
      // Interactive menus retain projection. They must also retain live
      // producer pairs: freezing the last pre-menu image prevents the world
      // from responding to head motion even though OpenXR keeps submitting.
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
        const auto distinct_frame_available=[&] {
          if(!original_surfaces)
            return opened_eyes->ready_fence->GetCompletedValue()>last_pair_pose_checked_ready_value;
          if(presentation_state.mode!=darktidevr::core::SharedPresentationMode::stereo_world) return true;
          if(original_reader.read(original_state)) {
            const auto tick=GetTickCount64();
            const auto& latest=original_state.slots[darktidevr::core::generated_frame_slot(original_state.latest_sequence)];
            if(!latest.tick_ms || latest.tick_ms>tick || tick-latest.tick_ms>=250)
              return opened_eyes->ready_fence->GetCompletedValue()>last_pair_pose_checked_ready_value;
          }
          if(generated_displayed_before_original>last_original_ready) {
            const auto elapsed=std::chrono::duration_cast<std::chrono::nanoseconds>(
                std::chrono::steady_clock::now()-last_tracking_prediction_at).count();
            // Ask the runtime for the next display prediction shortly before
            // the scheduled original. Tracking is serviced throughout this wait.
            return generated_cadence.original_ready(last_tracking_prediction+elapsed+tracking_period/2);
          }
          const auto original_available=original_surfaces->ready_fence->GetCompletedValue();
          if(original_available==UINT64_MAX) return true;
          if(generated_surfaces && generated_reader.read(generated_state)) {
            const auto& newest=generated_state.slots[darktidevr::core::generated_frame_slot(generated_state.latest_sequence)];
            const auto tick=GetTickCount64();
            if(newest.tick_ms<=tick && tick-newest.tick_ms<250) {
              const auto ready=generated_surfaces->ready_fence->GetCompletedValue();
              return ready==UINT64_MAX || (ready>generated_last_consumed &&
                  original_available>=newest.rendered_ready);
            }
          }
          for(const auto& original:pending_originals) if(original.ready>last_original_ready) return true;
          return original_available>ingested_original_ready;
        };
        while (!distinct_frame_available() && std::chrono::steady_clock::now() < deadline) {
          const auto tracking_now = std::chrono::steady_clock::now();
          // Image submission remains pair-driven for runtime reprojection, but
          // tracking must not depend on the game completing its next image.
          // Advance the last runtime prediction by elapsed monotonic time;
          // never republish an old located pose with a fresh timestamp.
          if (last_tracking_prediction > 0 && tracking_period > 0 &&
              tracking_now >= next_wait_tracking_update &&
              !synthetic_head_sweep && !synthetic_body_inspection &&
              !synthetic_roomscale_path && !synthetic_crouch_path &&
              !synthetic_neck_pivot_path && !synthetic_controller_path) {
            poll_session_events();
            if (!session_running_) break;
            const auto elapsed_ns = std::chrono::duration_cast<
                std::chrono::nanoseconds>(tracking_now - last_tracking_prediction_at).count();
            darktidevr::math::Pose wait_head{};
            bool wait_head_valid{};
            update_tracking(last_tracking_prediction + elapsed_ns, true,
                            wait_head, wait_head_valid);
            next_wait_tracking_update = tracking_now +
                std::chrono::nanoseconds(tracking_period);
          }
          const auto poll_sleep_start = std::chrono::steady_clock::now();
          pair_poll_wait.wait();
          frame_stage_timing.elapsed(FrameStage::PairPollSleep, poll_sleep_start);
        }
        if (!distinct_frame_available()) {
          ++pair_driven_timeouts;
        }
      }
      poll_session_events();
      // A stop reported now must not start another frame: Virtual Desktop
      // still reports shouldRender while it stops, and the frame then failed
      // ID3D12GraphicsCommandList::Close(theatre) with E_INVALIDARG (14
      // September, headset unworn). The loop top ends the session and waits.
      if (runtime_stop_pending_ && !runtime_exit_requested_) {
        continue;
      }
      XrFrameWaitInfo wait_info{XR_TYPE_FRAME_WAIT_INFO};
      XrFrameState frame_state{XR_TYPE_FRAME_STATE};
      frame_stage_timing.elapsed(FrameStage::PairWait, pair_wait_start);
      report_pose_wait("pair_wait", pair_wait_tick);
      const auto runtime_wait_tick = GetTickCount64();
      const auto runtime_wait_start = std::chrono::steady_clock::now();
      check_xr(xrWaitFrame(session_, &wait_info, &frame_state),
               "xrWaitFrame(theatre)");
      frame_stage_timing.elapsed(FrameStage::WaitFrame, runtime_wait_start);
      report_pose_wait("xrWaitFrame", runtime_wait_tick);
      XrFrameBeginInfo frame_begin{XR_TYPE_FRAME_BEGIN_INFO};
      const auto frame_begin_start = std::chrono::steady_clock::now();
      check_xr(xrBeginFrame(session_, &frame_begin), "xrBeginFrame(theatre)");
      frame_stage_timing.elapsed(FrameStage::BeginFrame, frame_begin_start);
      last_tracking_prediction = frame_state.predictedDisplayTime;
      tracking_period = frame_state.predictedDisplayPeriod;
      last_tracking_prediction_at = std::chrono::steady_clock::now();
      next_wait_tracking_update = last_tracking_prediction_at +
          std::chrono::nanoseconds(tracking_period);
      darktidevr::math::Pose current_head{};
      bool current_head_valid{};
      const auto tracking_start = std::chrono::steady_clock::now();
      // shouldRender alone decides: the first frames after xrBeginSession
      // still read READY here (events not yet polled), and gating them on a
      // visible state left the projection without located views ("Invalid
      // recentered projection inputs", 14 September).
      bool submit_layer = update_tracking(frame_state.predictedDisplayTime,
          frame_state.shouldRender == XR_TRUE, current_head, current_head_valid);
      frame_stage_timing.elapsed(FrameStage::Tracking, tracking_start);
      bool submitted_shared_pair_this_frame{};
      bool submitted_cached_pair_this_frame{};
      bool submitted_generated_this_frame{};
      bool submitted_flat_fallback_this_frame{};
      // The pose and field of view the eye images are SUBMITTED with, which
      // is not the runtime's own frustum: both the layer below and the game
      // rendering the pair use a recentered symmetric projection
      // (darktidevr_projection_math.lua: Projection.recentered_eye). Anything
      // the viewer draws into those images has to use it too, so it is
      // computed once, before the theatre command list, and read by the cuffs,
      // the reticle and the layer alike. With Virtual Desktop's frusta the two
      // conventions put a point 6.2 degrees apart horizontally -- in opposite
      // directions in the two eyes -- and 5.9 vertically.
      std::array<XrPosef, 2> submitted_view_poses{};
      std::array<XrFovf, 2> submitted_view_fovs{};
      bool submitted_view_projection_valid{};
      // Experimental keyboard and mouse play adds controller disabling and the
      // mouse-aimed reticle; the reticle needs to know before the eye images
      // are drawn, the pointer below after.
      const bool keyboard_mouse_input =
          presentation_sequence != 0 && presentation_state.keyboard_mouse;
      // Filled beside the eye images, because the reticle is drawn into them;
      // read again when the layers are assembled.
      std::optional<darktidevr::math::Pose> gameplay_reticle_pose;
      XrCompositionLayerQuad gameplay_reticle_quad{
          XR_TYPE_COMPOSITION_LAYER_QUAD};
      // Set when the reticle was drawn into the eye images, which is the one
      // reason not to hand the runtime the quad as well.
      bool rendered_gameplay_reticle{};
      bool menu_readback_copied_this_frame{};
      shared_eye_readback_copied_this_frame = false;
      projected_eye_readback_copied_this_frame = false;
      // Writes the projected-eye readbacks copied this frame (the cuffs' eye
      // images, or the board's own layer) as PPM files in %TEMP%.
      const auto write_projected_eye_readback =
          [&](const std::array<ID3D12Resource*, 2>& projected_eye_sources) {
        const auto eye_description = projected_eye_sources[0]->GetDesc();
        const std::array<const char*, 2> labels{"left", "right"};
        for (std::size_t eye = 0; eye < theatre_swapchain_count; ++eye) {
          void* mapped_pixels{};
          D3D12_RANGE read_range{0, projected_eye_readback_total_bytes};
          check(projected_eye_readbacks[eye]->Map(
                    0, &read_range, &mapped_pixels),
                "ID3D12Resource::Map(projected-eye readback)");
          const auto diagnostic_path =
              std::filesystem::temp_directory_path() /
              (std::string("darktidevr-projected-eye-") + labels[eye] +
               ".ppm");
          std::ofstream diagnostic(diagnostic_path, std::ios::binary);
          if (!diagnostic) {
            projected_eye_readbacks[eye]->Unmap(0, nullptr);
            throw std::runtime_error(
                "Could not open projected-eye readback output");
          }
          diagnostic << "P6\n" << eye_description.Width << ' '
                     << eye_description.Height << "\n255\n";
          const auto* pixels =
              static_cast<const std::uint8_t*>(mapped_pixels);
          std::vector<std::uint8_t> row(
              static_cast<std::size_t>(eye_description.Width) * 3);
          for (std::uint32_t y = 0; y < eye_description.Height; ++y) {
            const auto* source_row = pixels +
                static_cast<std::size_t>(y) *
                    projected_eye_readback_footprint.Footprint.RowPitch;
            for (std::uint32_t x = 0; x < eye_description.Width; ++x) {
              const auto* source =
                  source_row + static_cast<std::size_t>(x) * 4;
              auto* destination =
                  row.data() + static_cast<std::size_t>(x) * 3;
              destination[0] = source[0];
              destination[1] = source[1];
              destination[2] = source[2];
            }
            diagnostic.write(
                reinterpret_cast<const char*>(row.data()),
                static_cast<std::streamsize>(row.size()));
          }
          projected_eye_readbacks[eye]->Unmap(0, nullptr);
          std::cout << "openxr.projected_eye_readback="
                    << diagnostic_path.string() << '\n';
        }
        projected_eye_readback_requested = false;
      };
      if (submit_layer) {
        XrSwapchainImageAcquireInfo acquire_info{
            XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
        XrSwapchainImageWaitInfo image_wait{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};
        image_wait.timeout = XR_INFINITE_DURATION;
        for (std::size_t eye = 0; eye < theatre_swapchain_count; ++eye) {
          const auto acquire_start = std::chrono::steady_clock::now();
          check_xr(xrAcquireSwapchainImage(theatre_swapchains[eye],
                                           &acquire_info,
                                           &image_indices[eye]),
                   "xrAcquireSwapchainImage(theatre)");
          const auto swapchain_eye_tick = GetTickCount64();
          check_xr(xrWaitSwapchainImage(theatre_swapchains[eye], &image_wait),
                   "xrWaitSwapchainImage(theatre)");
          frame_stage_timing.elapsed(FrameStage::SwapchainAcquireWait, acquire_start);
          report_pose_wait("swapchain_eye", swapchain_eye_tick);
          resources[eye] = theatre_images[eye][image_indices[eye]].texture;
        }
        if (flat_swapchain != XR_NULL_HANDLE) {
          const auto acquire_start = std::chrono::steady_clock::now();
          check_xr(xrAcquireSwapchainImage(flat_swapchain, &acquire_info,
                                           &flat_image_index),
                   "xrAcquireSwapchainImage(flat capture)");
          const auto swapchain_flat_tick = GetTickCount64();
          check_xr(xrWaitSwapchainImage(flat_swapchain, &image_wait),
                   "xrWaitSwapchainImage(flat capture)");
          frame_stage_timing.elapsed(FrameStage::SwapchainAcquireWait, acquire_start);
          report_pose_wait("swapchain_flat", swapchain_flat_tick);
          flat_resource = flat_images[flat_image_index].texture;
        }

        check(allocator->Reset(),
              "ID3D12CommandAllocator::Reset(theatre)");
        check(command_list->Reset(allocator.Get(), nullptr),
              "ID3D12GraphicsCommandList::Reset(theatre)");
        UINT64 shared_ready_for_frame{};
        UINT64 menu_ready_for_frame{};
        bool discard_shared_pair_this_frame =
            opened_eyes && !projection_active;
        if (opened_eyes) {
          shared_ready_for_frame =
              opened_eyes->ready_fence->GetCompletedValue();
          const auto consumed =
              opened_eyes->consumed_fence->GetCompletedValue();
          if (!darktidevr::bridge::shared_fence_values_healthy(
                  shared_ready_for_frame, consumed)) {
            detach_shared_eyes("poisoned_fence_before_copy",
                               shared_ready_for_frame, consumed, frame_start);
            shared_ready_for_frame = 0;
            discard_shared_pair_this_frame = false;
          } else if (shared_ready_for_frame > shared_last_ready_value) {
            shared_last_ready_value = shared_ready_for_frame;
            shared_last_advance = std::chrono::steady_clock::now();
          }
        }
        if (opened_menu) {
          menu_ready_for_frame =
              opened_menu->ready_fence->GetCompletedValue();
          const auto consumed =
              opened_menu->consumed_fence->GetCompletedValue();
          if (!darktidevr::bridge::shared_fence_values_healthy(
                  menu_ready_for_frame, consumed)) {
            detach_shared_menu("poisoned_fence_before_copy",
                               menu_ready_for_frame, consumed, frame_start);
            menu_ready_for_frame = 0;
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
                rendered_pair_pose_sequence = tagged_sequence;
                rendered_pair_pose_ready_value = shared_ready_for_frame;
                rendered_pair_gameplay_generation =
                    rendered_pair.gameplay_generation;
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
        const auto committed_gameplay_generation =
            head_pose_writer
                ? head_pose_writer->read_gameplay_generation()
                : 0;
        // A pose-synchronised pair can still belong to the outgoing shop
        // camera. Resume only when Lua has restored the authoritative gameplay
        // orientation and the producer has stamped a completed pair with that
        // newly committed generation.
        const bool projection_pair_settled =
            !projection_resume_started || !cached_pair_valid ||
            (committed_gameplay_generation >
                 projection_resume_gameplay_generation &&
             rendered_pair_gameplay_generation ==
                 committed_gameplay_generation);
        // Queued originals are copied from the shared-eye resources, so the
        // ring can only attach in shared-eye mode.
        if (shared_eyes && !original_surfaces && std::chrono::steady_clock::now() >= next_generated_open) {
          next_generated_open = std::chrono::steady_clock::now() + std::chrono::seconds(1);
          if (original_reader.read(original_state) &&
              original_state.width==shared_eye_width*2 && original_state.height==shared_eye_height) {
            try {
              darktidevr::bridge::SharedGeneratedSurfaceNames original_names{{
                  L"Local\\DarktideVR-original-stereo-0",L"Local\\DarktideVR-original-stereo-1",
                  L"Local\\DarktideVR-original-stereo-2"},L"Local\\DarktideVR-original-stereo-ready",
                  L"Local\\DarktideVR-original-stereo-consumed"};
              original_surfaces=darktidevr::bridge::open_shared_generated_surfaces(device,original_names,
                  {{original_state.width,original_state.height},static_cast<DXGI_FORMAT>(original_state.format)});
              ingested_original_ready=last_original_ready=last_original_pose=generated_displayed_before_original=0;
              generated_cadence={};
              D3D12_HEAP_PROPERTIES heap{}; heap.Type=D3D12_HEAP_TYPE_DEFAULT;
              const auto description=cached_eye_resources[0]->GetDesc();
              for(auto& original:pending_originals) for(auto& eye:original.eyes)
                check(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&description,
                    D3D12_RESOURCE_STATE_COMMON,nullptr,IID_PPV_ARGS(&eye)),"Create queued original");
              std::cout << "openxr.original_stereo=attached\n";
            } catch (const std::exception& error) {
              generated_surfaces.reset();
              original_surfaces.reset();
              std::cout << "openxr.generated_stereo=waiting reason=" << error.what() << '\n';
            }
          }
        }
        if(original_surfaces && !generated_surfaces && generated_reader.read(generated_state) &&
            generated_state.width==shared_eye_width*2 && generated_state.height==shared_eye_height) {
          try {
            darktidevr::bridge::SharedGeneratedSurfaceNames names{{
                L"Local\\DarktideVR-generated-stereo-0",L"Local\\DarktideVR-generated-stereo-1",
                L"Local\\DarktideVR-generated-stereo-2"},L"Local\\DarktideVR-generated-stereo-ready",
                L"Local\\DarktideVR-generated-stereo-consumed"};
            generated_surfaces=darktidevr::bridge::open_shared_generated_surfaces(device,names,
                {{generated_state.width,generated_state.height},static_cast<DXGI_FORMAT>(generated_state.format)});
            std::cout << "openxr.generated_stereo=attached\n";
          } catch(const std::exception&) { /* Original delivery remains live. */ }
        }
        std::uint64_t generated_sequence_for_frame{};
        const bool generated_world = projection_active &&
            presentation_state.mode == darktidevr::core::SharedPresentationMode::stereo_world;
        bool ingested_original_this_frame{};
        std::uint64_t original_ring_sequence_for_frame{};
        PendingOriginal* selected_original{};
        PendingOriginal direct_original;
        const std::array<XrPosef,2>* original_ring_poses{};
        darktidevr::core::SharedGeneratedFrameSlot original_metadata{};
        bool original_ring_recent{};
        if(original_surfaces && original_reader.read(original_state)) {
          const auto tick=GetTickCount64();
          const auto& latest=original_state.slots[darktidevr::core::generated_frame_slot(original_state.latest_sequence)];
          original_ring_recent=latest.tick_ms && latest.tick_ms<=tick && tick-latest.tick_ms<250;
          const auto completed=original_surfaces->ready_fence->GetCompletedValue();
          if(completed!=UINT64_MAX) {
            auto available=std::min(completed,original_state.latest_sequence);
            // Prefer the exact original needed by the newest completed
            // generated image; a newer original can already occupy another slot.
            if(generated_surfaces && generated_reader.read(generated_state)) {
              const auto generated_ready=generated_surfaces->ready_fence->GetCompletedValue();
              const auto candidate=std::min(generated_ready,generated_state.latest_sequence);
              const auto& generated=generated_state.slots[darktidevr::core::generated_frame_slot(candidate)];
              const auto wanted=generated.rendered_ready;
              if(generated_ready!=UINT64_MAX && generated.sequence==candidate && candidate>generated_last_consumed &&
                  wanted>ingested_original_ready && wanted<=available &&
                  original_state.slots[darktidevr::core::generated_frame_slot(wanted)].sequence==wanted)
                available=wanted;
            }
            const auto& metadata=original_state.slots[darktidevr::core::generated_frame_slot(available)];
            const auto original_now=GetTickCount64();
            const bool expired=metadata.tick_ms>original_now || original_now-metadata.tick_ms>=250;
            if(available>ingested_original_ready && metadata.sequence==available && generated_world && !expired &&
                metadata.gameplay_generation==committed_gameplay_generation) {
              for(const auto& history:head_pose_history) if(history.first==metadata.current_pose) original_ring_poses=&history.second;
              if(original_ring_poses) original_metadata=metadata;
            } else if(available>ingested_original_ready && metadata.sequence==available &&
                (!generated_world || expired || metadata.gameplay_generation!=committed_gameplay_generation)) {
              check(original_surfaces->consumed_fence->Signal(available),"Discard outgoing original ring image");
              ingested_original_ready=available;
            }
          }
        }
        const bool direct_original_this_frame = direct_original_requested &&
            !generated_surfaces && original_surfaces && generated_world &&
            original_ring_poses && projection_pair_settled;
        if (direct_original_this_frame) {
          // A native image is displayed immediately; it need not be retained
          // for interpolation. Keep the shared slot owned until the existing
          // queue wait/copy/consumed sequence completes below.
          direct_original.ready = original_metadata.sequence;
          direct_original.pose = original_metadata.current_pose;
          direct_original.poses = *original_ring_poses;
          direct_original.generation = original_metadata.gameplay_generation;
          direct_original.tick = GetTickCount64();
          selected_original = &direct_original;
          ingested_original_ready = original_metadata.sequence;
          original_ring_sequence_for_frame = original_metadata.sequence;
          ingested_original_this_frame = true;
        } else if(original_surfaces && generated_world && original_ring_poses && projection_pair_settled) {
          PendingOriginal* destination{};
          for(auto& original:pending_originals)
            if((!original.ready || original.ready!=generated_displayed_before_original) &&
                (!destination || original.ready<destination->ready)) destination=&original;
          if(destination && destination->eyes[0] && destination->eyes[1]) {
            auto* packed_original=original_surfaces->textures[darktidevr::core::generated_frame_slot(original_metadata.sequence)].Get();
            // Both eye regions share one source. Keep it in COPY_SOURCE until
            // both copies finish, then restore all three resources together.
            std::array<D3D12_RESOURCE_BARRIER,3> barriers{};
            for(auto& barrier:barriers) barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
            barriers[0].Transition={packed_original,D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                D3D12_RESOURCE_STATE_COMMON,D3D12_RESOURCE_STATE_COPY_SOURCE};
            for(unsigned eye=0;eye<2;++eye)
              barriers[eye+1].Transition={destination->eyes[eye].Get(),D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                  D3D12_RESOURCE_STATE_COMMON,D3D12_RESOURCE_STATE_COPY_DEST};
            command_list->ResourceBarrier(static_cast<UINT>(barriers.size()),barriers.data());
            for(unsigned eye=0;eye<2;++eye) {
              D3D12_TEXTURE_COPY_LOCATION source{}; source.pResource=packed_original;
              source.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
              D3D12_TEXTURE_COPY_LOCATION target{}; target.pResource=destination->eyes[eye].Get();
              target.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
              const D3D12_BOX box{eye*shared_eye_width,0,0,(eye+1)*shared_eye_width,shared_eye_height,1};
              command_list->CopyTextureRegion(&target,0,0,0,&source,&box);
            }
            for(auto& barrier:barriers) std::swap(barrier.Transition.StateBefore,barrier.Transition.StateAfter);
            command_list->ResourceBarrier(static_cast<UINT>(barriers.size()),barriers.data());
            destination->ready=original_metadata.sequence; destination->pose=original_metadata.current_pose;
            destination->poses=*original_ring_poses; destination->generation=original_metadata.gameplay_generation;
            destination->tick=GetTickCount64();
            generated_cadence.observe_source(original_metadata.tick_ms, original_metadata.sequence);
            ingested_original_ready=original_metadata.sequence;
            original_ring_sequence_for_frame=original_metadata.sequence;
            ingested_original_this_frame=true;
          }
        }
        for(auto& original:pending_originals) {
          if(!generated_world || original.generation!=committed_gameplay_generation || original.ready<=last_original_ready)
            original.ready=0;
          if(!direct_original_this_frame && original.ready && original.ready==generated_displayed_before_original) selected_original=&original;
        }
        if (generated_surfaces && selected_original) ++generated_reserved_original_frames;
        if (generated_surfaces && !selected_original) {
          unsigned selection_outcome{}; // unavailable reader/fence
          // Poll once. Waiting here stalls the entire OpenXR submission loop.
          do {
            if (!generated_reader.read(generated_state)) break;
            const auto available = generated_surfaces->ready_fence->GetCompletedValue();
            if (available == UINT64_MAX) break;
            const auto latest = std::min(available,generated_state.latest_sequence);
            selection_outcome=1; // no new completed generated image
            if (latest > generated_last_consumed) {
              const auto& generated = generated_state.slots[darktidevr::core::generated_frame_slot(latest)];
              const auto now_ms = GetTickCount64();
              PendingOriginal* matching{};
              for(auto& original:pending_originals)
                if(original.ready && original.ready==generated.rendered_ready && original.pose==generated.current_pose)
                  matching=&original;
              if(generated.sequence!=latest || !generated_world ||
                  generated.gameplay_generation!=committed_gameplay_generation ||
                  generated.tick_ms>now_ms || now_ms-generated.tick_ms>=250 ||
                  generated_state.width!=shared_eye_width*2 || generated_state.height!=shared_eye_height)
                selection_outcome=2;
              else if(!matching) selection_outcome=3;
              else if(generated.rendered_ready<=last_original_ready ||
                  generated.previous_pose<last_original_pose || last_original_pose==0)
                selection_outcome=4;
              else selection_outcome=5; // valid candidate, missing endpoint history
              if (generated.sequence == latest && generated_world &&
                  matching &&
                  generated.rendered_ready > last_original_ready &&
                  // A slower consumer can skip source frames. Their midpoint
                  // remains temporally valid when both endpoints follow the
                  // last displayed original; equality would discard it forever.
                  generated.previous_pose >= last_original_pose && last_original_pose != 0 &&
                  generated.gameplay_generation == committed_gameplay_generation &&
                  generated.tick_ms <= now_ms && now_ms-generated.tick_ms < 250 &&
                  generated_state.width == shared_eye_width*2 && generated_state.height == shared_eye_height) {
                const std::array<XrPosef,2>* previous{};
                const std::array<XrPosef,2>* current{};
                for (const auto& entry : head_pose_history) {
                  if (entry.first == generated.previous_pose) previous=&entry.second;
                  if (entry.first == generated.current_pose) current=&entry.second;
                }
                if (previous && current) {
                  for (unsigned eye=0;eye<2;++eye) {
                    const auto& a=(*previous)[eye]; const auto& b=(*current)[eye];
                    auto& middle=generated_view_poses[eye];
                    middle.position={(a.position.x+b.position.x)*0.5F,(a.position.y+b.position.y)*0.5F,(a.position.z+b.position.z)*0.5F};
                    const auto dot=a.orientation.x*b.orientation.x+a.orientation.y*b.orientation.y+
                        a.orientation.z*b.orientation.z+a.orientation.w*b.orientation.w;
                    const float sign=dot<0 ? -1.0F : 1.0F;
                    auto& q=middle.orientation;
                    q={a.orientation.x+sign*b.orientation.x,a.orientation.y+sign*b.orientation.y,
                       a.orientation.z+sign*b.orientation.z,a.orientation.w+sign*b.orientation.w};
                    const auto norm=std::sqrt(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w);
                    q.x/=norm; q.y/=norm; q.z/=norm; q.w/=norm;
                  }
                  generated_sequence_for_frame=latest;
                  selected_original=matching;
                  selection_outcome=6;
                  break;
                }
              }
              if (generated.sequence == latest && (!generated_world ||
                  generated.rendered_ready <= last_original_ready ||
                  generated.gameplay_generation != committed_gameplay_generation ||
                  generated.tick_ms > now_ms || now_ms-generated.tick_ms >= 250)) {
                generated_surfaces->consumed_fence->Signal(latest);
                generated_last_consumed=latest;
              }
            }
          } while (false);
          ++generated_selection_outcomes[selection_outcome];
        }
        const bool use_generated_pair = generated_sequence_for_frame != 0;
        const auto generated_tick=generated_state.slots[
            darktidevr::core::generated_frame_slot(generated_state.latest_sequence)].tick_ms;
        const auto now_tick=GetTickCount64();
        const bool generation_recent=generated_tick && generated_tick<=now_tick && now_tick-generated_tick<250;
        if(!original_ring_recent) {
          for(auto& original:pending_originals) original.ready=0;
          generated_displayed_before_original=0;
        }
        if(original_ring_recent && generated_world && !selected_original) for(auto& original:pending_originals) {
          if(original.ready && (!generation_recent || now_tick-original.tick>=25) &&
              (!selected_original || original.ready<selected_original->ready)) selected_original=&original;
        }
        const bool use_queued_original=selected_original && !use_generated_pair &&
            (selected_original->ready!=generated_displayed_before_original ||
             generated_cadence.original_ready(frame_state.predictedDisplayTime));
        const auto original_ready_for_frame=use_queued_original ? selected_original->ready : shared_ready_for_frame;
        const auto original_pose_for_frame=use_queued_original ? selected_original->pose : rendered_pair_pose_sequence;
        submitted_original_view_poses=use_queued_original ? selected_original->poses : rendered_pair_view_poses;
        const bool use_shared_pair = !use_generated_pair && (use_queued_original || (!original_ring_recent &&
            projection_active && opened_eyes && shared_ready_for_frame != 0 &&
            (!window_capture ||
             (shared_pair_fresh && shared_pair_pose_synced &&
              projection_pair_settled))));
        if (projection_active && opened_eyes && !use_shared_pair &&
            shared_ready_for_frame != 0 && shared_pair_fresh &&
            shared_pair_pose_synced && !projection_pair_settled) {
          // The producer owns a single shared slot. A settling pair that is
          // intentionally hidden behind the cached image must still be
          // consumed, otherwise this very gate prevents the next pair it is
          // waiting for from ever being produced.
          discard_shared_pair_this_frame = true;
        }
        // On a menu-to-world transition the producer can take a variable
        // number of frames to publish a newly pose-synchronised pair.  Keep
        // presenting the last complete stereo pair during that interval.
        // Falling through to the desktop capture here exposes the engine's
        // transient mono/right-eye presentation in both eyes.
        constexpr std::uint64_t cached_pair_grace_milliseconds = 5000;
        const auto shared_pair_stale_milliseconds =
            static_cast<std::uint64_t>(
                std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now() - shared_last_advance)
                    .count());
        const bool use_cached_pair =
            darktidevr::core::cached_stereo_pair_allowed(
                use_shared_pair || use_generated_pair, cached_pair_valid, projection_active,
                shared_pair_stale_milliseconds,
                cached_pair_grace_milliseconds);
        if (use_cached_pair && frame_start >= next_cached_pair_report) {
          next_cached_pair_report = frame_start + std::chrono::seconds(2);
          std::cout << "openxr.cached_pair_reason fresh=" << shared_pair_fresh
                    << " pose_synced=" << shared_pair_pose_synced
                    << " settled=" << projection_pair_settled
                    << " ready=" << shared_ready_for_frame
                    << " committed_generation=" << committed_gameplay_generation
                    << " rendered_generation=" << rendered_pair_gameplay_generation
                    << " resume_generation=" << projection_resume_gameplay_generation
                    << '\n';
        }
        submitted_shared_pair_this_frame =
            use_shared_pair || use_cached_pair || use_generated_pair;
        submitted_generated_this_frame = use_generated_pair;
        submitted_cached_pair_this_frame = use_cached_pair;
        if (stereo && projection_views.size() == located_views.size() &&
            located_views_have_usable_fov()) {
          for (std::size_t eye = 0; eye < located_views.size(); ++eye) {
            const auto base_pose =
                submitted_generated_this_frame ? generated_view_poses[eye]
                : submitted_cached_pair_this_frame ? cached_pair_view_poses[eye]
                : submitted_shared_pair_this_frame &&
                          rendered_pair_pose_ready_value != 0
                    ? submitted_original_view_poses[eye]
                    : (recentered_view_poses_valid ? recentered_view_poses[eye]
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
            submitted_view_poses[eye].orientation = {
                submitted.orientation.x, submitted.orientation.y,
                submitted.orientation.z, submitted.orientation.w};
            submitted_view_poses[eye].position = {submitted.position.x,
                                                  submitted.position.y,
                                                  submitted.position.z};
            submitted_view_fovs[eye] = {recentered.symmetric_fov.angle_left,
                                        recentered.symmetric_fov.angle_right,
                                        recentered.symmetric_fov.angle_up,
                                        recentered.symmetric_fov.angle_down};
          }
          submitted_view_projection_valid = true;
        }
        // The reticle is drawn into the eye images (--reticle-in-eyes), so
        // its pose, its scale and the aim blend have to be known while
        // those images are being recorded, not afterwards as a quad layer
        // would allow. Nothing here depends on the recording; the atlas
        // branch below now paints the vignette sprite with this frame's
        // blend rather than the previous one's.
        if (enable_gameplay_reticle && submitted_shared_pair_this_frame &&
            presentation_state.mode == darktidevr::core::
                                           SharedPresentationMode::stereo_world &&
            (latest_controller_sample_ || keyboard_mouse_input) &&
            current_head_valid) {
          darktidevr::core::SharedGameplayAimState newest_aim{};
          if (gameplay_aim_state_reader.read(newest_aim) &&
              (newest_aim.transport_generation !=
                   gameplay_aim_transport_generation ||
               newest_aim.sequence >= gameplay_aim_sequence)) {
            if (newest_aim.transport_generation !=
                    gameplay_aim_transport_generation ||
                newest_aim.sequence != gameplay_aim_sequence) {
              ++gameplay_reticle_transport_samples_;
            }
            gameplay_aim_state = newest_aim;
            gameplay_aim_sequence = newest_aim.sequence;
            gameplay_aim_transport_generation =
                newest_aim.transport_generation;
          }
          const auto required =
              darktidevr::core::controller_orientation_valid |
              darktidevr::core::controller_position_valid;
          // A hand-aimed reticle disappears with its controller. Keyboard and
          // mouse aim publishes only world-depth target points from the mouse
          // pose and never needs a tracked controller.
          const bool reticle_source_tracked =
              keyboard_mouse_input
                  ? gameplay_aim_state.target_point_valid
                  : (latest_controller_sample_->hands[1].aim_tracking_flags &
                     required) == required &&
                        darktidevr::core::pointer_origin_within_reach(
                            latest_controller_sample_->hands[1].aim_pose.position,
                            current_head.position, 1.5F);
          const auto gameplay_aim_now_ns = static_cast<std::uint64_t>(
              std::chrono::duration_cast<std::chrono::nanoseconds>(
                  // The producer can publish while xrWaitFrame or the shared
                  // pair wait blocks. Sample time after the read; frame_start
                  // would misclassify that new aim as a future timestamp.
                  std::chrono::steady_clock::now().time_since_epoch())
                  .count());
          constexpr std::uint64_t maximum_gameplay_aim_age_ns = 100'000'000ULL;
          if (gameplay_aim_state.active &&
              darktidevr::core::gameplay_aim_state_is_fresh(
                  gameplay_aim_state, gameplay_aim_now_ns,
                  maximum_gameplay_aim_age_ns) &&
              reticle_source_tracked) {
            const auto reticle_distance_metres =
                gameplay_aim_state.distance_metres;
            if (gameplay_aim_state.target_point_valid && head_pose_writer) {
              for (auto entry = gameplay_aim_origin_history.rbegin();
                   entry != gameplay_aim_origin_history.rend(); ++entry) {
                if (entry->first != gameplay_aim_state.head_pose_sequence) continue;
                const auto target = darktidevr::core::resolve_gameplay_aim_target(
                    gameplay_aim_state, entry->first,
                    head_pose_writer->transport_generation(),
                    head_recenter_generation, entry->second);
                if (target) {
                  gameplay_reticle_pose = darktidevr::math::Pose{
                      current_head.orientation, *target};
                }
                break;
              }
            } else if (!gameplay_aim_state.target_point_valid) {
              const auto& right = latest_controller_sample_->hands[1];
              const auto direction = darktidevr::math::rotate(
                  right.aim_pose.orientation, {0.0F, 0.0F, -1.0F});
              gameplay_reticle_pose = darktidevr::math::Pose{
                  current_head.orientation,
                  {right.aim_pose.position.x + direction.x * reticle_distance_metres,
                   right.aim_pose.position.y + direction.y * reticle_distance_metres,
                   right.aim_pose.position.z + direction.z * reticle_distance_metres}};
            }
            if (gameplay_reticle_pose) {
              ++gameplay_reticle_frames_;
              const auto frame_start_ns = static_cast<std::uint64_t>(
                  std::chrono::duration_cast<std::chrono::nanoseconds>(
                      frame_start.time_since_epoch()).count());
              if (gameplay_aim_state.timestamp_ns > frame_start_ns) {
                ++gameplay_reticle_post_start_frames_;
              }
              if (gameplay_aim_state.hit) {
                ++gameplay_reticle_hit_frames_;
              } else {
                ++gameplay_reticle_miss_frames_;
              }
              gameplay_reticle_distance_metres_ = reticle_distance_metres;
            }
          }
        }
        {
          const bool ads_target_active =
              presentation_state.mode == darktidevr::core::SharedPresentationMode::stereo_world &&
              gameplay_aim_state.active && gameplay_aim_state.aiming_down_sights;
          const float ads_target = ads_target_active ? 1.0F : 0.0F;
          const auto ads_dt = std::clamp(
              std::chrono::duration<float>(frame_start - ads_last_tick).count(), 0.0F, 0.1F);
          ads_last_tick = frame_start;
          const auto ads_blend_before = ads_blend;
          ads_blend += (ads_target - ads_blend) * (1.0F - std::exp(-ads_dt / 0.15F));
          if (std::abs(ads_target - ads_blend) < 0.005F) ads_blend = ads_target;
          if ((ads_blend_before <= 0.0F) != (ads_blend <= 0.0F)) {
            std::cout << "openxr.ads aiming=" << (ads_blend > 0.0F ? 1 : 0)
                      << " target=" << ads_target << '\n';
          }
        }
        const auto reticle_scale_now = std::chrono::steady_clock::now();
        if (enable_gameplay_reticle && reticle_scale_now >= next_reticle_scale_poll &&
            !reticle_in_eyes_flag.empty()) {
          // Presence is the switch; the file's contents are not read.
          std::error_code flag_error;
          const auto present = std::filesystem::exists(
              std::filesystem::path{reticle_in_eyes_flag}, flag_error);
          const auto wanted = reticle_in_eyes_environment ||
                              (!flag_error && present);
          if (wanted != reticle_in_eyes_requested) {
            reticle_in_eyes_requested = wanted;
            std::cout << "openxr.reticle_in_eyes=" << (wanted ? 1 : 0) << '\n';
          }
        }
        if (enable_gameplay_reticle && reticle_scale_file[0] && reticle_scale_now >= next_reticle_scale_poll) {
          next_reticle_scale_poll = reticle_scale_now + std::chrono::milliseconds(250);
          std::ifstream input{std::filesystem::path{reticle_scale_file}};
          float percent{};
          char extra{};
          // Keep the last valid value during missing, partial or invalid writes.
          // Zero hides the reticle (a stereo cinematic publishes it).
          if ((input >> percent) && !(input >> extra) && std::isfinite(percent) &&
              (percent == 0.0F || (percent >= 25.0F && percent <= 150.0F))) {
            const auto updated = percent / 100.0F;
            if (updated != reticle_scale) {
              reticle_scale = updated;
              std::cout << "openxr.reticle_scale_percent=" << percent << '\n';
            }
          }
        }
        // The reticle sprite lives in the flat capture atlas, which is painted
        // only while a capture window exists.
        if (gameplay_reticle_pose && window_capture &&
            flat_swapchain != XR_NULL_HANDLE) {
          constexpr std::int32_t gameplay_reticle_extent = 41;
          // Leave transparent atlas texels outside the submitted rectangle so
          // compositor filtering cannot sample the adjacent opaque capture.
          constexpr std::int32_t gameplay_reticle_inset = 2;
          constexpr auto gameplay_reticle_sample_extent =
              gameplay_reticle_extent - 2 * gameplay_reticle_inset;
          gameplay_reticle_quad.layerFlags =
              XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;
          gameplay_reticle_quad.space = local_space_;
          gameplay_reticle_quad.eyeVisibility = XR_EYE_VISIBILITY_BOTH;
          gameplay_reticle_quad.subImage.swapchain = flat_swapchain;
          gameplay_reticle_quad.subImage.imageRect.offset = {
              static_cast<std::int32_t>(flat_capture_width) -
                  gameplay_reticle_extent - 1 + gameplay_reticle_inset,
              static_cast<std::int32_t>(flat_capture_height) -
                  gameplay_reticle_extent + gameplay_reticle_inset};
          gameplay_reticle_quad.subImage.imageRect.extent = {
              gameplay_reticle_sample_extent, gameplay_reticle_sample_extent};
          gameplay_reticle_quad.pose.orientation = {
              gameplay_reticle_pose->orientation.x,
              gameplay_reticle_pose->orientation.y,
              gameplay_reticle_pose->orientation.z,
              gameplay_reticle_pose->orientation.w};
          gameplay_reticle_quad.pose.position = {
              gameplay_reticle_pose->position.x,
              gameplay_reticle_pose->position.y,
              gameplay_reticle_pose->position.z};
          const auto angular_size_metres = std::clamp(
              gameplay_reticle_distance_metres_ * 0.049F, 0.105F, 0.84F) * reticle_scale *
              (1.0F - 0.4F * ads_blend) *
              (static_cast<float>(gameplay_reticle_sample_extent) /
               static_cast<float>(gameplay_reticle_extent));
          gameplay_reticle_quad.size = {angular_size_metres,
                                        angular_size_metres};
        }
        const bool spatial_menu_overlay =
            presentation_sequence != 0 &&
            presentation_state.mode == darktidevr::core::
                                           SharedPresentationMode::
                                               world_anchored_menu;
        const bool fullscreen_menu_overlay =
            presentation_sequence != 0 &&
            presentation_state.mode == darktidevr::core::
                                           SharedPresentationMode::flat_menu;
        const bool use_shared_menu = shared_menu_projection_enabled &&
                                     interactive_menu_projection &&
                                     opened_menu.has_value();
        // Every interactive menu is a spatial quad over projection. Ordinary
        // options/pause views use a head-relative opening anchor; vendor views
        // use their body/world anchor. If a live pair is unavailable, the
        // cached pair remains a pose-correct fallback rather than replacing
        // the normal live-world path.
        const bool use_window_flat_capture =
            window_capture &&
            !spatial_menu_overlay && !fullscreen_menu_overlay &&
            !use_shared_pair && !use_cached_pair && !use_generated_pair;
        const bool use_flat_capture =
            use_shared_menu || use_window_flat_capture;
        submitted_flat_fallback_this_frame = use_flat_capture;
        // Stereo and native UI already supply their own images. The gameplay
        // reticle is painted independently below, so it does not need captures.
        // Keep source_window_alive() running even while this worker sleeps.
        if (capture_worker && capture_on_demand &&
            capture_requested != use_window_flat_capture) {
          capture_requested = use_window_flat_capture;
          capture_worker->set_enabled(capture_requested);
          std::cout << "openxr.theatre_capture_active=" << (capture_requested ? 1 : 0)
                    << " attempts=" << capture_attempts.load(std::memory_order_relaxed) << '\n';
        }
        if (window_capture) {
          const auto flat_presentation_changed =
              use_flat_capture && presentation_sequence != 0 &&
              (!flat_fallback_anchor_state ||
               !darktidevr::core::same_flat_panel_anchor_identity(
                   *flat_fallback_anchor_state, presentation_state));
          // A re-seat needs a head this frame and the runtime's change to
          // have taken effect; until then the request is kept.
          const auto flat_reanchor =
              flat_fallback_active && use_flat_capture && flat_reanchor_pending_ &&
              current_head_valid &&
              frame_state.predictedDisplayTime >= flat_reanchor_after_;
          if (use_flat_capture != flat_fallback_active ||
              flat_presentation_changed || flat_reanchor) {
            flat_fallback_active = use_flat_capture;
            if (flat_reanchor) { flat_reanchor_pending_ = false; }
            ++flat_fallback_transitions;
            // Every board, loading screens included, is a spatial board in
            // the world (the user's intent, 16 September); a recenter
            // re-seats it from the current head rather than leaving it
            // where local space moved.
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
              if (presentation_sequence != 0) {
                flat_fallback_anchor_state = presentation_state;
              } else {
                flat_fallback_anchor_state.reset();
              }
            } else if (!flat_fallback_active) {
              flat_fallback_pose_valid = false;
              flat_fallback_anchor_state.reset();
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
          barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
          // The theatre image is a copy destination only when an eye pair is
          // actually copied this frame. Merely having a producer or window
          // capture object attached is insufficient: during startup, stale
          // pose rejection, and flat-only menu frames we draw the diagnostic
          // fallback into this image with ClearRenderTargetView instead.
          barrier.Transition.StateAfter =
              (use_shared_pair || use_cached_pair || use_generated_pair)
                  ? D3D12_RESOURCE_STATE_COPY_DEST
                  : D3D12_RESOURCE_STATE_RENDER_TARGET;
          barrier.Transition.Subresource =
              D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        }
        if (use_shared_pair || use_cached_pair || use_generated_pair) {
          command_list->ResourceBarrier(
              static_cast<UINT>(destination_barriers.size()),
              destination_barriers.data());
        }
        std::array<D3D12_RESOURCE_BARRIER, 2> cached_eye_barriers{};
        if (use_shared_pair || use_cached_pair || use_generated_pair) {
          for (std::size_t eye = 0; eye < cached_eye_resources.size(); ++eye) {
            auto& barrier = cached_eye_barriers[eye];
            barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
            barrier.Transition.pResource = cached_eye_resources[eye].Get();
            barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
            barrier.Transition.StateAfter =
                (use_shared_pair || use_generated_pair) ? D3D12_RESOURCE_STATE_COPY_DEST
                                : D3D12_RESOURCE_STATE_COPY_SOURCE;
            barrier.Transition.Subresource =
                D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
          }
          command_list->ResourceBarrier(
              static_cast<UINT>(cached_eye_barriers.size()),
              cached_eye_barriers.data());
        }
        if (pointer_swapchain != XR_NULL_HANDLE && pointer_upload_pixels &&
            !pointer_swatch_uploaded) {
          // A static swapchain is acquired exactly once. Stage the dark green
          // block and the target sprite in the pointer's own upload buffer,
          // copy them in, and release after this frame's command list has
          // been executed. Nothing else writes that buffer.
          std::uint32_t pointer_image_index{};
          check_xr(xrAcquireSwapchainImage(pointer_swapchain, &acquire_info,
                                           &pointer_image_index),
                   "xrAcquireSwapchainImage(pointer swatch)");
          check_xr(xrWaitSwapchainImage(pointer_swapchain, &image_wait),
                   "xrWaitSwapchainImage(pointer swatch)");
          for (std::uint32_t y = 0; y < pointer_swatch_extent; ++y) {
            auto* row = pointer_upload_pixels +
                        pointer_upload_footprint.Offset +
                        static_cast<std::size_t>(y) *
                            pointer_upload_footprint.Footprint.RowPitch;
            for (std::uint32_t x = 0; x < pointer_swatch_extent; ++x) {
              const bool ray_block = x < pointer_ray_block_extent &&
                                     y < pointer_ray_block_extent;
              row[x * 4 + 0] = std::byte{0};                          // blue
              row[x * 4 + 1] = ray_block ? std::byte{100} : std::byte{0};  // green
              row[x * 4 + 2] = std::byte{0};                          // red
              row[x * 4 + 3] = ray_block ? std::byte{255} : std::byte{0};
            }
          }
          darktidevr::core::paint_pointer_target(
              pointer_upload_pixels + pointer_upload_footprint.Offset +
                  static_cast<std::size_t>(pointer_target_texels.offset.y) *
                      pointer_upload_footprint.Footprint.RowPitch +
                  static_cast<std::size_t>(pointer_target_texels.offset.x) * 4,
              pointer_upload_footprint.Footprint.RowPitch);
          auto* pointer_resource = pointer_images[pointer_image_index].texture;
          D3D12_RESOURCE_BARRIER swatch_barrier{};
          swatch_barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
          swatch_barrier.Transition.pResource = pointer_resource;
          swatch_barrier.Transition.StateBefore =
              D3D12_RESOURCE_STATE_RENDER_TARGET;
          swatch_barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_DEST;
          swatch_barrier.Transition.Subresource =
              D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
          command_list->ResourceBarrier(1, &swatch_barrier);
          D3D12_TEXTURE_COPY_LOCATION swatch_source{};
          swatch_source.pResource = pointer_upload.Get();
          swatch_source.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
          swatch_source.PlacedFootprint = pointer_upload_footprint;
          D3D12_TEXTURE_COPY_LOCATION swatch_destination{};
          swatch_destination.pResource = pointer_resource;
          swatch_destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
          swatch_destination.SubresourceIndex = 0;
          command_list->CopyTextureRegion(&swatch_destination, 0, 0, 0,
                                          &swatch_source, nullptr);
          std::swap(swatch_barrier.Transition.StateBefore,
                    swatch_barrier.Transition.StateAfter);
          command_list->ResourceBarrier(1, &swatch_barrier);
          pointer_swatch_uploaded = true;
          pointer_swatch_release_pending = true;
        }
        const bool update_reticle_atlas = enable_gameplay_reticle && window_capture &&
            presentation_state.mode == darktidevr::core::SharedPresentationMode::stereo_world;
        if (use_flat_capture || update_reticle_atlas) {
          D3D12_RESOURCE_BARRIER flat_barrier{};
          flat_barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
          flat_barrier.Transition.pResource = flat_resource;
          flat_barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
          flat_barrier.Transition.StateAfter =
              D3D12_RESOURCE_STATE_COPY_DEST;
          flat_barrier.Transition.Subresource =
              D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
          command_list->ResourceBarrier(1, &flat_barrier);
          if (use_shared_menu) {
            D3D12_RESOURCE_BARRIER menu_barrier{};
            menu_barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
            menu_barrier.Transition.pResource = opened_menu->texture.Get();
            menu_barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
            menu_barrier.Transition.StateAfter =
                D3D12_RESOURCE_STATE_COPY_SOURCE;
            menu_barrier.Transition.Subresource =
                D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
            command_list->ResourceBarrier(1, &menu_barrier);
            D3D12_TEXTURE_COPY_LOCATION flat_destination{};
            flat_destination.pResource = flat_resource;
            flat_destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            flat_destination.SubresourceIndex = 0;
            D3D12_TEXTURE_COPY_LOCATION menu_source{};
            menu_source.pResource = opened_menu->texture.Get();
            menu_source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            menu_source.SubresourceIndex = 0;
            // The published crop can describe the next canvas before the menu
            // texture is reattached (loading screen to gameplay, 14
            // September): a box outside the source or the destination made
            // Close fail with E_INVALIDARG and killed the viewer. Clamp to
            // both textures and skip an empty copy.
            const auto menu_description = opened_menu->texture->GetDesc();
            const auto flat_description = flat_resource->GetDesc();
            const auto menu_width = static_cast<UINT>(menu_description.Width);
            const auto menu_height = menu_description.Height;
            const UINT crop_left = std::min(presentation_state.crop_x, menu_width);
            const UINT crop_top = std::min(presentation_state.crop_y, menu_height);
            UINT crop_right = std::min(
                presentation_state.crop_x + presentation_state.crop_width, menu_width);
            UINT crop_bottom = std::min(
                presentation_state.crop_y + presentation_state.crop_height, menu_height);
            crop_right = std::min(
                crop_right, crop_left + static_cast<UINT>(flat_description.Width));
            crop_bottom = std::min(crop_bottom, crop_top + flat_description.Height);
            const D3D12_BOX menu_crop{crop_left, crop_top, 0, crop_right, crop_bottom, 1};
            const bool crop_clamped =
                crop_right - crop_left != presentation_state.crop_width ||
                crop_bottom - crop_top != presentation_state.crop_height;
            if (crop_clamped) {
              ++menu_crop_clamped_frames;
              if (!menu_crop_clamp_logged) {
                menu_crop_clamp_logged = true;
                std::cout << "openxr.shared_menu_crop_clamped frame=" << frame
                          << " crop=" << presentation_state.crop_x << ","
                          << presentation_state.crop_y << ","
                          << presentation_state.crop_width << "x"
                          << presentation_state.crop_height
                          << " source=" << menu_width << "x" << menu_height
                          << " destination=" << flat_description.Width << "x"
                          << flat_description.Height << '\n';
              }
            }
            if (crop_right > crop_left && crop_bottom > crop_top) {
              command_list->CopyTextureRegion(&flat_destination, 0, 0, 0,
                                              &menu_source, &menu_crop);
              if (panel_renderer) {
                auto board_destination = flat_destination;
                board_destination.pResource = panel_renderer->board_texture();
                command_list->CopyTextureRegion(&board_destination, 0, 0, 0,
                                                &menu_source, &menu_crop);
                board_texture_written = true;
              }
            }
            if (menu_readback && !menu_readback_logged) {
              D3D12_TEXTURE_COPY_LOCATION destination{};
              destination.pResource = menu_readback.Get();
              destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
              destination.PlacedFootprint = menu_readback_footprint;
              D3D12_TEXTURE_COPY_LOCATION source{};
              source.pResource = opened_menu->texture.Get();
              source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
              source.SubresourceIndex = 0;
              command_list->CopyTextureRegion(&destination, 0, 0, 0,
                                              &source, nullptr);
              menu_readback_copied_this_frame = true;
            }
            std::swap(menu_barrier.Transition.StateBefore,
                      menu_barrier.Transition.StateAfter);
            command_list->ResourceBarrier(1, &menu_barrier);
          } else {
            const auto newest =
                latest_capture.load(std::memory_order_acquire);
            if (!update_reticle_atlas && newest && newest != consumed_capture) {
              for (std::uint32_t y = 0; y < flat_capture_height; ++y) {
                const auto* source = newest->data() +
                                     static_cast<std::size_t>(y) *
                                         flat_capture_width * 4;
                auto* destination = upload_pixels + upload_footprint.Offset +
                                    static_cast<std::size_t>(y) *
                                        upload_footprint.Footprint.RowPitch;
                std::memcpy(destination, source,
                            static_cast<std::size_t>(flat_capture_width) * 4);
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
            D3D12_TEXTURE_COPY_LOCATION destination{};
            destination.pResource = flat_resource;
            destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            destination.SubresourceIndex = 0;
            if (update_reticle_atlas) {
              // Each acquired swapchain image may still contain menu pixels.
              // Repaint synchronously rather than waiting for a window capture
              // that gameplay does not otherwise upload. Copy just the sprite.
              const UINT left = flat_capture_width - 42;
              const UINT top = flat_capture_height - 41;
              darktidevr::core::paint_reticle_atlas(
                  upload_pixels + upload_footprint.Offset +
                      static_cast<std::size_t>(top) * upload_footprint.Footprint.RowPitch + left * 4,
                  upload_footprint.Footprint.RowPitch);
              const D3D12_BOX sprite{left, top, 0, left + 41, top + 41, 1};
              command_list->CopyTextureRegion(&destination, left, top, 0, &source, &sprite);
              // Drawing the reticle ourselves means sampling it, and the
              // runtime's swapchain image is not ours to make a view on. The
              // panel renderer's board texture is, and the sprite's texel
              // rectangle is the same in both because the board was created
              // from the flat capture's own description.
              if (panel_renderer && reticle_in_eyes_requested) {
                auto board_destination = destination;
                board_destination.pResource = panel_renderer->board_texture();
                command_list->CopyTextureRegion(&board_destination, left, top,
                                                0, &source, &sprite);
                reticle_sprite_in_board_texture = true;
              }
              // The ADS vignette sprite sits left of the reticle with a
              // transparent gutter; repaint whenever THIS image's painted
              // strength is not the current one.
              const auto ads_image = flat_image_index < ads_painted_blend.size()
                                         ? flat_image_index
                                         : 0U;
              if (ads_painted_blend[ads_image] != ads_blend) {
                ads_painted_blend[ads_image] = ads_blend;
                const UINT vignette_left = left - 66;
                const UINT vignette_top = flat_capture_height - 66;
                darktidevr::core::paint_vignette_atlas(
                    upload_pixels + upload_footprint.Offset +
                        static_cast<std::size_t>(vignette_top) * upload_footprint.Footprint.RowPitch +
                        vignette_left * 4,
                    upload_footprint.Footprint.RowPitch, ads_blend);
                const D3D12_BOX vignette{vignette_left, vignette_top, 0,
                                         vignette_left + 64, vignette_top + 64, 1};
                command_list->CopyTextureRegion(&destination, vignette_left, vignette_top, 0,
                                                &source, &vignette);
              }
              // The atlas modified the upload buffer; a subsequent menu must
              // restore even the same last-captured window image.
              consumed_capture.reset();
            } else {
              command_list->CopyTextureRegion(&destination, 0, 0, 0, &source, nullptr);
              // The whole captured image goes over this swapchain image,
              // including the corner the vignette and reticle sprites live
              // in, so this image must be painted again before it is shown.
              if (flat_image_index < ads_painted_blend.size()) {
                ads_painted_blend[flat_image_index] = -1.0F;
              }
              if (panel_renderer && use_flat_capture) {
                auto board_destination = destination;
                board_destination.pResource = panel_renderer->board_texture();
                command_list->CopyTextureRegion(&board_destination, 0, 0, 0,
                                                &source, nullptr);
                board_texture_written = true;
                // Including the corner the reticle sprite lives in.
                reticle_sprite_in_board_texture = false;
              }
            }
          }
          std::swap(flat_barrier.Transition.StateBefore,
                    flat_barrier.Transition.StateAfter);
          command_list->ResourceBarrier(1, &flat_barrier);
        }
        if (use_generated_pair) {
          auto* texture=generated_surfaces->textures[
              darktidevr::core::generated_frame_slot(generated_sequence_for_frame)].Get();
          D3D12_RESOURCE_BARRIER barrier{};
          barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
          barrier.Transition={texture,D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
              D3D12_RESOURCE_STATE_COMMON,D3D12_RESOURCE_STATE_COPY_SOURCE};
          command_list->ResourceBarrier(1,&barrier);
          D3D12_TEXTURE_COPY_LOCATION source{}; source.pResource=texture;
          source.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
          for(unsigned eye=0;eye<2;++eye) {
            D3D12_TEXTURE_COPY_LOCATION destination{};
            destination.pResource=resources[separate_shared_eye_swapchains ? eye : 0];
            destination.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            const D3D12_BOX box{eye*shared_eye_width,0,0,(eye+1)*shared_eye_width,shared_eye_height,1};
            command_list->CopyTextureRegion(&destination,0,separate_shared_eye_swapchains ? 0 : eye*shared_eye_height,
                0,&source,&box);
            destination.pResource=cached_eye_resources[eye].Get();
            command_list->CopyTextureRegion(&destination,0,0,0,&source,&box);
          }
          std::swap(barrier.Transition.StateBefore,barrier.Transition.StateAfter);
          command_list->ResourceBarrier(1,&barrier);
          for(auto& cached_barrier:cached_eye_barriers)
            std::swap(cached_barrier.Transition.StateBefore,cached_barrier.Transition.StateAfter);
          command_list->ResourceBarrier(static_cast<UINT>(cached_eye_barriers.size()),cached_eye_barriers.data());
          // Repeated display slots must retain the interpolated image and its
          // pose; reverting to the earlier original would reverse time.
          cached_pair_view_poses=generated_view_poses;
          cached_pair_valid=true;
        } else if (use_shared_pair) {
          if (projection_resume_started) {
            const auto resume_latency =
                std::chrono::duration_cast<std::chrono::milliseconds>(
                    frame_start - *projection_resume_started);
            std::cout << "openxr.projection_resume fresh_pair_latency_ms="
                      << resume_latency.count() << " ready_advance="
                      << (shared_ready_for_frame - projection_resume_ready_value)
                      << " ready=" << shared_ready_for_frame
                      << " gameplay_generation="
                      << rendered_pair_gameplay_generation << '\n';
            projection_resume_started.reset();
          }
          if (original_ready_for_frame != last_submitted_shared_value) {
            last_submitted_shared_value = original_ready_for_frame;
            ++fresh_shared_pairs;
          } else {
            ++reused_shared_frames;
          }
          if (direct_original_this_frame) {
            std::array<ID3D12Resource*, 2> readbacks{};
            if (shared_eye_readback_requested) {
              for (unsigned eye = 0; eye < 2; ++eye)
                readbacks[eye] = shared_eye_readbacks[eye].Get();
              shared_eye_readback_copied_this_frame = readbacks[0] && readbacks[1];
            }
            darktidevr::xr::copy_packed_original(command_list.Get(),
                original_surfaces->textures[darktidevr::core::generated_frame_slot(
                    original_ring_sequence_for_frame)].Get(),
                shared_eye_width, shared_eye_height,
                {resources[0], resources[separate_shared_eye_swapchains ? 1 : 0]},
                separate_shared_eye_swapchains,
                {cached_eye_resources[0].Get(), cached_eye_resources[1].Get()},
                readbacks, shared_eye_readback_footprint);
            if (++direct_original_submitted <= 4 || direct_original_submitted % 600 == 0)
              std::cout << "openxr.native_original_direct submitted=" << direct_original_submitted
                        << " sequence=" << original_ring_sequence_for_frame << '\n';
          } else {
            const auto& original_eyes=use_queued_original ? selected_original->eyes : opened_eyes->eyes;
            for (std::size_t eye = 0; eye < original_eyes.size(); ++eye) {
              D3D12_RESOURCE_BARRIER eye_barrier{};
              eye_barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
              eye_barrier.Transition.pResource = original_eyes[eye].Get();
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
              source.pResource = original_eyes[eye].Get();
              source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
              command_list->CopyTextureRegion(
                  &destination, 0,
                  separate_shared_eye_swapchains
                      ? 0U
                      : static_cast<UINT>(eye * shared_eye_height),
                  0, &source, nullptr);
              D3D12_TEXTURE_COPY_LOCATION cached_destination{};
              cached_destination.pResource = cached_eye_resources[eye].Get();
              cached_destination.Type =
                  D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
              command_list->CopyTextureRegion(&cached_destination, 0, 0, 0,
                                              &source, nullptr);
              if (shared_eye_readback_requested &&
                  shared_eye_readbacks[eye]) {
                D3D12_TEXTURE_COPY_LOCATION readback_destination{};
                readback_destination.pResource =
                    shared_eye_readbacks[eye].Get();
                readback_destination.Type =
                    D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
                readback_destination.PlacedFootprint =
                    shared_eye_readback_footprint;
                command_list->CopyTextureRegion(&readback_destination, 0, 0, 0,
                                                &source, nullptr);
                shared_eye_readback_copied_this_frame = true;
              }
              std::swap(eye_barrier.Transition.StateBefore,
                        eye_barrier.Transition.StateAfter);
              command_list->ResourceBarrier(1, &eye_barrier);
            }
            }
          for (auto& barrier : cached_eye_barriers) {
            std::swap(barrier.Transition.StateBefore,
                      barrier.Transition.StateAfter);
          }
          command_list->ResourceBarrier(
              static_cast<UINT>(cached_eye_barriers.size()),
              cached_eye_barriers.data());
          cached_pair_view_poses = submitted_original_view_poses;
          cached_pair_valid = true;
        } else if (use_cached_pair) {
          ++cached_original_submissions;
          for (std::size_t eye = 0; eye < cached_eye_resources.size(); ++eye) {
            D3D12_TEXTURE_COPY_LOCATION destination{};
            destination.pResource =
                resources[separate_shared_eye_swapchains ? eye : 0U];
            destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            D3D12_TEXTURE_COPY_LOCATION source{};
            source.pResource = cached_eye_resources[eye].Get();
            source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            command_list->CopyTextureRegion(
                &destination, 0,
                separate_shared_eye_swapchains
                    ? 0U
                    : static_cast<UINT>(eye * shared_eye_height),
                0, &source, nullptr);
          }
          for (auto& barrier : cached_eye_barriers) {
            std::swap(barrier.Transition.StateBefore,
                      barrier.Transition.StateAfter);
          }
          command_list->ResourceBarrier(
              static_cast<UINT>(cached_eye_barriers.size()),
              cached_eye_barriers.data());
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
        bool rendered_tracked_cuffs{};
        const bool draw_tracked_cuffs =
            tracked_cuff_renderer && submitted_shared_pair_this_frame &&
            submitted_view_projection_valid && latest_controller_sample_;
        // Everything the quad layer needed, plus a texture to sample and a
        // projection to draw with. `gameplay_reticle_quad.size` is only set
        // when the quad was configured, which is the same condition.
        const bool draw_reticle_in_eyes =
            reticle_in_eyes_requested && panel_renderer &&
            reticle_sprite_in_board_texture && gameplay_reticle_pose &&
            reticle_scale > 0.0F && submitted_shared_pair_this_frame &&
            submitted_view_projection_valid &&
            gameplay_reticle_quad.size.width > 0.0F;
        if (draw_tracked_cuffs || draw_reticle_in_eyes) {
          for (auto& barrier : destination_barriers) {
            barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_DEST;
            barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
          }
          command_list->ResourceBarrier(
              static_cast<UINT>(destination_barriers.size()),
              destination_barriers.data());
          // Not the runtime's frustum and not the base pose: the images
          // these draw into are submitted with the recentered symmetric
          // projection, and the pair inside them was rendered with it, so a
          // cuff placed by the raw frustum sits about 6 degrees out -- and
          // out the opposite way in each eye, which is a stereo disparity
          // saying the wrong depth (18 September).
          const auto& cuff_view_poses = submitted_view_poses;
          const auto& cuff_view_fovs = submitted_view_fovs;
          const std::array<darktidevr::core::ControllerHandState, 2>
              cuff_hands{{latest_controller_sample_
                              ? latest_controller_sample_->hands[0]
                              : darktidevr::core::ControllerHandState{},
                          latest_controller_sample_
                              ? latest_controller_sample_->hands[1]
                              : darktidevr::core::ControllerHandState{}}};
          std::uint32_t frame_cuff_draws{};
          if (draw_tracked_cuffs) {
            for (std::size_t eye = 0; eye < theatre_swapchain_count; ++eye) {
              frame_cuff_draws += tracked_cuff_renderer->record(
                  command_list.Get(), eye, image_indices[eye],
                  cuff_view_poses[eye], cuff_view_fovs[eye], cuff_hands);
            }
          }
          if (draw_reticle_in_eyes) {
            // One quad, the same one the layer describes: the pose, the size
            // and the texel rectangle are read straight off it, so what is
            // drawn and what the quad layer would have shown are the same
            // thing in the same place.
            const darktidevr::harness::PanelQuad reticle_quad{
                gameplay_reticle_quad.pose, gameplay_reticle_quad.size,
                gameplay_reticle_quad.subImage.imageRect,
                darktidevr::harness::PanelQuad::Source::board};
            panel_renderer->begin(command_list.Get());
            // Both eyes, whichever way they are laid out: their own
            // swapchains, or the halves of one, exactly as the projection
            // layer describes them below.
            for (std::size_t eye = 0; eye < submitted_view_poses.size();
                 ++eye) {
              const auto image = separate_shared_eye_swapchains ? eye : 0U;
              const D3D12_CPU_DESCRIPTOR_HANDLE eye_target{
                  rtv_heap->GetCPUDescriptorHandleForHeapStart().ptr +
                  static_cast<SIZE_T>(rtv_base_offsets[image] +
                                      image_indices[image]) *
                      rtv_increment};
              XrRect2Di eye_rect{
                  {0, 0},
                  {static_cast<std::int32_t>(width),
                   static_cast<std::int32_t>(height)}};
              if (!separate_shared_eye_swapchains) {
                eye_rect = stereo_top_bottom_layout
                    ? XrRect2Di{{0, static_cast<std::int32_t>(
                                        eye * (height / 2))},
                                {static_cast<std::int32_t>(width),
                                 static_cast<std::int32_t>(height / 2)}}
                    : XrRect2Di{{static_cast<std::int32_t>(eye * (width / 2)),
                                 0},
                                {static_cast<std::int32_t>(width / 2),
                                 static_cast<std::int32_t>(height)}};
              }
              rendered_gameplay_reticle |=
                  panel_renderer->record(command_list.Get(), eye_target,
                                         eye_rect, eye,
                                         submitted_view_poses[eye],
                                         submitted_view_fovs[eye],
                                         &reticle_quad, 1, false) != 0U;
            }
            panel_renderer->end(command_list.Get());
            if (rendered_gameplay_reticle && !gameplay_reticle_layer_logged) {
              gameplay_reticle_layer_logged = true;
              std::cout << "openxr.gameplay_reticle layer=eyes texels="
                        << gameplay_reticle_quad.subImage.imageRect.extent.width
                        << " size_m=" << gameplay_reticle_quad.size.width
                        << '\n';
            }
          }
          const bool capture_projected_eyes =
              projected_eye_readback_requested &&
              (frame_cuff_draws != 0U || rendered_gameplay_reticle);
          if (capture_projected_eyes && rendered_gameplay_reticle) {
            // The centre of the quad, through the same transform the draw
            // used, so the readback can be checked rather than admired. NDC
            // is -1..1 with +Y up; the pixel is where to look in the PPM.
            for (std::size_t eye = 0; eye < submitted_view_poses.size();
                 ++eye) {
              const auto clip = darktidevr::harness::panel_point_clip(
                  submitted_view_poses[eye], submitted_view_fovs[eye],
                  gameplay_reticle_quad.pose, gameplay_reticle_quad.size,
                  0.5F, 0.5F);
              const auto inverse_w = clip[3] != 0.0F ? 1.0F / clip[3] : 0.0F;
              const auto ndc_x = clip[0] * inverse_w;
              const auto ndc_y = clip[1] * inverse_w;
              std::cout << "openxr.gameplay_reticle_clip eye=" << eye
                        << " ndc=" << ndc_x << ',' << ndc_y
                        << " pixel=" << (ndc_x * 0.5F + 0.5F) *
                                            static_cast<float>(width)
                        << ',' << (0.5F - ndc_y * 0.5F) *
                                     static_cast<float>(height)
                        << " w=" << clip[3] << '\n';
            }
          }
          if (capture_projected_eyes && draw_tracked_cuffs) {
            for (std::size_t eye = 0; eye < theatre_swapchain_count; ++eye) {
              for (std::size_t hand = 0; hand < cuff_hands.size(); ++hand) {
                const auto clip = darktidevr::harness::
                    tracked_cuff_clip_center(cuff_view_poses[eye],
                                             cuff_view_fovs[eye],
                                             cuff_hands[hand]);
                const auto inverse_w = clip[3] != 0.0F ? 1.0F / clip[3] : 0.0F;
                std::cout << "openxr.tracked_cuff_clip eye=" << eye
                          << " hand=" << hand << " ndc="
                          << clip[0] * inverse_w << ','
                          << clip[1] * inverse_w << ','
                          << clip[2] * inverse_w << " w=" << clip[3] << '\n';
              }
            }
          }
          if (capture_projected_eyes) {
            for (auto& barrier : destination_barriers) {
              barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
              barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
            }
            command_list->ResourceBarrier(
                static_cast<UINT>(destination_barriers.size()),
                destination_barriers.data());
            for (std::size_t eye = 0; eye < theatre_swapchain_count; ++eye) {
              D3D12_TEXTURE_COPY_LOCATION source{};
              source.pResource = resources[eye];
              source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
              D3D12_TEXTURE_COPY_LOCATION destination{};
              destination.pResource = projected_eye_readbacks[eye].Get();
              destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
              destination.PlacedFootprint =
                  projected_eye_readback_footprint;
              command_list->CopyTextureRegion(&destination, 0, 0, 0, &source,
                                              nullptr);
            }
            for (auto& barrier : destination_barriers) {
              barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_SOURCE;
              barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
            }
            command_list->ResourceBarrier(
                static_cast<UINT>(destination_barriers.size()),
                destination_barriers.data());
            projected_eye_readback_copied_this_frame = true;
          }
          rendered_tracked_cuffs = true;
          if (frame_cuff_draws != 0U) {
            ++tracked_cuff_frames;
            tracked_cuff_draws += frame_cuff_draws;
          }
        }
        if (!rendered_tracked_cuffs &&
            (use_shared_pair || use_cached_pair || use_generated_pair)) {
          for (auto& barrier : destination_barriers) {
            std::swap(barrier.Transition.StateBefore,
                      barrier.Transition.StateAfter);
          }
          command_list->ResourceBarrier(
              static_cast<UINT>(destination_barriers.size()),
              destination_barriers.data());
        }
        check_command_list_close(command_list.Get(), device, frame,
                                 "ID3D12GraphicsCommandList::Close(theatre)",
                                 [&]() {
          std::ostringstream text;
          auto size = [](ID3D12Resource* resource) {
            if (!resource) return std::string("null");
            const auto d = resource->GetDesc();
            return std::to_string(d.Width) + "x" + std::to_string(d.Height) +
                   "/f" + std::to_string(static_cast<int>(d.Format));
          };
          text << "shared=" << use_shared_pair << " cached=" << use_cached_pair
               << " generated=" << use_generated_pair << " menu=" << use_shared_menu
               << " queued_original=" << use_queued_original
               << " ingested_original=" << ingested_original_this_frame
               << " cuffs=" << rendered_tracked_cuffs
               << " separate_eyes=" << separate_shared_eye_swapchains
               << " shared_eye=" << shared_eye_width << "x" << shared_eye_height
               << " shared_source=" << (opened_eyes ? size(opened_eyes->eyes[0].Get()) : std::string("detached"))
               << " cached0=" << size(cached_eye_resources[0].Get())
               << " swapchain0=" << size(resources.empty() ? nullptr : resources[0])
               << " projected_readback=" << projected_eye_readback_copied_this_frame
               << " eye_readback=" << shared_eye_readback_copied_this_frame
               << " menu_readback=" << menu_readback_copied_this_frame;
          return text.str();
        });
        ID3D12CommandList* lists[]{command_list.Get()};
        if (use_generated_pair) {
          check(queue->Wait(generated_surfaces->ready_fence.Get(),generated_sequence_for_frame),
              "Wait(generated stereo ready)");
        }
        if (ingested_original_this_frame) {
          check(queue->Wait(original_surfaces->ready_fence.Get(),original_ring_sequence_for_frame),"Wait original ring ready");
        }
        if (use_shared_pair && !use_queued_original) {
          check(queue->Wait(opened_eyes->ready_fence.Get(),
                            shared_ready_for_frame),
                "ID3D12CommandQueue::Wait(shared eyes)");
        }
        if (use_shared_menu) {
          check(queue->Wait(opened_menu->ready_fence.Get(),
                            menu_ready_for_frame),
                "ID3D12CommandQueue::Wait(shared menu)");
        }
        queue->ExecuteCommandLists(1, lists);
        if (use_generated_pair) {
          check(queue->Signal(generated_surfaces->consumed_fence.Get(),generated_sequence_for_frame),
              "Signal(generated stereo consumed)");
          generated_last_consumed=generated_sequence_for_frame;
          generated_displayed_before_original=selected_original->ready;
          generated_cadence.generated(frame_state.predictedDisplayTime,frame_state.predictedDisplayPeriod);
          if (++generated_submitted <= 16 || generated_submitted%120==0)
            std::cout << "openxr.generated_stereo=submitted count=" << generated_submitted
                << " sequence=" << generated_sequence_for_frame << " before_original=" << selected_original->ready << '\n';
        }
        if (use_shared_pair && (!original_surfaces || use_queued_original)) {
          last_original_ready=original_ready_for_frame;
          last_original_pose=original_pose_for_frame;
          if(use_queued_original) selected_original->ready=0;
        }
        if (ingested_original_this_frame)
          check(queue->Signal(original_surfaces->consumed_fence.Get(),original_ring_sequence_for_frame),"Signal original ring consumed");
        if (original_surfaces && shared_ready_for_frame && !(use_shared_pair && !use_queued_original)) {
          // The legacy mailbox still supplies transition metadata. It no
          // longer owns the originals used for generated-stereo delivery.
          check(opened_eyes->consumed_fence->Signal(shared_ready_for_frame),"Discard legacy original mailbox");
        } else if (use_shared_pair && !use_queued_original) {
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
        if (use_shared_menu) {
          check(queue->Signal(opened_menu->consumed_fence.Get(),
                              menu_ready_for_frame),
                "ID3D12CommandQueue::Signal(shared menu consumed)");
        }
        const auto signal_value = ++fence_value;
        check(queue->Signal(fence.Get(), signal_value),
              "ID3D12CommandQueue::Signal(theatre)");
        const auto gpu_wait_tick = GetTickCount64();
        const auto gpu_wait_start = std::chrono::steady_clock::now();
        wait_for_fence(fence.Get(), signal_value, fence_event,
                       "ID3D12Fence::SetEventOnCompletion(theatre)");
        frame_stage_timing.elapsed(FrameStage::GpuFence, gpu_wait_start);
        report_pose_wait("gpu_fence", gpu_wait_tick);
        if (shared_eye_readback_copied_this_frame) {
          const auto eye_description = opened_eyes->eyes[0]->GetDesc();
          const std::array<const char*, 2> labels{"left", "right"};
          for (std::size_t eye = 0; eye < shared_eye_readbacks.size(); ++eye) {
            void* mapped_pixels{};
            D3D12_RANGE read_range{0, shared_eye_readback_total_bytes};
            check(shared_eye_readbacks[eye]->Map(
                      0, &read_range, &mapped_pixels),
                  "ID3D12Resource::Map(shared-eye readback)");
            const auto diagnostic_path =
                std::filesystem::temp_directory_path() /
                (std::string("darktidevr-shared-eye-") + labels[eye] +
                 ".ppm");
            std::ofstream diagnostic(diagnostic_path, std::ios::binary);
            if (!diagnostic) {
              shared_eye_readbacks[eye]->Unmap(0, nullptr);
              throw std::runtime_error(
                  "Could not open shared-eye readback output");
            }
            diagnostic << "P6\n" << eye_description.Width << ' '
                       << eye_description.Height << "\n255\n";
            const auto* pixels =
                static_cast<const std::uint8_t*>(mapped_pixels);
            std::vector<std::uint8_t> row(
                static_cast<std::size_t>(eye_description.Width) * 3);
            for (std::uint32_t y = 0; y < eye_description.Height; ++y) {
              const auto* source_row = pixels +
                  static_cast<std::size_t>(y) *
                      shared_eye_readback_footprint.Footprint.RowPitch;
              for (std::uint32_t x = 0; x < eye_description.Width; ++x) {
                const auto* source =
                    source_row + static_cast<std::size_t>(x) * 4;
                auto* destination = row.data() +
                    static_cast<std::size_t>(x) * 3;
                destination[0] = source[0];
                destination[1] = source[1];
                destination[2] = source[2];
              }
              diagnostic.write(
                  reinterpret_cast<const char*>(row.data()),
                  static_cast<std::streamsize>(row.size()));
            }
            shared_eye_readbacks[eye]->Unmap(0, nullptr);
            std::cout << "openxr.shared_eye_readback="
                      << diagnostic_path.string() << '\n';
          }
          shared_eye_readback_requested = false;
        }
        if (projected_eye_readback_copied_this_frame) {
          write_projected_eye_readback({resources.front(), resources.back()});
        }
        if (menu_readback_copied_this_frame && !menu_readback_logged &&
            ++menu_readback_copies >= 5) {
          void* mapped_pixels{};
          D3D12_RANGE read_range{0, menu_readback_total_bytes};
          check(menu_readback->Map(0, &read_range, &mapped_pixels),
                "ID3D12Resource::Map(menu readback)");
          const auto* pixels = static_cast<const std::uint8_t*>(mapped_pixels);
          std::uint64_t rgb_nonzero{};
          std::uint64_t alpha_nonzero{};
          std::uint64_t rgb_nonzero_alpha_zero{};
          std::uint64_t rgb_energy_alpha_zero{};
          auto nonzero_min_x = (std::numeric_limits<std::uint32_t>::max)();
          auto nonzero_min_y = (std::numeric_limits<std::uint32_t>::max)();
          std::uint32_t nonzero_max_x{};
          std::uint32_t nonzero_max_y{};
          const auto menu_extent = opened_menu->texture->GetDesc();
          for (std::uint32_t y = 0; y < menu_extent.Height; ++y) {
            const auto* row = pixels +
                static_cast<std::size_t>(y) *
                    menu_readback_footprint.Footprint.RowPitch;
            for (std::uint32_t x = 0; x < menu_extent.Width; ++x) {
              const auto* pixel = row + static_cast<std::size_t>(x) * 4;
              const auto rgb = static_cast<unsigned>(pixel[0]) + pixel[1] +
                               pixel[2];
              rgb_nonzero += rgb != 0 ? 1 : 0;
              alpha_nonzero += pixel[3] != 0 ? 1 : 0;
              if (rgb != 0 || pixel[3] != 0) {
                nonzero_min_x = (std::min)(nonzero_min_x, x);
                nonzero_min_y = (std::min)(nonzero_min_y, y);
                nonzero_max_x = (std::max)(nonzero_max_x, x);
                nonzero_max_y = (std::max)(nonzero_max_y, y);
              }
              if (rgb != 0 && pixel[3] == 0) {
                ++rgb_nonzero_alpha_zero;
                rgb_energy_alpha_zero += rgb;
              }
            }
          }
          const auto diagnostic_path =
              std::filesystem::temp_directory_path() /
              "darktidevr-shared-menu.ppm";
          std::ofstream diagnostic(diagnostic_path, std::ios::binary);
          // The crop can describe a larger source than the attached texture
          // (a canvas resize in flight); read only pixels the readback holds.
          const auto menu_width_pixels = static_cast<std::uint32_t>(menu_extent.Width);
          const auto crop_x = (std::min)(presentation_state.crop_x, menu_width_pixels);
          const auto crop_y = (std::min)(presentation_state.crop_y, menu_extent.Height);
          const auto crop_width = (std::min)(presentation_state.crop_width,
                                             menu_width_pixels - crop_x);
          const auto crop_height = (std::min)(presentation_state.crop_height,
                                              menu_extent.Height - crop_y);
          if (diagnostic && crop_width > 0 && crop_height > 0) {
            diagnostic << "P6\n" << crop_width << ' ' << crop_height << "\n255\n";
            std::vector<std::uint8_t> diagnostic_row(
                static_cast<std::size_t>(crop_width) * 3);
            for (std::uint32_t y = 0; y < crop_height; ++y) {
              const auto source_y = crop_y + y;
              const auto* source_row = pixels +
                  static_cast<std::size_t>(source_y) *
                      menu_readback_footprint.Footprint.RowPitch +
                  static_cast<std::size_t>(crop_x) * 4;
              for (std::uint32_t x = 0; x < crop_width; ++x) {
                const auto* source =
                    source_row + static_cast<std::size_t>(x) * 4;
                const auto alpha = static_cast<unsigned>(source[3]);
                const auto checker =
                    ((x / 32 + y / 32) & 1U) != 0 ? 56U : 24U;
                for (std::size_t channel = 0; channel < 3; ++channel) {
                  diagnostic_row[static_cast<std::size_t>(x) * 3 + channel] =
                      static_cast<std::uint8_t>((std::min)(
                          255U, static_cast<unsigned>(source[channel]) +
                                    checker * (255U - alpha) / 255U));
                }
              }
              diagnostic.write(
                  reinterpret_cast<const char*>(diagnostic_row.data()),
                  static_cast<std::streamsize>(diagnostic_row.size()));
            }
            std::cout << "openxr.shared_menu_diagnostic="
                      << diagnostic_path.string() << '\n';
          }
          const auto full_diagnostic_path =
              std::filesystem::temp_directory_path() /
              "darktidevr-shared-menu-full.ppm";
          std::ofstream full_diagnostic(full_diagnostic_path,
                                        std::ios::binary);
          if (full_diagnostic) {
            full_diagnostic << "P6\n" << menu_extent.Width << ' '
                            << menu_extent.Height << "\n255\n";
            std::vector<std::uint8_t> full_row(
                static_cast<std::size_t>(menu_extent.Width) * 3);
            for (std::uint32_t y = 0; y < menu_extent.Height; ++y) {
              const auto* source_row = pixels +
                  static_cast<std::size_t>(y) *
                      menu_readback_footprint.Footprint.RowPitch;
              for (std::uint32_t x = 0; x < menu_extent.Width; ++x) {
                const auto* source =
                    source_row + static_cast<std::size_t>(x) * 4;
                for (std::size_t channel = 0; channel < 3; ++channel) {
                  full_row[static_cast<std::size_t>(x) * 3 + channel] =
                      source[channel];
                }
              }
              full_diagnostic.write(
                  reinterpret_cast<const char*>(full_row.data()),
                  static_cast<std::streamsize>(full_row.size()));
            }
            std::cout << "openxr.shared_menu_full_diagnostic="
                      << full_diagnostic_path.string() << '\n';
          }
          menu_readback->Unmap(0, nullptr);
          menu_readback_logged = true;
          std::cout << "openxr.shared_menu_pixels rgb_nonzero="
                    << rgb_nonzero << " alpha_nonzero=" << alpha_nonzero
                    << " rgb_nonzero_alpha_zero="
                    << rgb_nonzero_alpha_zero
                    << " rgb_energy_alpha_zero=" << rgb_energy_alpha_zero;
          if (nonzero_min_x !=
              (std::numeric_limits<std::uint32_t>::max)()) {
            std::cout << " bounds=" << nonzero_min_x << ',' << nonzero_min_y
                      << '-' << nonzero_max_x << ',' << nonzero_max_y;
          } else {
            std::cout << " bounds=empty";
          }
          std::cout << '\n';
        }
        XrSwapchainImageReleaseInfo release_info{
            XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
        for (const auto swapchain : theatre_swapchains) {
          check_xr(xrReleaseSwapchainImage(swapchain, &release_info),
                   "xrReleaseSwapchainImage(theatre)");
        }
        if (flat_swapchain != XR_NULL_HANDLE) {
          check_xr(xrReleaseSwapchainImage(flat_swapchain, &release_info),
                   "xrReleaseSwapchainImage(flat capture)");
        }
        if (pointer_swatch_release_pending) {
          check_xr(xrReleaseSwapchainImage(pointer_swapchain, &release_info),
                   "xrReleaseSwapchainImage(pointer swatch)");
          pointer_swatch_release_pending = false;
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
      // Darktide's ordinary UI PSOs target an opaque desktop backbuffer and
      // do not provide a reliable compositing alpha channel.  The dedicated
      // shared-menu texture is therefore an opaque spatial board; treating
      // its undefined/preserved alpha as coverage makes valid menu RGB vanish
      // while the diagnostic primitives (which explicitly write alpha) remain.
      flat_fallback_quad.layerFlags =
          XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;
      flat_fallback_quad.space =
          flat_fallback_pose_valid ? local_space_ : view_space_;
      flat_fallback_quad.eyeVisibility = XR_EYE_VISIBILITY_BOTH;
      flat_fallback_quad.subImage.swapchain = flat_swapchain;
      flat_fallback_quad.subImage.imageRect.offset = {0, 0};
      flat_fallback_quad.subImage.imageRect.extent = {
          static_cast<std::int32_t>(flat_capture_width),
          static_cast<std::int32_t>(flat_capture_height)};
      flat_fallback_quad.pose = flat_fallback_pose;
      const auto flat_interactive_mode =
          presentation_sequence != 0 && darktidevr::core::
              flat_interactive_active(presentation_state.mode);
      // With a shared menu attached the pointer space is the published
      // presentation source; only the window-capture fallback reads the
      // physical client extent.
      const auto native_window_extent =
          flat_interactive_mode && window_capture &&
                  !(shared_menu_projection_enabled && opened_menu.has_value())
              ? window_capture->source_extent()
              : std::nullopt;
      // In-game menus (including the mode-6 premium store) retain the eye
      // canvas while their pixels are fitted into the native desktop window.
      // A gameplay shop is mode 5 while the live per-eye shared surfaces remain
      // attached; its portrait eye image is squeezed into the landscape native
      // window.  Character select is also mode 5, but has no shared eye
      // surfaces and must retain its ordinary 16:9 aspect.  Surface ownership
      // is stable across transient Windows client resizes, unlike comparing
      // source dimensions.
      const auto flat_interactive_eye_encoded =
          presentation_sequence != 0 &&
          darktidevr::core::flat_interactive_uses_eye_aspect(
              presentation_state.mode, opened_eyes.has_value());
      const auto panel_source_width =
          flat_interactive_eye_encoded
              ? shared_eye_width
              : (presentation_sequence != 0
                     ? presentation_state.crop_width
                     : flat_capture_width);
      const auto panel_source_height =
          flat_interactive_eye_encoded
              ? shared_eye_height
              : (presentation_sequence != 0
                     ? presentation_state.crop_height
                     : flat_capture_height);
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
      std::optional<darktidevr::math::Pose> controller_pointer_pose;
      std::optional<darktidevr::core::PanelPointerMapping>
          controller_pointer_hit;
      const auto menu_input_source_width =
          native_window_extent ? native_window_extent->first
                                : (presentation_sequence != 0
                                       ? presentation_state.source_width
                                       : flat_capture_width);
      const auto menu_input_source_height =
          native_window_extent ? native_window_extent->second
                                : (presentation_sequence != 0
                                       ? presentation_state.source_height
                                       : flat_capture_height);
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
        // Controller tracking is useful in every presentation state, but
        // gameplay buttons must never leak into loading screens or menus. In
        // particular, the synthetic utility phase includes Back/Menu and can
        // otherwise close the state-gated Psykhanium flow before it commits.
        const auto emit_synthetic_gameplay =
            synthetic_gameplay_input &&
            presentation_state.mode == darktidevr::core::
                                           SharedPresentationMode::stereo_world;
        auto synthetic =
            darktidevr::harness::synthetic_controller_path_sample(
                synthetic_controller_frames_++, ++controller_sequence_,
                timestamp_ns, panel_pose, panel_extent.width_metres,
                panel_extent.height_metres, emit_synthetic_gameplay);
        populate_body_local_controller_poses(synthetic.state);
        if (synthetic_body_path) {
          darktidevr::harness::apply_synthetic_body_reach_path(
              synthetic.state, synthetic_controller_frames_ - 1);
        }
        // Presentation mode 1 briefly appears during character-select/range
        // transitions. The typed aim publisher becomes active only after Lua
        // has accepted the private-range controller-aim contract, so use that
        // as the matrix epoch instead of consuming phases in a transient world.
        if (synthetic_weapon_aim_matrix) {
          if (emit_synthetic_gameplay && gameplay_aim_state.active) {
            darktidevr::harness::apply_synthetic_weapon_aim_matrix(
                synthetic.state, synthetic_weapon_aim_matrix_frames_);
            ++synthetic_weapon_aim_matrix_frames_;
          } else {
            // Frame zero is the matrix's explicit neutral warm-up state. Do
            // not let the generic controller diagnostic leak an attack while
            // the private-range aim publisher is still becoming active.
            darktidevr::harness::apply_synthetic_weapon_aim_matrix(
                synthetic.state, 0);
          }
        }
        if (synthetic_holster_once) {
          // Draws the ranged weapon over the shoulder once gameplay input is
          // live, then holds both hands still (two-hand grip previews).
          darktidevr::harness::apply_synthetic_holster_path(
              synthetic.state,
              emit_synthetic_gameplay ? synthetic_holster_frames_++ : 110, true);
        }
        if (synthetic_movement_reference_path && emit_synthetic_gameplay) {
          darktidevr::harness::apply_synthetic_movement_reference_path(
              synthetic.state, synthetic_movement_reference_frames_++);
        }
        // Body-path diagnostics intentionally replace the game-facing poses.
        // Reconstruct the corresponding absolute OpenXR poses afterwards so
        // native compositor geometry and Lua-controlled hands consume one
        // physically consistent controller sample.
        if (synthetic_body_path && controller_recenter_pose_) {
          for (auto& hand : synthetic.state.hands) {
            hand.aim_pose = darktidevr::core::anchored_controller_pose(
                *controller_recenter_pose_, hand.body_aim_pose);
            hand.grip_pose = darktidevr::core::anchored_controller_pose(
                *controller_recenter_pose_, hand.body_grip_pose);
            hand.aim_tracking_flags = hand.body_aim_tracking_flags;
            hand.grip_tracking_flags = hand.body_grip_tracking_flags;
          }
        }
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
      // A synthetic weapon matrix exists solely to exercise gameplay actions
      // after the private-range aim publisher is active.  Its neutral warm-up
      // still carries a moving tracked pose; treating that pose as a menu ray
      // moves the real Windows cursor throughout splash/character select.
      // Physical controllers and dedicated menu tests retain their normal
      // pointer path, while this matrix stays completely inert until gameplay.
      const bool synthetic_weapon_pointer_suppressed =
          synthetic_weapon_aim_matrix && !gameplay_aim_state.active;
      // The desktop mouse works in every menu, whatever the input settings, so
      // any settings state can be undone with it. Its position is marked
      // whenever no controller ray owns the pointer.
      const bool controllers_ignored =
          presentation_sequence != 0 && presentation_state.controllers_disabled;
      std::optional<std::pair<std::uint32_t, std::uint32_t>> desktop_cursor;
      bool desktop_owns_pointer = false;
      if (!submitted_flat_fallback_this_frame || !latest_controller_sample_ ||
          synthetic_weapon_pointer_suppressed ||
          menu_filter_presentation_generation != presentation_transport_generation) {
        menu_aim_filter.reset();
      }
      menu_filter_presentation_generation = presentation_transport_generation;
      if (submitted_flat_fallback_this_frame && latest_controller_sample_ &&
          !synthetic_weapon_pointer_suppressed && !controllers_ignored) {
        const auto& right = latest_controller_sample_->hands[1];
        std::optional<darktidevr::math::Pose> pointer_pose = right.aim_pose;
        if (menu_aim_stabilization && !synthetic_controller_path) {
          const auto tracked = darktidevr::core::controller_orientation_tracked |
                               darktidevr::core::controller_position_tracked;
          const auto orientation = menu_aim_filter.update(
              right.aim_pose.orientation, latest_controller_sample_->sequence,
              frame_state.predictedDisplayTime, head_recenter_generation,
              (right.aim_tracking_flags & tracked) == tracked);
          if (orientation) {
            pointer_pose->orientation = *orientation;
            if (++menu_filter_samples % 6 == 0 && menu_filter_trace_samples < 200) {
              ++menu_filter_trace_samples;
              const auto raw = right.aim_pose.orientation;
              std::cout << "openxr.menu_aim_filter_sample sequence="
                        << latest_controller_sample_->sequence
                        << " pose_time_ns=" << frame_state.predictedDisplayTime
                        << " epoch=" << head_recenter_generation
                        << " raw=" << raw.x << ',' << raw.y << ',' << raw.z << ',' << raw.w
                        << " filtered=" << orientation->x << ',' << orientation->y
                        << ',' << orientation->z << ',' << orientation->w << '\n';
            }
          } else {
            pointer_pose.reset();
          }
        }
        const auto required =
            darktidevr::core::controller_orientation_valid |
            darktidevr::core::controller_position_valid;
        if (pointer_pose && (right.aim_tracking_flags & required) == required &&
            current_head_valid &&
            darktidevr::core::pointer_origin_within_reach(
                right.aim_pose.position, current_head.position, 1.5F)) {
          const auto direction = darktidevr::math::rotate(
              pointer_pose->orientation, {0.0F, 0.0F, -1.0F});
          ++controller_pointer_rays_;
          const auto pointer = darktidevr::core::map_pointer_to_panel(
              {pointer_pose->position, direction}, panel_pose,
              panel_extent.width_metres, panel_extent.height_metres,
              menu_input_source_width, menu_input_source_height,
              flat_interactive_mode
                  ? 0
                  : (presentation_sequence != 0 ? presentation_state.crop_x
                                                : 0),
              flat_interactive_mode
                  ? 0
                  : (presentation_sequence != 0 ? presentation_state.crop_y
                                                : 0),
              menu_input_source_width, menu_input_source_height);
          if (pointer) {
            ++controller_pointer_hits_;
            controller_pointer_x_ = pointer->source_x;
            controller_pointer_y_ = pointer->source_y;
            controller_pointer_pose = *pointer_pose;
            controller_pointer_hit = *pointer;
            menu_pointer_position =
                std::pair{pointer->source_x, pointer->source_y};
          }
        }
      }
      bool desktop_pointer_primary_down{};
      const auto menu_mode =
          presentation_sequence != 0 &&
          (presentation_state.mode == darktidevr::core::
                                          SharedPresentationMode::flat_menu ||
           presentation_state.mode == darktidevr::core::
                                          SharedPresentationMode::world_anchored_menu ||
           flat_interactive_mode);
      if (menu_mode && submitted_flat_fallback_this_frame) {
        const auto desktop_pointer = menu_input_injector->read_desktop_pointer(
            menu_input_source_width, menu_input_source_height);
        // A tracked controller ray remains authoritative even when named test
        // controls are enabled. Desktop hover is only the fallback when no
        // controller ray hits the panel, or the explicit owner while its
        // native button is held. This lets unattended named events reuse a
        // desktop position without making a live controller operate the stale
        // desktop cursor.
        if (desktop_pointer &&
            (!menu_pointer_position || desktop_pointer->primary_down ||
             desktop_pointer->auxiliary_down)) {
          menu_pointer_position =
              std::pair{desktop_pointer->source_x, desktop_pointer->source_y};
          desktop_pointer_primary_down = desktop_pointer->primary_down;
          desktop_owns_pointer = true;
        }
        if (desktop_pointer && !controller_pointer_hit) {
          desktop_cursor =
              std::pair{desktop_pointer->source_x, desktop_pointer->source_y};
        }
      }
      bool shared_menu_primary_down{};
      int shared_menu_scroll_steps{};
      bool shared_menu_back_down{};
      bool shared_menu_back_pressed{};
      if (menu_input_injector) {
        darktidevr::core::MenuPointerInput input{};
        input.active = menu_mode && submitted_flat_fallback_this_frame;
        input.source_position = menu_pointer_position;
        input.time_seconds =
            std::chrono::duration<double>(frame_start - start).count();
        if (latest_controller_sample_ && !controllers_ignored) {
          const auto& right = latest_controller_sample_->hands[1];
          input.trigger = right.trigger;
          input.thumbstick_y = right.thumbstick_y;
          // Back is the right secondary button only. The left menu button
          // used to double as back, but Virtual Desktop takes a double tap
          // of it to switch between the VR and desktop views, and the first
          // tap was closing the menu the user was in.
          input.back =
              (right.buttons & darktidevr::core::controller_secondary) != 0;
        }
        for (const auto& event : menu_pointer_state.update(input)) {
          ++menu_input_events;
          if (event.type == darktidevr::core::MenuPointerEventType::scroll) {
            shared_menu_scroll_steps = event.scroll_steps;
          }
          if (event.type == darktidevr::core::MenuPointerEventType::back) {
            shared_menu_back_pressed = true;
            std::cout << "openxr.menu_input_event=back\n";
          }
          // The game input adapter owns the XR cursor. Only the explicit
          // legacy injection mode may move Windows' cursor or send buttons.
          // A position read from the desktop mouse is never written back: the
          // round trip through the panel would drag against the real mouse.
          const bool desktop_move =
              desktop_owns_pointer &&
              event.type == darktidevr::core::MenuPointerEventType::move;
          if (enable_menu_input && !desktop_move &&
              menu_input_injector->dispatch(
                  event, menu_input_source_width,
                  menu_input_source_height)) {
            ++menu_input_dispatched;
          }
        }
      }
      if (enable_menu_test_controls) {
        if (WaitForSingleObject(menu_test_primary_down_event, 0) ==
            WAIT_OBJECT_0) {
          menu_test_primary_held = true;
          std::cout << "openxr.menu_test_event=primary_down\n";
        }
        if (WaitForSingleObject(menu_test_primary_up_event, 0) ==
            WAIT_OBJECT_0) {
          menu_test_primary_held = false;
          std::cout << "openxr.menu_test_event=primary_up\n";
        }
        if (WaitForSingleObject(menu_test_primary_event, 0) ==
            WAIT_OBJECT_0) {
          shared_menu_primary_down = true;
          std::cout << "openxr.menu_test_event=primary\n";
        }
        if (WaitForSingleObject(menu_test_back_event, 0) == WAIT_OBJECT_0) {
          shared_menu_back_down = true;
          shared_menu_back_pressed = true;
          std::cout << "openxr.menu_test_event=back\n";
        }
        if (WaitForSingleObject(menu_test_scroll_up_event, 0) ==
            WAIT_OBJECT_0) {
          shared_menu_scroll_steps = 1;
          std::cout << "openxr.menu_test_event=scroll_up\n";
        }
        if (WaitForSingleObject(menu_test_scroll_down_event, 0) ==
            WAIT_OBJECT_0) {
          shared_menu_scroll_steps = -1;
          std::cout << "openxr.menu_test_event=scroll_down\n";
        }
        shared_menu_primary_down =
            shared_menu_primary_down || menu_test_primary_held;
      }
      {
        darktidevr::core::SharedMenuPointerState shared_pointer{};
        shared_pointer.sequence = ++menu_pointer_sequence;
        shared_pointer.timestamp_ns = static_cast<std::uint64_t>(
            std::chrono::duration_cast<std::chrono::nanoseconds>(
                frame_start.time_since_epoch())
                .count());
        shared_pointer.source_width = menu_input_source_width;
        shared_pointer.source_height = menu_input_source_height;
        shared_pointer.scroll_steps = shared_menu_scroll_steps;
        shared_pointer.active = menu_mode &&
                                submitted_flat_fallback_this_frame &&
                                menu_pointer_position.has_value();
        if (menu_pointer_position) {
          shared_pointer.source_x = menu_pointer_position->first;
          shared_pointer.source_y = menu_pointer_position->second;
        }
        if (latest_controller_sample_ && !controllers_ignored) {
          const auto& left = latest_controller_sample_->hands[0];
          const auto& right = latest_controller_sample_->hands[1];
          shared_pointer.primary_down =
              right.trigger >= 0.55F ||
              (right.buttons & darktidevr::core::controller_primary) != 0;
          shared_pointer.secondary_down = left.trigger >= 0.55F;
          shared_pointer.back_down =
              (right.buttons & darktidevr::core::controller_secondary) != 0;
        }
        shared_pointer.back_down =
            shared_pointer.back_down || shared_menu_back_down;
        // Desktop buttons already reach the stock UI service. Publishing a
        // second edge here can replay that click on a later game/UI frame.
        // Desktop coordinates retain fallback/held pointing; Lua snapshots their
        // immediate point for stock mouse press/hold/release and wheel events.
        shared_pointer.primary_down =
            shared_pointer.primary_down || shared_menu_primary_down;
        const bool was_primary_armed = menu_primary_state.armed();
        // Secondary uses the same release/activation guard, independently of
        // primary. Both clicks target the existing right-hand menu ray.
        if (menu_secondary_state.update(
                presentation_state, menu_mode && submitted_flat_fallback_this_frame,
                shared_pointer.active, shared_pointer.secondary_down,
                std::chrono::duration<double>(frame_start - start).count())) {
          ++menu_secondary_press_sequence;
        }
        const bool primary_pressed = menu_primary_state.update(
            presentation_state, menu_mode && submitted_flat_fallback_this_frame,
            shared_pointer.active, shared_pointer.primary_down,
            std::chrono::duration<double>(frame_start - start).count());
        if (!was_primary_armed && menu_primary_state.armed()) {
          std::cout << "openxr.menu_primary=armed sequence="
                    << presentation_sequence << '\n';
        }
        if (primary_pressed) {
          ++menu_primary_press_sequence;
          std::cout << "openxr.menu_primary=pressed sequence="
                    << presentation_sequence << " trigger="
                    << (latest_controller_sample_
                            ? latest_controller_sample_->hands[1].trigger
                            : 0.0F)
                    << " desktop=" << desktop_pointer_primary_down
                    << " test=" << shared_menu_primary_down << '\n';
        }
        // The shared Lua transport must use the debounced state-machine edge,
        // not a second raw controller-level edge detector. The latter used to
        // bypass menu-entry Back arming and could immediately close a menu
        // when a sleeping controller briefly transitioned after activation.
        if (shared_menu_back_pressed) {
          ++menu_back_press_sequence;
        }
        if (shared_menu_scroll_steps != 0) {
          last_shared_menu_scroll_steps = shared_menu_scroll_steps;
          ++menu_scroll_sequence;
        }
        shared_pointer.scroll_steps = last_shared_menu_scroll_steps;
        shared_pointer.primary_press_sequence =
            menu_primary_press_sequence;
        shared_pointer.secondary_press_sequence = menu_secondary_press_sequence;
        shared_pointer.back_press_sequence = menu_back_press_sequence;
        shared_pointer.scroll_sequence = menu_scroll_sequence;
        if (!menu_pointer_writer.publish(shared_pointer)) {
          throw std::runtime_error("Shared menu pointer rejected sample");
        }
      }
      XrCompositionLayerProjection projection{
          XR_TYPE_COMPOSITION_LAYER_PROJECTION};
      // `submitted_view_projection_valid`: without a usable field of view
      // there is no projection to submit. Virtual Desktop has reported views
      // with valid pose flags and an all-zero FOV while the headset was not
      // streaming (16 September), which used to throw here and stop the
      // viewer; now the frame simply carries no projection layer.
      if (stereo && submitted_view_projection_valid) {
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
          // Computed before the theatre command list, so that what was drawn
          // into these images used this same projection.
          projection_view.pose = submitted_view_poses[eye];
          projection_view.fov = submitted_view_fovs[eye];
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
      std::array<XrCompositionLayerQuad, 3> pointer_quads{{
          {XR_TYPE_COMPOSITION_LAYER_QUAD},
          {XR_TYPE_COMPOSITION_LAYER_QUAD},
          {XR_TYPE_COMPOSITION_LAYER_QUAD},
      }};
      const auto configure_pointer_quad =
          [&](XrCompositionLayerQuad& quad,
              darktidevr::math::Pose pose, XrExtent2Df size,
              XrRect2Di texels) {
            quad.layerFlags =
                XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;
            quad.space = local_space_;
            quad.eyeVisibility = XR_EYE_VISIBILITY_BOTH;
            quad.subImage.swapchain = pointer_swapchain;
            quad.subImage.imageRect = texels;
            quad.pose.orientation = {pose.orientation.x,
                                     pose.orientation.y,
                                     pose.orientation.z,
                                     pose.orientation.w};
            quad.pose.position = {pose.position.x, pose.position.y,
                                  pose.position.z};
            quad.size = size;
          };
      const bool pointer_swatch_ready =
          menu_mode && submitted_flat_fallback_this_frame &&
          pointer_swatch_uploaded && !pointer_swatch_release_pending;
      bool pointer_ray_visible = false;
      bool pointer_target_visible = false;
      if (pointer_swatch_ready && desktop_cursor) {
        // No laser: the target sprite alone marks the desktop mouse, at the
        // pixel the stock UI service reads, just in front of the panel.
        const auto cursor = darktidevr::core::panel_point_from_source(
            panel_pose, panel_extent.width_metres, panel_extent.height_metres,
            desktop_cursor->first, desktop_cursor->second,
            flat_interactive_mode
                ? 0
                : (presentation_sequence != 0 ? presentation_state.crop_x : 0),
            flat_interactive_mode
                ? 0
                : (presentation_sequence != 0 ? presentation_state.crop_y : 0),
            menu_input_source_width, menu_input_source_height);
        if (cursor) {
          const auto panel_normal = darktidevr::math::rotate(
              panel_pose.orientation, {0.0F, 0.0F, 1.0F});
          configure_pointer_quad(
              pointer_quads[2],
              {panel_pose.orientation,
               {cursor->x + panel_normal.x * 0.004F,
                cursor->y + panel_normal.y * 0.004F,
                cursor->z + panel_normal.z * 0.004F}},
              {0.045F, 0.045F}, pointer_target_texels);
          pointer_target_visible = true;
        }
      }
      if (pointer_swatch_ready && controller_pointer_pose &&
          controller_pointer_hit) {
        pointer_ray_visible = true;
        pointer_target_visible = true;
        // The ray reaches halfway to the panel so the beam never covers
        // what it points at; two crossed strips make it visible from any
        // angle. The hit is marked by the target sprite (cyan ring and
        // cross), the one cursor for every menu: no capture path paints a
        // cursor of its own and the game only ever shows the Windows one.
        const auto ray_direction = darktidevr::math::rotate(
            controller_pointer_pose->orientation, {0.0F, 0.0F, -1.0F});
        const auto distance = controller_pointer_hit->distance_metres * 0.5F;
        const darktidevr::math::Vec3 ray_midpoint{
            controller_pointer_pose->position.x +
                ray_direction.x * distance * 0.5F,
            controller_pointer_pose->position.y +
                ray_direction.y * distance * 0.5F,
            controller_pointer_pose->position.z +
                ray_direction.z * distance * 0.5F};
        constexpr float half_pi = 1.57079632679489661923F;
        const auto ray_orientation = darktidevr::math::multiply(
            controller_pointer_pose->orientation,
            darktidevr::math::from_axis_angle(
                {1.0F, 0.0F, 0.0F}, -half_pi));
        configure_pointer_quad(
            pointer_quads[0], {ray_orientation, ray_midpoint},
            {0.008F, distance}, pointer_ray_texels);
        configure_pointer_quad(
            pointer_quads[1],
            {darktidevr::math::multiply(
                 ray_orientation,
                 darktidevr::math::from_axis_angle(
                     {0.0F, 1.0F, 0.0F}, half_pi)),
             ray_midpoint},
            {0.008F, distance}, pointer_ray_texels);
        const auto full_distance = controller_pointer_hit->distance_metres;
        const darktidevr::math::Vec3 hit_position{
            controller_pointer_pose->position.x +
                ray_direction.x * full_distance,
            controller_pointer_pose->position.y +
                ray_direction.y * full_distance,
            controller_pointer_pose->position.z +
                ray_direction.z * full_distance};
        const auto panel_normal = darktidevr::math::rotate(
            panel_pose.orientation, {0.0F, 0.0F, 1.0F});
        // 48 texels at 4.5 cm: the ring spans about 4 cm, the size the
        // capture-painted reticle had on a 2 m panel.
        configure_pointer_quad(
            pointer_quads[2],
            {panel_pose.orientation,
             {hit_position.x + panel_normal.x * 0.004F,
              hit_position.y + panel_normal.y * 0.004F,
              hit_position.z + panel_normal.z * 0.004F}},
            {0.045F, 0.045F}, pointer_target_texels);
      }
      // Head-locked focus vignette while aiming down sights: a metre ahead in
      // view space, wide enough to cover the field of view, sampling the
      // atlas sprite whose alpha follows ads_blend.
      XrCompositionLayerQuad ads_vignette_quad{XR_TYPE_COMPOSITION_LAYER_QUAD};
      // `enable_gameplay_reticle`: the sprite is painted only inside the
      // reticle atlas branch (update_reticle_atlas), so without it the quad
      // would sample a corner of the captured game window instead -- opaque
      // pixels across the whole view (review, 18 September).
      const bool submit_ads_vignette =
          ads_blend > 0.01F && enable_gameplay_reticle && window_capture &&
          flat_swapchain != XR_NULL_HANDLE &&
          view_space_ != XR_NULL_HANDLE && submitted_shared_pair_this_frame;
      if (submit_ads_vignette) {
        ads_vignette_quad.layerFlags = XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;
        ads_vignette_quad.space = view_space_;
        ads_vignette_quad.eyeVisibility = XR_EYE_VISIBILITY_BOTH;
        ads_vignette_quad.subImage.swapchain = flat_swapchain;
        ads_vignette_quad.subImage.imageRect.offset = {
            static_cast<std::int32_t>(flat_capture_width) - 42 - 66 + 1,
            static_cast<std::int32_t>(flat_capture_height) - 66 + 1};
        ads_vignette_quad.subImage.imageRect.extent = {62, 62};
        ads_vignette_quad.pose.orientation = {0.0F, 0.0F, 0.0F, 1.0F};
        ads_vignette_quad.pose.position = {0.0F, 0.0F, -1.0F};
        // Sized from the runtime's own field of view, so the sprite's
        // darkening reaches its peak at the edge of what the eye sees
        // (core/reticle_atlas.h). A fixed 3.6 m put that peak at 61 degrees,
        // outside the headset's view.
        float vignette_half{};
        for (const auto& view : located_views) {
          vignette_half = (std::max)(
              vignette_half,
              darktidevr::core::vignette_half_extent(
                  view.fov.angleLeft, view.fov.angleRight, view.fov.angleUp,
                  view.fov.angleDown));
        }
        if (!(vignette_half > 0.1F) || !std::isfinite(vignette_half)) {
          vignette_half = 1.8F;
        }
        ads_vignette_quad.size = {2.0F * vignette_half, 2.0F * vignette_half};
        if (!ads_vignette_logged) {
          ads_vignette_logged = true;
          std::cout << "openxr.ads_vignette blend=" << ads_blend
                    << " half_extent_m=" << vignette_half
                    << " peak_deg="
                    << std::atan(vignette_half) * 57.2957795F
                    << " images=" << ads_painted_blend.size()
                    << " sprite=" << ads_vignette_quad.subImage.imageRect.offset.x
                    << ',' << ads_vignette_quad.subImage.imageRect.offset.y
                    << '\n';
        }
      }
      // The board and its pointer as a projection layer of their own, drawn
      // from this frame's located eyes with the runtime's own field of view
      // and blended over the world by premultiplied alpha, as the quad
      // layers were. A board with no seat yet (no head) stays a view-space
      // quad layer.
      XrCompositionLayerProjection board_projection{
          XR_TYPE_COMPOSITION_LAYER_PROJECTION};
      std::array<XrCompositionLayerProjectionView, 2> board_projection_views{{
          {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW},
          {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW}}};
      bool board_in_projection_this_frame{};
      if (panel_renderer && submit_layer && board_texture_written &&
          submitted_flat_fallback_this_frame && flat_fallback_pose_valid &&
          located_views.size() == board_swapchains.size()) {
        XrSwapchainImageAcquireInfo board_acquire{
            XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
        XrSwapchainImageWaitInfo board_wait{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};
        board_wait.timeout = XR_INFINITE_DURATION;
        std::array<std::uint32_t, 2> board_image_indices{};
        std::array<ID3D12Resource*, 2> board_resources{};
        for (std::size_t eye = 0; eye < board_swapchains.size(); ++eye) {
          check_xr(xrAcquireSwapchainImage(board_swapchains[eye],
                                           &board_acquire,
                                           &board_image_indices[eye]),
                   "xrAcquireSwapchainImage(board)");
          check_xr(xrWaitSwapchainImage(board_swapchains[eye], &board_wait),
                   "xrWaitSwapchainImage(board)");
          board_resources[eye] =
              board_images[eye][board_image_indices[eye]].texture;
        }
        check(board_allocator->Reset(),
              "ID3D12CommandAllocator::Reset(board)");
        check(board_command_list->Reset(board_allocator.Get(), nullptr),
              "ID3D12GraphicsCommandList::Reset(board)");
        if (!panel_renderer->swatch_ready() && pointer_swatch_uploaded) {
          panel_renderer->upload_swatch(board_command_list.Get(),
                                        pointer_upload.Get(),
                                        pointer_upload_footprint);
        }
        std::array<darktidevr::harness::PanelQuad,
                   darktidevr::harness::PanelRenderer::maximum_quads_per_eye>
            board_quads{};
        std::size_t board_quad_count{};
        board_quads[board_quad_count++] = {
            flat_fallback_quad.pose, flat_fallback_quad.size,
            flat_fallback_quad.subImage.imageRect,
            darktidevr::harness::PanelQuad::Source::board};
        for (std::size_t pointer_index = 0;
             pointer_index < pointer_quads.size(); ++pointer_index) {
          if (pointer_index == 2 ? pointer_target_visible
                                 : pointer_ray_visible) {
            const auto& pointer_quad = pointer_quads[pointer_index];
            board_quads[board_quad_count++] = {
                pointer_quad.pose, pointer_quad.size,
                pointer_quad.subImage.imageRect,
                darktidevr::harness::PanelQuad::Source::swatch};
          }
        }
        const XrRect2Di board_rect{{0, 0}, board_eye_extent};
        panel_renderer->begin(board_command_list.Get());
        for (std::size_t eye = 0; eye < board_swapchains.size(); ++eye) {
          const D3D12_CPU_DESCRIPTOR_HANDLE board_target{
              board_rtv_heap->GetCPUDescriptorHandleForHeapStart().ptr +
              static_cast<SIZE_T>(board_rtv_base_offsets[eye] +
                                  board_image_indices[eye]) *
                  rtv_increment};
          panel_renderer->record(board_command_list.Get(), board_target,
                                 board_rect, eye, located_views[eye].pose,
                                 located_views[eye].fov, board_quads.data(),
                                 board_quad_count, true);
        }
        panel_renderer->end(board_command_list.Get());
        const bool board_readback = projected_eye_readback_requested &&
                                    !projected_eye_readback_copied_this_frame &&
                                    projected_eye_readbacks[1] &&
                                    board_eye_extent.width ==
                                        static_cast<std::int32_t>(width) &&
                                    board_eye_extent.height ==
                                        static_cast<std::int32_t>(height);
        if (board_readback) {
          for (std::size_t eye = 0; eye < board_resources.size(); ++eye) {
            D3D12_RESOURCE_BARRIER barrier{};
            barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
            barrier.Transition.pResource = board_resources[eye];
            barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
            barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
            barrier.Transition.Subresource =
                D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
            board_command_list->ResourceBarrier(1, &barrier);
            D3D12_TEXTURE_COPY_LOCATION source{};
            source.pResource = board_resources[eye];
            source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            D3D12_TEXTURE_COPY_LOCATION destination{};
            destination.pResource = projected_eye_readbacks[eye].Get();
            destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
            destination.PlacedFootprint = projected_eye_readback_footprint;
            board_command_list->CopyTextureRegion(&destination, 0, 0, 0,
                                                  &source, nullptr);
            std::swap(barrier.Transition.StateBefore,
                      barrier.Transition.StateAfter);
            board_command_list->ResourceBarrier(1, &barrier);
          }
        }
        check(board_command_list->Close(),
              "ID3D12GraphicsCommandList::Close(board)");
        ID3D12CommandList* board_lists[]{board_command_list.Get()};
        queue->ExecuteCommandLists(1, board_lists);
        const auto board_signal_value = ++fence_value;
        check(queue->Signal(fence.Get(), board_signal_value),
              "ID3D12CommandQueue::Signal(board)");
        wait_for_fence(fence.Get(), board_signal_value, fence_event,
                       "ID3D12Fence::SetEventOnCompletion(board)");
        if (board_readback) {
          write_projected_eye_readback(board_resources);
        }
        XrSwapchainImageReleaseInfo board_release{
            XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
        for (std::size_t eye = 0; eye < board_swapchains.size(); ++eye) {
          check_xr(xrReleaseSwapchainImage(board_swapchains[eye],
                                           &board_release),
                   "xrReleaseSwapchainImage(board)");
          auto& view = board_projection_views[eye];
          view.pose = located_views[eye].pose;
          view.fov = located_views[eye].fov;
          view.subImage.swapchain = board_swapchains[eye];
          view.subImage.imageRect = board_rect;
          view.subImage.imageArrayIndex = 0;
        }
        board_projection.layerFlags =
            XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;
        board_projection.space = local_space_;
        board_projection.viewCount =
            static_cast<std::uint32_t>(board_projection_views.size());
        board_projection.views = board_projection_views.data();
        board_in_projection_this_frame = true;
        if (++board_projection_frames == 1) {
          std::cout << "openxr.board_projection=first-frame quads="
                    << board_quad_count << " mode="
                    << static_cast<std::uint32_t>(presentation_state.mode)
                    << " extent=" << board_eye_extent.width << 'x'
                    << board_eye_extent.height << '\n';
        }
      }
      std::array<const XrCompositionLayerBaseHeader*, 8> layers{};
      std::uint32_t layer_count{};
      if (submit_layer) {
        if (submitted_shared_pair_this_frame && stereo &&
            submitted_view_projection_valid) {
          layers[layer_count++] =
              reinterpret_cast<const XrCompositionLayerBaseHeader*>(
                  &projection);
        }
        if (board_in_projection_this_frame) {
          layers[layer_count++] =
              reinterpret_cast<const XrCompositionLayerBaseHeader*>(
                  &board_projection);
        } else if (submitted_flat_fallback_this_frame) {
          layers[layer_count++] =
              reinterpret_cast<const XrCompositionLayerBaseHeader*>(
                  &flat_fallback_quad);
        } else if (!stereo) {
          layers[layer_count++] =
              reinterpret_cast<const XrCompositionLayerBaseHeader*>(&quads[0]);
        }
        for (std::size_t pointer_index = 0;
             pointer_index < pointer_quads.size(); ++pointer_index) {
          if (!board_in_projection_this_frame &&
              (pointer_index == 2 ? pointer_target_visible
                                  : pointer_ray_visible)) {
            layers[layer_count++] =
                reinterpret_cast<const XrCompositionLayerBaseHeader*>(
                    &pointer_quads[pointer_index]);
          }
        }
        // The quad carries a swapchain only when the flat capture exists
        // (its sprite lives in that texture). Submitting it without one sends
        // a null swapchain to xrEndFrame, which throws and stops the viewer;
        // reachable today through the synthetic benchmark, which asks for the
        // reticle and defers the window capture.
        if (gameplay_reticle_pose && reticle_scale > 0.0F &&
            !rendered_gameplay_reticle &&
            gameplay_reticle_quad.subImage.swapchain != XR_NULL_HANDLE) {
          if (!gameplay_reticle_layer_logged) {
            gameplay_reticle_layer_logged = true;
            std::cout << "openxr.gameplay_reticle layer=quad\n";
          }
          layers[layer_count++] =
              reinterpret_cast<const XrCompositionLayerBaseHeader*>(
                  &gameplay_reticle_quad);
        }
        if (submit_ads_vignette) {
          layers[layer_count++] =
              reinterpret_cast<const XrCompositionLayerBaseHeader*>(
                  &ads_vignette_quad);
        }
      }
      XrFrameEndInfo frame_end{XR_TYPE_FRAME_END_INFO};
      frame_end.displayTime = frame_state.predictedDisplayTime;
      frame_end.environmentBlendMode = environment_blend_mode_;
      frame_end.layerCount = layer_count;
      frame_end.layers = layer_count != 0 ? layers.data() : nullptr;
      const auto xrEndFrame_tick = GetTickCount64();
      const auto frame_end_start = std::chrono::steady_clock::now();
      check_xr(xrEndFrame(session_, &frame_end), "xrEndFrame(theatre)");
      const auto distinct_total = fresh_shared_pairs + generated_submitted;
      if (cadence_generation != rendered_pair_gameplay_generation) {
        delivery_cadence.break_continuity();
        cadence_generation = rendered_pair_gameplay_generation;
      }
      delivery_cadence.observe(frame_state.predictedDisplayTime,
          submitted_shared_pair_this_frame && stereo && layer_count != 0,
          distinct_total != cadence_distinct_total);
      cadence_distinct_total = distinct_total;
      frame_stage_timing.elapsed(FrameStage::EndFrame, frame_end_start);
      report_pose_wait("xrEndFrame", xrEndFrame_tick);
      ++processed_frames;
      poll_session_events();
      frame_stage_timing.elapsed(FrameStage::ActiveLoop, frame_start);
      if ((frame + 1) % 120 == 0) {
        const char* pair_wait_mode = pair_poll_wait.failures() != previous_pair_wait_failures
            ? "mixed_failure" : pair_poll_wait.precise() ? "high_resolution" : "standard";
        frame_stage_timing.write(std::cout, processed_frames, frame_state.predictedDisplayPeriod,
                                pair_wait_mode);
        std::cout << "openxr.pair_poll_wait requested=" << precise_pair_wait_requested
                  << " precise=" << pair_poll_wait.precise()
                  << " failures=" << pair_poll_wait.failures() << '\n';
        previous_pair_wait_failures = pair_poll_wait.failures();
        frame_stage_timing.reset();
        const auto report_time = std::chrono::steady_clock::now();
        const auto live_seconds =
            std::chrono::duration<double>(report_time - start).count();
        const auto interval_seconds = std::chrono::duration<double>(
            report_time - last_live_report).count();
        const auto interval_submissions =
            submitted_frames - last_live_submitted_frames;
        const auto interval_fresh_pairs =
            fresh_shared_pairs - last_live_fresh_shared_pairs;
        const auto interval_generated_pairs=generated_submitted-last_live_generated_submissions;
        const auto interval_fallback_frames =
            flat_fallback_frames - last_live_fallback_frames;
        std::cout << "openxr.live.submission_fps="
                  << submitted_frames / live_seconds
                  << " fresh_pair_fps=" << fresh_shared_pairs / live_seconds
                  << " interval_seconds=" << interval_seconds
                  << " gameplay_generation=" << rendered_pair_gameplay_generation
                  << " interval_submission_fps="
                  << interval_submissions / interval_seconds
                  << " interval_fresh_pair_fps="
                  << interval_fresh_pairs / interval_seconds
                  << " interval_generated_pair_fps=" << interval_generated_pairs/interval_seconds
                  << " interval_distinct_pair_fps=" << (interval_fresh_pairs+interval_generated_pairs)/interval_seconds
                  << " interval_cached_pair_fps=" << (cached_original_submissions-last_live_cached_original_submissions)/interval_seconds
                  << " cadence_distinct=" << delivery_cadence.window().distinct
                  << " cadence_repeats=" << delivery_cadence.window().repeats
                  << " repeat_run_peak=" << delivery_cadence.window().repeat_run_peak
                  << " repeat_runs_ended=" << delivery_cadence.window().ended_repeat_runs
                  << " distinct_gap_samples=" << delivery_cadence.window().gaps
                  << " distinct_gap_max_ms=" << delivery_cadence.window().maximum_gap_ns/1.0e6
                  << " cadence_clock_breaks=" << delivery_cadence.window().clock_breaks
                  << " source_period_ms=" << generated_cadence.source_period/1.0e6
                  << " interval_fallback_fps="
                  << interval_fallback_frames / interval_seconds
                  << " reused_frames=" << reused_shared_frames
                  << " pair_pose_mismatches=" << pair_pose_mismatches
                  << " shared_ready=" << shared_last_ready_value
                  << " checked_ready="
                  << last_pair_pose_checked_ready_value
                  << " rendered_tag_ready="
                  << rendered_pair_pose_ready_value
                  << std::endl;
        delivery_cadence.reset_window();
        if(generated_surfaces) {
          std::cout << "openxr.generated_selection gameplay_generation=" << rendered_pair_gameplay_generation
                    << " interval_seconds=" << interval_seconds
                    << " reserved_original=" << generated_reserved_original_frames
                    << " unavailable=" << generated_selection_outcomes[0]
                    << " no_new=" << generated_selection_outcomes[1]
                    << " metadata_rejected=" << generated_selection_outcomes[2]
                    << " original_missing=" << generated_selection_outcomes[3]
                    << " order_rejected=" << generated_selection_outcomes[4]
                    << " history_missing=" << generated_selection_outcomes[5]
                    << " selected=" << generated_selection_outcomes[6]
                    << " original_latest=" << original_state.latest_sequence
                    << " original_ingested=" << ingested_original_ready
                    << " original_displayed=" << last_original_ready
                    << " generated_latest=" << generated_state.latest_sequence
                    << " generated_consumed=" << generated_last_consumed << '\n';
        }
        generated_selection_outcomes={};
        generated_reserved_original_frames=0;
        if (synthetic_roomscale_path) {
          std::cout << "openxr.synthetic_roomscale frame="
                    << synthetic_roomscale_frames << " camera="
                    << latest_camera_translation.x << ','
                    << latest_camera_translation.y << ','
                    << latest_camera_translation.z << " body_follow="
                    << latest_body_follow_offset.x << ','
                    << latest_body_follow_offset.y << ','
                    << latest_body_follow_offset.z << std::endl;
        }
        last_live_report = report_time;
        last_live_submitted_frames = submitted_frames;
        last_live_fresh_shared_pairs = fresh_shared_pairs;
        last_live_generated_submissions=generated_submitted;
        last_live_cached_original_submissions=cached_original_submissions;
        last_live_fallback_frames = flat_fallback_frames;
      }
    }

    const auto elapsed = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - start);
    capture_worker.reset();
    if (menu_input_injector) {
      for (const auto& event : menu_pointer_state.update({})) {
        ++menu_input_events;
        if (menu_input_injector->dispatch(
                event,
                presentation_sequence != 0 ? presentation_state.source_width
                                           : flat_capture_width,
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
              << "openxr.theatre_capture_attempts="
              << capture_attempts.load(std::memory_order_relaxed) << '\n'
              << "openxr.theatre_capture_failures="
              << capture_failures_total.load(std::memory_order_relaxed) << '\n'
              << "openxr.theatre_capture_window="
              << (window_capture ? "acquired"
                                 : (capture_title ? "pending" : "none"))
              << '\n'
              << "openxr.theatre_stale_frames=" << capture_stale_frames
              << '\n'
              << "openxr.flat_fallback_frames=" << flat_fallback_frames
              << '\n'
              << "openxr.flat_fallback_transitions="
              << flat_fallback_transitions << '\n'
              << "openxr.fresh_shared_pairs=" << fresh_shared_pairs << '\n'
              << "openxr.generated_submitted_frames=" << generated_submitted << '\n'
              << "openxr.reused_shared_frames=" << reused_shared_frames
              << '\n'
              << "openxr.tracked_cuff_frames=" << tracked_cuff_frames << '\n'
              << "openxr.tracked_cuff_draws=" << tracked_cuff_draws << '\n'
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
              << "openxr.controller_left_thumbstick_active_frames="
              << controller_thumbstick_active_frames_[0] << '\n'
              << "openxr.controller_right_thumbstick_active_frames="
              << controller_thumbstick_active_frames_[1] << '\n'
              << "openxr.controller_left_thumbstick_changed_frames="
              << controller_thumbstick_changed_frames_[0] << '\n'
              << "openxr.controller_right_thumbstick_changed_frames="
              << controller_thumbstick_changed_frames_[1] << '\n'
              << "openxr.controller_pointer_rays=" << controller_pointer_rays_
              << '\n'
              << "openxr.controller_pointer_hits=" << controller_pointer_hits_
              << '\n'
              << "openxr.controller_pointer_last_source="
              << controller_pointer_x_ << ',' << controller_pointer_y_ << '\n'
              << "openxr.gameplay_reticle_frames="
              << gameplay_reticle_frames_ << '\n'
              << "openxr.gameplay_reticle_post_start_frames="
              << gameplay_reticle_post_start_frames_ << '\n'
              << "openxr.gameplay_reticle_hit_frames="
              << gameplay_reticle_hit_frames_ << '\n'
              << "openxr.gameplay_reticle_miss_frames="
              << gameplay_reticle_miss_frames_ << '\n'
              << "openxr.gameplay_reticle_transport_samples="
              << gameplay_reticle_transport_samples_ << '\n'
              << "openxr.gameplay_reticle_distance_metres="
              << gameplay_reticle_distance_metres_ << '\n'
              << "openxr.menu_input_events=" << menu_input_events << '\n'
              << "openxr.menu_input_dispatched=" << menu_input_dispatched
              << '\n'
              << "openxr.synthetic_controller_frames="
              << synthetic_controller_frames_ << '\n'
              << "openxr.synthetic_weapon_aim_matrix_frames="
              << synthetic_weapon_aim_matrix_frames_ << '\n'
              << "openxr.synthetic_movement_reference_frames="
              << synthetic_movement_reference_frames_ << '\n'
              << "openxr.synthetic_controller_phase_frames=";
    for (std::size_t index = 0;
         index < synthetic_controller_phase_frames_.size(); ++index) {
      std::cout << (index == 0 ? "" : ",")
                << synthetic_controller_phase_frames_[index];
    }
    std::cout << '\n'
              << "openxr.synthetic_head_frames=" << synthetic_head_frames
              << '\n'
              << "openxr.synthetic_body_inspection_frames="
              << synthetic_body_inspection_frames << '\n'
              << "openxr.synthetic_roomscale_frames="
              << synthetic_roomscale_frames << '\n'
              << "openxr.synthetic_crouch_frames="
              << synthetic_crouch_frames << '\n'
              << "openxr.synthetic_head_phase_frames=";
    for (std::size_t index = 0;
         index < synthetic_head_phase_frames.size(); ++index) {
      std::cout << (index == 0 ? "" : ",")
                << synthetic_head_phase_frames[index];
    }
    std::cout << '\n';
    if (upload) {
      upload->Unmap(0, nullptr);
      upload_pixels = nullptr;
    }
    CloseHandle(fence_event);
    if (projection_active_event) {
      CloseHandle(projection_active_event);
      projection_active_event = nullptr;
    }
    if (menu_test_primary_event) {
      CloseHandle(menu_test_primary_event);
    }
    if (menu_test_primary_down_event) {
      CloseHandle(menu_test_primary_down_event);
    }
    if (menu_test_primary_up_event) {
      CloseHandle(menu_test_primary_up_event);
    }
    if (menu_test_back_event) {
      CloseHandle(menu_test_back_event);
    }
    if (menu_test_scroll_up_event) {
      CloseHandle(menu_test_scroll_up_event);
    }
    if (menu_test_scroll_down_event) {
      CloseHandle(menu_test_scroll_down_event);
    }
    for (const auto swapchain : theatre_swapchains) {
      check_xr(xrDestroySwapchain(swapchain), "xrDestroySwapchain(theatre)");
    }
    if (flat_swapchain != XR_NULL_HANDLE) {
      check_xr(xrDestroySwapchain(flat_swapchain),
               "xrDestroySwapchain(flat capture)");
    }
    if (pointer_swapchain != XR_NULL_HANDLE) {
      check_xr(xrDestroySwapchain(pointer_swapchain),
               "xrDestroySwapchain(pointer swatch)");
    }
    for (const auto swapchain : board_swapchains) {
      if (swapchain != XR_NULL_HANDLE) {
        check_xr(xrDestroySwapchain(swapchain), "xrDestroySwapchain(board)");
      }
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
      if (stage_space_ != XR_NULL_HANDLE) {
        xrDestroySpace(stage_space_);
        stage_space_ = XR_NULL_HANDLE;
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

  std::string path_string(XrPath value) const {
    if (value == XR_NULL_PATH) {
      return "<null>";
    }
    std::uint32_t required{};
    check_xr(xrPathToString(instance_, value, 0, &required, nullptr),
             "xrPathToString(size)");
    std::string result(required, '\0');
    check_xr(xrPathToString(instance_, value, required, &required,
                            result.data()),
             "xrPathToString(value)");
    if (!result.empty() && result.back() == '\0') {
      result.pop_back();
    }
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

      const std::array<XrActionSuggestedBinding, 19> touch_bindings{{
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
          {haptic_action_, path("/user/hand/left/output/haptic")},
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

      const std::array<XrActionSuggestedBinding, 7> simple_bindings{{
          {grip_action_, path("/user/hand/left/input/grip/pose")},
          {grip_action_, path("/user/hand/right/input/grip/pose")},
          {primary_action_, path("/user/hand/left/input/select/click")},
          {primary_action_, path("/user/hand/right/input/select/click")},
          {menu_action_, path("/user/hand/left/input/menu/click")},
          {haptic_action_, path("/user/hand/left/output/haptic")},
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

  // Plays one pulse on each requested hand. Logs the first pulses and every
  // failure kind once; a missing session or action set is skipped quietly.
  void apply_haptic_pulse(const darktidevr::core::HapticPulse& pulse,
                          std::uint64_t request) {
    if (session_ == XR_NULL_HANDLE || haptic_action_ == XR_NULL_HANDLE) {
      return;
    }
    XrHapticVibration vibration{XR_TYPE_HAPTIC_VIBRATION};
    vibration.amplitude = pulse.amplitude;
    vibration.duration =
        static_cast<XrDuration>(pulse.duration_ms) * 1'000'000;
    vibration.frequency = pulse.frequency_hz > 0.0F
                              ? pulse.frequency_hz
                              : XR_FREQUENCY_UNSPECIFIED;
    for (std::size_t hand = 0; hand < hand_paths_.size(); ++hand) {
      if ((pulse.hands & (1U << hand)) == 0) {
        continue;
      }
      XrHapticActionInfo info{XR_TYPE_HAPTIC_ACTION_INFO};
      info.action = haptic_action_;
      info.subactionPath = hand_paths_[hand];
      const auto result = xrApplyHapticFeedback(
          session_, &info,
          reinterpret_cast<const XrHapticBaseHeader*>(&vibration));
      ++haptic_pulses_;
      const bool failed = XR_FAILED(result);
      if (haptic_pulses_ <= 10 || (failed && haptic_failures_logged_ < 5)) {
        if (failed) {
          ++haptic_failures_logged_;
        }
        std::cout << "openxr.haptic request=" << request
                  << " hand=" << (hand == 0 ? "left" : "right")
                  << " amplitude=" << pulse.amplitude
                  << " duration_ms=" << pulse.duration_ms
                  << " frequency_hz=" << pulse.frequency_hz
                  << " result=" << static_cast<int>(result) << '\n';
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
        ++controller_thumbstick_active_frames_[hand];
        if (stick.changedSinceLastSync) {
          ++controller_thumbstick_changed_frames_[hand];
        }
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
    for (std::size_t hand = 0; hand < hand_paths_.size(); ++hand) {
      if (!controller_profile_logged_[hand]) {
        const auto& state = sample.hands[hand];
        const auto required_flags =
            darktidevr::core::controller_orientation_valid |
            darktidevr::core::controller_position_valid;
        if ((state.aim_tracking_flags & required_flags) != required_flags ||
            (state.grip_tracking_flags & required_flags) != required_flags) {
          continue;
        }
        XrInteractionProfileState profile{
            XR_TYPE_INTERACTION_PROFILE_STATE};
        check_xr(xrGetCurrentInteractionProfile(
                     session_, hand_paths_[hand], &profile),
                 "xrGetCurrentInteractionProfile");
        const auto aim_from_grip = darktidevr::math::compose(
            darktidevr::math::inverse(state.aim_pose), state.grip_pose);
        const auto grip_forward = darktidevr::math::rotate(
            state.grip_pose.orientation, {0.0F, 0.0F, -1.0F});
        const auto grip_up = darktidevr::math::rotate(
            state.grip_pose.orientation, {0.0F, 1.0F, 0.0F});
        const auto aim_forward = darktidevr::math::rotate(
            state.aim_pose.orientation, {0.0F, 0.0F, -1.0F});
        const auto dot = [](darktidevr::math::Vec3 left,
                            darktidevr::math::Vec3 right) {
          return left.x * right.x + left.y * right.y + left.z * right.z;
        };
        std::cout << "openxr.controller_profile hand="
                  << (hand == 0 ? "left" : "right")
                  << " profile=" << path_string(profile.interactionProfile)
                  << " aim_from_grip_q=" << aim_from_grip.orientation.x << ','
                  << aim_from_grip.orientation.y << ','
                  << aim_from_grip.orientation.z << ','
                  << aim_from_grip.orientation.w
                  << " aim_from_grip_p=" << aim_from_grip.position.x << ','
                  << aim_from_grip.position.y << ','
                  << aim_from_grip.position.z
                  << " grip_forward_dot_aim_forward="
                  << dot(grip_forward, aim_forward)
                  << " grip_up_dot_aim_forward="
                  << dot(grip_up, aim_forward) << '\n';
        controller_profile_logged_[hand] = true;
      }
    }
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
    if (stage_space_ != XR_NULL_HANDLE) {
      xrDestroySpace(stage_space_);
      stage_space_ = XR_NULL_HANDLE;
    }
    if (session_ != XR_NULL_HANDLE) {
      xrDestroySession(session_);
      session_ = XR_NULL_HANDLE;
    }
    session_running_ = false;
  }

  void create_swapchains(const std::vector<std::int64_t>& formats,
                         bool create_projection_swapchains, ID3D12Device* device) {
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
      const auto create_result = xrCreateSwapchain(session_, &create_info, &swapchain);
      if (XR_FAILED(create_result)) {
        // VDXR's OVR wrapper reports only the numeric result. Read the optional
        // thread-local diagnostic from its already loaded backend immediately;
        // do not load/initialize another runtime or infer that old text is fresh.
        // ABI: LibOVR 3621783c/include/OVR_ErrorCode.h and OVR_CAPI.h.
        if (const auto backend = GetModuleHandleW(L"VirtualDesktop.LibOVRRT64_1.dll")) {
          struct OvrErrorInfo {
            std::int32_t result;
            char text[512];
          };
          static_assert(sizeof(OvrErrorInfo) == 516);
          using GetLastError = void(__cdecl*)(OvrErrorInfo*);
          const auto address = GetProcAddress(backend, "ovr_GetLastErrorInfo");
          if (address) {
            GetLastError read_error{};
            static_assert(sizeof(read_error) == sizeof(address));
            std::memcpy(&read_error, &address, sizeof(read_error));
            OvrErrorInfo error{};
            read_error(&error);
            error.text[sizeof(error.text) - 1] = '\0';
            std::cerr << "openxr.swapchain_failure.vd_last_error result=" << error.result
                      << " text=" << error.text << '\n';
          }
        }
        darktidevr::xr::report_runtime_d3d11_diagnostics(std::cerr);
        darktidevr::xr::probe_runtime_d3d11_import_adapters(std::cerr);
        std::cerr << "openxr.swapchain_failure eye=" << swapchains_.size()
                  << " result=" << create_result
                  << " width=" << create_info.width << " height=" << create_info.height
                  << " format=" << create_info.format << " samples=" << create_info.sampleCount
                  << " usage=" << create_info.usageFlags << " array=" << create_info.arraySize
                  << " faces=" << create_info.faceCount << " mips=" << create_info.mipCount
                  << " device_removed_reason="
                  << static_cast<std::uint32_t>(device->GetDeviceRemovedReason()) << '\n';
        ComPtr<ID3D12InfoQueue> messages;
        if (SUCCEEDED(device->QueryInterface(IID_PPV_ARGS(&messages)))) {
          const auto count = messages->GetNumStoredMessagesAllowedByRetrievalFilter();
          std::cerr << "openxr.swapchain_failure.d3d12_messages=" << count << '\n';
          const auto first = count > 8 ? count - 8 : 0;
          for (auto index = first; index < count; ++index) {
            SIZE_T bytes{};
            if (FAILED(messages->GetMessage(index, nullptr, &bytes)) ||
                bytes < sizeof(D3D12_MESSAGE) || bytes > 1024 * 1024) {
              continue;
            }
            std::vector<std::byte> storage(bytes);
            auto* message = reinterpret_cast<D3D12_MESSAGE*>(storage.data());
            if (SUCCEEDED(messages->GetMessage(index, message, &bytes))) {
              std::cerr << "openxr.swapchain_failure.d3d12 id=" << message->ID
                        << " severity=" << message->Severity << " text="
                        << (message->pDescription ? message->pDescription : "unavailable") << '\n';
            }
          }
        } else {
          std::cerr << "openxr.swapchain_failure.d3d12_messages=unavailable\n";
        }
      }
      check_xr(create_result, "xrCreateSwapchain");
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
          if (session_state_ == XR_SESSION_STATE_STOPPING) {
            // The runtime stops a running session when the headset sleeps
            // (unworn); READY follows when it wakes. Loops that can wait for
            // that pause instead of exiting.
            runtime_stop_pending_ = true;
            if (!runtime_stop_resumable_) {
              runtime_exit_requested_ = true;
            }
          } else if (session_state_ == XR_SESSION_STATE_EXITING ||
                     session_state_ == XR_SESSION_STATE_LOSS_PENDING) {
            runtime_exit_requested_ = true;
          }
        }
      } else if (event.type ==
                 XR_TYPE_EVENT_DATA_REFERENCE_SPACE_CHANGE_PENDING) {
        const auto* changed = reinterpret_cast<
            const XrEventDataReferenceSpaceChangePending*>(&event);
        if (changed->session == session_ &&
            changed->referenceSpaceType == XR_REFERENCE_SPACE_TYPE_LOCAL) {
          reference_space_recenter_pending_ = true;
          flat_reanchor_pending_ = true;
          flat_reanchor_after_ = changed->changeTime;
          std::cout << "openxr.head_recenter=runtime-pending\n";
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
    // Our own exit request also passes through STOPPING; that one ends here.
    runtime_stop_resumable_ = false;
    if (!session_running_) {
      return;
    }
    if (session_state_ != XR_SESSION_STATE_STOPPING) {
      check_xr(xrRequestExitSession(session_), "xrRequestExitSession");
    }
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
  XrSpace stage_space_{XR_NULL_HANDLE};
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
  std::uint64_t haptic_pulses_{};
  std::uint32_t haptic_failures_logged_{};
  std::array<XrSpace, 2> aim_spaces_{XR_NULL_HANDLE, XR_NULL_HANDLE};
  std::array<XrSpace, 2> grip_spaces_{XR_NULL_HANDLE, XR_NULL_HANDLE};
  std::unique_ptr<darktidevr::core::SharedControllerStateWriter>
      controller_writer_;
  std::uint64_t controller_sequence_{};
  std::optional<darktidevr::core::SharedControllerState>
      latest_controller_sample_;
  std::optional<darktidevr::math::Pose> controller_recenter_pose_;
  bool reference_space_recenter_pending_{};
  // Set with every recenter (the runtime's reference-space change or the
  // game's request): the spatial flat board is re-seated from the current
  // head at the next frame instead of being left where local space moved.
  // Worn 16 September: thirteen runtime recenters in a session left the
  // loading and menu boards off to the side and turning against the head.
  bool flat_reanchor_pending_{};
  // The runtime announces a reference-space change before it takes
  // effect (changeTime); a re-seat before then would seat the board from
  // the old head and the space would move under it. Zero for a game
  // request, which is applied at once.
  XrTime flat_reanchor_after_{};
  std::uint64_t controller_samples_{};
  std::array<bool, 2> controller_profile_logged_{};
  float runtime_ipd_metres_{};
  std::array<std::uint64_t, 2> controller_aim_tracked_frames_{};
  std::array<std::uint64_t, 2> controller_thumbstick_active_frames_{};
  std::array<std::uint64_t, 2> controller_thumbstick_changed_frames_{};
  std::uint64_t controller_pointer_rays_{};
  std::uint64_t gameplay_reticle_frames_{};
  std::uint64_t gameplay_reticle_post_start_frames_{};
  std::uint64_t gameplay_reticle_hit_frames_{};
  std::uint64_t gameplay_reticle_miss_frames_{};
  std::uint64_t gameplay_reticle_transport_samples_{};
  float gameplay_reticle_distance_metres_{};
  std::uint64_t controller_pointer_hits_{};
  std::uint32_t controller_pointer_x_{};
  std::uint32_t controller_pointer_y_{};
  std::uint64_t synthetic_controller_frames_{};
  std::uint64_t synthetic_weapon_aim_matrix_frames_{};
  std::uint64_t synthetic_movement_reference_frames_{};
  std::uint64_t synthetic_holster_frames_{};
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
  bool runtime_exit_requested_{};
  bool runtime_stop_pending_{};
  bool runtime_stop_resumable_{};
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
    wait_for_fence(fence_.Get(), value, fence_event_,
                   "ID3D12Fence::SetEventOnCompletion");
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
            << "Usage: darktidevr-xr-harness [--frames N] [--show] [--flush-log] [--stop-file PATH (shared eyes only)] "
               "[--debug-layer] [--runtime-d3d11-diagnostics] [--probe-shared-import-adapters] [--no-openxr | --require-openxr] [--require-rendering] "
               "[--xr-frames N | --xr-seconds N] [--theatre] "
               "[--stereo-sbs] [--stereo-tb] "
                "[--capture-window-title TEXT [--capture-window-deferred] "
                "[--capture-window-policy on_demand|always]] [--shared-eyes] "
                "[--enable-menu-input [--menu-input-window-title TEXT]] "
                "[--menu-aim-stabilization] "
                "[--synthetic-controller-path] "
                "[--synthetic-body-path] "
                "[--synthetic-gameplay-input] "
                "[--synthetic-weapon-aim-matrix] "
                "[--synthetic-movement-reference-path] "
                "[--enable-gameplay-reticle] "
                "[--tracked-cuff-overlay] "
                "[--synthetic-head-sweep] "
                "[--synthetic-body-inspection] "
                "[--synthetic-neck-pivot-path] "
                "[--synthetic-roomscale-path] "
                "[--synthetic-crouch-path] "
                "[--synthetic-billboard-sweep] "
                "[--projection-translation-scale N] "
                "[--shared-pose-sequence-offset N] "
               "[--pair-driven-shared | --continuous-shared] "
               "[--resize-at N]\n\n"
            << "Creates an independent D3D12 swapchain and reports OpenXR "
               "discovery.\n"
            << "--no-openxr runs desktop graphics only without runtime discovery.\n"
            << "--runtime-d3d11-diagnostics requests the D3D11 debug layer inside this process; not for performance measurements.\n"
            << "It never loads or modifies Darktide.\n";
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  try {
    UINT frames = 120;
    bool show = false;
    bool debug_layer = false;
    bool runtime_d3d11_diagnostics = false;
    bool probe_shared_import_adapters = false;
    bool no_openxr = false;
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
    bool enable_menu_test_controls = false;
    bool menu_aim_stabilization = false;
    bool synthetic_controller_path = false;
    bool synthetic_body_path = false;
    bool synthetic_gameplay_input = false;
    bool synthetic_weapon_aim_matrix = false;
    bool synthetic_movement_reference_path = false;
    bool synthetic_holster_once = false;
    bool enable_gameplay_reticle = false;
    bool tracked_cuff_overlay = false;
    bool synthetic_head_sweep = false;
    bool synthetic_body_inspection = false;
    bool synthetic_neck_pivot_path = false;
    bool synthetic_roomscale_path = false;
    bool synthetic_crouch_path = false;
    bool synthetic_billboard_sweep = false;
    float projection_translation_scale = 1.0F;
    std::wstring menu_input_title = L"Warhammer 40,000: Darktide";
    std::optional<std::wstring> capture_window_title;
    bool capture_window_deferred = false;
    bool capture_window_always = false;
    std::uint32_t xr_frames{};
    std::optional<std::chrono::seconds> xr_duration;
    std::optional<std::wstring> stop_file;
    std::optional<UINT> resize_at;
    for (int index = 1; index < argc; ++index) {
      const std::wstring argument = argv[index];
      if (argument == L"--help" || argument == L"-h") {
        usage();
        return 0;
      }
      if (argument == L"--show") {
        show = true;
      } else if (argument == L"--flush-log") {
        std::cout << std::unitbuf;
        std::wcout << std::unitbuf;
      } else if (argument == L"--stop-file" && index + 1 < argc) {
        stop_file = argv[++index];
      } else if (argument == L"--debug-layer") {
        debug_layer = true;
      } else if (argument == L"--runtime-d3d11-diagnostics") {
        runtime_d3d11_diagnostics = true;
      } else if (argument == L"--probe-shared-import-adapters") {
        probe_shared_import_adapters = true;
        runtime_d3d11_diagnostics = true;
      } else if (argument == L"--no-openxr") {
        no_openxr = true;
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
      } else if (argument == L"--capture-window-deferred") {
        capture_window_deferred = true;
      } else if (argument == L"--capture-window-policy" && index + 1 < argc) {
        const std::wstring policy = argv[++index];
        if (policy == L"always") {
          capture_window_always = true;
        } else if (policy == L"on_demand") {
          capture_window_always = false;
        } else {
          throw std::invalid_argument(
              "--capture-window-policy accepts on_demand or always");
        }
      } else if (argument == L"--enable-menu-input") {
        enable_menu_input = true;
      } else if (argument == L"--enable-menu-test-controls") {
        enable_menu_test_controls = true;
      } else if (argument == L"--menu-aim-stabilization") {
        menu_aim_stabilization = true;
      } else if (argument == L"--synthetic-controller-path") {
        synthetic_controller_path = true;
      } else if (argument == L"--synthetic-body-path") {
        synthetic_body_path = true;
      } else if (argument == L"--synthetic-gameplay-input") {
        synthetic_gameplay_input = true;
      } else if (argument == L"--synthetic-weapon-aim-matrix") {
        synthetic_weapon_aim_matrix = true;
      } else if (argument == L"--synthetic-movement-reference-path") {
        synthetic_movement_reference_path = true;
      } else if (argument == L"--synthetic-holster-once") {
        synthetic_holster_once = true;
      } else if (argument == L"--enable-gameplay-reticle") {
        enable_gameplay_reticle = true;
      } else if (argument == L"--tracked-cuff-overlay") {
        tracked_cuff_overlay = true;
      } else if (argument == L"--synthetic-head-sweep") {
        synthetic_head_sweep = true;
      } else if (argument == L"--synthetic-body-inspection") {
        synthetic_body_inspection = true;
      } else if (argument == L"--synthetic-neck-pivot-path") {
        synthetic_neck_pivot_path = true;
      } else if (argument == L"--synthetic-roomscale-path") {
        synthetic_roomscale_path = true;
      } else if (argument == L"--synthetic-crouch-path") {
        synthetic_crouch_path = true;
      } else if (argument == L"--synthetic-billboard-sweep") {
        require_openxr = true;
        synthetic_billboard_sweep = true;
      } else if (argument == L"--projection-translation-scale" &&
                 index + 1 < argc) {
        projection_translation_scale = std::stof(argv[++index]);
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
    if (stop_file && (!shared_eyes || stop_file->empty())) {
      throw std::invalid_argument("--stop-file requires shared eyes and a nonempty path");
    }
    if (no_openxr && (require_openxr || xr_frames > 0 || xr_duration ||
                      synthetic_billboard_sweep || runtime_d3d11_diagnostics)) {
      throw std::invalid_argument("--no-openxr cannot be combined with XR requests");
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
    if (enable_menu_test_controls && !shared_eyes) {
      throw std::invalid_argument(
          "--enable-menu-test-controls requires --shared-eyes");
    }
    if (menu_aim_stabilization && !shared_eyes) {
      throw std::invalid_argument(
          "--menu-aim-stabilization requires --shared-eyes");
    }
    if (!std::isfinite(projection_translation_scale) ||
        projection_translation_scale < -2.0F ||
        projection_translation_scale > 2.0F) {
      throw std::invalid_argument(
          "--projection-translation-scale must be finite and between -2 and 2");
    }
    if (synthetic_controller_path && !shared_eyes) {
      throw std::invalid_argument(
          "--synthetic-controller-path requires --shared-eyes");
    }
    if (synthetic_gameplay_input && !synthetic_controller_path) {
      throw std::invalid_argument(
          "--synthetic-gameplay-input requires --synthetic-controller-path");
    }
    if (synthetic_weapon_aim_matrix && !synthetic_gameplay_input) {
      throw std::invalid_argument(
          "--synthetic-weapon-aim-matrix requires --synthetic-gameplay-input");
    }
    if (synthetic_holster_once && (!synthetic_gameplay_input || !synthetic_body_path)) {
      throw std::invalid_argument(
          "--synthetic-holster-once requires --synthetic-gameplay-input and --synthetic-body-path");
    }
    if (synthetic_movement_reference_path && !synthetic_gameplay_input) {
      throw std::invalid_argument(
          "--synthetic-movement-reference-path requires --synthetic-gameplay-input");
    }
    if (synthetic_body_path && !synthetic_controller_path) {
      throw std::invalid_argument(
          "--synthetic-body-path requires --synthetic-controller-path");
    }
    if (synthetic_head_sweep && !shared_eyes) {
      throw std::invalid_argument(
          "--synthetic-head-sweep requires --shared-eyes");
    }
    if (synthetic_body_inspection && !shared_eyes) {
      throw std::invalid_argument(
          "--synthetic-body-inspection requires --shared-eyes");
    }
    if (enable_gameplay_reticle && !shared_eyes) {
      throw std::invalid_argument(
          "--enable-gameplay-reticle requires --shared-eyes");
    }
    if (tracked_cuff_overlay && !shared_eyes) {
      throw std::invalid_argument(
          "--tracked-cuff-overlay requires --shared-eyes");
    }
    if (synthetic_neck_pivot_path && !shared_eyes) {
      throw std::invalid_argument(
          "--synthetic-neck-pivot-path requires --shared-eyes");
    }
    if (synthetic_neck_pivot_path &&
        (synthetic_head_sweep || synthetic_body_inspection)) {
      throw std::invalid_argument(
          "Synthetic orientation diagnostics are mutually exclusive");
    }
    if (synthetic_head_sweep && synthetic_body_inspection) {
      throw std::invalid_argument(
          "--synthetic-head-sweep and --synthetic-body-inspection are exclusive");
    }
    if (synthetic_roomscale_path && !shared_eyes) {
      throw std::invalid_argument(
          "--synthetic-roomscale-path requires --shared-eyes");
    }
    if (synthetic_crouch_path && !shared_eyes) {
      throw std::invalid_argument(
          "--synthetic-crouch-path requires --shared-eyes");
    }
    if (synthetic_crouch_path && synthetic_roomscale_path) {
      throw std::invalid_argument(
          "--synthetic-crouch-path and --synthetic-roomscale-path are exclusive");
    }
    if (synthetic_billboard_sweep && theatre) {
      throw std::invalid_argument(
          "--synthetic-billboard-sweep uses the standalone synthetic scene");
    }
    if (xr_duration && xr_duration->count() == 0) {
      throw std::invalid_argument("--xr-seconds must be greater than zero");
    }
    if (stereo_top_bottom && shared_eyes) {
      throw std::invalid_argument(
          "--stereo-tb cannot be combined with --shared-eyes");
    }
    if ((capture_window_deferred || capture_window_always) &&
        !capture_window_title) {
      throw std::invalid_argument(
          "--capture-window-deferred and --capture-window-policy require "
          "--capture-window-title");
    }
    pair_driven_shared = shared_eyes && pair_driven_shared;

    darktidevr::xr::RuntimeD3D11Diagnostics runtime_diagnostics(
        runtime_d3d11_diagnostics,probe_shared_import_adapters);
    OpenXrProbe openxr(!no_openxr);
    Harness harness(show, debug_layer, openxr.adapter_luid(),
                    openxr.minimum_feature_level());
    openxr.create_session(harness.device(), harness.queue(), !theatre);
    darktidevr::xr::report_runtime_d3d11_diagnostics(std::cout);
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
                                     capture_window_title,
                                     capture_window_deferred,
                                     capture_window_always, stereo_sbs,
                                     stereo_top_bottom, shared_eyes,
                                     shared_pose_sequence_offset,
                                     pair_driven_shared,
                                     true, enable_menu_input,
                                     enable_menu_test_controls,
                                     menu_aim_stabilization,
                                     menu_input_title,
                                     synthetic_controller_path,
                                     synthetic_body_path,
                                     synthetic_gameplay_input,
                                     synthetic_weapon_aim_matrix,
                                     synthetic_movement_reference_path,
                                     synthetic_holster_once,
                                     enable_gameplay_reticle,
                                     tracked_cuff_overlay,
                                     synthetic_head_sweep,
                                     synthetic_body_inspection,
                                     synthetic_neck_pivot_path,
                                     synthetic_roomscale_path,
                                     synthetic_crouch_path,
                                     projection_translation_scale, stop_file);
      } else {
        openxr.run_frame_lifecycle(xr_frames, harness.device(), harness.queue(),
                                   require_rendering,
                                   synthetic_billboard_sweep);
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
