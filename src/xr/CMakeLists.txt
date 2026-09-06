add_library(darktidevr-window-capture STATIC window_capture.cpp)
target_include_directories(darktidevr-window-capture PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-window-capture PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-window-capture PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-window-capture PRIVATE gdi32 user32)

add_library(darktidevr-menu-input STATIC menu_input_injector.cpp)
target_include_directories(darktidevr-menu-input PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-menu-input PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-menu-input PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-menu-input PUBLIC darktidevr_core user32)

add_library(darktidevr-synthetic-controller STATIC
  synthetic_controller_path.cpp)
target_include_directories(darktidevr-synthetic-controller PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-synthetic-controller PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-synthetic-controller PUBLIC darktidevr_core)

add_library(darktidevr-synthetic-head STATIC synthetic_head_path.cpp)
target_include_directories(darktidevr-synthetic-head PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-synthetic-head PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-synthetic-head PUBLIC darktidevr_core)

add_library(darktidevr-tracked-cuff STATIC tracked_cuff_mesh.cpp)
target_include_directories(darktidevr-tracked-cuff PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-tracked-cuff PRIVATE
  /W4 /WX /permissive-)
target_link_libraries(darktidevr-tracked-cuff PUBLIC darktidevr_core)

add_library(darktidevr-tracked-cuff-renderer STATIC tracked_cuff_renderer.cpp)
target_include_directories(darktidevr-tracked-cuff-renderer PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(darktidevr-tracked-cuff-renderer PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr-tracked-cuff-renderer PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN)
target_link_libraries(darktidevr-tracked-cuff-renderer PUBLIC
  OpenXR::openxr_loader darktidevr-tracked-cuff darktidevr_core
  d3d12 d3dcompiler dxgi)

add_library(darktidevr-ui-projection STATIC ui_projection_layer.cpp)
target_compile_options(darktidevr-ui-projection PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-ui-projection PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
target_link_libraries(darktidevr-ui-projection PUBLIC OpenXR::openxr_loader d3d12)

add_executable(darktidevr-xr-harness main.cpp synthetic_scene.cpp)
target_compile_options(darktidevr-xr-harness PRIVATE /W4 /WX /permissive-)
target_compile_definitions(darktidevr-xr-harness PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr-xr-harness PRIVATE
  OpenXR::openxr_loader darktidevr_core darktidevr_bridge darktidevr-window-capture
  darktidevr-menu-input darktidevr-synthetic-controller
  darktidevr-synthetic-head darktidevr-tracked-cuff-renderer darktidevr-ui-projection
  d3d12 d3dcompiler dxgi dxguid)

add_custom_command(TARGET darktidevr-xr-harness POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "$<TARGET_FILE:openxr_loader>"
    "$<TARGET_FILE_DIR:darktidevr-xr-harness>"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${openxrsdk_SOURCE_DIR}/LICENSE"
    "$<TARGET_FILE_DIR:darktidevr-xr-harness>/OPENXR-LICENSE.txt"
  COMMENT "Copying the pinned Khronos OpenXR loader beside the harness"
)


# Preserve existing launcher and artifact paths while separating source ownership.
set_target_properties(darktidevr-xr-harness PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/tests/xr_harness")
