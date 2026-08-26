#include <Windows.h>
#include <d3d12.h>
#include <wrl/client.h>

#include <chrono>
#include <cmath>
#include <iostream>
#include <stdexcept>

using Microsoft::WRL::ComPtr;

int wmain(int argc, wchar_t** argv) {
  try {
    if (argc != 2) {
      throw std::invalid_argument("Expected native capture DLL path");
    }
    const auto module = LoadLibraryW(argv[1]);
    if (!module) {
      throw std::runtime_error("LoadLibraryW failed");
    }
    const auto install = reinterpret_cast<int (*)()>(
        GetProcAddress(module, "dtvr_install"));
    const auto set_diagnostic_hooks = reinterpret_cast<int (*)(int)>(
        GetProcAddress(module, "dtvr_set_diagnostic_render_hooks"));
    const auto take_gpu_stage_profile = reinterpret_cast<int (*)(
        int, unsigned long long*)>(
        GetProcAddress(module, "dtvr_take_gpu_stage_profile"));
    const auto capture = reinterpret_cast<int (*)(int)>(
        GetProcAddress(module, "dtvr_capture_eye"));
    const auto arm_pose = reinterpret_cast<int (*)(int, unsigned long long)>(
        GetProcAddress(module, "dtvr_arm_eye_capture_pose"));
    const auto set_render_extent =
        reinterpret_cast<int (*)(unsigned long long, unsigned int)>(
            GetProcAddress(module, "dtvr_set_swapchain_render_extent"));
    const auto lock_client_extent = reinterpret_cast<int (*)(int)>(
        GetProcAddress(module, "dtvr_lock_swapchain_client_extent"));
    const auto set_render_projection = reinterpret_cast<int (*)(float, float)>(
        GetProcAddress(module, "dtvr_set_render_projection"));
    const auto tag_queue_depth = reinterpret_cast<unsigned long long (*)()>(
        GetProcAddress(module, "dtvr_boundary_tag_queue_depth"));
    const auto tag_reset_count = reinterpret_cast<unsigned long long (*)()>(
        GetProcAddress(module, "dtvr_boundary_tag_reset_count"));
    const auto reset_tags = reinterpret_cast<int (*)()>(
        GetProcAddress(module, "dtvr_reset_eye_capture_tags"));
    const auto wait_eye_capture =
        reinterpret_cast<int (*)(int, unsigned long long, unsigned int)>(
            GetProcAddress(module, "dtvr_wait_eye_capture_count"));
    const auto ready = reinterpret_cast<unsigned long long (*)()>(
        GetProcAddress(module, "dtvr_ready_value"));
    const auto execute_count = reinterpret_cast<unsigned long long (*)()>(
        GetProcAddress(module, "dtvr_execute_call_count"));
    const auto present_count = reinterpret_cast<unsigned long long (*)()>(
        GetProcAddress(module, "dtvr_present_count"));
    const auto capture_stage = reinterpret_cast<int (*)()>(
        GetProcAddress(module, "dtvr_capture_stage"));
    const auto enable_present_capture = reinterpret_cast<int (*)()>(
        GetProcAddress(module, "dtvr_enable_present_capture"));
    const auto disable_present_capture = reinterpret_cast<int (*)()>(
        GetProcAddress(module, "dtvr_disable_present_capture"));
    const auto enable_marker_log =
        reinterpret_cast<int (*)()>(GetProcAddress(module,
                                                   "dtvr_enable_marker_log"));
    const auto read_head_pose = reinterpret_cast<int (*)(
        float*, unsigned long long*)>(
        GetProcAddress(module, "dtvr_read_head_pose"));
    const auto read_controller_state = reinterpret_cast<int (*)(
        float*, unsigned int*, unsigned int*, unsigned long long*,
        unsigned long long*)>(
        GetProcAddress(module, "dtvr_read_controller_state"));
    const auto qpc_ticks = reinterpret_cast<unsigned long long (*)()>(
        GetProcAddress(module, "dtvr_qpc_ticks"));
    const auto qpc_frequency = reinterpret_cast<unsigned long long (*)()>(
        GetProcAddress(module, "dtvr_qpc_frequency"));
    const auto set_billboard_view_basis = reinterpret_cast<int (*)(
        float, float, float, float, float, float, int)>(
        GetProcAddress(module, "dtvr_set_billboard_view_basis"));
    const auto set_billboard_staging_view_basis = reinterpret_cast<int (*)(
        float, float, float, float, float, float, int)>(
        GetProcAddress(module, "dtvr_set_billboard_staging_view_basis"));
    const auto set_billboard_direct_view_direction =
        reinterpret_cast<int (*)(float, float, int)>(GetProcAddress(
            module, "dtvr_set_billboard_direct_view_direction"));
    const auto billboard_resource_map_count =
        reinterpret_cast<unsigned long long (*)()>(GetProcAddress(
            module, "dtvr_billboard_resource_map_count"));
    const auto billboard_resource_map_match_count =
        reinterpret_cast<unsigned long long (*)()>(GetProcAddress(
            module, "dtvr_billboard_resource_map_match_count"));
    const auto billboard_resource_unmap_count =
        reinterpret_cast<unsigned long long (*)()>(GetProcAddress(
            module, "dtvr_billboard_resource_unmap_count"));
    if (!install || !set_diagnostic_hooks || !take_gpu_stage_profile ||
        !capture || !arm_pose ||
        !set_render_extent ||
        !lock_client_extent || !set_render_projection ||
        !tag_queue_depth || !reset_tags || !wait_eye_capture ||
        !tag_reset_count || !ready || !execute_count || !present_count ||
        !capture_stage || !enable_present_capture || !disable_present_capture ||
        !enable_marker_log || !read_head_pose || !read_controller_state ||
        !qpc_ticks || !qpc_frequency ||
        !set_billboard_view_basis || !set_billboard_staging_view_basis ||
        !set_billboard_direct_view_direction ||
        !billboard_resource_map_count ||
        !billboard_resource_map_match_count ||
        !billboard_resource_unmap_count) {
      throw std::runtime_error("Native capture export contract is incomplete");
    }
    const auto steady_ns = static_cast<double>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now().time_since_epoch())
            .count());
    const auto frequency = qpc_frequency();
    const auto qpc_ns = static_cast<double>(qpc_ticks()) * 1'000'000'000.0 /
                        static_cast<double>(frequency);
    if (frequency == 0 || std::abs(steady_ns - qpc_ns) > 50'000'000.0) {
      throw std::runtime_error(
          "Controller timestamp and native QPC clocks do not share an epoch");
    }
    if (set_billboard_view_basis(1.0F, 0.0F, 0.0F, 0.0F, 0.0F,
                                 1.0F, -1) != 1 ||
        set_billboard_view_basis(1.0F, 0.0F, 0.0F, 0.0F, 0.0F,
                                 1.0F, 1) != 2) {
      throw std::runtime_error(
          "Retired billboard descriptor writes must remain fail-closed");
    }
    if (set_billboard_staging_view_basis(1.0F, 0.0F, 0.0F, 0.0F,
                                         0.0F, 1.0F, 1) != 4 ||
        set_billboard_direct_view_direction(1.0F, 0.0F, 1) != 3) {
      throw std::runtime_error(
          "Billboard writes must fail closed before diagnostic selection");
    }
    if (read_head_pose(nullptr, nullptr) != 1) {
      throw std::runtime_error("Head-pose export must reject null output");
    }
    if (read_controller_state(nullptr, nullptr, nullptr, nullptr, nullptr) !=
        1) {
      throw std::runtime_error(
          "Controller-state export must reject null output");
    }
    if (arm_pose(-1, 1) != 60) {
      throw std::runtime_error("Pose-tagged capture must reject invalid eyes");
    }
    if (set_render_extent(639, 2160) != 1 ||
        set_render_extent(1920, 2160) != 0 ||
        set_render_extent(0, 0) != 0) {
      throw std::runtime_error("Swapchain render-extent override contract failed");
    }
    if (lock_client_extent(0) != 0) {
      throw std::runtime_error("Swapchain client-extent lock contract failed");
    }
    if (set_render_projection(0.0F, 1.0F) != 1 ||
        set_render_projection(1.6F, 0.8888889F) != 0) {
      throw std::runtime_error("Render projection contract failed");
    }
    for (unsigned long long sequence = 1; sequence <= 9; ++sequence) {
      if (arm_pose(0, sequence) != 0) {
        throw std::runtime_error("A stale eye-tag queue must recover silently");
      }
    }
    if (tag_queue_depth() > 8 || tag_reset_count() == 0) {
      throw std::runtime_error("Eye-tag queue did not perform bounded recovery");
    }
    if (wait_eye_capture(-1, 0, 0) != 70 ||
        wait_eye_capture(0, 0, 0) != 0 || reset_tags() != 0 ||
        tag_queue_depth() != 0) {
      throw std::runtime_error("Synchronized eye wait/reset contract failed");
    }
    if (set_diagnostic_hooks(1) != 0 ||
        set_billboard_direct_view_direction(0.0F, 0.0F, 1) != 2 ||
        set_billboard_direct_view_direction(3.0F, 4.0F, 1) != 0 ||
        set_billboard_direct_view_direction(0.0F, 0.0F, 0) != 0 ||
        install() != 0 || install() != 0) {
      throw std::runtime_error("Hook installation must succeed and be idempotent");
    }
    if (set_diagnostic_hooks(0) != 1) {
      throw std::runtime_error(
          "Diagnostic hook selection must be immutable after installation");
    }
    ComPtr<ID3D12Device> device;
    if (FAILED(D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_12_0,
                                 IID_PPV_ARGS(&device)))) {
      throw std::runtime_error("Failed to create the map-tracking test device");
    }
    D3D12_HEAP_PROPERTIES upload_properties{};
    upload_properties.Type = D3D12_HEAP_TYPE_UPLOAD;
    D3D12_RESOURCE_DESC buffer_description{};
    buffer_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    buffer_description.Width = 256;
    buffer_description.Height = 1;
    buffer_description.DepthOrArraySize = 1;
    buffer_description.MipLevels = 1;
    buffer_description.SampleDesc.Count = 1;
    buffer_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    ComPtr<ID3D12Resource> upload_buffer;
    if (FAILED(device->CreateCommittedResource(
            &upload_properties, D3D12_HEAP_FLAG_NONE, &buffer_description,
            D3D12_RESOURCE_STATE_GENERIC_READ, nullptr,
            IID_PPV_ARGS(&upload_buffer)))) {
      throw std::runtime_error("Failed to create the map-tracking test buffer");
    }
    const auto maps_before = billboard_resource_map_count();
    const auto matches_before = billboard_resource_map_match_count();
    const auto unmaps_before = billboard_resource_unmap_count();
    void* mapped{};
    const D3D12_RANGE no_cpu_reads{0, 0};
    if (FAILED(upload_buffer->Map(0, &no_cpu_reads, &mapped)) || !mapped) {
      throw std::runtime_error("Failed to map the map-tracking test buffer");
    }
    const D3D12_RANGE no_cpu_writes{0, 0};
    upload_buffer->Unmap(0, &no_cpu_writes);
    if (billboard_resource_map_count() != maps_before + 1 ||
        billboard_resource_map_match_count() != matches_before + 1 ||
        billboard_resource_unmap_count() != unmaps_before + 1) {
      throw std::runtime_error("Mapped upload tracking did not observe Map/Unmap");
    }
    unsigned long long stage_values[6]{};
    if (take_gpu_stage_profile(-1, stage_values) != 1 ||
        take_gpu_stage_profile(0, nullptr) != 1) {
      throw std::runtime_error("GPU stage profile argument validation failed");
    }
    if (enable_marker_log() != 0 || enable_marker_log() != 0) {
      throw std::runtime_error("Marker logging must enable idempotently");
    }
    if (enable_present_capture() != 0 || enable_present_capture() != 0) {
      throw std::runtime_error("Present capture must enable idempotently");
    }
    if (disable_present_capture() != 0 || disable_present_capture() != 0) {
      throw std::runtime_error("Present capture must disable idempotently");
    }
    if (capture(-1) != 30 || capture(2) != 30) {
      throw std::runtime_error("Invalid eye indices must be rejected");
    }
    if (capture(0) != 31 || capture_stage() != 1 || ready() != 0 || execute_count() != 0 ||
        present_count() != 0) {
      throw std::runtime_error(
          "Capture without an observed game queue/swapchain must remain inert");
    }
    std::cout << "native_capture.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "native_capture: " << error.what() << '\n';
    return 1;
  }
}
