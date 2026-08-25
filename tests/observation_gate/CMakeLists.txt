add_executable(darktidevr-observation-gate-tests main.cpp)
target_compile_options(darktidevr-observation-gate-tests PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-observation-gate-tests PRIVATE
  darktidevr_darktide_adapter)

if(BUILD_TESTING)
  add_test(NAME observation_gate COMMAND darktidevr-observation-gate-tests)
endif()
