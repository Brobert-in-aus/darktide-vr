add_executable(darktidevr-core-math-tests main.cpp)
target_compile_options(darktidevr-core-math-tests PRIVATE /W4 /WX /permissive-)
target_link_libraries(darktidevr-core-math-tests PRIVATE darktidevr_core)

if(BUILD_TESTING)
  add_test(NAME core_math COMMAND darktidevr-core-math-tests)
endif()

add_executable(darktidevr-pose-performance-tests pose_performance.cpp pose_math_baseline.cpp)
target_compile_options(darktidevr-pose-performance-tests PRIVATE /W4 /WX /permissive-)
target_link_libraries(darktidevr-pose-performance-tests PRIVATE darktidevr_core)
add_test(NAME pose_performance COMMAND darktidevr-pose-performance-tests)
