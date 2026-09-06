add_executable(darktidevr-streamline-stereo-inputs-tests main.cpp)
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
