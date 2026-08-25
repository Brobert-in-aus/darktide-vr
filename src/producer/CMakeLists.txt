add_library(darktidevr_native_capture SHARED native_capture.cpp)
target_compile_options(darktidevr_native_capture PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr_native_capture PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr_native_capture PRIVATE
  minhook darktidevr_core d3d12 dxgi dxguid)
set_target_properties(darktidevr_native_capture PROPERTIES
  OUTPUT_NAME "darktidevr_native_capture")
