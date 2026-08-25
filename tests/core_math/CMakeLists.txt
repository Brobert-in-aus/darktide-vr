add_executable(darktidevr-core-math-tests main.cpp)
target_compile_options(darktidevr-core-math-tests PRIVATE /W4 /WX /permissive-)
target_link_libraries(darktidevr-core-math-tests PRIVATE darktidevr_core)

if(BUILD_TESTING)
  add_test(NAME core_math COMMAND darktidevr-core-math-tests)
endif()
