add_executable(darktidevr-streamline-stereo-inputs-tests main.cpp)
target_compile_options(darktidevr-streamline-stereo-inputs-tests PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-streamline-stereo-inputs-tests PRIVATE
  darktidevr_core)

add_test(
  NAME streamline_stereo_inputs
  COMMAND darktidevr-streamline-stereo-inputs-tests)
set_tests_properties(streamline_stereo_inputs PROPERTIES
  LABELS "phase1;streamline")
