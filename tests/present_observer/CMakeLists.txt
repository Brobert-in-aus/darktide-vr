add_test(
  NAME present_observer_summary
  COMMAND
    powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/validate-summary.ps1"
    -Summarizer
    "${PROJECT_SOURCE_DIR}/tools/present_observer/summarize-presentmon.ps1"
    -Fixture
    "${CMAKE_CURRENT_SOURCE_DIR}/fixture.csv")

set_tests_properties(present_observer_summary PROPERTIES LABELS "phase0;present")

add_test(
  NAME camera_probe_summary
  COMMAND
    powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/validate-camera-summary.ps1"
    -Summarizer
    "${PROJECT_SOURCE_DIR}/tools/camera_probe/summarize-camera-log.ps1"
    -Fixture
    "${CMAKE_CURRENT_SOURCE_DIR}/camera-fixture.log")

set_tests_properties(camera_probe_summary PROPERTIES LABELS "phase0;camera")
