add_executable(darktidevr-two-bone-ik-tests main.cpp)
target_compile_options(darktidevr-two-bone-ik-tests PRIVATE /W4 /WX /permissive-)
target_link_libraries(darktidevr-two-bone-ik-tests PRIVATE darktidevr_core)

if(BUILD_TESTING)
  add_test(NAME two_bone_ik COMMAND darktidevr-two-bone-ik-tests)
  set_tests_properties(two_bone_ik PROPERTIES LABELS "phase1;ik;presentation")
endif()
