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

if(BUILD_TESTING)
  add_executable(darktidevr-capture-worker-tests capture_worker_tests.cpp)
  target_compile_options(darktidevr-capture-worker-tests PRIVATE /W4 /WX /permissive-)
  target_include_directories(darktidevr-capture-worker-tests PRIVATE "${PROJECT_SOURCE_DIR}/src/xr")
  add_test(NAME capture_worker COMMAND darktidevr-capture-worker-tests)
  set_tests_properties(capture_worker PROPERTIES TIMEOUT 10)
  add_executable(darktidevr-pair-poll-wait-tests pair_poll_wait_tests.cpp)
  target_compile_options(darktidevr-pair-poll-wait-tests PRIVATE /W4 /WX /permissive-)
  target_compile_definitions(darktidevr-pair-poll-wait-tests PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
  target_include_directories(darktidevr-pair-poll-wait-tests PRIVATE "${PROJECT_SOURCE_DIR}/src/xr")
  add_test(NAME pair_poll_wait COMMAND darktidevr-pair-poll-wait-tests)
  set_tests_properties(pair_poll_wait PROPERTIES TIMEOUT 10)
  add_executable(darktidevr-frame-stage-timing-tests frame_stage_timing_tests.cpp)
  target_compile_options(darktidevr-frame-stage-timing-tests PRIVATE /W4 /WX /permissive-)
  target_link_libraries(darktidevr-frame-stage-timing-tests PRIVATE darktidevr_core)
  add_test(NAME frame_stage_timing COMMAND darktidevr-frame-stage-timing-tests)
  add_executable(darktidevr-delivery-cadence-tests delivery_cadence_tests.cpp)
  target_compile_options(darktidevr-delivery-cadence-tests PRIVATE /W4 /WX /permissive-)
  target_link_libraries(darktidevr-delivery-cadence-tests PRIVATE darktidevr_core)
  add_test(NAME delivery_cadence COMMAND darktidevr-delivery-cadence-tests)
  add_executable(darktidevr-d3d11-shared-process-tests d3d11_shared_process_tests.cpp)
  target_compile_options(darktidevr-d3d11-shared-process-tests PRIVATE /W4 /WX /permissive-)
  target_compile_definitions(darktidevr-d3d11-shared-process-tests PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
  target_link_libraries(darktidevr-d3d11-shared-process-tests PRIVATE d3d11 dxgi dxguid)
  add_test(NAME d3d11_shared_process COMMAND darktidevr-d3d11-shared-process-tests)
  set_tests_properties(d3d11_shared_process PROPERTIES TIMEOUT 30)
  add_executable(darktidevr-runtime-d3d11-diagnostics-tests runtime_d3d11_diagnostics_tests.cpp)
  target_compile_options(darktidevr-runtime-d3d11-diagnostics-tests PRIVATE /W4 /WX /permissive-)
  target_compile_definitions(darktidevr-runtime-d3d11-diagnostics-tests PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
  target_link_libraries(darktidevr-runtime-d3d11-diagnostics-tests PRIVATE darktidevr-runtime-d3d11-diagnostics d3d11 dxguid)
  add_test(NAME runtime_d3d11_diagnostics COMMAND darktidevr-runtime-d3d11-diagnostics-tests)
  set_tests_properties(runtime_d3d11_diagnostics PROPERTIES TIMEOUT 30)
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

  add_executable(darktidevr-panel-renderer-tests panel_renderer_tests.cpp)
  target_compile_options(darktidevr-panel-renderer-tests PRIVATE
    /W4 /WX /permissive-)
  target_compile_definitions(darktidevr-panel-renderer-tests PRIVATE
    NOMINMAX WIN32_LEAN_AND_MEAN)
  target_link_libraries(darktidevr-panel-renderer-tests PRIVATE
    darktidevr-panel-renderer d3d12 dxgi)
  add_test(NAME panel_renderer COMMAND darktidevr-panel-renderer-tests)
  set_tests_properties(panel_renderer PROPERTIES
    LABELS "phase1;openxr;menu;d3d12")

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
  add_test(NAME d3d12_smoke COMMAND darktidevr-xr-harness --no-openxr --frames 3)
  set_tests_properties(d3d12_smoke PROPERTIES TIMEOUT 30)
  add_test(NAME d3d12_debug_resize
    COMMAND darktidevr-xr-harness --no-openxr --frames 8 --resize-at 4 --debug-layer)
  set_tests_properties(d3d12_debug_resize PROPERTIES TIMEOUT 30)
  set_tests_properties(d3d12_smoke d3d12_debug_resize PROPERTIES
    ENVIRONMENT "DARKTIDEVR_TEST_TRANSPORTS=1" RUN_SERIAL TRUE
    FAIL_REGULAR_EXPRESSION "openxr.active_runtime=;openxr.instance=created;openxr.session=created")
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
    set_tests_properties(xr_projection_smoke xr_theatre_smoke xr_stereo_sbs_smoke
      PROPERTIES ENVIRONMENT "DARKTIDEVR_TEST_TRANSPORTS=1" RUN_SERIAL TRUE)
  endif()
endif()
