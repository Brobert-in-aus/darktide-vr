add_executable(darktidevr-gameplay-aim-state-tests main.cpp)
target_compile_options(darktidevr-gameplay-aim-state-tests PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-gameplay-aim-state-tests PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-gameplay-aim-state-tests PRIVATE darktidevr_core)
add_test(NAME gameplay_aim_state_transport
  COMMAND darktidevr-gameplay-aim-state-tests)
set_tests_properties(gameplay_aim_state_transport PROPERTIES
  LABELS "phase1;input;transport")
