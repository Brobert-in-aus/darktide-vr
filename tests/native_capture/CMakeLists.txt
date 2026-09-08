add_executable(darktidevr-native-capture-tests main.cpp)
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
  add_test(NAME diagnostic_append_log COMMAND darktidevr-diagnostic-append-tests)
  set_tests_properties(diagnostic_append_log PROPERTIES TIMEOUT 30 LABELS "native;offline")
  add_test(NAME native_capture_hooks
    COMMAND darktidevr-native-capture-tests
      $<TARGET_FILE:darktidevr_native_capture>)
  set_tests_properties(native_capture_hooks PROPERTIES
    LABELS "phase1;d3d12;native")
endif()
