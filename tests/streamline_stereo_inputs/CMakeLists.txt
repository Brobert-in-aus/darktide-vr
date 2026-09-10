add_executable(darktidevr-streamline-stereo-inputs-tests main.cpp)
add_executable(darktidevr-cluster-list-benchmark
  "${PROJECT_SOURCE_DIR}/tools/renderer_probe/benchmark-cluster-list.cpp")
target_compile_options(darktidevr-cluster-list-benchmark PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-cluster-list-benchmark PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
target_link_libraries(darktidevr-cluster-list-benchmark PRIVATE d3d12 dxgi dxguid)
add_executable(darktidevr-motion-cleanup-benchmark
  "${PROJECT_SOURCE_DIR}/tools/renderer_probe/benchmark-motion-cleanup.cpp")
target_compile_options(darktidevr-motion-cleanup-benchmark PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-motion-cleanup-benchmark PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
target_link_libraries(darktidevr-motion-cleanup-benchmark PRIVATE darktidevr_core d3d12 dxgi dxguid)

add_executable(darktidevr-stereo-input-copy-benchmark
  "${PROJECT_SOURCE_DIR}/tools/renderer_probe/benchmark-stereo-input-copy.cpp")
target_compile_options(darktidevr-stereo-input-copy-benchmark PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-stereo-input-copy-benchmark PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
target_link_libraries(darktidevr-stereo-input-copy-benchmark PRIVATE darktidevr_core d3d12 dxgi dxguid)
add_executable(darktidevr-stereo-input-copy-tests input_copy.cpp)
target_compile_options(darktidevr-stereo-input-copy-tests PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-stereo-input-copy-tests PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
target_link_libraries(darktidevr-stereo-input-copy-tests PRIVATE darktidevr_core d3d12 dxgi dxguid)
add_test(NAME stereo_input_copy COMMAND darktidevr-stereo-input-copy-tests)
set_tests_properties(stereo_input_copy PROPERTIES LABELS "phase1;streamline;gpu")
target_compile_options(darktidevr-streamline-stereo-inputs-tests PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-streamline-stereo-inputs-tests PRIVATE
  darktidevr_core)

add_test(
  NAME streamline_stereo_inputs
  COMMAND darktidevr-streamline-stereo-inputs-tests)
set_tests_properties(streamline_stereo_inputs PROPERTIES
  LABELS "phase1;streamline")

add_executable(darktidevr-streamline-input-lifetime-tests lifetime.cpp)
target_compile_options(darktidevr-streamline-input-lifetime-tests PRIVATE /W4 /WX /permissive-)
target_link_libraries(darktidevr-streamline-input-lifetime-tests PRIVATE darktidevr_core)
add_test(NAME streamline_input_lifetime COMMAND darktidevr-streamline-input-lifetime-tests)
set_tests_properties(streamline_input_lifetime PROPERTIES LABELS "phase1;streamline")

add_executable(darktidevr-streamline-submission-tests submission.cpp)
target_compile_options(darktidevr-streamline-submission-tests PRIVATE /W4 /WX /permissive-)
target_link_libraries(darktidevr-streamline-submission-tests PRIVATE darktidevr_core)
add_test(NAME streamline_submission COMMAND darktidevr-streamline-submission-tests)
add_executable(darktidevr-ui-capture-blend-tests ui_capture_blend.cpp)
target_compile_options(darktidevr-ui-capture-blend-tests PRIVATE /W4 /WX /permissive-)
target_link_libraries(darktidevr-ui-capture-blend-tests PRIVATE darktidevr_core)
add_test(NAME ui_capture_blend COMMAND darktidevr-ui-capture-blend-tests)
add_executable(darktidevr-ngx-capture-window-tests ngx_capture_window.cpp)
target_link_libraries(darktidevr-ngx-capture-window-tests PRIVATE darktidevr_core)
target_compile_options(darktidevr-ngx-capture-window-tests PRIVATE /W4 /WX /permissive-)
add_test(NAME ngx_capture_window COMMAND darktidevr-ngx-capture-window-tests)
add_executable(darktidevr-ngx-command-observation-tests ngx_command_observations.cpp)
target_link_libraries(darktidevr-ngx-command-observation-tests PRIVATE darktidevr_core)
target_compile_options(darktidevr-ngx-command-observation-tests PRIVATE /W4 /WX /permissive-)
add_test(NAME ngx_command_observations COMMAND darktidevr-ngx-command-observation-tests)
add_executable(darktidevr-ngx-feature-registry-tests ngx_feature_registry.cpp)
target_link_libraries(darktidevr-ngx-feature-registry-tests PRIVATE darktidevr_core)
target_compile_options(darktidevr-ngx-feature-registry-tests PRIVATE /W4 /WX /permissive-)
add_test(NAME ngx_feature_registry COMMAND darktidevr-ngx-feature-registry-tests)
add_executable(darktidevr-ngx-sr-observation-tests ngx_sr_observation.cpp)
target_link_libraries(darktidevr-ngx-sr-observation-tests PRIVATE darktidevr_core)
target_compile_options(darktidevr-ngx-sr-observation-tests PRIVATE /W4 /WX /permissive-)
add_test(NAME ngx_sr_observation COMMAND darktidevr-ngx-sr-observation-tests)
set_tests_properties(streamline_submission PROPERTIES LABELS "phase1;streamline")

add_executable(darktidevr-stereo-color-resample-tests resample.cpp)
target_compile_options(darktidevr-stereo-color-resample-tests PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-stereo-color-resample-tests PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
target_link_libraries(darktidevr-stereo-color-resample-tests PRIVATE darktidevr_core d3d12 dxgi dxguid d3dcompiler)
add_test(NAME stereo_color_resample COMMAND darktidevr-stereo-color-resample-tests)
set_tests_properties(stereo_color_resample PROPERTIES LABELS "phase1;streamline;gpu")

set(DARKTIDEVR_STREAMLINE_REFERENCE_INCLUDE_DIR "" CACHE PATH
  "Optional official Streamline v2.7.30 include directory for ABI validation")
if(DARKTIDEVR_STREAMLINE_REFERENCE_INCLUDE_DIR)
  add_executable(darktidevr-streamline-abi-reference abi_reference.cpp)
  target_include_directories(darktidevr-streamline-abi-reference PRIVATE
    "${PROJECT_SOURCE_DIR}/src")
  target_include_directories(darktidevr-streamline-abi-reference SYSTEM PRIVATE
    "${DARKTIDEVR_STREAMLINE_REFERENCE_INCLUDE_DIR}")
  target_compile_options(darktidevr-streamline-abi-reference PRIVATE /W4 /WX /permissive-)
  add_test(NAME streamline_abi_reference COMMAND darktidevr-streamline-abi-reference)
  set_tests_properties(streamline_abi_reference PROPERTIES LABELS "phase1;streamline")
endif()

set(DARKTIDEVR_NGX_REFERENCE_INCLUDE_DIR "" CACHE PATH
  "Optional NGX headers from Streamline v2.7.30 for Windows x64 ABI validation")
if(DARKTIDEVR_NGX_REFERENCE_INCLUDE_DIR)
  file(SHA256 "${DARKTIDEVR_NGX_REFERENCE_INCLUDE_DIR}/nvsdk_ngx_params.h" ngx_params_hash)
  file(SHA256 "${DARKTIDEVR_NGX_REFERENCE_INCLUDE_DIR}/nvsdk_ngx_defs.h" ngx_defs_hash)
  if(NOT ngx_params_hash STREQUAL "dd9ef57ac264256ddd63b3c75b2894f519c72a1a9c9c23814fb433aa71478ada" OR
     NOT ngx_defs_hash STREQUAL "0444c2ec3f07e6dfe6762657c072314419a6c9a4e670f6885d62b8713654e958")
    message(FATAL_ERROR "NGX ABI reference requires unmodified Streamline v2.7.30 params/defs headers")
  endif()
  add_executable(darktidevr-ngx-abi-reference ngx_abi_reference.cpp)
  target_include_directories(darktidevr-ngx-abi-reference PRIVATE "${PROJECT_SOURCE_DIR}/src")
  target_include_directories(darktidevr-ngx-abi-reference SYSTEM PRIVATE
    "${DARKTIDEVR_NGX_REFERENCE_INCLUDE_DIR}")
  target_compile_options(darktidevr-ngx-abi-reference PRIVATE /W4 /WX /permissive-)
  add_test(NAME ngx_abi_reference COMMAND darktidevr-ngx-abi-reference)
  set_tests_properties(ngx_abi_reference PROPERTIES LABELS "phase1;streamline")
endif()

add_executable(darktidevr-bounded-diagnostic-tests bounded_diagnostic.cpp)
target_link_libraries(darktidevr-bounded-diagnostic-tests PRIVATE darktidevr_core)
target_compile_options(darktidevr-bounded-diagnostic-tests PRIVATE /W4 /WX /permissive-)
add_test(NAME bounded_diagnostic COMMAND darktidevr-bounded-diagnostic-tests)

add_executable(darktidevr-present-cpu-profile-tests present_cpu_profile.cpp)
target_link_libraries(darktidevr-present-cpu-profile-tests PRIVATE darktidevr_core)
target_compile_options(darktidevr-present-cpu-profile-tests PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-present-cpu-profile-tests PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
add_test(NAME present_cpu_profile_off COMMAND darktidevr-present-cpu-profile-tests)
add_test(NAME present_cpu_profile_on COMMAND darktidevr-present-cpu-profile-tests enabled)
set_tests_properties(present_cpu_profile_off present_cpu_profile_on PROPERTIES RUN_SERIAL TRUE)

add_executable(darktidevr-resource-name-match-tests resource_name_match.cpp)
target_link_libraries(darktidevr-resource-name-match-tests PRIVATE darktidevr_core d3d12 dxgi dxguid)
target_compile_options(darktidevr-resource-name-match-tests PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-resource-name-match-tests PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
add_test(NAME resource_name_match COMMAND darktidevr-resource-name-match-tests)

add_executable(darktidevr-command-recording-snapshot-tests command_recording_snapshot.cpp)
target_link_libraries(darktidevr-command-recording-snapshot-tests PRIVATE darktidevr_core)
target_compile_options(darktidevr-command-recording-snapshot-tests PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-command-recording-snapshot-tests PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
add_test(NAME command_recording_snapshot COMMAND darktidevr-command-recording-snapshot-tests)

add_executable(darktidevr-buffer-address-lookup-tests buffer_address_lookup.cpp)
target_link_libraries(darktidevr-buffer-address-lookup-tests PRIVATE darktidevr_core d3d12 dxgi dxguid)
target_compile_options(darktidevr-buffer-address-lookup-tests PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-buffer-address-lookup-tests PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
add_test(NAME buffer_address_lookup COMMAND darktidevr-buffer-address-lookup-tests)
