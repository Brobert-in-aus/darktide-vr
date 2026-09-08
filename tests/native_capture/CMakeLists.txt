add_executable(darktidevr-native-capture-tests main.cpp)
add_executable(darktidevr-bootstrap-selection-tests bootstrap_selection.cpp)
target_compile_options(darktidevr-bootstrap-selection-tests PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-bootstrap-selection-tests PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-bootstrap-selection-tests PRIVATE d3d12)
add_executable(darktidevr-pipeline-probe-tests pipeline_probe.cpp)
target_compile_options(darktidevr-pipeline-probe-tests PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-pipeline-probe-tests PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-pipeline-probe-tests PRIVATE d3d12 d3dcompiler)
add_executable(darktidevr-billboard-basis-tests billboard_basis.cpp)
target_compile_options(darktidevr-billboard-basis-tests PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-billboard-basis-tests PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-billboard-basis-tests PRIVATE d3d11 d3dcompiler)
add_executable(darktidevr-diagnostic-append-tests diagnostic_append_log.cpp)
target_include_directories(darktidevr-diagnostic-append-tests PRIVATE "${PROJECT_SOURCE_DIR}/src")
target_compile_options(darktidevr-diagnostic-append-tests PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-diagnostic-append-tests PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_compile_options(darktidevr-native-capture-tests PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-native-capture-tests PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-native-capture-tests PRIVATE
  darktidevr_core
  d3d12)

if(BUILD_TESTING)
  add_test(NAME billboard_compiled_basis COMMAND darktidevr-billboard-basis-tests
    "${CMAKE_CURRENT_SOURCE_DIR}/billboard_basis.cs.hlsl")
  set_tests_properties(billboard_compiled_basis PROPERTIES TIMEOUT 30 LABELS "billboard;offline")
  add_test(NAME bootstrap_selection COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-bootstrap-selection.ps1"
    -Executable $<TARGET_FILE:darktidevr-bootstrap-selection-tests>
    -CaptureLibrary $<TARGET_FILE:darktidevr_native_capture>
    -BootstrapLibrary $<TARGET_FILE:darktidevr_d3d12_bootstrap>)
  set_tests_properties(bootstrap_selection PROPERTIES TIMEOUT 60 LABELS "native;d3d12;offline")
  foreach(mode IN ITEMS apply fallback)
    add_test(NAME pipeline_probe_${mode} COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
      "${CMAKE_CURRENT_SOURCE_DIR}/test-pipeline-probe.ps1"
      -Executable $<TARGET_FILE:darktidevr-pipeline-probe-tests>
      -CaptureLibrary $<TARGET_FILE:darktidevr_native_capture>
      -ReflectionLibrary "${PROJECT_SOURCE_DIR}/build/dependencies/dxc-runtime/dxcompiler.dll" -Mode ${mode})
    set_tests_properties(pipeline_probe_${mode} PROPERTIES TIMEOUT 45 LABELS "native;d3d12;offline")
  endforeach()
  add_test(NAME diagnostic_append_log COMMAND darktidevr-diagnostic-append-tests)
  set_tests_properties(diagnostic_append_log PROPERTIES TIMEOUT 30 LABELS "native;offline")
  add_test(NAME native_capture_hooks
    COMMAND darktidevr-native-capture-tests
      $<TARGET_FILE:darktidevr_native_capture>)
  set_tests_properties(native_capture_hooks PROPERTIES
    LABELS "phase1;d3d12;native")
endif()
