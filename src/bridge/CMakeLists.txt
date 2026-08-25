add_library(darktidevr_bridge STATIC shared_eye_surfaces.cpp)
target_include_directories(darktidevr_bridge PUBLIC "${PROJECT_SOURCE_DIR}/src")
target_compile_options(darktidevr_bridge PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr_bridge PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr_bridge PUBLIC darktidevr_core d3d12)
