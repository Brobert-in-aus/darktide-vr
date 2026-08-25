add_executable(darktidevr-shared-eye-surfaces-tests main.cpp)
target_compile_options(darktidevr-shared-eye-surfaces-tests PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-shared-eye-surfaces-tests PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-shared-eye-surfaces-tests PRIVATE
  darktidevr_bridge d3d12)

if(BUILD_TESTING)
  add_test(NAME shared_eye_surfaces COMMAND darktidevr-shared-eye-surfaces-tests)
  set_tests_properties(shared_eye_surfaces PROPERTIES LABELS "phase1;d3d12;stereo")
endif()
