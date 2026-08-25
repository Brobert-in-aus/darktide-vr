add_executable(darktidevr-presentation-policy-tests main.cpp)
target_compile_options(darktidevr-presentation-policy-tests PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-presentation-policy-tests PRIVATE
  darktidevr_core)

if(BUILD_TESTING)
  add_test(NAME presentation_policy COMMAND darktidevr-presentation-policy-tests)
  set_tests_properties(presentation_policy PROPERTIES LABELS "phase1;camera")
endif()
