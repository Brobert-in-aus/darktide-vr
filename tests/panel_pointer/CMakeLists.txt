add_executable(darktidevr-panel-pointer-tests main.cpp menu_pointer_input_tests.cpp)
target_compile_options(darktidevr-panel-pointer-tests PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-panel-pointer-tests PRIVATE darktidevr_core)
add_test(NAME panel_pointer COMMAND darktidevr-panel-pointer-tests)
set_tests_properties(panel_pointer PROPERTIES
  LABELS "phase1;input;pointer")
