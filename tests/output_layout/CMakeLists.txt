add_executable(darktidevr-output-layout-tests main.cpp)
target_compile_options(darktidevr-output-layout-tests PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-output-layout-tests PRIVATE darktidevr_core)

if(BUILD_TESTING)
  add_test(NAME output_layout COMMAND darktidevr-output-layout-tests)
  set_tests_properties(output_layout PROPERTIES LABELS "phase1;rendering")
endif()
