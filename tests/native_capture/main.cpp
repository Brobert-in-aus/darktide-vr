#include <Windows.h>

#include <iostream>
#include <stdexcept>

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
    if (!install || !capture || !arm_pose || !set_render_extent ||
        !lock_client_extent || !set_render_projection ||
        !tag_queue_depth || !reset_tags || !wait_eye_capture ||
        !tag_reset_count || !ready || !execute_count || !present_count ||
        !capture_stage || !enable_present_capture || !disable_present_capture ||
        !enable_marker_log || !read_head_pose) {
      throw std::runtime_error("Native capture export contract is incomplete");
    }
    if (read_head_pose(nullptr, nullptr) != 1) {
      throw std::runtime_error("Head-pose export must reject null output");
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
    if (install() != 0 || install() != 0) {
      throw std::runtime_error("Hook installation must succeed and be idempotent");
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
