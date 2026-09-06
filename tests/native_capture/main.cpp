#include "producer/buffer_registry.h"
#include "producer/pipeline_identity.h"
#include "producer/object_lifetime.h"
#include "../isolated_transports.h"
#include <Windows.h>
#include <d3d12.h>
#include <wrl/client.h>

#include "core/shared_controller_state.h"
#include "core/shared_menu_pointer_state.h"

#include <chrono>
#include <cmath>
#include <iostream>
#include <stdexcept>

using Microsoft::WRL::ComPtr;

int wmain(int argc, wchar_t** argv) {
  try {
    darktidevr::tests::isolate_transports();
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
    const auto read_head_pose_v2 = reinterpret_cast<int (*)(
        float*, unsigned long long*, unsigned long long*)>(
        GetProcAddress(module, "dtvr_read_head_pose_v2"));
    const auto read_controller_state = reinterpret_cast<int (*)(
        float*, unsigned int*, unsigned int*, unsigned long long*,
        unsigned long long*)>(
        GetProcAddress(module, "dtvr_read_controller_state"));
    const auto read_controller_state_v2 = reinterpret_cast<int (*)(
        float*, unsigned int*, unsigned int*, unsigned long long*,
        unsigned long long*, unsigned long long*)>(
        GetProcAddress(module, "dtvr_read_controller_state_v2"));
    const auto read_menu_pointer_state = reinterpret_cast<int (*)(
        unsigned int*, unsigned long long*, unsigned long long*)>(
        GetProcAddress(module, "dtvr_read_menu_pointer_state"));
    const auto read_menu_pointer_state_v2 = reinterpret_cast<int (*)(
        unsigned int*, unsigned long long*, unsigned long long*,
        unsigned long long*)>(
        GetProcAddress(module, "dtvr_read_menu_pointer_state_v2"));
    const auto read_gameplay_input = reinterpret_cast<int (*)(
        int, unsigned long long*, unsigned long long*, unsigned long long*,
        unsigned long long*, float*)>(
        GetProcAddress(module, "dtvr_read_gameplay_input"));
    const auto read_menu_pointer_state_v3 = reinterpret_cast<int (*)(
        unsigned int*, unsigned int, unsigned long long*, unsigned long long*,
        unsigned long long*)>(
        GetProcAddress(module, "dtvr_read_menu_pointer_state_v3"));
    const auto qpc_ticks = reinterpret_cast<unsigned long long (*)()>(
        GetProcAddress(module, "dtvr_qpc_ticks"));
    const auto qpc_frequency = reinterpret_cast<unsigned long long (*)()>(
        GetProcAddress(module, "dtvr_qpc_frequency"));
    const auto arm_options_menu_capture = reinterpret_cast<int (*)()>(
        GetProcAddress(module, "dtvr_arm_options_menu_capture"));
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
    const auto solve_two_bone_ik = reinterpret_cast<int (*)(
        const float*, unsigned int, float*, unsigned int, unsigned int*)>(
        GetProcAddress(module, "dtvr_solve_two_bone_ik"));
    if (!install || !set_diagnostic_hooks || !take_gpu_stage_profile ||
        !capture || !arm_pose ||
        !set_render_extent ||
        !lock_client_extent || !set_render_projection ||
        !tag_queue_depth || !reset_tags || !wait_eye_capture ||
        !tag_reset_count || !ready || !execute_count || !present_count ||
        !capture_stage || !enable_present_capture || !disable_present_capture ||
        !enable_marker_log || !read_head_pose || !read_head_pose_v2 ||
        !read_controller_state ||
        !read_controller_state_v2 ||
        !read_menu_pointer_state || !read_menu_pointer_state_v2 || !read_menu_pointer_state_v3 ||
        !read_gameplay_input ||
        !qpc_ticks || !qpc_frequency || !arm_options_menu_capture ||
        !set_billboard_view_basis || !set_billboard_staging_view_basis ||
        !set_billboard_direct_view_direction ||
        !billboard_resource_map_count ||
        !billboard_resource_map_match_count ||
        !billboard_resource_unmap_count || !solve_two_bone_ik) {
      throw std::runtime_error("Native capture export contract is incomplete");
    }
    if (arm_options_menu_capture() != 1) {
      throw std::runtime_error("Options menu capture arm export failed");
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
    if (read_head_pose_v2(nullptr, nullptr, nullptr) != 1) {
      throw std::runtime_error(
          "Versioned head-pose export must reject null output");
    }
    if (read_controller_state(nullptr, nullptr, nullptr, nullptr, nullptr) !=
        1) {
      throw std::runtime_error(
          "Controller-state export must reject null output");
    }
    if (read_controller_state_v2(nullptr, nullptr, nullptr, nullptr, nullptr,
                                 nullptr) != 1) {
      throw std::runtime_error(
          "Versioned controller-state export must reject null output");
    }
    darktidevr::core::SharedControllerState controller_sample{};
    controller_sample.sequence = 42;
    controller_sample.timestamp_ns = 123456789;
    for (auto& hand : controller_sample.hands) {
      hand.aim_pose.orientation.w = 1.0F;
      hand.grip_pose.orientation.w = 1.0F;
      hand.body_aim_pose.orientation.w = 1.0F;
      hand.body_grip_pose.orientation.w = 1.0F;
      hand.body_aim_tracking_flags =
          darktidevr::core::controller_orientation_valid |
          darktidevr::core::controller_position_valid;
      hand.body_grip_tracking_flags = hand.body_aim_tracking_flags;
    }
    controller_sample.hands[0].body_aim_pose.position =
        {0.1F, 0.2F, 0.3F};
    controller_sample.hands[0].thumbstick_x = 0.625F;
    controller_sample.hands[0].thumbstick_y = -0.75F;
    controller_sample.hands[0].buttons =
        darktidevr::core::controller_stick_click;
    controller_sample.hands[1].body_grip_pose.position =
        {-0.4F, 0.5F, 0.6F};
    controller_sample.hands[1].thumbstick_x = -0.875F;
    controller_sample.hands[1].thumbstick_y = 1.0F;
    controller_sample.hands[1].trigger = 0.9F;
    darktidevr::core::SharedControllerStateWriter controller_writer;
    if (!controller_writer.publish(controller_sample)) {
      throw std::runtime_error(
          "Controller-state export fixture could not be published");
    }
    float controller_values[36]{};
    unsigned int controller_tracking_flags[4]{};
    unsigned int controller_buttons[2]{};
    unsigned long long controller_sequence{};
    unsigned long long controller_timestamp_ns{};
    unsigned long long controller_transport_generation{};
    if (read_controller_state_v2(
            controller_values, controller_tracking_flags,
            controller_buttons, &controller_sequence,
            &controller_timestamp_ns, &controller_transport_generation) != 0 ||
        controller_sequence != controller_sample.sequence ||
        controller_timestamp_ns != controller_sample.timestamp_ns ||
        controller_transport_generation == 0 ||
        std::abs(controller_values[16] - 0.625F) > 0.0001F ||
        std::abs(controller_values[17] + 0.75F) > 0.0001F ||
        std::abs(controller_values[34] + 0.875F) > 0.0001F ||
        std::abs(controller_values[35] - 1.0F) > 0.0001F ||
        controller_buttons[0] != controller_sample.hands[0].buttons ||
        controller_tracking_flags[0] !=
            controller_sample.hands[0].body_aim_tracking_flags) {
      throw std::runtime_error(
          "Controller-state export changed the Lua-facing transport layout");
    }
    if (read_menu_pointer_state(nullptr, nullptr, nullptr) != 1) {
      throw std::runtime_error(
          "Menu-pointer-state export must reject null output");
    }
    darktidevr::core::SharedMenuPointerState menu_sample{};
    menu_sample.sequence = 8;
    menu_sample.timestamp_ns = 456789;
    menu_sample.active = true;
    menu_sample.source_width = menu_sample.source_height = 100;
    menu_sample.secondary_down = true;
    menu_sample.secondary_press_sequence = 23;
    darktidevr::core::SharedMenuPointerStateWriter menu_writer;
    unsigned int menu_values[14]{};
    menu_values[11] = menu_values[12] = menu_values[13] = 0xabcdefU;
    unsigned long long menu_sequence{}, menu_timestamp{}, menu_generation{};
    if (!menu_writer.publish(menu_sample) ||
        read_menu_pointer_state(menu_values, &menu_sequence, &menu_timestamp) != 0 ||
        read_menu_pointer_state_v2(menu_values, &menu_sequence, &menu_timestamp, &menu_generation) != 0 ||
        menu_values[11] != 0xabcdefU || menu_values[12] != 0xabcdefU || menu_values[13] != 0xabcdefU) {
      throw std::runtime_error("Legacy menu exports wrote beyond their eleven-value ABI");
    }
    if (read_menu_pointer_state_v3(menu_values, 12, &menu_sequence, &menu_timestamp, &menu_generation) != 1 ||
        read_menu_pointer_state_v3(menu_values, 13, &menu_sequence, &menu_timestamp, nullptr) != 1 ||
        read_menu_pointer_state_v3(nullptr, 13, &menu_sequence, &menu_timestamp, &menu_generation) != 1 ||
        menu_values[11] != 0xabcdefU) {
      throw std::runtime_error("Secondary menu export accepted invalid output capacity/pointers");
    }
    if (read_menu_pointer_state_v3(menu_values, 13, &menu_sequence, &menu_timestamp, &menu_generation) != 0 ||
        menu_values[11] != 1 || menu_values[12] != 23 || menu_values[13] != 0xabcdefU ||
        menu_sequence != 8 || menu_timestamp != 456789 || menu_generation == 0) {
      throw std::runtime_error("Secondary menu export changed the Lua-facing transport layout");
    }
    if (read_menu_pointer_state_v2(nullptr, nullptr, nullptr, nullptr) != 1) {
      throw std::runtime_error(
          "Versioned menu-pointer export must reject null output");
    }
    unsigned long long gameplay_pressed{};
    unsigned long long gameplay_held{};
    unsigned long long gameplay_released{};
    unsigned long long gameplay_sequence{};
    float gameplay_movement[2]{};
    if (read_gameplay_input(
            1, &gameplay_pressed, &gameplay_held, &gameplay_released,
            &gameplay_sequence, gameplay_movement) != 2 ||
        gameplay_pressed != 0 || gameplay_held != 0 ||
        gameplay_released != 0 || gameplay_sequence != 0 ||
        gameplay_movement[0] != 0.0F || gameplay_movement[1] != 0.0F) {
      throw std::runtime_error(
          "Stale controller transport must not drive gameplay input: pressed=" +
          std::to_string(gameplay_pressed) +
          " held=" + std::to_string(gameplay_held) +
          " released=" + std::to_string(gameplay_released) +
          " sequence=" + std::to_string(gameplay_sequence) +
          " movement=" + std::to_string(gameplay_movement[0]) + "," +
          std::to_string(gameplay_movement[1]));
    }
    controller_sample.sequence = 43;
    controller_sample.timestamp_ns = static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now().time_since_epoch())
            .count());
    controller_sample.hands[1].trigger = 1.0F;
    if (!controller_writer.publish(controller_sample) ||
        read_gameplay_input(
            1, &gameplay_pressed, &gameplay_held, &gameplay_released,
            &gameplay_sequence, gameplay_movement) != 0 ||
        gameplay_pressed != 0 || gameplay_held != 0 || gameplay_sequence != 43) {
      throw std::runtime_error(
          "Fresh reconnect inherited held gameplay input without release");
    }
    controller_sample.sequence = 44;
    controller_sample.hands[1].trigger = 0.0F;
    if (!controller_writer.publish(controller_sample) ||
        read_gameplay_input(1, &gameplay_pressed, &gameplay_held, &gameplay_released,
                            &gameplay_sequence, gameplay_movement) != 0 || gameplay_held != 0) {
      throw std::runtime_error("Released reconnect failed to rearm gameplay input");
    }
    controller_sample.sequence = 45;
    controller_sample.hands[1].trigger = 1.0F;
    if (!controller_writer.publish(controller_sample) ||
        read_gameplay_input(1, &gameplay_pressed, &gameplay_held, &gameplay_released,
                            &gameplay_sequence, gameplay_movement) != 0 ||
        (gameplay_pressed & 1ULL) == 0 || (gameplay_held & 1ULL) == 0) {
      throw std::runtime_error("Fresh press after reconnect release did not drive gameplay input");
    }
    controller_sample.sequence = 46;
    controller_sample.timestamp_ns -= 200'000'000ULL;
    if (!controller_writer.publish(controller_sample) ||
        read_gameplay_input(
            1, &gameplay_pressed, &gameplay_held, &gameplay_released,
            &gameplay_sequence, gameplay_movement) != 2 ||
        gameplay_held != 0 || (gameplay_released & 1ULL) == 0 ||
        gameplay_sequence != 0) {
      throw std::runtime_error(
          "Expired controller transport did not release gameplay input");
    }
    float ik_input[17]{0.0F, 0.0F, 1.5F, 0.45F, 0.35F, 1.25F,
                       0.25F, 0.1F, 0.8F, 0.0F, 1.0F, 0.0F,
                       0.0F, 0.0F, -1.0F, 0.36F, 0.34F};
    float ik_output[14]{};
    unsigned int ik_flags{};
    if (solve_two_bone_ik(nullptr, 17, ik_output, 14, &ik_flags) != 1 ||
        solve_two_bone_ik(ik_input, 16, ik_output, 14, &ik_flags) != 2 ||
        solve_two_bone_ik(ik_input, 17, ik_output, 14, &ik_flags) != 0 ||
        ik_flags != 0 || std::abs(ik_output[3] - ik_input[3]) > 1.0e-4F ||
        std::abs(ik_output[4] - ik_input[4]) > 1.0e-4F ||
        std::abs(ik_output[5] - ik_input[5]) > 1.0e-4F) {
      throw std::runtime_error("Native two-bone IK export contract failed");
    }
    ik_input[3] = 2.0F;
    ik_input[4] = 0.0F;
    ik_input[5] = 1.5F;
    if (solve_two_bone_ik(ik_input, 17, ik_output, 14, &ik_flags) != 0 ||
        (ik_flags & 2U) == 0U || ik_output[13] >= 0.70F) {
      throw std::runtime_error("Native two-bone IK reach clamp failed");
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
    // Private identity survives metadata refresh, but belongs only to its owner.
    ComPtr<ID3D12Fence> identity_owner;
    ComPtr<ID3D12Fence> unrelated_owner;
    if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                                  IID_PPV_ARGS(&identity_owner))) ||
        FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                                  IID_PPV_ARGS(&unrelated_owner)))) {
      throw std::runtime_error("Could not create identity fixtures");
    }
    bool expired = false;
    if (!darktidevr::producer::mark_billboard_pipeline(identity_owner.Get()) ||
        !darktidevr::producer::is_billboard_pipeline(identity_owner.Get()) ||
        darktidevr::producer::is_billboard_pipeline(unrelated_owner.Get()) ||
        !darktidevr::producer::observe_lifetime(identity_owner.Get(),
            __uuidof(ID3D12Fence), [&expired] { expired = true; })) {
      throw std::runtime_error("Object identity must be private to its owner");
    }
    identity_owner.Reset();
    if (!expired || darktidevr::producer::is_billboard_pipeline(unrelated_owner.Get())) {
      throw std::runtime_error("Object release must retire its lifetime and identity");
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
    const auto registry = std::make_shared<darktidevr::producer::BufferRegistry>();
    for (int refresh = 0; refresh < 2; ++refresh) {
      registry->track(upload_buffer.Get(), upload_buffer->GetGPUVirtualAddress(),
                      upload_buffer->GetDesc().Width, D3D12_HEAP_TYPE_UPLOAD);
      if (registry->resources.size() != 1) {
        throw std::runtime_error("Refreshing a buffer must replace its old registry record");
      }
    }
    upload_buffer.Reset();
    if (!registry->resources.empty()) {
      throw std::runtime_error("Destroyed buffers must leave no registry records");
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
