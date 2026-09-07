
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
  execute_process(COMMAND "${Python3_EXECUTABLE}" -c "import numpy; import PIL"
    RESULT_VARIABLE DARKTIDEVR_ANALYSIS_IMPORT_RESULT OUTPUT_QUIET ERROR_QUIET)
  if(NOT DARKTIDEVR_ANALYSIS_IMPORT_RESULT EQUAL 0)
    message(FATAL_ERROR "Offline image-analysis tests require NumPy and Pillow. Run \"${Python3_EXECUTABLE}\" -m pip install -r \"${PROJECT_SOURCE_DIR}/tools/stereo/requirements-analysis.txt\", then configure again.")
  endif()
  add_test(NAME generated_health_analysis COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-generated-health.py")
  add_test(NAME dlss_ui_detail COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tests/streamline_stereo_inputs/test_ui_detail.py")
  add_test(NAME dlss_ui_capture_identity COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tests/streamline_stereo_inputs/test_generated_ui_check.py")
  add_test(NAME ui_binding_audit COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-ui-binding-audit.py")
  add_test(NAME menu_input COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-menu-input.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_menu_input.lua"
    "${CMAKE_CURRENT_SOURCE_DIR}/menu-view-inventory.txt")
  add_test(NAME menu_widgets COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-menu-widgets.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_menu_widgets.lua")
  add_test(NAME reticle_surfaces COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-reticle-surfaces.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_aim.lua")
  add_test(NAME melee_animation_owner COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-animation.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_body_proxy.lua")
  add_test(NAME gameplay_heading COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-gameplay-heading.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua")
  add_test(NAME turning COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-turning.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_turning.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe_localization.lua")
  add_test(NAME menu_prompts COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-menu-prompts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_menu_prompts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe_localization.lua")
  add_test(NAME ranged_aim COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-ranged-aim.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_aim.lua")
  add_test(NAME gameplay_context COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-gameplay-context.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_gameplay_context.lua")
  add_test(NAME online_rules COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-online-rules.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_online_rules.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_gameplay_context.lua")
  add_test(NAME grenade_aim COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-grenade-aim.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_grenade_aim.lua")
  add_test(NAME melee_aim COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-aim.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_aim.lua")
  add_test(NAME gpu_trace_analysis COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tools/stereo/test-analyze-gpu-batch-trace.py")
  add_test(NAME visual_settings COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-visual-settings.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_visual_settings.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua")
  add_test(NAME wrist_transform COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-wrist-transform.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua")
  add_test(NAME equipment_hand_sync COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-equipment-hand-sync.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua")
  add_test(NAME hand_anatomy COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-hand-anatomy.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_body_proxy.lua")
  add_test(NAME rigid_hand_readiness COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-rigid-hand-readiness.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_body_proxy.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua")
  add_test(NAME animation_aim COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-animation-aim.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua")
  add_test(NAME block_direction COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-block-direction.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_combat_direction.lua")
  add_test(NAME melee_animation_source COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-animation-source.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_body_proxy.lua")
  add_test(NAME melee_contact_policy COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-contact-policy.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_contact_policy.lua")
  add_test(NAME melee_sweep_plan COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-sweep-plan.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_sweep_plan.lua")
  add_test(NAME melee_volume COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-volume.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_volume.lua")
  add_test(NAME marker_gui COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-marker-gui.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_marker_gui.lua")
  add_test(NAME melee_contacts COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-contacts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_contacts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_contact_policy.lua")
    add_test(NAME melee_timing COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-timing.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_timing.lua")
    add_test(NAME gameplay_ui_input COMMAND "${LUAJIT_VALIDATOR}"
      "${CMAKE_CURRENT_SOURCE_DIR}/test-gameplay-ui-input.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_gameplay_ui_input.lua")
  add_test(NAME hud_panel COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-hud-panel.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_hud_panel.lua")
  add_test(NAME hud_options COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-hud-options.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_hud_panel.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe_data.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe_localization.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_bindings.lua")
  add_test(NAME controller_bindings COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-controller-bindings.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_bindings.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe_localization.lua"
      "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/game-input-actions.lua")
  add_test(NAME weapon_hand_roles COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-weapon-hand-roles.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_weapon_hand_roles.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua")
  add_test(NAME gameplay_ui_ownership COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-gameplay-ui-ownership.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_gameplay_context.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_bindings.lua")
  add_test(NAME scanner_stick_reference COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-scanner-stick-reference.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_gameplay_context.lua")
  add_test(NAME smart_tag_marker_target COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-smart-tag-marker-target.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_online_rules.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_gameplay_context.lua")
  add_test(NAME controller_prompts COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-controller-prompts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_bindings.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_prompts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe_localization.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_menu_prompts.lua")
  add_test(NAME melee_simulation COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-simulation.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_simulation.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_contacts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_contact_policy.lua")
  add_test(NAME melee_probe COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-probe.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_probe.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_volume.lua")
  add_test(NAME melee_hit_zone COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-hit-zone.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_hit_zone.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_contacts.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_diagnostics.lua")
  add_test(NAME melee_live_probe COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-live-probe.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_live_probe.lua")
  add_test(NAME melee_diagnostics COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-diagnostics.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_diagnostics.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_simulation.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_sweep_plan.lua")
endif()
add_test(NAME startup_advance
  COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-startup-advance.ps1")
