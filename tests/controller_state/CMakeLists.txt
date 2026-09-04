add_executable(darktidevr-controller-state-tests main.cpp)
target_compile_options(darktidevr-controller-state-tests PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-controller-state-tests PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-controller-state-tests PRIVATE darktidevr_core)
add_test(NAME controller_state_transport
  COMMAND darktidevr-controller-state-tests)
set_tests_properties(controller_state_transport PROPERTIES
  LABELS "phase1;input;transport")

if(BUILD_TESTING)
  add_executable(darktidevr-transport-isolation-tests isolation.cpp)
  target_compile_options(darktidevr-transport-isolation-tests PRIVATE /W4 /WX /permissive-)
  target_compile_definitions(darktidevr-transport-isolation-tests PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
  target_link_libraries(darktidevr-transport-isolation-tests PRIVATE darktidevr_core)
  add_test(NAME transport_process_isolation COMMAND darktidevr-transport-isolation-tests
    "$<TARGET_FILE:darktidevr-controller-state-tests>")
endif()
