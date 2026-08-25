add_library(darktidevr-window-capture STATIC window_capture.cpp)
target_include_directories(darktidevr-window-capture PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-window-capture PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-window-capture PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-window-capture PRIVATE gdi32 user32)

add_executable(darktidevr-eye-capture eye_capture.cpp)
target_compile_options(darktidevr-eye-capture PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-eye-capture PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-eye-capture PRIVATE
  darktidevr-window-capture user32)

add_executable(darktidevr-xr-harness main.cpp synthetic_scene.cpp)
target_compile_options(darktidevr-xr-harness PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-xr-harness PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-xr-harness PRIVATE
  OpenXR::openxr_loader darktidevr_core darktidevr_bridge darktidevr-window-capture
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
