add_executable(darktidevr-semantic-camera-tests main.cpp)
target_compile_options(darktidevr-semantic-camera-tests PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-semantic-camera-tests PRIVATE
  darktidevr_darktide_adapter darktidevr_core)

if(BUILD_TESTING)
  add_test(NAME semantic_camera COMMAND darktidevr-semantic-camera-tests)
  set_tests_properties(semantic_camera PROPERTIES LABELS "phase1;camera")
endif()
