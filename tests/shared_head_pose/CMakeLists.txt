add_executable(darktidevr-shared-head-pose-tests main.cpp)
target_compile_options(darktidevr-shared-head-pose-tests PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-shared-head-pose-tests PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-shared-head-pose-tests PRIVATE darktidevr_core)

if(BUILD_TESTING)
  add_test(NAME shared_head_pose COMMAND darktidevr-shared-head-pose-tests)
  set_tests_properties(shared_head_pose PROPERTIES LABELS "phase1;camera;ipc")
endif()
