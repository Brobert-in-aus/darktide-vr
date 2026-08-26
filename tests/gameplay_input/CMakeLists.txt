add_executable(darktidevr-gameplay-input-tests main.cpp)

target_link_libraries(darktidevr-gameplay-input-tests PRIVATE darktidevr_core)
target_compile_options(darktidevr-gameplay-input-tests PRIVATE /W4 /WX /permissive-)

add_test(NAME gameplay_input COMMAND darktidevr-gameplay-input-tests)
