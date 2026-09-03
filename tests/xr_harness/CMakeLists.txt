add_library(darktidevr-window-capture STATIC window_capture.cpp)
target_include_directories(darktidevr-window-capture PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-window-capture PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-window-capture PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-window-capture PRIVATE gdi32 user32)

add_library(darktidevr-menu-input STATIC menu_input_injector.cpp)
target_include_directories(darktidevr-menu-input PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-menu-input PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-menu-input PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-menu-input PUBLIC darktidevr_core user32)

add_library(darktidevr-synthetic-controller STATIC
  synthetic_controller_path.cpp)
target_include_directories(darktidevr-synthetic-controller PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-synthetic-controller PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-synthetic-controller PUBLIC darktidevr_core)

add_library(darktidevr-synthetic-head STATIC synthetic_head_path.cpp)
target_include_directories(darktidevr-synthetic-head PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-synthetic-head PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-synthetic-head PUBLIC darktidevr_core)

add_library(darktidevr-tracked-cuff STATIC tracked_cuff_mesh.cpp)
target_include_directories(darktidevr-tracked-cuff PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-tracked-cuff PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-tracked-cuff PUBLIC darktidevr_core)

add_library(darktidevr-tracked-cuff-renderer STATIC tracked_cuff_renderer.cpp)
target_include_directories(darktidevr-tracked-cuff-renderer PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-tracked-cuff-renderer PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-tracked-cuff-renderer PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN)
target_link_libraries(darktidevr-tracked-cuff-renderer PUBLIC
  OpenXR::openxr_loader darktidevr-tracked-cuff darktidevr_core
  d3d12 d3dcompiler dxgi)

add_executable(darktidevr-eye-capture eye_capture.cpp)
target_compile_options(darktidevr-eye-capture PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-eye-capture PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-eye-capture PRIVATE
  darktidevr-window-capture user32)

add_executable(darktidevr-shared-eye-capture shared_eye_capture.cpp)
target_compile_options(darktidevr-shared-eye-capture PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-shared-eye-capture PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-shared-eye-capture PRIVATE
  darktidevr_bridge d3d12 dxgi)

add_executable(darktidevr-synthetic-controller-publisher
  synthetic_controller_publisher.cpp)
target_compile_options(darktidevr-synthetic-controller-publisher PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-synthetic-controller-publisher PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-synthetic-controller-publisher PRIVATE
  darktidevr-synthetic-controller darktidevr_core)

add_executable(darktidevr-synthetic-head-publisher
  synthetic_head_publisher.cpp)
target_compile_options(darktidevr-synthetic-head-publisher PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-synthetic-head-publisher PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-synthetic-head-publisher PRIVATE
  darktidevr_core)

add_executable(darktidevr-xr-harness main.cpp synthetic_scene.cpp)
target_compile_options(darktidevr-xr-harness PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-xr-harness PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-xr-harness PRIVATE
  OpenXR::openxr_loader darktidevr_core darktidevr_bridge darktidevr-window-capture
  darktidevr-menu-input darktidevr-synthetic-controller
  darktidevr-synthetic-head darktidevr-tracked-cuff-renderer
  d3d12 d3dcompiler dxgi dxguid)

add_custom_command(TARGET darktidevr-xr-harness POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "$<TARGET_FILE:openxr_loader>"
    "$<TARGET_FILE_DIR:darktidevr-xr-harness>"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${openxrsdk_SOURCE_DIR}/LICENSE"
    "$<TARGET_FILE_DIR:darktidevr-xr-harness>/OPENXR-LICENSE.txt"
  COMMENT "Copying the pinned Khronos OpenXR loader beside the harness"
)

if(BUILD_TESTING)
  add_executable(darktidevr-synthetic-controller-tests
    synthetic_controller_path_tests.cpp)
  target_compile_options(darktidevr-synthetic-controller-tests PRIVATE
    /W4 /WX /permissive-)
  target_link_libraries(darktidevr-synthetic-controller-tests PRIVATE
    darktidevr-synthetic-controller)
  add_test(NAME synthetic_controller_path
    COMMAND darktidevr-synthetic-controller-tests)
  set_tests_properties(synthetic_controller_path PROPERTIES
    LABELS "phase1;input;pointer")

  add_executable(darktidevr-synthetic-head-tests
    synthetic_head_path_tests.cpp)
  target_compile_options(darktidevr-synthetic-head-tests PRIVATE
    /W4 /WX /permissive-)
  target_link_libraries(darktidevr-synthetic-head-tests PRIVATE
    darktidevr-synthetic-head)
  add_test(NAME synthetic_head_path COMMAND darktidevr-synthetic-head-tests)
  set_tests_properties(synthetic_head_path PROPERTIES
    LABELS "phase1;headset;billboard")

  add_executable(darktidevr-menu-input-tests menu_input_injector_tests.cpp)
  target_compile_options(darktidevr-menu-input-tests PRIVATE
    /W4 /WX /permissive-)
  target_compile_definitions(darktidevr-menu-input-tests PRIVATE
    NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
  target_link_libraries(darktidevr-menu-input-tests PRIVATE
    darktidevr-menu-input)
  add_test(NAME menu_input_injector COMMAND darktidevr-menu-input-tests)
  set_tests_properties(menu_input_injector PROPERTIES
    LABELS "phase1;input;pointer")

  add_executable(darktidevr-tracked-cuff-tests tracked_cuff_mesh_tests.cpp)
  target_compile_options(darktidevr-tracked-cuff-tests PRIVATE
    /W4 /WX /permissive-)
  target_link_libraries(darktidevr-tracked-cuff-tests PRIVATE
    darktidevr-tracked-cuff)
  add_test(NAME tracked_cuff_mesh COMMAND darktidevr-tracked-cuff-tests)
  set_tests_properties(tracked_cuff_mesh PROPERTIES
    LABELS "phase1;openxr;hands")

  add_executable(darktidevr-tracked-cuff-renderer-tests
    tracked_cuff_renderer_tests.cpp)
  target_compile_options(darktidevr-tracked-cuff-renderer-tests PRIVATE
    /W4 /WX /permissive-)
  target_compile_definitions(darktidevr-tracked-cuff-renderer-tests PRIVATE
    NOMINMAX WIN32_LEAN_AND_MEAN)
  target_link_libraries(darktidevr-tracked-cuff-renderer-tests PRIVATE
    darktidevr-tracked-cuff-renderer d3d12 dxgi)
  add_test(NAME tracked_cuff_renderer
    COMMAND darktidevr-tracked-cuff-renderer-tests)
  set_tests_properties(tracked_cuff_renderer PROPERTIES
    LABELS "phase1;openxr;hands;d3d12")

  add_executable(darktidevr-window-capture-tests window_capture_tests.cpp)
  target_compile_options(darktidevr-window-capture-tests PRIVATE
    /W4 /WX /permissive-)
  target_compile_definitions(darktidevr-window-capture-tests PRIVATE
    NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
  target_link_libraries(darktidevr-window-capture-tests PRIVATE
    darktidevr-window-capture user32)
  add_test(NAME window_capture_recovery
    COMMAND darktidevr-window-capture-tests)
  set_tests_properties(window_capture_recovery PROPERTIES
    LABELS "phase1;capture")

  add_test(NAME xr_harness_help COMMAND darktidevr-xr-harness --help)
  add_test(NAME shared_eye_capture_help
    COMMAND darktidevr-shared-eye-capture --help)
  add_test(NAME synthetic_controller_publisher_help
    COMMAND darktidevr-synthetic-controller-publisher --help)
  add_test(NAME d3d12_smoke COMMAND darktidevr-xr-harness --frames 3)
  set_tests_properties(d3d12_smoke PROPERTIES TIMEOUT 30)
  add_test(NAME d3d12_debug_resize
    COMMAND darktidevr-xr-harness --frames 8 --resize-at 4 --debug-layer)
  set_tests_properties(d3d12_debug_resize PROPERTIES TIMEOUT 30)
  if(DARKTIDEVR_ENABLE_HEADSET_TESTS)
    add_test(NAME xr_projection_smoke
      COMMAND darktidevr-xr-harness --frames 30 --debug-layer
        --require-rendering --xr-frames 300)
    set_tests_properties(xr_projection_smoke PROPERTIES
      TIMEOUT 30
      LABELS "headset;openxr;d3d12")
    add_test(NAME xr_theatre_smoke
      COMMAND darktidevr-xr-harness --frames 30 --debug-layer
        --require-rendering --xr-frames 300 --theatre)
    set_tests_properties(xr_theatre_smoke PROPERTIES
      TIMEOUT 30
      LABELS "headset;openxr;d3d12;phase1;theatre")
    add_test(NAME xr_stereo_sbs_smoke
      COMMAND darktidevr-xr-harness --frames 30 --debug-layer
        --require-rendering --xr-frames 300 --stereo-sbs)
    set_tests_properties(xr_stereo_sbs_smoke PROPERTIES
      TIMEOUT 30
      LABELS "headset;openxr;d3d12;phase1;stereo")
  endif()
endif()
