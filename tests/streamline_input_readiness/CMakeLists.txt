add_test(
  NAME streamline_input_readiness
  COMMAND
    powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/validate-readiness.ps1"
    -Helper
    "${PROJECT_SOURCE_DIR}/tools/stereo/get-streamline-stereo-input-readiness.ps1")

set_tests_properties(streamline_input_readiness PROPERTIES LABELS "phase1;streamline")

add_test(NAME ngx_output_observation
  COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/validate-ngx-observation.ps1"
    -Reader "${PROJECT_SOURCE_DIR}/tools/stereo/read-ngx-output-probe.ps1")
set_tests_properties(ngx_output_observation PROPERTIES LABELS "phase1;streamline")
add_test(NAME ngx_queue_completion
  COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/validate-ngx-queue.ps1"
    -Reader "${PROJECT_SOURCE_DIR}/tools/stereo/read-ngx-queue-probe.ps1")
