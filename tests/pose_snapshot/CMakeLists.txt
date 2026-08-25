add_executable(darktidevr-pose-snapshot-tests main.cpp)
target_compile_options(darktidevr-pose-snapshot-tests PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-pose-snapshot-tests PRIVATE darktidevr_core)

if(BUILD_TESTING)
  add_test(NAME pose_snapshot COMMAND darktidevr-pose-snapshot-tests)
  set_tests_properties(pose_snapshot PROPERTIES LABELS "phase1;camera")
endif()
