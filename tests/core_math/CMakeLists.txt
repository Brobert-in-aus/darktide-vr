add_executable(darktidevr-core-math-tests main.cpp)
target_compile_options(darktidevr-core-math-tests PRIVATE /W4 /WX /permissive-)
target_link_libraries(darktidevr-core-math-tests PRIVATE darktidevr_core)

if(BUILD_TESTING)
  add_test(NAME core_math COMMAND darktidevr-core-math-tests)
endif()

# The reticle and vignette sprites, which had never had a test: both faults
# that kept the aim-down-sights vignette invisible for five days are checkable
# without a headset (18 September).
add_executable(darktidevr-reticle-atlas-tests reticle_atlas_tests.cpp)
target_compile_options(darktidevr-reticle-atlas-tests PRIVATE /W4 /WX /permissive-)
target_link_libraries(darktidevr-reticle-atlas-tests PRIVATE darktidevr_core)
if(BUILD_TESTING)
  add_test(NAME reticle_atlas COMMAND darktidevr-reticle-atlas-tests)
  set_tests_properties(reticle_atlas PROPERTIES
    PASS_REGULAR_EXPRESSION "reticle_atlas.result=pass")
endif()

add_executable(darktidevr-pose-performance-tests pose_performance.cpp pose_math_baseline.cpp)
target_compile_options(darktidevr-pose-performance-tests PRIVATE /W4 /WX /permissive-)
target_link_libraries(darktidevr-pose-performance-tests PRIVATE darktidevr_core)
add_test(NAME pose_performance COMMAND darktidevr-pose-performance-tests)
