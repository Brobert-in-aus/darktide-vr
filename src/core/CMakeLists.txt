add_library(darktidevr_core STATIC
  fingerprint.cpp
  head_tracking.cpp
  menu_pointer_input.cpp
  output_layout.cpp
  panel_pointer.cpp
  pose_snapshot.cpp
  presentation_policy.cpp
  shared_controller_state.cpp
  shared_head_pose.cpp
  shared_presentation_state.cpp
  xr_math.cpp
)

target_include_directories(darktidevr_core PUBLIC
  "${PROJECT_SOURCE_DIR}/src"
)

target_compile_definitions(darktidevr_core PRIVATE
  NOMINMAX
  WIN32_LEAN_AND_MEAN
  UNICODE
  _UNICODE
)

target_compile_options(darktidevr_core PRIVATE /W4 /WX /permissive-)
target_link_libraries(darktidevr_core PRIVATE bcrypt version)
