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
