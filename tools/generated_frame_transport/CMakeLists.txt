add_executable(darktidevr-generated-frame-consumer main.cpp)
target_compile_options(darktidevr-generated-frame-consumer PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-generated-frame-consumer PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-generated-frame-consumer PRIVATE
  darktidevr_bridge d3d12)

# Keep existing research command paths compatible.
set_target_properties(darktidevr-generated-frame-consumer PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/tests/generated_frame_transport")
