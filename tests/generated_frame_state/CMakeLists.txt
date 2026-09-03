add_executable(darktidevr-generated-frame-state-tests main.cpp)
target_compile_options(darktidevr-generated-frame-state-tests PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-generated-frame-state-tests PRIVATE
  darktidevr_core)

if(BUILD_TESTING)
  add_test(NAME generated_frame_state
    COMMAND darktidevr-generated-frame-state-tests)
  set_tests_properties(generated_frame_state PROPERTIES
    LABELS "phase1;transport")
endif()
