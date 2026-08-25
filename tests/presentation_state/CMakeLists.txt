add_executable(darktidevr-presentation-state-tests main.cpp)
target_compile_options(darktidevr-presentation-state-tests PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-presentation-state-tests PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-presentation-state-tests PRIVATE
  darktidevr_core)
add_test(NAME presentation_state_transport
  COMMAND darktidevr-presentation-state-tests)
set_tests_properties(presentation_state_transport PROPERTIES
  LABELS "phase1;presentation;transport")
