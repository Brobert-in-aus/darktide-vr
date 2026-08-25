add_library(darktidevr_darktide_adapter STATIC
  observation_gate.cpp
  present_candidates.cpp
  semantic_camera.cpp
)
target_include_directories(darktidevr_darktide_adapter PUBLIC
  "${PROJECT_SOURCE_DIR}/src")
target_compile_options(darktidevr_darktide_adapter PRIVATE /W4 /WX /permissive-)
