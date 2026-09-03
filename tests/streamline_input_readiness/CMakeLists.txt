add_test(
  NAME streamline_input_readiness
  COMMAND
    powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/validate-readiness.ps1"
    -Helper
    "${PROJECT_SOURCE_DIR}/tools/stereo/get-streamline-stereo-input-readiness.ps1")

set_tests_properties(streamline_input_readiness PROPERTIES LABELS "phase1;streamline")
