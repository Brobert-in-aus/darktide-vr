
if(BUILD_TESTING)
  add_test(NAME validate-xr-readiness COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/validate-xr-readiness.ps1")
  add_test(NAME lua_source_compile COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${PROJECT_SOURCE_DIR}/tools/stereo/test-darktide-lua-source.ps1")
  add_test(NAME lua_source_invariants COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${PROJECT_SOURCE_DIR}/tools/stereo/test-darktide-lua-invariants.ps1")
  set(LUAJIT_VALIDATOR "${PROJECT_SOURCE_DIR}/build/dependencies/luajit/src/luajit.exe")
  add_test(NAME luajit_compiler_contract COMMAND "${LUAJIT_VALIDATOR}"
    "${PROJECT_SOURCE_DIR}/tools/lua/test-compiler.lua")
  add_test(NAME projection_math COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-projection-math.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_projection_math.lua")
  find_package(Python3 REQUIRED COMPONENTS Interpreter)
  add_test(NAME menu_widgets COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-menu-widgets.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_menu_widgets.lua")
  add_test(NAME gpu_trace_analysis COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tools/stereo/test-analyze-gpu-batch-trace.py")
endif()
