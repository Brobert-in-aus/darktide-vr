
if(BUILD_TESTING)
  add_test(NAME component_provenance COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-component-provenance.ps1")
  add_test(NAME mode_switch COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-mode-switch.ps1")
  add_test(NAME offline_workload_readiness COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-offline-workload-readiness.ps1")
  add_test(NAME synthetic_framegen_settings COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-synthetic-framegen-settings.ps1")
  add_test(NAME quest_watcher_cleanup COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-quest-watcher.ps1")
  add_test(NAME validate-xr-readiness COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/validate-xr-readiness.ps1")
  add_test(NAME preflight_device_inventory COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-preflight-device-inventory.ps1")
  add_test(NAME quest_proximity_results COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-quest-proximity-results.ps1")
  add_test(NAME xr_smoke_timeout COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-xr-smoke-timeout.ps1")
  set_tests_properties(xr_smoke_timeout PROPERTIES TIMEOUT 30)
  add_test(NAME lua_source_compile COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${PROJECT_SOURCE_DIR}/tools/stereo/test-darktide-lua-source.ps1")
  add_test(NAME lua_source_invariants COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${PROJECT_SOURCE_DIR}/tools/stereo/test-darktide-lua-invariants.ps1")
  add_test(NAME deployment_transaction COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-deployment-transaction.ps1")
  add_test(NAME focused_trial_status COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-focused-trial-status.ps1")
  add_test(NAME deployment_sync COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-deployment-sync.ps1")
  add_test(NAME vr_mod_load_order COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-vr-mod-load-order.ps1")
  add_test(NAME deployment_recovery COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-deployment-recovery.ps1")
  add_test(NAME source_checkout_identity COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-source-checkout-identity.ps1")
  add_test(NAME runtime_package_integrity COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-runtime-package.ps1")
  set(LUAJIT_VALIDATOR "${PROJECT_SOURCE_DIR}/build/dependencies/luajit/src/luajit.exe")
  add_test(NAME solo_mission_benchmark COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-solo-mission-benchmark.lua"
    "${PROJECT_SOURCE_DIR}/tools/stereo/solo-mission-benchmark.lua")
  add_test(NAME render_world_census COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-render-world-census.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_render_world_census.lua")
  add_test(NAME native_startup_flags COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-native-startup.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_native_startup.lua")
  add_test(NAME luajit_compiler_contract COMMAND "${LUAJIT_VALIDATOR}"
    "${PROJECT_SOURCE_DIR}/tools/lua/test-compiler.lua")
  add_test(NAME luajit_source_path COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-luajit-source-path.ps1")
  add_test(NAME installed_lua_gates COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-installed-lua-gates.ps1")
  add_test(NAME projection_math COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-projection-math.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_projection_math.lua")
  find_package(Python3 REQUIRED COMPONENTS Interpreter)
  add_test(NAME cascade_stage_reader COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-cascade-stage.py" --native "$<TARGET_FILE:darktidevr-cascade-stage-forwarding-tests>")
  add_test(NAME compute_dispatch_reader COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-compute-dispatch.py")
  add_test(NAME particle_submission_reader COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-particle-submissions.py")
  add_test(NAME stereo_camera_coherence COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-stereo-camera-coherence.py")
  add_test(NAME synthetic_gpu_load COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-synthetic-gpu-load.py")
  add_test(NAME cluster_list_initialization COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-cluster-list-initialization.py")
  add_test(NAME synthetic_framegen_analysis COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-synthetic-framegen-analysis.py")
  add_test(NAME billboard_build_output COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tools/stereo/test-build-atlas-billboard-candidates.py")
  add_test(NAME xr_disabled_contract COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-xr-disabled-contract.py"
    "$<TARGET_FILE:darktidevr-xr-harness>")
  set_tests_properties(xr_disabled_contract PROPERTIES TIMEOUT 30)
  execute_process(COMMAND "${Python3_EXECUTABLE}" -c "import numpy; import PIL"
    RESULT_VARIABLE DARKTIDEVR_ANALYSIS_IMPORT_RESULT OUTPUT_QUIET ERROR_QUIET)
  if(NOT DARKTIDEVR_ANALYSIS_IMPORT_RESULT EQUAL 0)
    message(FATAL_ERROR "Offline image-analysis tests require NumPy and Pillow. Run \"${Python3_EXECUTABLE}\" -m pip install -r \"${PROJECT_SOURCE_DIR}/tools/stereo/requirements-analysis.txt\", then configure again.")
  endif()
  add_test(NAME generated_health_analysis COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-generated-health.py")
  add_test(NAME xr_frame_stage_analysis COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-xr-frame-stages.py")
  add_test(NAME vdxr_trace_analysis COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-vdxr-trace.py")
  add_test(NAME vdxr_wait_overlap_analysis COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-vdxr-wait-overlap.py")
  add_test(NAME vdxr_app_statistics_analysis COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-vdxr-app-statistics.py")
  add_test(NAME marker_metrics_analysis COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-marker-metrics-summary.py")
  add_test(NAME dlss_ui_detail COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tests/streamline_stereo_inputs/test_ui_detail.py")
  add_test(NAME ngx_sr_probe_reader COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tests/streamline_stereo_inputs/test_ngx_sr_probe.py"
    --native "$<TARGET_FILE:darktidevr-ngx-sr-observation-tests>")
  add_test(NAME dlss_ui_input_comparison COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tests/streamline_stereo_inputs/test_ui_input_comparison.py")
  add_test(NAME dlss_ui_alpha_regions COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tests/streamline_stereo_inputs/test_ui_alpha_check.py")
  add_test(NAME dlss_ui_capture_identity COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tests/streamline_stereo_inputs/test_generated_ui_check.py")
  add_test(NAME ui_readback_native_roundtrip COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tests/streamline_stereo_inputs/test_ui_readback_native.py"
    "$<TARGET_FILE:darktidevr-ui-readback-tests>")
  set_tests_properties(ui_readback_native_roundtrip PROPERTIES TIMEOUT 30)
  add_test(NAME ui_binding_audit COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-ui-binding-audit.py")
  add_test(NAME menu_input COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-menu-input.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_menu_input.lua"
    "${CMAKE_CURRENT_SOURCE_DIR}/menu-view-inventory.txt")
  add_test(NAME menu_widgets COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-menu-widgets.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_menu_widgets.lua")
  add_test(NAME menu_renderer_lifetime COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-menu-renderer-lifetime.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME reticle_surfaces COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-reticle-surfaces.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_aim.lua")
  add_test(NAME melee_animation_owner COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-animation.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_body_proxy.lua")
  add_test(NAME gameplay_heading COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-gameplay-heading.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME psykh_entry COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-psykhanium-entry.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_gameplay_context.lua")
  add_test(NAME turning COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-turning.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_turning.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_localization.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_bindings.lua")
  add_test(NAME keyboard_mouse COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-keyboard-mouse.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_keyboard_mouse.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_localization.lua")
  add_test(NAME keyboard_mouse_melee COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-keyboard-mouse-melee.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_keyboard_mouse.lua")
  file(GLOB DARKTIDEVR_MOD_LUA_SOURCES "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/*.lua")
  list(SORT DARKTIDEVR_MOD_LUA_SOURCES)
  add_test(NAME dmf_unique_hooks COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-dmf-unique-hooks.lua" ${DARKTIDEVR_MOD_LUA_SOURCES})
  add_test(NAME keyboard_mouse_melee_input COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-keyboard-mouse-melee-input.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_keyboard_mouse.lua")
  add_test(NAME keyboard_mouse_aim_source COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-keyboard-mouse-aim-source.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_keyboard_mouse.lua")
  add_test(NAME menu_prompts COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-menu-prompts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_menu_prompts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_localization.lua")
  add_test(NAME ranged_aim COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-ranged-aim.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_aim.lua")
  add_test(NAME gameplay_context COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-gameplay-context.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_gameplay_context.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME spectator_input COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-spectator-input.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_spectator_input.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_bindings.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_gameplay_context.lua")
  add_test(NAME online_rules COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-online-rules.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_online_rules.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_gameplay_context.lua")
  add_test(NAME grenade_aim COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-grenade-aim.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_grenade_aim.lua")
  add_test(NAME melee_aim COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-aim.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_aim.lua")
  add_test(NAME gpu_trace_analysis COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tools/stereo/test-analyze-gpu-batch-trace.py")
  add_test(NAME visual_settings COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-visual-settings.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_visual_settings.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME wrist_transform COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-wrist-transform.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME equipment_hand_sync COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-equipment-hand-sync.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME hand_anatomy COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-hand-anatomy.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_body_proxy.lua")
  add_test(NAME weapon_sound_owner COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-weapon-sound-owner.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_weapon_sound.lua")
  add_test(NAME rigid_hand_readiness COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-rigid-hand-readiness.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_body_proxy.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME animation_aim COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-animation-aim.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME block_direction COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-block-direction.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_combat_direction.lua")
  add_test(NAME melee_animation_source COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-animation-source.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_body_proxy.lua")
  add_test(NAME melee_contact_policy COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-contact-policy.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_contact_policy.lua")
  add_test(NAME melee_sweep_plan COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-sweep-plan.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_sweep_plan.lua")
  add_test(NAME melee_volume COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-volume.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_volume.lua")
  add_test(NAME marker_gui COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-marker-gui.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_marker_gui.lua")
  add_test(NAME marker_metrics COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-marker-metrics.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_marker_metrics.lua")
  add_test(NAME marker_plane COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-marker-plane.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_marker_plane.lua")
  add_test(NAME marker_world COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-marker-world.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_marker_world.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_marker_plane.lua")
  add_test(NAME marker_atlas COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-marker-atlas.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_marker_atlas.lua")
  set_tests_properties(marker_atlas PROPERTIES PASS_REGULAR_EXPRESSION "marker_atlas.result=pass")
  add_test(NAME widget_surface COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-widget-surface.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_widget_surface.lua")
  add_test(NAME widget_capture COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-widget-capture.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_widget_capture.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_widget_surface.lua")
  add_test(NAME widget_scenegraph COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-widget-scenegraph.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_widget_scenegraph.lua")
  add_test(NAME widget_capture_state COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-widget-capture-state.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_widget_capture_state.lua")
  add_test(NAME widget_capture_session COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-widget-capture-session.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr")
  add_test(NAME widget_quad COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-widget-quad.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr")
  add_test(NAME widget_display COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-widget-display.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr")
  add_test(NAME reticle_owner COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-reticle-owner.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_aim.lua")
  add_test(NAME communication_gesture COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-communication-gesture.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_communication_gesture.lua")
  add_test(NAME communication_navigation COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-communication-navigation.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_communication_navigation.lua")
  add_test(NAME communication_context COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-communication-context.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_communication_context.lua")
  add_test(NAME communication_wheel COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-communication-wheel.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr")
  add_test(NAME communication_input COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-communication-input.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr")
  add_test(NAME push_to_talk_input COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-push-to-talk-input.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_push_to_talk_input.lua")
  add_test(NAME exclusive_gameplay_stick COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-exclusive-gameplay-stick.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr")
  add_test(NAME melee_contacts COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-contacts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_contacts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_contact_policy.lua")
    add_test(NAME melee_timing COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-timing.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_timing.lua")
    add_test(NAME gameplay_ui_input COMMAND "${LUAJIT_VALIDATOR}"
      "${CMAKE_CURRENT_SOURCE_DIR}/test-gameplay-ui-input.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_gameplay_ui_input.lua")
  add_test(NAME roomscale COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-roomscale.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_roomscale.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME online_reticle COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-online-reticle.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_online_reticle.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME ranged_evidence COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-ranged-evidence.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_ranged_evidence.lua")
  add_test(NAME weapon_stabilization COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-weapon-stabilization.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_weapon_stabilization.lua")
  add_test(NAME weapon_assist COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-weapon-assist.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_weapon_assist.lua")
  add_test(NAME crosshair_feedback COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-crosshair-feedback.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_crosshair_feedback.lua")
  add_test(NAME options_layout COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-options-layout.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_options_layout.lua")
  add_test(NAME session_control COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-session-control.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_session_control.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_viewer.lua")
  add_test(NAME pose_trace COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-pose-trace.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_pose_trace.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME ammo_readout COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-ammo-readout.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_ammo_readout.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME haptics COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-haptics.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_haptics.lua")
  add_test(NAME holsters COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-holsters.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_holsters.lua")
  add_test(NAME scanner_holo COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-scanner-holo.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_scanner_holo.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME body_mirror COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-body-mirror.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_body_mirror.lua")
  add_test(NAME teammate_status COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-teammate-status.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_teammate_status.lua")
  add_test(NAME hand_overlay COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-hand-overlay.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_hand_overlay.lua")
  add_test(NAME body_hand_rig COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-body-hand-rig.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_body_proxy.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME rig_scan COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-rig-scan.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_rig_scan.lua")
  add_test(NAME wrist_display COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-wrist-display.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_wrist_display.lua")
  add_test(NAME tracked_eye_anchor COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-tracked-eye-anchor.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME frame_profile COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-frame-profile.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_frame_profile.lua")
  add_test(NAME item_radial COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-item-radial.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_item_radial.lua")
  add_test(NAME weapon_charge_display COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-weapon-charge-display.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_weapon_charge_display.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_crosshair_feedback.lua")
  add_test(NAME tag_gesture COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-tag-gesture.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_tag_gesture.lua")
  add_test(NAME comms_gesture COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-comms-gesture.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_comms_gesture.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_weapon_inspect.lua")
  add_test(NAME weapon_inspect COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-weapon-inspect.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_weapon_inspect.lua")
  add_test(NAME reach_interact COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-reach-interact.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_reach_interact.lua")
  add_test(NAME eye_anchor_offset COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-eye-anchor-offset.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME arm_length COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-arm-length.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_arm_length.lua")
  add_test(NAME skull_throw COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-skull-throw.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_skull_throw.lua")
  add_test(NAME forearm_holsters COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-forearm-holsters.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_forearm_holsters.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_holsters.lua")
  add_test(NAME holster_counts COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-holster-counts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_holster_counts.lua")
  add_test(NAME sight_ads COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-sight-ads.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_sight_ads.lua")
  add_test(NAME body_frame COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-body-frame.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_body_frame.lua")
  add_test(NAME gun_sights COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-gun-sights.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_gun_sights.lua")
  add_test(NAME weapon_parked_parts COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-weapon-parked-parts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_weapon_parked_parts.lua")
  add_test(NAME gun_aim COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-gun-aim.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_gun_aim.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
    add_test(NAME two_hand_pose COMMAND "${LUAJIT_VALIDATOR}"
      "${CMAKE_CURRENT_SOURCE_DIR}/test-two-hand-pose.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_two_hand_pose.lua")
    add_test(NAME two_hand_support COMMAND "${LUAJIT_VALIDATOR}"
      "${CMAKE_CURRENT_SOURCE_DIR}/test-two-hand-support.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_two_hand_support.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_two_hand_pose.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_bindings.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_body_proxy.lua")
    add_test(NAME hud_panel COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-hud-panel.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_hud_panel.lua")
  add_test(NAME hud_options COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-hud-options.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_hud_panel.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_data.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_localization.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_bindings.lua")
  add_test(NAME controller_bindings COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-controller-bindings.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_bindings.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_localization.lua"
      "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/game-input-actions.lua")
  add_test(NAME weapon_hand_roles COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-weapon-hand-roles.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_weapon_hand_roles.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua")
  add_test(NAME gameplay_ui_ownership COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-gameplay-ui-ownership.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_gameplay_context.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_bindings.lua")
  add_test(NAME scanner_stick_reference COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-scanner-stick-reference.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_gameplay_context.lua")
  add_test(NAME smart_tag_marker_target COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-smart-tag-marker-target.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_online_rules.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_gameplay_context.lua")
  add_test(NAME controller_prompts COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-controller-prompts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_bindings.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_prompts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_localization.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_menu_prompts.lua")
  add_test(NAME melee_simulation COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-simulation.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_simulation.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_contacts.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_contact_policy.lua")
  add_test(NAME melee_preview COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-preview.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_preview.lua")
  add_test(NAME melee_simulation_visual COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-simulation-visual.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_aim.lua")
  add_test(NAME melee_preview_display COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-preview-display.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_preview_display.lua")
  add_test(NAME melee_probe COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-probe.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_probe.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_volume.lua")
  add_test(NAME melee_hit_zone COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-hit-zone.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_hit_zone.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_contacts.lua"
      "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_diagnostics.lua")
  add_test(NAME melee_live_probe COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-live-probe.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_live_probe.lua")
  add_test(NAME melee_diagnostics COMMAND "${LUAJIT_VALIDATOR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/test-melee-diagnostics.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_diagnostics.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_simulation.lua"
    "${PROJECT_SOURCE_DIR}/mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_sweep_plan.lua")
endif()
add_test(NAME startup_advance
  COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
    "${CMAKE_CURRENT_SOURCE_DIR}/test-startup-advance.ps1")

add_library(darktidevr-ui-pixel-hash SHARED "${PROJECT_SOURCE_DIR}/tools/stereo/ui_pixel_hash.cpp")
target_compile_options(darktidevr-ui-pixel-hash PRIVATE /W4 /WX /permissive-)

if(BUILD_TESTING)
  add_test(NAME ui_pixel_hash_helper COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tests/streamline_stereo_inputs/test_ui_pixel_hash.py"
    "$<TARGET_FILE:darktidevr-ui-pixel-hash>")
  # Analysis and reader suites that were present but never registered.
  add_test(NAME engine_preparation_reader COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-engine-preparation.py")
  execute_process(COMMAND "${Python3_EXECUTABLE}" -c "import capstone; import pefile"
    RESULT_VARIABLE DARKTIDEVR_ENGINE_INSPECTION_IMPORT_RESULT OUTPUT_QUIET ERROR_QUIET)
  if(DARKTIDEVR_ENGINE_INSPECTION_IMPORT_RESULT EQUAL 0)
    add_test(NAME engine_unwind_ownership COMMAND "${Python3_EXECUTABLE}" -B
      "${CMAKE_CURRENT_SOURCE_DIR}/test-engine-unwind-ownership.py")
  else()
    message(STATUS "engine_unwind_ownership skipped: capstone/pefile are not importable by ${Python3_EXECUTABLE}")
  endif()
  add_test(NAME packed_shader_groups COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-packed-shader-groups.py")
  add_test(NAME dispatch_bundle_reader COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-dispatch-bundle-reader.py")
  add_test(NAME residency_unwind_index COMMAND "${Python3_EXECUTABLE}" -B
    "${CMAKE_CURRENT_SOURCE_DIR}/test-residency-unwind-index.py")
  add_test(NAME billboard_readback_analysis COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tools/stereo/test-analyze-billboard-readback.py")
  add_test(NAME synthetic_gpu_stage_summary COMMAND "${Python3_EXECUTABLE}" -B
    "${PROJECT_SOURCE_DIR}/tools/stereo/test-summarize-synthetic-gpu-stages.py")
endif()
