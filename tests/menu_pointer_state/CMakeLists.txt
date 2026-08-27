add_executable(darktidevr-menu-pointer-state-tests main.cpp)

target_link_libraries(darktidevr-menu-pointer-state-tests
  PRIVATE darktidevr_core
)

add_test(NAME menu_pointer_state_transport
  COMMAND darktidevr-menu-pointer-state-tests)
set_tests_properties(menu_pointer_state_transport PROPERTIES
  TIMEOUT 10
)
