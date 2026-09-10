add_library(darktidevr_native_capture SHARED native_capture.cpp resource_handle_trace.cpp ngx_output_probe.cpp ngx_output_copy_probe.cpp generated_stereo.cpp streamline_continuous_submission.cpp stereo_ui_readback.cpp ngx_gpu_timing.cpp billboard_draw_readback.cpp)
target_sources(darktidevr_native_capture PRIVATE particle_submission_probe.cpp)
target_sources(darktidevr_native_capture PRIVATE compute_dispatch_probe.cpp)
target_sources(darktidevr_native_capture PRIVATE native_original_ring.cpp)
target_sources(darktidevr_native_capture PRIVATE engine_preparation_probe.cpp)
target_compile_options(darktidevr_native_capture PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr_native_capture PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_link_libraries(darktidevr_native_capture PRIVATE
  minhook darktidevr_core d3d12 dxgi dxguid d3dcompiler)
set_target_properties(darktidevr_native_capture PROPERTIES
  OUTPUT_NAME "darktidevr_native_capture")

option(DARKTIDEVR_BUILD_LEGACY_WINMM "Build the retired winmm bootstrap experiment" OFF)
if(DARKTIDEVR_BUILD_LEGACY_WINMM)
add_library(darktidevr_winmm_bootstrap SHARED
  winmm_bootstrap.cpp
  winmm_bootstrap.def)
target_compile_options(darktidevr_winmm_bootstrap PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr_winmm_bootstrap PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
set_target_properties(darktidevr_winmm_bootstrap PROPERTIES
  OUTPUT_NAME "winmm"
  PREFIX "")

endif()

add_library(darktidevr_d3d12_bootstrap SHARED
  d3d12_bootstrap.cpp
  d3d12_bootstrap.def)
target_compile_options(darktidevr_d3d12_bootstrap PRIVATE
  /W4 /WX /permissive-)
target_compile_definitions(darktidevr_d3d12_bootstrap PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
set_target_properties(darktidevr_d3d12_bootstrap PROPERTIES
  OUTPUT_NAME "d3d12"
  PREFIX "")
