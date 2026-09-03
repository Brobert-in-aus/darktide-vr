add_executable(darktidevr-generated-frame-consumer main.cpp)
target_compile_options(darktidevr-generated-frame-consumer PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-generated-frame-consumer PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-generated-frame-consumer PRIVATE
  darktidevr_bridge d3d12)
