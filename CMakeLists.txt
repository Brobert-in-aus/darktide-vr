cmake_minimum_required(VERSION 3.25)

project(DarktideVR VERSION 0.1.0 LANGUAGES CXX)

if(NOT WIN32)
  message(FATAL_ERROR "Phase 0 targets Windows x64 only")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "DarktideVR requires a 64-bit toolchain")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(CTest)
include(FetchContent)

option(DARKTIDEVR_ENABLE_HEADSET_TESTS
  "Register tests that require a connected, compositor-visible OpenXR HMD" OFF)

# Khronos' Windows loader model is application-local. Pin the generated SDK so
# builds do not depend on a machine-wide loader or code generation toolchain.
set(DYNAMIC_LOADER ON CACHE BOOL "Build OpenXR as an app-local DLL" FORCE)
set(BUILD_API_LAYERS OFF CACHE BOOL "Do not build OpenXR API layers" FORCE)
set(BUILD_TESTS OFF CACHE BOOL "Do not build upstream OpenXR tests" FORCE)
set(BUILD_SDK_TESTS OFF CACHE BOOL "Do not build upstream OpenXR samples" FORCE)
set(BUILD_CONFORMANCE_TESTS OFF CACHE BOOL "Do not build the OpenXR CTS" FORCE)
set(BUILD_ALL_EXTENSIONS OFF CACHE BOOL "Build only platform extensions" FORCE)
set(INSTALL_SYMBOLS OFF CACHE BOOL "Do not install dependency symbols" FORCE)

FetchContent_Declare(
  OpenXRSDK
  GIT_REPOSITORY https://github.com/KhronosGroup/OpenXR-SDK.git
  GIT_TAG 5267613edf3d937e3d77556a106a65c2f82b25c6
  GIT_SHALLOW TRUE
  GIT_PROGRESS TRUE
)
FetchContent_MakeAvailable(OpenXRSDK)

# Native capture hooks are pinned to a reviewed upstream revision. They are
# loaded explicitly by the offline Lua mod and are never installed system-wide.
FetchContent_Declare(
  minhook
  GIT_REPOSITORY https://github.com/TsudaKageyu/minhook.git
  GIT_TAG c3fcafdc10146beb5919319d0683e44e3c30d537
  GIT_SHALLOW TRUE
  GIT_PROGRESS TRUE
)
FetchContent_MakeAvailable(minhook)

add_subdirectory(src/core)
add_subdirectory(src/bridge)
add_subdirectory(src/producer)
add_subdirectory(src/adapters/darktide)
add_subdirectory(tools/fingerprint)
add_subdirectory(tools/debug)
add_subdirectory(tests/core_math)
add_subdirectory(tests/controller_state)
add_subdirectory(tests/gameplay_input)
add_subdirectory(tests/gameplay_aim_state)
add_subdirectory(tests/menu_pointer_state)
add_subdirectory(tests/observation_gate)
add_subdirectory(tests/native_capture)
add_subdirectory(tests/output_layout)
add_subdirectory(tests/panel_pointer)
add_subdirectory(tests/semantic_camera)
add_subdirectory(tests/shared_eye_surfaces)
add_subdirectory(tests/shared_head_pose)
add_subdirectory(tests/pose_snapshot)
add_subdirectory(tests/presentation_policy)
add_subdirectory(tests/presentation_state)
add_subdirectory(tests/two_bone_ik)
add_subdirectory(tests/present_observer)
add_subdirectory(tests/xr_harness)
