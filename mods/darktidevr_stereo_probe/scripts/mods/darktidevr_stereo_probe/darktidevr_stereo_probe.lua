local mod = get_mod("darktidevr_stereo_probe")

local ScriptCamera = require("scripts/foundation/utilities/script_camera")
local ScriptViewport = require("scripts/foundation/utilities/script_viewport")
local ScriptWorld = require("scripts/foundation/utilities/script_world")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIScenegraph = require("scripts/managers/ui/ui_scenegraph")

local primary_viewport_name = "player1"
local right_viewport_name = "darktidevr_right_eye"
local half_ipd = 0.032
local stereo_vertical_tangent_scale = 2
local ui_eye_separation = half_ipd * 2

-- Arm the gameplay-world path as well as the separately managed character-
-- select UI world. CameraManager supplies the level world's player1 camera.
local requested = true
local active = false
local failed = false
local active_manager = nil
local active_world = nil
local active_base_rotation = nil
-- `fixed` gives physical head tracking exclusive orientation ownership.
-- Future snap/smooth thumbstick turning can select `yaw_only`; that path
-- deliberately accepts only game yaw and continues rejecting pitch and roll.
local game_rotation_mode = "fixed"
-- World markers are authored as one screen-GUI pass from the cached player
-- camera. Reproject and enqueue them between the sequential eye submissions so
-- the right eye receives depth-correct marker coordinates.
local stereo_world_markers_requested = true
local world_markers_context = nil
local interaction_hud_context = nil
local world_marker_command_capture = false
local world_marker_reprojecting = false
local world_marker_left_commands = {}
local world_marker_capture_logged = false
local observed_ui_viewports = {}
local ui_stereo_spawner = nil
local ui_stereo_world = nil
local ui_stereo_right_viewport = nil
local ui_stereo_right_name = "darktidevr_main_menu_right_eye"
local ui_offscreen_requested = false -- accepted engine intermediate path
local ui_offscreen_primary_requested = true -- give each eye its own output slot
-- Native/DLAA aliases output_target to back_buffer. Override only back_buffer
-- for this control so the engine preserves that alias instead of layering a
-- distinct full-size output_target over the surface under inspection.
local ui_back_buffer_only_requested = false
local ui_offscreen_trace_requested = false
local ui_offscreen_trace_frame = 0
local ui_offscreen_trace_complete = false
local ui_offscreen_trace_warmup_frames = 180
local ui_offscreen_trace_sample_frames = 4
local ui_offscreen_active = false
local ui_left_output_target = nil
local ui_right_output_target = nil
local ui_left_render_target = nil
local ui_right_render_target = nil
local ui_left_material = nil
local ui_right_material = nil
local ui_compositor_package = "packages/ui/views/scanner_display_view/scanner_display_view"
local ui_compositor_package_reference = "DarktideVRStereoProbeCompositor"
local ui_compositor_material =
    "content/ui/materials/render_target_masks/ui_render_target_straight_blur"
-- Bounded pipeline-localization probe: show the left viewport's pre-final-blit
-- output_target beside the right viewport's completed back_buffer.  The two
-- cameras remain frozen so fixed-row artifacts can be compared directly.
local ui_compositor_left_output_probe_requested = false
local ui_compositor_package_id = nil
local ui_compositor_package_loaded = false
local ui_compositor_package_failed = false
-- Safe pre-XR fallback. The live OpenXR runtime recommendation replaces this
-- through the shared XR-state packet before eye resources are created.
-- The physical mirror is decoupled by swapchain-window WM_SIZE virtualization;
-- the remaining projection work must use an asymmetric per-eye frustum rather
-- than increasing this render extent for a symmetric overscan workaround.
local ui_eye_target_width = 2112
local ui_eye_target_height = 2304
local ui_runtime_extent_logged = false
local ui_native_capture_requested = true -- copy each completed full-origin eye
local ui_camera_output_candidate_probe_index = -1
local ui_native_observer_requested = false
local diagnostic_render_hooks_requested = false
local vertex_shader_dump_requested = false
-- PSO-time, whitelist-only substitution. Replacement shaders are validated
-- against the live shader interface before D3D12 ever sees them.
local billboard_shader_substitution_requested = true
local billboard_horizon_lock_requested = false -- enable only with the fingerprinted diagnostic sidecar
local billboard_selector_probe_requested = false
local ui_table4_alias_probe_requested = false -- unsafe without exact draw identity
local ui_present_capture_requested = false
local ui_alternating_full_requested = false
local ui_top_bottom_requested = false -- shared-surface layouts are diagnostic only
local ui_alternating_full_eye = 0
local ui_alternating_full_last_present = nil
local ui_double_render_probe_requested = false
local ui_sequential_render_requested = false -- native capture owns sequencing
local ui_native_capture_active = false
local ui_native_capture = nil
local ui_native_capture_last_result = nil
local ui_native_sync_initialized = false
local ui_native_sync_last_result = nil
local ui_native_sync_timeout_ms = 100
local ui_native_sync_requested = false -- Lua blocks renderer submission; falsified
-- Bounded causal probe: Darktide exposes only a global DLSS history reset.
-- Reset before both sequential eyes to prevent either camera consuming the
-- other eye's history. This intentionally sacrifices temporal accumulation.
local ui_reset_dlss_each_eye_requested = false
-- Native/no-upscaler probe: after each sequential world submission, copy the
-- directly rendered swapchain before the following eye can overwrite it.
local ui_direct_swapchain_capture_requested = false
local ui_boundary_census_requested = false -- expensive diagnostic logging only
local ui_mirror_client_width = 0
local ui_mirror_client_height = 0
local ui_virtual_client_extent_requested = false
local ui_virtual_size_message_requested = true
local head_pose_values = nil
local head_pose_sequence = nil
local head_tracking_requested = true
local head_translation_requested = true -- additive camera-only room-scale lean
local head_pose_last_sequence = 0
local head_render_vertical_fov = nil
local head_render_aspect_ratio = nil
local head_render_frusta = nil
local render_timing_label = nil
local render_timing_frequency = nil
local render_timing_samples = 0
local render_timing_left_ticks = 0
local render_timing_right_ticks = 0
local render_timing_pair_ticks = 0
local render_timing_left_max_ticks = 0
local render_timing_right_max_ticks = 0
local render_timing_pair_max_ticks = 0
local gpu_profile_values = nil
local gpu_stage_profile_values = nil
local controller_observation = {
    values = nil,
    tracking_flags = nil,
    buttons = nil,
    sequence = nil,
    timestamp_ns = nil,
    last_sequence = 0,
    first_tracked_logged = false,
    right_aim_usable = false,
    right_aim_age_ms = math.huge,
    right_aim_flags = 0,
    right_aim_yaw = nil,
    right_aim_pitch = nil,
    right_aim_roll = nil,
    body_yaw_anchor = nil,
    authoring_enabled = false,
    authoring_pose_active = false,
    authoring_last_check_t = -math.huge,
    authoring_writes = 0,
    epoch_block_sequence = -1,
    downstream_last_sequence = 0,
    downstream_missing_logged = false,
    first_person_seam_last_sequence = 0,
    first_person_seam_last_log_t = -math.huge
}
local performance_profile_requested = false -- opt-in diagnostic; allocates GPU timestamp work
-- Reuse the shading/LOD preparation performed by the primary eye. The second
-- eye still receives a complete native Application.render_world submission.
local reuse_prepared_frame_requested = true
local reuse_prepared_frame_failed = false
local ui_native_observer_last_present = 0
local main_menu_ui_hidden = true
local ui_swap_viewport_halves_requested = false -- bounded identity probe; normal mapping restored
local ui_focused_ab_trace_requested = false
-- One bounded causal probe: only the observed physical-right, six-index batch
-- with cached PSO fingerprint 6427276088126068298 is clamped to the left-eye
-- instance count. Revert to false immediately after the capture.
local ui_candidate_instance_clamp_requested = false
-- Second bounded test for the same PSO: pair its unique per-frame left/right
-- batch, require compatible table-4 layouts, alias only that right batch to
-- the left data, and retain the already-falsified count clamp as a control.
local ui_candidate_table4_probe_requested = false
-- Bounded architecture probe: build both eyes at the known-rich logical
-- right-half center, tag the left with a tiny X offset, and let the native
-- command-list hook remap both raster outputs to true SBS halves.
local ui_rich_center_sbs_remap_requested = false
local ui_full_origin_ab_requested = false
local ui_full_origin_ab_start_present = nil
local ui_full_origin_ab_phase_presents = 4800
local ui_full_origin_ab_duplicate_active = false
local ui_full_origin_ab_complete = false
local ui_camera_freeze_requested = false -- normal tracked-camera behavior
local ui_camera_freeze_start_present = nil
local ui_camera_freeze_warmup_presents = 0
local ui_camera_frozen_position = nil
local ui_camera_frozen_rotation = nil
local ui_base_vertical_fov = nil
local ui_rect_matrix_requested = false
local ui_rect_matrix_start_present = nil
local ui_rect_matrix_phase = 0
local ui_rect_matrix_phase_presents = 2400
local ui_rect_matrix_complete = false
-- Capture-only four-rectangle pass census. One frozen primary camera is
-- sampled for two presents at each known detail tier after a short settle.
local ui_rect_trace_requested = false
local ui_rect_trace_phase = 0
local ui_rect_trace_phase_start_present = nil
local ui_rect_trace_sample_start_present = nil
local ui_rect_trace_sampling = false
local ui_rect_trace_complete = false
local ui_rect_trace_warmup_presents = 120
local ui_rect_trace_sample_presents = 2
local ui_focused_ab_trace_frame = 0
local ui_focused_ab_trace_complete = false
local ui_focused_ab_warmup_frames = 180
local ui_focused_ab_sample_frames = 3
-- Armed only for the current assertion-bypass feasibility run. Revert to false
-- immediately after the bounded test.
local ui_stereo_requested = true -- zero-IPD stereo cached-pipeline census
local presentation = {
    sequence = 0,
    mode = nil,
    fullscreen_view_signature = "",
    fullscreen_empty_updates = 0,
    fullscreen_restore_delay_updates = 12,
    logged_view_classification = {},
    psykhanium = {
        stage = "idle",
        deadline = 0,
        last_error = nil,
    },
    explicit_flat_menu_views = {
        system_view = true,
        options_view = true,
        player_character_options_view = true,
        custom_settings_view = true,
        social_menu_roster_view = true,
        mission_voting_view = true,
    },
    flat_loading_views = {
        loading_view = true,
        mission_intro_view = true,
        video_view = true,
        splash_video_view = true,
        cutscene_view = true,
    },
    non_gameplay_views = {
        splash_view = true,
        title_view = true,
        class_selection_view = true,
        main_menu_view = true,
        main_menu_background_view = true,
    },
}

-- Stingray 1.6 exposed a native SteamVR namespace when its VR subsystem was
-- compiled in. Record presence only; do not call or mutate an undocumented
-- backend in the correctness build.
mod:info(
    "DARKTIDEVR_STEREO engine_vr_namespace SteamVR=%s SteamVRSystem=%s OpenVR=%s",
    type(rawget(_G, "SteamVR")),
    type(rawget(_G, "SteamVRSystem")),
    type(rawget(_G, "OpenVR"))
)

local function ensure_ui_native_hooks()
    if ui_native_capture then
        return true
    end

    local ffi = Mods and Mods.lua and Mods.lua.ffi

    if not ffi then
        mod:error("DARKTIDEVR_STEREO native_capture ffi_unavailable")
        return false
    end

    pcall(ffi.cdef, [[
        int dtvr_install(void);
        int dtvr_set_projection_active(int enabled);
        int dtvr_set_presentation_state(unsigned int mode, unsigned long long sequence,
            unsigned int source_width, unsigned int source_height,
            unsigned int crop_x, unsigned int crop_y,
            unsigned int crop_width, unsigned int crop_height,
            float maximum_panel_width_metres,
            float maximum_panel_height_metres);
        int dtvr_capture_eye(int eye);
        int dtvr_capture_armed_swapchain_eye(int eye);
        int dtvr_set_camera_output_candidate_index(int index);
        int dtvr_arm_eye_capture(int eye);
        int dtvr_arm_eye_capture_pose(int eye, unsigned long long pose_sequence);
        int dtvr_reset_eye_capture_tags(void);
        int dtvr_wait_eye_capture_count(int eye, unsigned long long target, unsigned int timeout_ms);
        int dtvr_set_swapchain_render_extent(unsigned long long width, unsigned int height);
        int dtvr_enable_boundary_census(void);
        int dtvr_set_mirror_client_extent(unsigned int width, unsigned int height);
        int dtvr_set_virtual_client_extent(int enabled);
        int dtvr_set_virtual_size_message(int enabled);
        int dtvr_lock_swapchain_client_extent(int enabled);
        int dtvr_set_render_projection(float vertical_fov_radians, float aspect_ratio);
        unsigned long long dtvr_boundary_arm_count(void);
        unsigned long long dtvr_boundary_transition_count(void);
        unsigned long long dtvr_boundary_eye_capture_count(int eye);
        unsigned long long dtvr_boundary_eye_pose_sequence(int eye);
        unsigned long long dtvr_boundary_tag_queue_depth(void);
        unsigned long long dtvr_boundary_tag_reset_count(void);
        unsigned long long dtvr_ready_value(void);
        unsigned long long dtvr_execute_call_count(void);
        unsigned long long dtvr_present_count(void);
        int dtvr_capture_stage(void);
        int dtvr_enable_present_capture(void);
        int dtvr_disable_present_capture(void);
        int dtvr_enable_alternating_full_capture(void);
        int dtvr_disable_alternating_full_capture(void);
        int dtvr_set_alternating_present_eye(int eye);
        int dtvr_enable_top_bottom_capture(void);
        int dtvr_disable_top_bottom_capture(void);
        unsigned long long dtvr_alternating_eye_copy_count(int eye);
        unsigned long long dtvr_alternating_eye_tag_count(void);
        int dtvr_alternating_last_capture_result(void);
        int dtvr_enable_table4_alias(void);
        int dtvr_disable_table4_alias(void);
        unsigned long long dtvr_table4_alias_count(void);
        unsigned long long dtvr_table4_exact_match_count(void);
        unsigned long long dtvr_table4_exact_ambiguous_count(void);
        int dtvr_enable_candidate_instance_clamp(void);
        int dtvr_disable_candidate_instance_clamp(void);
        unsigned long long dtvr_candidate_instance_clamp_count(void);
        int dtvr_enable_candidate_table4_alias(void);
        int dtvr_disable_candidate_table4_alias(void);
        unsigned long long dtvr_candidate_table4_alias_count(void);
        unsigned long long dtvr_candidate_table4_match_count(void);
        unsigned long long dtvr_candidate_table4_ambiguous_count(void);
        int dtvr_enable_rich_center_sbs_remap(void);
        int dtvr_disable_rich_center_sbs_remap(void);
        int dtvr_set_focused_trace_phase(int phase);
        unsigned long long dtvr_focused_trace_count(void);
        int dtvr_enable_marker_log(void);
        int dtvr_set_diagnostic_render_hooks(int enabled);
        int dtvr_set_billboard_shader_substitution(int enabled);
        unsigned long long dtvr_billboard_shader_substitution_count(void);
        unsigned long long dtvr_billboard_shader_substitution_reject_count(void);
        unsigned long long dtvr_billboard_shader_substitution_result_count(
            unsigned int rank, unsigned int kind);
        int dtvr_set_vertex_shader_dump(int enabled);
        int dtvr_set_billboard_view_basis(float right_x, float right_y,
            float right_z, float up_x, float up_y,
            float up_z, int enabled);
        int dtvr_set_billboard_staging_view_basis(float right_x, float right_y,
            float right_z, float up_x, float up_y,
            float up_z, int enabled);
        unsigned long long dtvr_billboard_stride_candidate_count(void);
        unsigned long long dtvr_billboard_b1_bound_count(void);
        unsigned long long dtvr_billboard_b2_bound_count(void);
        unsigned long long dtvr_billboard_exact_shader_draw_count(void);
        unsigned long long dtvr_billboard_exact_pso_draw_count(void);
        unsigned long long dtvr_billboard_exact_pso_cbv_slot_count(
            unsigned int slot);
        unsigned long long dtvr_billboard_exact_pso_table_slot_count(
            unsigned int slot);
        unsigned long long dtvr_billboard_exact_register_count(
            unsigned int shader_register);
        unsigned long long dtvr_billboard_exact_vertex_table_slot_count(
            unsigned int slot);
        unsigned long long dtvr_billboard_exact_descriptor_offset_count(
            unsigned int offset);
        unsigned long long dtvr_billboard_exact_table_span_count(
            unsigned int span);
        unsigned long long dtvr_billboard_exact_cbv_descriptor_count(void);
        unsigned long long dtvr_billboard_exact_buffer_resource_count(void);
        unsigned long long dtvr_billboard_exact_heap_type_count(
            unsigned int heap_type);
        unsigned long long dtvr_billboard_exact_map_success_count(void);
        unsigned long long dtvr_billboard_exact_map_failure_count(void);
        unsigned long long dtvr_billboard_resource_map_count(void);
        unsigned long long dtvr_billboard_resource_map_match_count(void);
        unsigned long long dtvr_billboard_resource_unmap_count(void);
        unsigned long long dtvr_billboard_selected_map_stack_count(void);
        unsigned long long dtvr_billboard_upload_flush_count(void);
        int dtvr_billboard_upload_flush_hook_state(void);
        unsigned long long dtvr_billboard_selected_cpu_address(void);
        unsigned long long dtvr_billboard_selected_gpu_address(void);
        unsigned long long dtvr_billboard_selected_size(void);
        unsigned long long dtvr_billboard_shadow_stage_count(
            unsigned int stage);
        unsigned long long dtvr_billboard_exact_command_list_type_count(
            unsigned int type);
        unsigned long long dtvr_billboard_exact_root_mapping_count(void);
        unsigned long long dtvr_billboard_root_metadata_draw_count(void);
        unsigned long long dtvr_diagnostic_root_signature_create_count(void);
        unsigned long long dtvr_diagnostic_graphics_pso_create_count(void);
        unsigned long long dtvr_diagnostic_compute_pso_create_count(void);
        unsigned long long dtvr_diagnostic_stream_pso_create_count(void);
        unsigned long long dtvr_diagnostic_graphics_pipeline_load_count(void);
        unsigned long long dtvr_diagnostic_compute_pipeline_load_count(void);
        unsigned long long dtvr_diagnostic_stream_pipeline_load_count(void);
        unsigned long long dtvr_billboard_root_b2_candidate_draw_count(void);
        unsigned long long dtvr_billboard_candidate_shader_hash(unsigned int rank);
        unsigned long long dtvr_billboard_candidate_shader_count(unsigned int rank);
        unsigned int dtvr_billboard_candidate_shader_hash_low(unsigned int rank);
        unsigned int dtvr_billboard_candidate_shader_hash_high(unsigned int rank);
        unsigned long long dtvr_billboard_table_b2_draw_count(void);
        unsigned long long dtvr_billboard_bound_table_b2_draw_count(void);
        unsigned long long dtvr_billboard_observed_draw_count(void);
        unsigned long long dtvr_billboard_direct_draw_hook_count(void);
        int dtvr_billboard_probe_state(void);
        unsigned long long dtvr_billboard_observed_stride_count(
            unsigned int slot, unsigned int stride);
        unsigned long long dtvr_billboard_basis_patch_count(void);
        int dtvr_read_head_pose(float *values, unsigned long long *sequence);
        int dtvr_read_controller_state(float *values,
            unsigned int *tracking_flags, unsigned int *buttons,
            unsigned long long *sequence,
            unsigned long long *timestamp_ns);
        unsigned long long dtvr_qpc_ticks(void);
        unsigned long long dtvr_qpc_frequency(void);
        int dtvr_take_gpu_eye_profile(int eye, unsigned long long *values);
        int dtvr_take_gpu_stage_profile(int eye, unsigned long long *values);
        int dtvr_set_gpu_eye_profile(int enabled);
    ]])

    local ok, library = pcall(
        ffi.load,
        "../mods/darktidevr_stereo_probe/bin/darktidevr_native_capture.dll"
    )

    if not ok then
        mod:error("DARKTIDEVR_STEREO native_capture load_failed error=%s", tostring(library))
        return false
    end

    local diagnostic_result = library.dtvr_set_diagnostic_render_hooks(
        (diagnostic_render_hooks_requested or vertex_shader_dump_requested or
            billboard_horizon_lock_requested or
            billboard_selector_probe_requested or
            ui_native_observer_requested or
            performance_profile_requested) and
            1 or 0)
    if diagnostic_result ~= 0 then
        mod:error("DARKTIDEVR_STEREO diagnostic_hook_select_failed code=%d",
            diagnostic_result)
        return false
    end

    local substitution_result = library.dtvr_set_billboard_shader_substitution(
        billboard_shader_substitution_requested and 1 or 0)
    if substitution_result ~= 0 then
        mod:error("DARKTIDEVR_STEREO billboard_shader_substitution_select_failed code=%d",
            substitution_result)
        return false
    end

    local shader_dump_result = library.dtvr_set_vertex_shader_dump(
        vertex_shader_dump_requested and 1 or 0)
    if shader_dump_result ~= 0 then
        mod:error("DARKTIDEVR_STEREO shader_dump_select_failed code=%d",
            shader_dump_result)
        return false
    end

    local install_result = library.dtvr_install()

    if install_result ~= 0 then
        mod:error("DARKTIDEVR_STEREO native_capture install_failed code=%d", install_result)
        return false
    end

    -- Selector-only diagnostics must be active before any particular camera
    -- path exists. Character select uses UIWorldSpawner rather than the
    -- gameplay CameraManager, so enabling this only from update_stereo left
    -- the native draw hooks active while the dry selector itself stayed off.
    -- Mode 2 records state and categorizes draws but is hard-disabled from
    -- issuing any GPU writes.
    if billboard_horizon_lock_requested then
        -- Darktide is Z-up. c_billboard.view columns 0 and 2 are the sprite's
        -- screen-facing right and up axes, not right and camera-forward.
        library.dtvr_set_billboard_staging_view_basis(
            1, 0, 0,
            0, 0, 1,
            1
        )
    elseif billboard_selector_probe_requested then
        library.dtvr_set_billboard_view_basis(
            1, 0, 0,
            0, 1, 0,
            2
        )
    end

    if vertex_shader_dump_requested then
        library.dtvr_enable_marker_log()
    end

    ui_native_capture = library
    ui_native_capture.dtvr_set_projection_active(0)
    head_pose_values = ffi.new("float[20]")
    head_pose_sequence = ffi.new("unsigned long long[1]")
    controller_observation.values = ffi.new("float[36]")
    controller_observation.tracking_flags = ffi.new("unsigned int[4]")
    controller_observation.buttons = ffi.new("unsigned int[2]")
    controller_observation.sequence = ffi.new("unsigned long long[1]")
    controller_observation.timestamp_ns = ffi.new("unsigned long long[1]")
    gpu_profile_values = ffi.new("unsigned long long[4]")
    gpu_stage_profile_values = ffi.new("unsigned long long[6]")
    ui_native_capture.dtvr_set_gpu_eye_profile(
        performance_profile_requested and 1 or 0)
    mod:info("DARKTIDEVR_STEREO native_hooks installed")
    if billboard_shader_substitution_requested then
        mod:info(
            "DARKTIDEVR_STEREO billboard_shader_substitution applied=%d rejected=%d",
            tonumber(library.dtvr_billboard_shader_substitution_count()),
            tonumber(library.dtvr_billboard_shader_substitution_reject_count())
        )
        local shader_labels = {
            "6e5fa4d1f1e2cd16", "25920ba45ba58e76",
            "af848a96a230342a", "903cb53d8ac05f28",
            "13e04962148fc216"
        }
        for rank = 0, #shader_labels - 1 do
            mod:info(
                "DARKTIDEVR_STEREO billboard_shader_result hash=%s attempts=%d applied=%d validation_rejects=%d creation_rejects=%d",
                shader_labels[rank + 1],
                tonumber(library.dtvr_billboard_shader_substitution_result_count(rank, 0)),
                tonumber(library.dtvr_billboard_shader_substitution_result_count(rank, 1)),
                tonumber(library.dtvr_billboard_shader_substitution_result_count(rank, 2)),
                tonumber(library.dtvr_billboard_shader_substitution_result_count(rank, 3))
            )
        end
    end

    return true
end

function presentation.publish_mode(mode, reason)
    if not ui_native_capture or presentation.mode == mode then
        return
    end
    presentation.sequence = presentation.sequence + 1
    local result = tonumber(ui_native_capture.dtvr_set_presentation_state(
        mode,
        presentation.sequence,
        ui_eye_target_width,
        ui_eye_target_height,
        0,
        0,
        ui_eye_target_width,
        ui_eye_target_height,
        2,
        2
    ))
    if result ~= 0 then
        mod:error(
            "DARKTIDEVR_PRESENTATION publish_failed mode=%d sequence=%d code=%d",
            mode,
            presentation.sequence,
            result
        )
        return
    end
    presentation.mode = mode
    mod:info(
        "DARKTIDEVR_PRESENTATION mode=%d sequence=%d reason=%s source=%dx%d",
        mode,
        presentation.sequence,
        tostring(reason),
        ui_eye_target_width,
        ui_eye_target_height
    )
end

function presentation.classify_active_view(manager, view_name)
    if presentation.non_gameplay_views[view_name] then
        return nil, "non_gameplay"
    end
    if presentation.flat_loading_views[view_name] then
        return 2, "loading_or_cinematic"
    end

    local settings = nil
    local handler = manager and manager._view_handler
    if handler and handler.settings_by_view_name then
        local ok, value = pcall(handler.settings_by_view_name, handler, view_name)
        if ok then
            settings = value
        end
    end
    local disables_world = settings and settings.disable_game_world == true
    local explicit = presentation.explicit_flat_menu_views[view_name] == true
    -- View identity and settings are authoritative. The shared `active` flag
    -- tracks whichever stereo world was most recently constructed and can be
    -- cleared by destruction of the old character-select world after the hub
    -- camera is already live.
    local classification = (disables_world or explicit) and 4 or nil
    if not presentation.logged_view_classification[view_name] then
        presentation.logged_view_classification[view_name] = true
        mod:info(
            "DARKTIDEVR_PRESENTATION classify view=%s class=%s disable_game_world=%s allow_hud=%s",
            tostring(view_name),
            classification == 4 and "flat_menu" or "ignored",
            tostring(settings and settings.disable_game_world),
            tostring(settings and settings.allow_hud)
        )
    end
    return classification, disables_world and "disable_game_world" or
        (explicit and "explicit" or "spatial_or_hud")
end

function presentation.reconcile_fullscreen_views(manager)
    if not ui_native_capture or not manager or not manager.active_views then
        return
    end
    local ok, views = pcall(manager.active_views, manager)
    if not ok or type(views) ~= "table" then
        return
    end

    local classified = {}
    local desired_mode = nil
    for i = 1, #views do
        local view_name = views[i]
        local mode, reason = presentation.classify_active_view(manager, view_name)
        if mode then
            classified[#classified + 1] = tostring(view_name) .. ":" .. reason
            if mode == 2 or not desired_mode then
                desired_mode = mode
            end
        end
    end
    local signature = table.concat(classified, ",")
    if signature ~= presentation.fullscreen_view_signature then
        presentation.fullscreen_view_signature = signature
        mod:info(
            "DARKTIDEVR_PRESENTATION fullscreen_stack count=%d views=%s",
            #classified,
            signature ~= "" and signature or "none"
        )
    end

    if desired_mode then
        presentation.fullscreen_empty_updates = 0
        presentation.publish_mode(desired_mode, signature)
    elseif presentation.mode == 4 then
        presentation.fullscreen_empty_updates =
            presentation.fullscreen_empty_updates + 1
        if presentation.fullscreen_empty_updates >=
                presentation.fullscreen_restore_delay_updates then
            presentation.fullscreen_empty_updates = 0
            presentation.publish_mode(1, "fullscreen_stack_empty")
        end
    elseif presentation.mode ~= 1 then
        presentation.publish_mode(1, "stereo_world")
    end
end

function presentation.on_view_open(manager, view_name)
    local active_ok, is_active = pcall(manager.view_active, manager, view_name)
    mod:info(
        "DARKTIDEVR_PRESENTATION open view=%s active=%s",
        tostring(view_name),
        tostring(active_ok and is_active)
    )
    if active_ok and is_active then
        local mode, reason = presentation.classify_active_view(manager, view_name)
        if mode then
            presentation.fullscreen_empty_updates = 0
            presentation.publish_mode(mode, tostring(view_name) .. ":" .. reason)
        end
    end
end

function presentation.on_view_close(manager, view_name)
    mod:info(
        "DARKTIDEVR_PRESENTATION close view=%s",
        tostring(view_name)
    )
    presentation.reconcile_fullscreen_views(manager)
end

function presentation.trigger_widget(manager, view_name, widget_name)
    local view = manager:view_instance(view_name)
    if not view or type(view.widgets_by_name) ~= "function" or
            type(view.widget_hotspot_content) ~= "function" then
        return false, "view_instance_not_ready"
    end
    local widgets = view:widgets_by_name()
    local widget = widgets and widgets[widget_name]
    local hotspot = widget and view:widget_hotspot_content(widget_name)
    if not widget or not hotspot then
        return false, "widget_not_ready"
    end
    if hotspot.disabled then
        return false, "widget_disabled"
    end
    if type(hotspot.pressed_callback) ~= "function" then
        return false, "pressed_callback_missing"
    end
    local ok, error_message = pcall(hotspot.pressed_callback)
    if not ok then
        return false, tostring(error_message)
    end
    return true, nil
end

function presentation.update_psykhanium(manager, t)
    local state = presentation.psykhanium
    if state.stage == "idle" and Mods and Mods.lua and Mods.lua.io then
        local flag_path =
            "./../mods/darktidevr_stereo_probe/darktidevr_enter_psykhanium.flag"
        local flag = Mods.lua.io.open(flag_path, "r")
        if flag then
            local request = flag:read("*all")
            flag:close()
            if string.find(request or "", "enter", 1, true) then
                local consumed = Mods.lua.io.open(flag_path, "w")
                if consumed then
                    consumed:write("consumed\n")
                    consumed:close()
                end
                state.stage = "wait_for_hub"
                state.deadline = t + 300
                state.last_error = nil
                mod:info("DARKTIDEVR_PSYKHANIUM armed source=one_shot_flag")
            end
        end
    end
    if state.stage == "idle" or state.stage == "complete" or
            state.stage == "blocked" then
        return
    end
    if t > state.deadline then
        state.stage = "blocked"
        state.last_error = "timeout"
        mod:error("DARKTIDEVR_PSYKHANIUM blocked reason=timeout")
        return
    end

    if state.stage == "wait_for_hub" then
        if not Managers.state or not Managers.state.game_mode or
                not Managers.backend then
            return
        end
        local mode_ok, game_mode = pcall(
            Managers.state.game_mode.game_mode_name,
            Managers.state.game_mode)
        local auth_ok, authenticated = pcall(
            Managers.backend.authenticated,
            Managers.backend)
        if not mode_ok or game_mode ~= "hub" or
                not auth_ok or not authenticated then
            return
        end
        state.stage = "open_training_view"
        state.deadline = t + 20
        mod:info("DARKTIDEVR_PSYKHANIUM stage=open_training_view")
    end

    if state.stage == "open_training_view" then
        if manager:view_active("training_grounds_view") then
            state.stage = "select_shooting_range"
            state.deadline = t + 20
            mod:info("DARKTIDEVR_PSYKHANIUM stage=select_shooting_range")
            return
        end
        local ok, result = pcall(
            manager.open_view, manager, "training_grounds_view")
        if not ok then
            state.stage = "blocked"
            state.last_error = tostring(result)
            mod:error(
                "DARKTIDEVR_PSYKHANIUM blocked stage=open_training_view error=%s",
                state.last_error)
        else
            state.stage = "wait_training_view"
            state.deadline = t + 20
            mod:info("DARKTIDEVR_PSYKHANIUM stage=wait_training_view")
        end
        return
    end

    if state.stage == "wait_training_view" and
            manager:view_active("training_grounds_view") then
        state.stage = "select_shooting_range"
    end
    if state.stage == "select_shooting_range" then
        local ok, reason = presentation.trigger_widget(
            manager, "training_grounds_view", "option_button_3")
        if ok then
            state.stage = "wait_options_view"
            state.deadline = t + 20
            mod:info("DARKTIDEVR_PSYKHANIUM stage=wait_options_view")
        elseif reason == "widget_disabled" then
            state.stage = "blocked"
            state.last_error = reason
            mod:error(
                "DARKTIDEVR_PSYKHANIUM blocked stage=select_shooting_range reason=%s",
                reason)
        end
        return
    end

    if state.stage == "wait_options_view" and
            manager:view_active("training_grounds_options_view") then
        local ok, reason = presentation.trigger_widget(
            manager, "training_grounds_options_view", "play_button")
        if ok then
            state.stage = "wait_shooting_range"
            state.deadline = t + 90
            mod:info("DARKTIDEVR_PSYKHANIUM stage=wait_shooting_range")
        elseif reason == "widget_disabled" then
            state.stage = "blocked"
            state.last_error = reason
            mod:error(
                "DARKTIDEVR_PSYKHANIUM blocked stage=play reason=%s", reason)
        end
        return
    end

    if state.stage == "wait_shooting_range" and Managers.state and
            Managers.state.game_mode and
            type(Managers.state.game_mode.game_mode_name) == "function" then
        local ok, game_mode = pcall(
            Managers.state.game_mode.game_mode_name,
            Managers.state.game_mode)
        if ok and (game_mode == "shooting_range" or
                game_mode == "training_grounds") then
            state.stage = "complete"
            state.last_error = nil
            mod:info(
                "DARKTIDEVR_PSYKHANIUM result=pass game_mode=%s",
                tostring(game_mode))
        end
    end
end

local function refresh_xr_render_extent()
    if not ui_native_capture or not head_pose_values or not head_pose_sequence then
        return false
    end

    if ui_native_capture.dtvr_read_head_pose(
            head_pose_values, head_pose_sequence) ~= 0 then
        return false
    end

    local width = math.floor(tonumber(head_pose_values[17]) + 0.5)
    local height = math.floor(tonumber(head_pose_values[18]) + 0.5)
    if width < 640 or width > 7680 or height < 640 or height > 7680 then
        return false
    end

    if width ~= ui_eye_target_width or height ~= ui_eye_target_height then
        mod:info(
            "DARKTIDEVR_STEREO runtime_extent %dx%d fallback=%dx%d",
            width, height, ui_eye_target_width, ui_eye_target_height
        )
        ui_eye_target_width = width
        ui_eye_target_height = height
    end
    if not ui_runtime_extent_logged then
        mod:info(
            "DARKTIDEVR_STEREO render_extent source=openxr size=%dx%d",
            width, height
        )
        ui_runtime_extent_logged = true
    end
    return true
end

local function apply_head_tracking(clean_position, clean_rotation)
    if not head_tracking_requested or not ui_native_capture or
            not head_pose_values or not head_pose_sequence then
        return clean_position, clean_rotation
    end

    local result = ui_native_capture.dtvr_read_head_pose(
        head_pose_values,
        head_pose_sequence
    )

    if result ~= 0 then
        return clean_position, clean_rotation
    end

    local sequence = tonumber(head_pose_sequence[0])
    local render_vertical_fov = tonumber(head_pose_values[7])
    local render_aspect_ratio = tonumber(head_pose_values[8])
    if render_vertical_fov > 0 and render_vertical_fov < math.pi and
            render_aspect_ratio > 0 then
        head_render_vertical_fov = render_vertical_fov
        head_render_aspect_ratio = render_aspect_ratio
    end
    local left_frustum = {
        left = tonumber(head_pose_values[9]),
        right = tonumber(head_pose_values[10]),
        down = tonumber(head_pose_values[11]),
        up = tonumber(head_pose_values[12])
    }
    local right_frustum = {
        left = tonumber(head_pose_values[13]),
        right = tonumber(head_pose_values[14]),
        down = tonumber(head_pose_values[15]),
        up = tonumber(head_pose_values[16])
    }
    local function valid_frustum(frustum)
        return frustum.left == frustum.left and
            frustum.right == frustum.right and
            frustum.down == frustum.down and
            frustum.up == frustum.up and
            frustum.left > -math.pi * 0.5 and
            frustum.right < math.pi * 0.5 and
            frustum.down > -math.pi * 0.5 and
            frustum.up < math.pi * 0.5 and
            frustum.left < frustum.right and
            frustum.down < frustum.up
    end
    if valid_frustum(left_frustum) and valid_frustum(right_frustum) then
        head_render_frusta = { left_frustum, right_frustum }
    end
    local runtime_ipd = tonumber(head_pose_values[19])
    -- The native reader rejects stale snapshots. Clear usability before each
    -- attempt so a failed read can never leave the previous pose live.
    controller_observation.right_aim_usable = false
    if controller_observation.values and
            ui_native_capture.dtvr_read_controller_state(
                controller_observation.values,
                controller_observation.tracking_flags,
                controller_observation.buttons,
                controller_observation.sequence,
                controller_observation.timestamp_ns) == 0 then
        local controller_sequence = tonumber(controller_observation.sequence[0])
        if controller_sequence < controller_observation.last_sequence then
            -- A new harness/XR session starts controller sequencing at one.
            -- Capture a new game-world yaw when its first pose reaches the
            -- active orientation class.
            controller_observation.body_yaw_anchor = nil
            controller_observation.first_person_seam_last_sequence = 0
            -- One complete fresh sample must follow an epoch transition before
            -- authoring can resume.
            controller_observation.epoch_block_sequence = controller_sequence
        end
        controller_observation.last_sequence = controller_sequence
        local left_aim_flags = tonumber(controller_observation.tracking_flags[0])
        local right_aim_flags = tonumber(controller_observation.tracking_flags[2])
        controller_observation.right_aim_flags = right_aim_flags
        local controller_timestamp_ns =
            tonumber(controller_observation.timestamp_ns[0])
        local qpc_frequency =
            tonumber(ui_native_capture.dtvr_qpc_frequency())
        local controller_age_ns = math.huge
        if qpc_frequency > 0 then
            controller_age_ns =
                tonumber(ui_native_capture.dtvr_qpc_ticks()) *
                    1000000000 / qpc_frequency - controller_timestamp_ns
        end
        controller_observation.right_aim_age_ms = controller_age_ns / 1000000
        controller_observation.right_aim_usable =
            bit.band(right_aim_flags, 5) == 5 and
            controller_age_ns >= -5000000 and
            controller_age_ns <= 100000000 and
            controller_sequence ~= controller_observation.epoch_block_sequence
        if controller_observation.right_aim_usable then
            local right_aim_rotation = Quaternion.from_elements(
                controller_observation.values[21],
                controller_observation.values[22],
                controller_observation.values[23],
                controller_observation.values[24]
            )
            controller_observation.right_aim_yaw,
                controller_observation.right_aim_pitch,
                controller_observation.right_aim_roll =
                    Quaternion.to_yaw_pitch_roll(right_aim_rotation)
        end
        if not controller_observation.first_tracked_logged and
                (bit.band(left_aim_flags, 4) ~= 0 or
                 bit.band(right_aim_flags, 4) ~= 0) then
            controller_observation.first_tracked_logged = true
            mod:info("DARKTIDEVR_CONTROLLER observed sequence=%d left_aim_flags=%d right_aim_flags=%d right_aim_age_ms=%.3f usable=%s",
                controller_sequence,
                left_aim_flags,
                right_aim_flags,
                controller_observation.right_aim_age_ms,
                tostring(controller_observation.right_aim_usable))
        end
    end
    local character_scale = 1
    local local_player = Managers and Managers.player and
        Managers.player:local_player(1)
    local archetype_name = local_player and local_player:archetype_name()
    if archetype_name == "ogryn" then
        -- Darktide's reviewed breed data uses 1.61 m for the Ogryn player
        -- height and 1.21 m for the baseline human. Scale physical head
        -- translation and the runtime eye separation together so the larger
        -- character sees a consistently smaller world.
        character_scale = 1.61 / 1.21
    end
    if runtime_ipd >= 0.03 and runtime_ipd <= 0.10 then
        half_ipd = runtime_ipd * character_scale * 0.5
        ui_eye_separation = half_ipd * 2
    end
    local head_rotation = Quaternion.from_elements(
        head_pose_values[3],
        -head_pose_values[5],
        head_pose_values[4],
        head_pose_values[6]
    )
    local tracked_rotation = Quaternion.multiply(clean_rotation, head_rotation)
    local tracked_position = clean_position

    if head_translation_requested then
        local local_x = head_pose_values[0] * character_scale
        local local_y = -head_pose_values[2] * character_scale
        local local_z = head_pose_values[1] * character_scale
        tracked_position = clean_position +
            Quaternion.right(clean_rotation) * local_x +
            Quaternion.forward(clean_rotation) * local_y +
            Quaternion.up(clean_rotation) * local_z
    end

    if head_pose_last_sequence == 0 then
        mod:info("DARKTIDEVR_STEREO head_tracking active mode=%s sequence=%d runtime_ipd=%.4f character_scale=%.3f",
            head_translation_requested and "6dof" or "3dof",
            sequence,
            runtime_ipd,
            character_scale)
    end
    head_pose_last_sequence = sequence

    return tracked_position, tracked_rotation
end

-- Renderer diagnostics must install while the title state is still active so
-- subsequent main-menu and gameplay package loads pass their real PSO and
-- root-signature creation descriptors through our hooks. Delaying this until
-- UIWorldSpawner.create_viewport is too late for shader/root localization.
if ui_native_observer_requested or diagnostic_render_hooks_requested or
        vertex_shader_dump_requested or billboard_horizon_lock_requested or
        billboard_selector_probe_requested or performance_profile_requested then
    ensure_ui_native_hooks()
end

local function enable_ui_native_capture()
    if not ensure_ui_native_hooks() then
        return false
    end

    ui_native_capture_active = true
    ui_native_capture_last_result = nil
    ui_native_sync_initialized = false
    ui_native_sync_last_result = nil
    refresh_xr_render_extent()

    if ui_boundary_census_requested then
        local census_result = ui_native_capture.dtvr_enable_boundary_census()
        if census_result ~= 0 then
            mod:error("DARKTIDEVR_STEREO boundary_census_failed code=%d",
                tonumber(census_result))
        end
    end

    local mirror_result = ui_native_capture.dtvr_set_mirror_client_extent(
        ui_mirror_client_width,
        ui_mirror_client_height
    )
    if mirror_result ~= 0 then
        mod:error("DARKTIDEVR_STEREO mirror_extent_failed code=%d",
            tonumber(mirror_result))
    end

    local virtual_client_result =
        ui_native_capture.dtvr_set_virtual_client_extent(
            ui_virtual_client_extent_requested and 1 or 0
        )
    if virtual_client_result ~= 0 then
        mod:error("DARKTIDEVR_STEREO virtual_client_extent_failed code=%d",
            tonumber(virtual_client_result))
    end

    local virtual_size_message_result =
        ui_native_capture.dtvr_set_virtual_size_message(
            ui_virtual_size_message_requested and 1 or 0
        )
    if virtual_size_message_result ~= 0 then
        mod:error("DARKTIDEVR_STEREO virtual_size_message_failed code=%d",
            tonumber(virtual_size_message_result))
    end

    local extent_result = ui_native_capture.dtvr_set_swapchain_render_extent(
        ui_eye_target_width,
        ui_eye_target_height
    )
    if extent_result ~= 0 then
        mod:error("DARKTIDEVR_STEREO swapchain_extent_failed code=%d",
            tonumber(extent_result))
        ui_native_capture_active = false
        return false
    end
    local candidate_result =
        ui_native_capture.dtvr_set_camera_output_candidate_index(
            ui_camera_output_candidate_probe_index
        )
    if candidate_result ~= 0 then
        mod:error("DARKTIDEVR_STEREO candidate_select_failed code=%d",
            tonumber(candidate_result))
    end
    local client_lock_result =
        ui_native_capture.dtvr_lock_swapchain_client_extent(0)
    if client_lock_result ~= 0 then
        mod:error("DARKTIDEVR_STEREO client_extent_lock_failed code=%d",
            tonumber(client_lock_result))
        ui_native_capture_active = false
        return false
    end

    return true
end

local function report_native_observer()
    if not ui_native_capture or
            (not ui_native_observer_requested and
                not ui_present_capture_requested and
                not head_tracking_requested) then
        return
    end

    local presents = tonumber(ui_native_capture.dtvr_present_count())

    if presents >= ui_native_observer_last_present + 120 then
        local executes = tonumber(ui_native_capture.dtvr_execute_call_count())
        mod:info(
            "DARKTIDEVR_STEREO native_observer presents=%d execute_calls=%d ratio=%.3f ready=%d",
            presents,
            executes,
            executes / presents,
            tonumber(ui_native_capture.dtvr_ready_value())
        )
        if ui_table4_alias_probe_requested then
            mod:info(
                "DARKTIDEVR_STEREO table4_alias substitutions=%d",
                tonumber(ui_native_capture.dtvr_table4_alias_count())
            )
        end
        mod:info(
            "DARKTIDEVR_STEREO table4_exact matches=%d ambiguous=%d",
            tonumber(ui_native_capture.dtvr_table4_exact_match_count()),
            tonumber(ui_native_capture.dtvr_table4_exact_ambiguous_count())
        )
        mod:info(
            "DARKTIDEVR_STEREO boundary arms=%d transitions=%d captures=%d/%d pose=%d/%d queue=%d resets=%d",
            tonumber(ui_native_capture.dtvr_boundary_arm_count()),
            tonumber(ui_native_capture.dtvr_boundary_transition_count()),
            tonumber(ui_native_capture.dtvr_boundary_eye_capture_count(0)),
            tonumber(ui_native_capture.dtvr_boundary_eye_capture_count(1)),
            tonumber(ui_native_capture.dtvr_boundary_eye_pose_sequence(0)),
            tonumber(ui_native_capture.dtvr_boundary_eye_pose_sequence(1)),
            tonumber(ui_native_capture.dtvr_boundary_tag_queue_depth()),
            tonumber(ui_native_capture.dtvr_boundary_tag_reset_count())
        )
        if ui_alternating_full_requested then
            mod:info(
                "DARKTIDEVR_STEREO alternating tags=%d copies=%d/%d capture_result=%d",
                tonumber(ui_native_capture.dtvr_alternating_eye_tag_count()),
                tonumber(ui_native_capture.dtvr_alternating_eye_copy_count(0)),
                tonumber(ui_native_capture.dtvr_alternating_eye_copy_count(1)),
                tonumber(ui_native_capture.dtvr_alternating_last_capture_result())
            )
        end
        if ui_candidate_instance_clamp_requested then
            mod:info(
                "DARKTIDEVR_STEREO candidate_instance_clamp substitutions=%d",
                tonumber(ui_native_capture.dtvr_candidate_instance_clamp_count())
            )
        end
        if ui_candidate_table4_probe_requested then
            mod:info(
                "DARKTIDEVR_STEREO candidate_table4 matches=%d aliases=%d ambiguous=%d clamp=%d",
                tonumber(ui_native_capture.dtvr_candidate_table4_match_count()),
                tonumber(ui_native_capture.dtvr_candidate_table4_alias_count()),
                tonumber(ui_native_capture.dtvr_candidate_table4_ambiguous_count()),
                tonumber(ui_native_capture.dtvr_candidate_instance_clamp_count())
            )
        end
        if billboard_horizon_lock_requested or
                billboard_selector_probe_requested then
            local function top_billboard_strides(slot)
                local ranked = {}
                for stride = 0, 256 do
                    local count = tonumber(
                        ui_native_capture.dtvr_billboard_observed_stride_count(
                            slot, stride))
                    if count > 0 then
                        ranked[#ranked + 1] = { stride = stride, count = count }
                    end
                end
                table.sort(ranked, function(a, b)
                    return a.count > b.count
                end)
                local values = {}
                for index = 1, math.min(5, #ranked) do
                    values[#values + 1] = string.format(
                        "%d:%d", ranked[index].stride, ranked[index].count)
                end
                return table.concat(values, ",")
            end
            local function top_billboard_root_slots(counter, maximum)
                local ranked = {}
                for slot = 0, maximum or 31 do
                    local count = tonumber(counter(slot))
                    if count > 0 then
                        ranked[#ranked + 1] = { slot = slot, count = count }
                    end
                end
                table.sort(ranked, function(a, b)
                    return a.count > b.count
                end)
                local values = {}
                for index = 1, math.min(8, #ranked) do
                    values[#values + 1] = string.format(
                        "%d:%d", ranked[index].slot, ranked[index].count)
                end
                return table.concat(values, ",")
            end
            mod:info(
                "DARKTIDEVR_STEREO billboard state=%d hook_draws=%d observed=%d slot0=%s slot1=%s particle_layout=%d exact_pso=%d cl_types=%s registers=%s cbv_slots=%s table_slots=%s selected_tables=%s descriptor_offsets=%s table_spans=%s cbv_desc=%d buffers=%d heaps=%s map=%d/%d tracked_maps=%d/%d/%d producer_stacks=%d upload_flush=%d/%d selected=%d/%d shadow_stages=%s root_meta=%d direct_cbv=%d table_cbv=%d table_cbv_bound=%d patches=%d",
                ui_native_capture.dtvr_billboard_probe_state(),
                tonumber(ui_native_capture.dtvr_billboard_direct_draw_hook_count()),
                tonumber(ui_native_capture.dtvr_billboard_observed_draw_count()),
                top_billboard_strides(0), top_billboard_strides(1),
                tonumber(ui_native_capture.dtvr_billboard_exact_shader_draw_count()),
                tonumber(ui_native_capture.dtvr_billboard_exact_pso_draw_count()),
                top_billboard_root_slots(
                    ui_native_capture.dtvr_billboard_exact_command_list_type_count,
                    7),
                top_billboard_root_slots(
                    ui_native_capture.dtvr_billboard_exact_register_count, 63),
                top_billboard_root_slots(
                    ui_native_capture.dtvr_billboard_exact_pso_cbv_slot_count),
                top_billboard_root_slots(
                    ui_native_capture.dtvr_billboard_exact_pso_table_slot_count),
                top_billboard_root_slots(
                    ui_native_capture.dtvr_billboard_exact_vertex_table_slot_count),
                top_billboard_root_slots(
                    ui_native_capture.dtvr_billboard_exact_descriptor_offset_count,
                    63),
                top_billboard_root_slots(
                    ui_native_capture.dtvr_billboard_exact_table_span_count, 63),
                tonumber(ui_native_capture.dtvr_billboard_exact_cbv_descriptor_count()),
                tonumber(ui_native_capture.dtvr_billboard_exact_buffer_resource_count()),
                top_billboard_root_slots(
                    ui_native_capture.dtvr_billboard_exact_heap_type_count, 4),
                tonumber(ui_native_capture.dtvr_billboard_exact_map_success_count()),
                tonumber(ui_native_capture.dtvr_billboard_exact_map_failure_count()),
                tonumber(ui_native_capture.dtvr_billboard_resource_map_count()),
                tonumber(ui_native_capture.dtvr_billboard_resource_map_match_count()),
                tonumber(ui_native_capture.dtvr_billboard_resource_unmap_count()),
                tonumber(ui_native_capture.dtvr_billboard_selected_map_stack_count()),
                ui_native_capture.dtvr_billboard_upload_flush_hook_state(),
                tonumber(ui_native_capture.dtvr_billboard_upload_flush_count()),
                ui_native_capture.dtvr_billboard_selected_cpu_address() ~= 0 and 1 or 0,
                tonumber(ui_native_capture.dtvr_billboard_selected_size()),
                top_billboard_root_slots(
                    ui_native_capture.dtvr_billboard_shadow_stage_count, 15),
                tonumber(ui_native_capture.dtvr_billboard_root_metadata_draw_count()),
                tonumber(ui_native_capture.dtvr_billboard_exact_root_mapping_count()),
                tonumber(ui_native_capture.dtvr_billboard_table_b2_draw_count()),
                tonumber(ui_native_capture.dtvr_billboard_bound_table_b2_draw_count()),
                tonumber(ui_native_capture.dtvr_billboard_basis_patch_count())
            )
            mod:info(
                "DARKTIDEVR_STEREO creation_hooks roots=%d pso=%d/%d/%d loads=%d/%d/%d",
                tonumber(ui_native_capture.dtvr_diagnostic_root_signature_create_count()),
                tonumber(ui_native_capture.dtvr_diagnostic_graphics_pso_create_count()),
                tonumber(ui_native_capture.dtvr_diagnostic_compute_pso_create_count()),
                tonumber(ui_native_capture.dtvr_diagnostic_stream_pso_create_count()),
                tonumber(ui_native_capture.dtvr_diagnostic_graphics_pipeline_load_count()),
                tonumber(ui_native_capture.dtvr_diagnostic_compute_pipeline_load_count()),
                tonumber(ui_native_capture.dtvr_diagnostic_stream_pipeline_load_count())
            )
            local candidate_shaders = {}
            for rank = 0, 7 do
                local hash_low = tonumber(
                    ui_native_capture.dtvr_billboard_candidate_shader_hash_low(rank))
                local hash_high = tonumber(
                    ui_native_capture.dtvr_billboard_candidate_shader_hash_high(rank))
                local count = tonumber(
                    ui_native_capture.dtvr_billboard_candidate_shader_count(rank))
                if count > 0 then
                    candidate_shaders[#candidate_shaders + 1] = string.format(
                        "%08x%08x:%d", hash_high, hash_low, count)
                end
            end
            mod:info(
                "DARKTIDEVR_STEREO billboard_b2 candidates=%d shaders=%s",
                tonumber(ui_native_capture.dtvr_billboard_root_b2_candidate_draw_count()),
                table.concat(candidate_shaders, ",")
            )
        end
        ui_native_observer_last_present = presents
    end
end

local function arm_eye_capture(eye)
    return ui_native_capture.dtvr_arm_eye_capture_pose(
        eye,
        head_pose_last_sequence
    )
end

local function report_native_capture_result(result)
    if result ~= ui_native_capture_last_result then
        if result == 0 then
            mod:info("DARKTIDEVR_STEREO native_capture publishing")
        else
            mod:warning(
                "DARKTIDEVR_STEREO native_capture waiting code=%d stage=%d",
                result,
                ui_native_capture.dtvr_capture_stage()
            )
        end

        ui_native_capture_last_result = result
    end
end

local function performance_tick()
    if not performance_profile_requested or not ui_native_capture then
        return nil
    end
    local value = tonumber(ui_native_capture.dtvr_qpc_ticks())
    if not value or value == 0 then
        return nil
    end
    return value
end

local function reset_render_timings(label)
    render_timing_label = label
    render_timing_frequency = ui_native_capture and
        tonumber(ui_native_capture.dtvr_qpc_frequency()) or nil
    render_timing_samples = 0
    render_timing_left_ticks = 0
    render_timing_right_ticks = 0
    render_timing_pair_ticks = 0
    render_timing_left_max_ticks = 0
    render_timing_right_max_ticks = 0
    render_timing_pair_max_ticks = 0
end

local function take_gpu_eye_profile(eye)
    if not ui_native_capture or not gpu_profile_values then
        return nil
    end
    if ui_native_capture.dtvr_take_gpu_eye_profile(
            eye, gpu_profile_values) ~= 0 then
        return nil
    end
    local count = tonumber(gpu_profile_values[0])
    local total = tonumber(gpu_profile_values[1])
    local maximum = tonumber(gpu_profile_values[2])
    local frequency = tonumber(gpu_profile_values[3])
    if not count or count == 0 or not frequency or frequency <= 0 then
        return nil
    end
    return {
        count = count,
        average_ms = total / count * 1000 / frequency,
        maximum_ms = maximum * 1000 / frequency
    }
end

local function take_gpu_stage_profile(eye)
    if not ui_native_capture or not gpu_stage_profile_values then
        return nil
    end
    if ui_native_capture.dtvr_take_gpu_stage_profile(
            eye, gpu_stage_profile_values) ~= 0 then
        return nil
    end
    local count = tonumber(gpu_stage_profile_values[0])
    local world_total = tonumber(gpu_stage_profile_values[1])
    local world_maximum = tonumber(gpu_stage_profile_values[2])
    local output_total = tonumber(gpu_stage_profile_values[3])
    local output_maximum = tonumber(gpu_stage_profile_values[4])
    local frequency = tonumber(gpu_stage_profile_values[5])
    if not count or count == 0 or not frequency or frequency <= 0 then
        return nil
    end
    return {
        count = count,
        pre_full_average_ms = world_total / count * 1000 / frequency,
        pre_full_maximum_ms = world_maximum * 1000 / frequency,
        post_full_average_ms = output_total / count * 1000 / frequency,
        post_full_maximum_ms = output_maximum * 1000 / frequency
    }
end

local function record_render_timings(label, left_ticks, right_ticks, pair_ticks)
    if not left_ticks or not right_ticks or not pair_ticks then
        return
    end
    if render_timing_label ~= label or not render_timing_frequency or
            render_timing_frequency <= 0 then
        reset_render_timings(label)
    end
    if not render_timing_frequency or render_timing_frequency <= 0 then
        return
    end
    render_timing_samples = render_timing_samples + 1
    render_timing_left_ticks = render_timing_left_ticks + left_ticks
    render_timing_right_ticks = render_timing_right_ticks + right_ticks
    render_timing_pair_ticks = render_timing_pair_ticks + pair_ticks
    render_timing_left_max_ticks = math.max(
        render_timing_left_max_ticks, left_ticks)
    render_timing_right_max_ticks = math.max(
        render_timing_right_max_ticks, right_ticks)
    render_timing_pair_max_ticks = math.max(
        render_timing_pair_max_ticks, pair_ticks)
    if render_timing_samples >= 240 then
        local to_ms = 1000 / render_timing_frequency
        mod:info(
            "DARKTIDEVR_PERF target=%s samples=%d left_avg_ms=%.3f right_avg_ms=%.3f pair_avg_ms=%.3f left_max_ms=%.3f right_max_ms=%.3f pair_max_ms=%.3f",
            label,
            render_timing_samples,
            render_timing_left_ticks / render_timing_samples * to_ms,
            render_timing_right_ticks / render_timing_samples * to_ms,
            render_timing_pair_ticks / render_timing_samples * to_ms,
            render_timing_left_max_ticks * to_ms,
            render_timing_right_max_ticks * to_ms,
            render_timing_pair_max_ticks * to_ms
        )
        local left_gpu = take_gpu_eye_profile(0)
        local right_gpu = take_gpu_eye_profile(1)
        if left_gpu and right_gpu then
            mod:info(
                "DARKTIDEVR_GPU_PERF target=%s left_samples=%d right_samples=%d left_avg_ms=%.3f right_avg_ms=%.3f interval_sum_avg_ms=%.3f left_max_ms=%.3f right_max_ms=%.3f",
                label,
                left_gpu.count,
                right_gpu.count,
                left_gpu.average_ms,
                right_gpu.average_ms,
                left_gpu.average_ms + right_gpu.average_ms,
                left_gpu.maximum_ms,
                right_gpu.maximum_ms
            )
        end
        local left_stage = take_gpu_stage_profile(0)
        local right_stage = take_gpu_stage_profile(1)
        if left_stage and right_stage then
            mod:info(
                "DARKTIDEVR_GPU_STAGE target=%s left_samples=%d right_samples=%d left_pre_full_avg_ms=%.3f left_post_full_avg_ms=%.3f right_pre_full_avg_ms=%.3f right_post_full_avg_ms=%.3f left_pre_full_max_ms=%.3f left_post_full_max_ms=%.3f right_pre_full_max_ms=%.3f right_post_full_max_ms=%.3f",
                label,
                left_stage.count,
                right_stage.count,
                left_stage.pre_full_average_ms,
                left_stage.post_full_average_ms,
                right_stage.pre_full_average_ms,
                right_stage.post_full_average_ms,
                left_stage.pre_full_maximum_ms,
                left_stage.post_full_maximum_ms,
                right_stage.pre_full_maximum_ms,
                right_stage.post_full_maximum_ms
            )
        end
        reset_render_timings(label)
    end
end

local function render_second_eye_from_prepared_frame(world, primary, right)
    if not reuse_prepared_frame_requested or reuse_prepared_frame_failed then
        return false
    end
    local camera = ScriptViewport.camera(right)
    local shading_environment =
        Viewport.get_data(primary, "shading_environment")
    if not camera or not shading_environment then
        reuse_prepared_frame_failed = true
        mod:warning(
            "DARKTIDEVR_PERF prepared_second_eye unavailable; restoring full wrapper"
        )
        return false
    end
    local ok, error_message = pcall(
        Application.render_world,
        world,
        camera,
        right,
        shading_environment
    )
    if not ok then
        reuse_prepared_frame_failed = true
        mod:error(
            "DARKTIDEVR_PERF prepared_second_eye failed error=%s",
            tostring(error_message)
        )
        return false
    end
    return true
end

local function wait_for_eye_capture(eye, target)
    local result = tonumber(ui_native_capture.dtvr_wait_eye_capture_count(
        eye,
        target,
        ui_native_sync_timeout_ms
    ))
    if result ~= ui_native_sync_last_result then
        if result == 0 then
            mod:info("DARKTIDEVR_STEREO native_sync publishing")
        else
            mod:warning(
                "DARKTIDEVR_STEREO native_sync waiting code=%d eye=%d target=%d",
                result,
                eye,
                target
            )
        end
        ui_native_sync_last_result = result
    end
    return result
end

local function teardown()
    if ui_native_capture then
        ui_native_capture.dtvr_set_projection_active(0)
    end
    -- This function is reached when CameraManager has already transitioned to
    -- a different world. Stingray owns the old world's viewports and destroys
    -- them with that world; even querying ScriptWorld here reports a fatal
    -- script error once its `viewports` data is gone. Clear only our references
    -- and let world destruction reclaim the old right-eye viewport.

    active = false
    active_manager = nil
    active_world = nil
    active_base_rotation = nil
end

local function setup(manager)
    local world = manager._world

    if not world or not ScriptWorld.has_viewport(world, primary_viewport_name) then
        return false
    end

    if ScriptWorld.has_viewport(world, right_viewport_name) then
        ScriptWorld.destroy_viewport(world, right_viewport_name)
    end

    local primary = ScriptWorld.viewport(world, primary_viewport_name)
    local primary_camera = ScriptViewport.camera(primary)
    local shading_environment_name =
        Viewport.get_data(primary, "default_shading_environment_name")

    if not shading_environment_name then
        return false
    end

    if ui_native_capture_requested and not ui_native_capture_active and
            not enable_ui_native_capture() then
        return false
    end

    local right = ScriptWorld.create_viewport(
        world,
        right_viewport_name,
        ui_offscreen_active and "default_with_alpha" or "default",
        2,
        nil,
        nil,
        nil,
        false,
        shading_environment_name,
        nil
    )

    if ui_native_capture_active then
        -- Each sequential submission renders from a complete, identical
        -- viewport origin. Native capture publishes the intermediate target
        -- before the following eye can overwrite it.
        Viewport.set_rect(primary, 0, 0, 1, 1)
        Viewport.set_rect(right, 0, 0, 1, 1)
    else
        Viewport.set_rect(primary, 0, 0, 0.5, 1)
        Viewport.set_rect(right, 0.5, 0, 0.5, 1)
    end

    active = true
    active_manager = manager
    active_world = world
    -- Preserve only the scene's initial heading. Darktide's lobby camera
    -- starts with a downward presentation pitch; VR must initialize level and
    -- let the headset provide every subsequent pitch/roll component.
    local base_yaw = Quaternion.yaw(
        ScriptCamera.local_rotation(primary_camera)
    )
    local game_mode = Managers and Managers.state and
        Managers.state.game_mode
    local game_mode_name = game_mode and game_mode:game_mode_name()
    if game_mode_name == "hub" then
        -- The hub's third-person presentation camera faces back toward the
        -- operative. Its stored yaw is opposite the desired neutral headset
        -- heading when VR takes orientation ownership.
        base_yaw = base_yaw + math.pi
    end
    active_base_rotation = QuaternionBox(
        Quaternion.axis_angle(Vector3.up(), base_yaw)
    )
    -- CameraManager is also present on the title screen. Only gameplay owns
    -- this generic stereo path; character select is signalled separately by
    -- setup_ui_stereo, and title/loading remain on the spatial flat panel.
    if Managers and Managers.state and Managers.state.game_mode then
        ui_native_capture.dtvr_set_projection_active(1)
    end
    mod:info(
        "DARKTIDEVR_STEREO active mode=synchronized_sequential half_ipd=%.3f",
        half_ipd
    )

    return true
end

local function copy_projection(source, destination)
    Camera.set_vertical_fov(destination, Camera.vertical_fov(source))
    Camera.set_near_range(destination, Camera.near_range(source))
    Camera.set_far_range(destination, Camera.far_range(source))
end

local function publish_render_projection(camera)
    if not ui_native_capture then
        return
    end

    local projection_result = ui_native_capture.dtvr_set_render_projection(
        Camera.vertical_fov(camera),
        ui_eye_target_width / ui_eye_target_height
    )
    if projection_result ~= 0 then
        error("native render projection rejected: " ..
            tostring(projection_result))
    end
end

local runtime_recentered_projection_logged = false

local function axis_angle_quaternion(x, y, z, radians)
    local half = radians * 0.5
    local scale = math.sin(half)
    return Quaternion.from_elements(
        x * scale,
        y * scale,
        z * scale,
        math.cos(half)
    )
end

local function runtime_recentered_eye(frustum, target_aspect_ratio)
    local horizontal_center = (frustum.left + frustum.right) * 0.5
    local vertical_center = (frustum.down + frustum.up) * 0.5
    local vertical_half = (frustum.up - frustum.down) * 0.5
    local horizontal_half = math.atan(
        math.tan(vertical_half) * target_aspect_ratio
    )

    -- OpenXR +Y maps to Stingray +Z, and OpenXR +X maps to Stingray +X.
    -- Keep the order identical to xr_math::recentered_symmetric_projection.
    local yaw = axis_angle_quaternion(0, 0, 1, -horizontal_center)
    local pitch = axis_angle_quaternion(1, 0, 0, vertical_center)
    return {
        rotation = Quaternion.multiply(yaw, pitch),
        vertical_fov = vertical_half * 2,
        horizontal_half = horizontal_half,
        horizontal_center = horizontal_center,
        vertical_center = vertical_center
    }
end

local function apply_runtime_recentered_projection(primary, right)
    if not head_render_frusta then
        return false
    end

    local target_aspect_ratio = ui_eye_target_width / ui_eye_target_height
    local left = runtime_recentered_eye(
        head_render_frusta[1], target_aspect_ratio
    )
    local right_eye = runtime_recentered_eye(
        head_render_frusta[2], target_aspect_ratio
    )
    local identity = Matrix4x4.from_elements(
        1, 0, 0,
        0, 1, 0,
        0, 0, 1,
        0, 0, 0
    )
    Camera.set_post_projection_transform(primary, identity)
    Camera.set_post_projection_transform(right, identity)
    Camera.set_vertical_fov(primary, left.vertical_fov)
    Camera.set_vertical_fov(right, right_eye.vertical_fov)
    if not runtime_recentered_projection_logged then
        mod:info(
            "DARKTIDEVR_STEREO runtime_recentered_projection left=%.6f,%.6f,%.6f right=%.6f,%.6f,%.6f",
            left.vertical_fov,
            left.horizontal_center,
            left.vertical_center,
            right_eye.vertical_fov,
            right_eye.horizontal_center,
            right_eye.vertical_center
        )
        runtime_recentered_projection_logged = true
    end
    return left.rotation, right_eye.rotation
end

local function apply_half_width_projection(primary, right)
    local base_vertical_fov = ui_base_vertical_fov or Camera.vertical_fov(primary)
    local tangent_scale = stereo_vertical_tangent_scale
    local target_aspect_ratio = ui_eye_target_width / ui_eye_target_height
    local runtime_projection_matches_target = head_render_vertical_fov and
        head_render_aspect_ratio and
        math.abs(head_render_aspect_ratio - target_aspect_ratio) < 0.001
    local left_optical_rotation = nil
    local right_optical_rotation = nil
    if runtime_projection_matches_target then
        left_optical_rotation, right_optical_rotation =
            apply_runtime_recentered_projection(primary, right)
    end
    if left_optical_rotation and right_optical_rotation then
        Camera.set_near_range(right, Camera.near_range(primary))
        Camera.set_far_range(right, Camera.far_range(primary))
        publish_render_projection(primary)
        return left_optical_rotation, right_optical_rotation
    end

    local stereo_vertical_fov = runtime_projection_matches_target and
        head_render_vertical_fov or
        2 * math.atan(math.tan(base_vertical_fov * 0.5) * tangent_scale)

    -- Each eye owns half the backbuffer width. Preserve the original
    -- horizontal scene coverage by doubling tan(vertical_fov / 2), rather
    -- than allowing the half-width viewport to crop the image horizontally.
    Camera.set_vertical_fov(primary, stereo_vertical_fov)
    Camera.set_vertical_fov(right, stereo_vertical_fov)
    Camera.set_near_range(right, Camera.near_range(primary))
    Camera.set_far_range(right, Camera.far_range(primary))

    publish_render_projection(primary)
    return nil, nil
end

local function apply_ui_eye_offsets(spawner)
    if spawner ~= ui_stereo_spawner or not ui_stereo_right_viewport then
        return
    end

    local primary_camera = spawner._camera
    local right_camera = ScriptViewport.camera(ui_stereo_right_viewport)
    local primary_unit = spawner._camera_unit
    local right_unit = Camera.get_data(right_camera, "unit")
    local clean_position = Unit.local_position(primary_unit, 1)
    local clean_rotation = Unit.local_rotation(primary_unit, 1)

    if ui_camera_freeze_requested and ui_native_capture then
        local presents = tonumber(ui_native_capture.dtvr_present_count())

        if not ui_camera_freeze_start_present then
            ui_camera_freeze_start_present = presents
        end

        if not ui_camera_frozen_position and
                presents - ui_camera_freeze_start_present >=
                    ui_camera_freeze_warmup_presents then
            -- Unit.local_* returns frame-scoped values.  Retaining those raw
            -- userdata objects across presents leaves an invalid value for
            -- Unit.set_local_*.  Boxes own a durable copy; unbox a fresh
            -- engine value each time the frozen transform is applied.
            ui_camera_frozen_position = Vector3Box(clean_position)
            ui_camera_frozen_rotation = QuaternionBox(clean_rotation)
            mod:info(
                "DARKTIDEVR_STEREO camera_freeze locked present=%d",
                presents
            )
        end

        if ui_camera_frozen_position then
            clean_position = ui_camera_frozen_position:unbox()
            clean_rotation = ui_camera_frozen_rotation:unbox()
            Unit.set_local_position(primary_unit, 1, clean_position)
            Unit.set_local_rotation(primary_unit, 1, clean_rotation)
            ScriptCamera.force_update(ui_stereo_world, primary_camera)
        end
    end
    clean_position, clean_rotation = apply_head_tracking(
        clean_position,
        clean_rotation
    )
    Unit.set_local_position(primary_unit, 1, clean_position)
    Unit.set_local_rotation(primary_unit, 1, clean_rotation)
    ScriptCamera.force_update(ui_stereo_world, primary_camera)
    local eye_axis = Quaternion.right(clean_rotation)

    -- The frozen base pose is restored before tracking is composed, preventing
    -- repeated pre-render callbacks from accumulating head motion. Keep the
    -- two eyes symmetric around that tracked center so their camera geometry
    -- matches the recentered OpenXR projection poses.
    local left_optical_rotation, right_optical_rotation =
        apply_half_width_projection(primary_camera, right_camera)
    local primary_rotation = left_optical_rotation and
        Quaternion.multiply(clean_rotation, left_optical_rotation) or
        clean_rotation
    local duplicate_rotation = right_optical_rotation and
        Quaternion.multiply(clean_rotation, right_optical_rotation) or
        clean_rotation
    Unit.set_local_position(
        primary_unit,
        1,
        clean_position - eye_axis * (ui_eye_separation * 0.5)
    )
    Unit.set_local_rotation(primary_unit, 1, primary_rotation)
    -- Unit movement does not immediately refresh the camera's cached view
    -- matrix. The previous force_update occurred at clean_position, which
    -- made the primary render use the center pose while only the duplicate
    -- received its eye offset.
    ScriptCamera.force_update(ui_stereo_world, primary_camera)
    Unit.set_local_position(
        right_unit,
        1,
        clean_position + eye_axis * (ui_eye_separation * 0.5)
    )
    Unit.set_local_rotation(right_unit, 1, duplicate_rotation)
    ScriptCamera.force_update(ui_stereo_world, right_camera)
end

local ui_rect_matrix_phases = {
    { name = "left_half", x = 0, width = 0.5 },
    { name = "center_half", x = 0.25, width = 0.5 },
    { name = "right_half", x = 0.5, width = 0.5 },
    { name = "full", x = 0, width = 1 }
}

local function apply_ui_rect_matrix_phase(primary, phase)
    local definition = ui_rect_matrix_phases[phase]
    Viewport.set_rect(primary, definition.x, 0, definition.width, 1)
    mod:info(
        "DARKTIDEVR_STEREO rect_matrix phase=%s x=%.2f width=%.2f",
        definition.name,
        definition.x,
        definition.width
    )
end

local function update_ui_rect_matrix()
    if not ui_rect_matrix_requested or ui_rect_matrix_complete or
            not ui_camera_frozen_position or not ui_stereo_world or
            not ui_stereo_spawner or not ui_stereo_right_viewport or
            not ui_native_capture then
        return
    end

    local primary = ui_stereo_spawner._viewport
    local duplicate = ui_stereo_right_viewport
    local presents = tonumber(ui_native_capture.dtvr_present_count())

    if not ui_rect_matrix_start_present then
        ui_rect_matrix_start_present = presents
        ui_rect_matrix_phase = 1
        ScriptWorld.activate_viewport(ui_stereo_world, primary)
        ScriptWorld.deactivate_viewport(ui_stereo_world, duplicate)
        apply_ui_rect_matrix_phase(primary, ui_rect_matrix_phase)
        return
    end

    local next_phase = math.floor(
        (presents - ui_rect_matrix_start_present) /
            ui_rect_matrix_phase_presents
    ) + 1

    if next_phase > #ui_rect_matrix_phases then
        ScriptWorld.activate_viewport(ui_stereo_world, primary)
        ScriptWorld.activate_viewport(ui_stereo_world, duplicate)
        if ui_swap_viewport_halves_requested then
            Viewport.set_rect(primary, 0.5, 0, 0.5, 1)
            Viewport.set_rect(duplicate, 0, 0, 0.5, 1)
        else
            Viewport.set_rect(primary, 0, 0, 0.5, 1)
            Viewport.set_rect(duplicate, 0.5, 0, 0.5, 1)
        end
        ui_rect_matrix_complete = true
        mod:info("DARKTIDEVR_STEREO rect_matrix complete restored=sbs")
    elseif next_phase ~= ui_rect_matrix_phase then
        ui_rect_matrix_phase = next_phase
        apply_ui_rect_matrix_phase(primary, ui_rect_matrix_phase)
    end
end

local function update_ui_rect_trace()
    if not ui_rect_trace_requested or ui_rect_trace_complete or
            not ui_camera_frozen_position or not ui_stereo_world or
            not ui_stereo_spawner or not ui_stereo_right_viewport or
            not ui_native_capture then
        return
    end

    local primary = ui_stereo_spawner._viewport
    local duplicate = ui_stereo_right_viewport
    local presents = tonumber(ui_native_capture.dtvr_present_count())

    if ui_rect_trace_phase == 0 then
        ui_rect_trace_phase = 1
        ui_rect_trace_phase_start_present = presents
        ScriptWorld.activate_viewport(ui_stereo_world, primary)
        ScriptWorld.deactivate_viewport(ui_stereo_world, duplicate)
        apply_ui_rect_matrix_phase(primary, ui_rect_trace_phase)
        mod:info("DARKTIDEVR_STEREO rect_trace warmup phase=1")
        return
    end

    if not ui_rect_trace_sampling and
            presents - ui_rect_trace_phase_start_present >=
                ui_rect_trace_warmup_presents then
        local result = ui_native_capture.dtvr_set_focused_trace_phase(
            ui_rect_trace_phase
        )
        ui_rect_trace_sampling = true
        ui_rect_trace_sample_start_present = presents
        mod:info(
            "DARKTIDEVR_STEREO rect_trace sample phase=%d result=%d",
            ui_rect_trace_phase,
            tonumber(result)
        )
        return
    end

    if ui_rect_trace_sampling and
            presents - ui_rect_trace_sample_start_present >=
                ui_rect_trace_sample_presents then
        ui_native_capture.dtvr_set_focused_trace_phase(0)
        ui_rect_trace_sampling = false

        if ui_rect_trace_phase == #ui_rect_matrix_phases then
            ScriptWorld.activate_viewport(ui_stereo_world, primary)
            ScriptWorld.activate_viewport(ui_stereo_world, duplicate)
            Viewport.set_rect(primary, 0, 0, 0.5, 1)
            Viewport.set_rect(duplicate, 0.5, 0, 0.5, 1)
            ui_rect_trace_complete = true
            mod:info(
                "DARKTIDEVR_STEREO rect_trace complete records=%d",
                tonumber(ui_native_capture.dtvr_focused_trace_count())
            )
            return
        end

        ui_rect_trace_phase = ui_rect_trace_phase + 1
        ui_rect_trace_phase_start_present = presents
        apply_ui_rect_matrix_phase(primary, ui_rect_trace_phase)
        mod:info(
            "DARKTIDEVR_STEREO rect_trace warmup phase=%d",
            ui_rect_trace_phase
        )
    end
end

local function apply_ui_direct_sbs_rects(primary, duplicate)
    if ui_swap_viewport_halves_requested then
        Viewport.set_rect(primary, 0.5, 0, 0.5, 1)
        Viewport.set_rect(duplicate, 0, 0, 0.5, 1)
    else
        Viewport.set_rect(primary, 0, 0, 0.5, 1)
        Viewport.set_rect(duplicate, 0.5, 0, 0.5, 1)
    end
end

local function apply_ui_rich_center_sbs_rects(primary, duplicate)
    -- x/width=0.996 and 1.0 are native eye tags. Both centers remain in the
    -- matrix's rich-right tier while native RSSetViewports/ScissorRects moves
    -- their actual raster output to x=0 and x=width respectively.
    Viewport.set_rect(primary, 0.498, 0, 0.5, 1)
    Viewport.set_rect(duplicate, 0.5, 0, 0.5, 1)
end

local function update_ui_alternating_full()
    if not ui_alternating_full_requested or not ui_native_capture or
            not ui_stereo_world or not ui_stereo_spawner or
            not ui_stereo_right_viewport then
        return
    end

    local presents = tonumber(ui_native_capture.dtvr_present_count())
    if ui_alternating_full_last_present == nil then
        ui_alternating_full_last_present = presents
    elseif presents == ui_alternating_full_last_present then
        return
    else
        ui_alternating_full_last_present = presents
        ui_alternating_full_eye = 1 - ui_alternating_full_eye
    end

    local primary = ui_stereo_spawner._viewport
    local duplicate = ui_stereo_right_viewport
    if ui_alternating_full_eye == 0 then
        ScriptWorld.activate_viewport(ui_stereo_world, primary)
        ScriptWorld.deactivate_viewport(ui_stereo_world, duplicate)
    else
        ScriptWorld.deactivate_viewport(ui_stereo_world, primary)
        ScriptWorld.activate_viewport(ui_stereo_world, duplicate)
    end
    ui_native_capture.dtvr_set_alternating_present_eye(
        ui_alternating_full_eye
    )
end

local function update_ui_full_origin_ab()
    if not ui_full_origin_ab_requested or ui_full_origin_ab_complete or
            not ui_stereo_world or not ui_stereo_spawner or
            not ui_stereo_right_viewport or not ui_native_capture then
        return
    end

    local primary = ui_stereo_spawner._viewport
    local duplicate = ui_stereo_right_viewport
    local presents = tonumber(ui_native_capture.dtvr_present_count())

    if not ui_full_origin_ab_start_present then
        ui_full_origin_ab_start_present = presents
        Viewport.set_rect(primary, 0, 0, 1, 1)
        Viewport.set_rect(duplicate, 0, 0, 1, 1)
        ScriptWorld.activate_viewport(ui_stereo_world, primary)
        ScriptWorld.deactivate_viewport(ui_stereo_world, duplicate)
        mod:info("DARKTIDEVR_STEREO full_origin_ab phase=primary")
        return
    end

    local elapsed = presents - ui_full_origin_ab_start_present
    if not ui_full_origin_ab_duplicate_active and
            elapsed >= ui_full_origin_ab_phase_presents then
        ScriptWorld.deactivate_viewport(ui_stereo_world, primary)
        ScriptWorld.activate_viewport(ui_stereo_world, duplicate)
        ui_full_origin_ab_duplicate_active = true
        mod:info("DARKTIDEVR_STEREO full_origin_ab phase=duplicate")
    elseif ui_full_origin_ab_duplicate_active and
            elapsed >= ui_full_origin_ab_phase_presents * 2 then
        ScriptWorld.activate_viewport(ui_stereo_world, primary)
        ScriptWorld.activate_viewport(ui_stereo_world, duplicate)
        apply_ui_direct_sbs_rects(primary, duplicate)
        ui_full_origin_ab_complete = true
        mod:info("DARKTIDEVR_STEREO full_origin_ab complete restored=sbs")
    end
end

local function update_ui_focused_ab_trace()
    if not ui_focused_ab_trace_requested or ui_focused_ab_trace_complete or
            not ui_native_capture or not ui_stereo_spawner or
            not ui_stereo_right_viewport or head_pose_last_sequence == 0 then
        return
    end

    ui_focused_ab_trace_frame = ui_focused_ab_trace_frame + 1

    local phase_a_start = ui_focused_ab_warmup_frames
    local swap_frame = phase_a_start + ui_focused_ab_sample_frames
    local phase_b_start = swap_frame + ui_focused_ab_warmup_frames
    local complete_frame = phase_b_start + ui_focused_ab_sample_frames

    if ui_focused_ab_trace_frame == phase_a_start then
        local result = ui_native_capture.dtvr_set_focused_trace_phase(1)
        mod:info(
            "DARKTIDEVR_STEREO focused_trace phase=A primary_half=left result=%d",
            tonumber(result)
        )
    elseif ui_focused_ab_trace_frame == swap_frame then
        ui_native_capture.dtvr_set_focused_trace_phase(0)
        ui_swap_viewport_halves_requested = true
        apply_ui_direct_sbs_rects(
            ui_stereo_spawner._viewport,
            ui_stereo_right_viewport
        )
        mod:info(
            "DARKTIDEVR_STEREO focused_trace warmup=B primary_half=right"
        )
    elseif ui_focused_ab_trace_frame == phase_b_start then
        local result = ui_native_capture.dtvr_set_focused_trace_phase(2)
        mod:info(
            "DARKTIDEVR_STEREO focused_trace phase=B primary_half=right result=%d",
            tonumber(result)
        )
    elseif ui_focused_ab_trace_frame == complete_frame then
        ui_native_capture.dtvr_set_focused_trace_phase(0)
        ui_focused_ab_trace_complete = true
        mod:info(
            "DARKTIDEVR_STEREO focused_trace complete records=%d",
            tonumber(ui_native_capture.dtvr_focused_trace_count())
        )
    end
end

local function teardown_ui_stereo()
    if ui_native_capture then
        ui_native_capture.dtvr_set_projection_active(0)
    end
    if ui_native_capture then
        ui_native_capture.dtvr_disable_rich_center_sbs_remap()
        ui_native_capture.dtvr_disable_alternating_full_capture()
        ui_native_capture.dtvr_disable_top_bottom_capture()
        if ui_alternating_full_requested or ui_top_bottom_requested then
            ui_native_capture.dtvr_disable_present_capture()
        end
    end

    if ui_stereo_world then
        if ui_stereo_spawner and ui_stereo_spawner._viewport then
            Viewport.set_rect(ui_stereo_spawner._viewport, 0, 0, 1, 1)
        end

        if ScriptWorld.has_viewport(ui_stereo_world, ui_stereo_right_name) then
            ScriptWorld.destroy_viewport(ui_stereo_world, ui_stereo_right_name)
        end
    end

    ui_stereo_spawner = nil
    ui_stereo_world = nil
    ui_stereo_right_viewport = nil
    ui_base_vertical_fov = nil
end

local function destroy_ui_offscreen_resources()
    if ui_left_material then
        Gui.destroy_material(ui_left_material.gui, ui_left_material.material)
        ui_left_material = nil
    end

    if ui_right_material then
        Gui.destroy_material(ui_right_material.gui, ui_right_material.material)
        ui_right_material = nil
    end

    if ui_left_render_target then
        Renderer.destroy_resource(ui_left_render_target)
        ui_left_render_target = nil
    end

    if ui_right_render_target then
        Renderer.destroy_resource(ui_right_render_target)
        ui_right_render_target = nil
    end

    if ui_left_output_target then
        Renderer.destroy_resource(ui_left_output_target)
        ui_left_output_target = nil
    end

    if ui_right_output_target then
        Renderer.destroy_resource(ui_right_output_target)
        ui_right_output_target = nil
    end

    ui_offscreen_active = false
end

local function create_eye_render_target(name, width, height)
    ResourceReferenceContext.push("DarktideVR:offscreen_stereo")
    ResourceReferenceContext.push(name)
    local target = Renderer.create_resource(
        "render_target",
        "R8G8B8A8",
        nil,
        width,
        height,
        name
    )
    ResourceReferenceContext.pop(name)
    ResourceReferenceContext.pop("DarktideVR:offscreen_stereo")

    return target
end

local function eye_render_target_mapping(output_target, back_buffer)
    if ui_back_buffer_only_requested then
        return { back_buffer = back_buffer }
    end

    return {
        output_target = output_target,
        back_buffer = back_buffer
    }
end

local function setup_ui_stereo(spawner)
    local world = spawner._world
    local primary = spawner._viewport

    if not world or not primary then
        return
    end

    if ScriptWorld.has_viewport(world, ui_stereo_right_name) then
        ScriptWorld.destroy_viewport(world, ui_stereo_right_name)
    end

    local shading_environment_name =
        Viewport.get_data(primary, "default_shading_environment_name")
    local shading_callback = Viewport.get_data(primary, "shading_callback")
    local viewport_layer = Viewport.get_data(primary, "layer")
    if not shading_environment_name then
        error("main-menu viewport has no shading environment")
    end

    if ui_offscreen_requested then
        if ui_offscreen_primary_requested and
                (not ui_left_render_target or not ui_left_output_target) then
            error("primary eye targets were not installed at viewport creation")
        end

        ui_right_output_target = create_eye_render_target(
            "darktidevr_right_eye_output",
            ui_eye_target_width,
            ui_eye_target_height
        )
        ui_right_render_target = create_eye_render_target(
            "darktidevr_right_eye_final",
            ui_eye_target_width,
            ui_eye_target_height
        )
        ui_offscreen_active = true
    end

    local right = ScriptWorld.create_viewport(
        world,
        ui_stereo_right_name,
        ui_offscreen_active and "default_with_alpha" or "default",
        2,
        nil,
        nil,
        nil,
        false,
        shading_environment_name,
        shading_callback,
        nil,
        -- `output_target` drives the deferred attachment dimensions, while
        -- `back_buffer` receives the completed/tonemapped viewport. They must
        -- be distinct: mapping only one either leaves the world graph at the
        -- desktop size or exposes an internal intermediate to the compositor.
        ui_offscreen_active and eye_render_target_mapping(
            ui_right_output_target,
            ui_right_render_target
        ) or nil
    )

    if ui_top_bottom_requested then
        if not ensure_ui_native_hooks() then
            error("top/bottom eye publication requires native hooks")
        end
        local layout_result = ui_native_capture.dtvr_enable_top_bottom_capture()
        local capture_result = ui_native_capture.dtvr_enable_present_capture()
        if layout_result ~= 0 or capture_result ~= 0 then
            error("top/bottom eye publication failed")
        end
        Viewport.set_rect(primary, 0, 0, 1, 0.5)
        Viewport.set_rect(right, 0, 0.5, 1, 0.5)
    elseif ui_alternating_full_requested then
        if not ensure_ui_native_hooks() then
            error("alternating full-eye capture requires native hooks")
        end
        local alternating_result =
            ui_native_capture.dtvr_enable_alternating_full_capture()
        local capture_result = ui_native_capture.dtvr_enable_present_capture()
        if alternating_result ~= 0 or capture_result ~= 0 then
            error("alternating full-eye capture failed")
        end
        Viewport.set_rect(primary, 0, 0, 1, 1)
        Viewport.set_rect(right, 0, 0, 1, 1)
        ui_alternating_full_eye = 0
        ui_alternating_full_last_present =
            tonumber(ui_native_capture.dtvr_present_count())
        ScriptWorld.activate_viewport(world, primary)
        ScriptWorld.deactivate_viewport(world, right)
        ui_native_capture.dtvr_set_alternating_present_eye(0)
    elseif ui_rich_center_sbs_remap_requested then
        if not ensure_ui_native_hooks() then
            error("rich-center SBS remap requires native hooks")
        end
        local remap_result =
            ui_native_capture.dtvr_enable_rich_center_sbs_remap()
        if remap_result ~= 0 then
            error("native rich-center SBS remap failed: " ..
                tostring(remap_result))
        end
        apply_ui_rich_center_sbs_rects(primary, right)
    elseif ui_double_render_probe_requested then
        Viewport.set_rect(primary, 0, 0, 1, 1)
        Viewport.set_rect(right, 0, 0, 1, 1)
    elseif ui_native_capture_active then
        Viewport.set_rect(primary, 0, 0, 1, 1)
        Viewport.set_rect(right, 0, 0, 1, 1)
    elseif ui_offscreen_active then
        Viewport.set_rect(primary, 0, 0, 1, 1)
        Viewport.set_rect(right, 0, 0, 1, 1)
    else
        apply_ui_direct_sbs_rects(primary, right)
    end
    ui_base_vertical_fov = Camera.vertical_fov(spawner._camera)
    ui_stereo_spawner = spawner
    ui_stereo_world = world
    ui_stereo_right_viewport = right
    if ui_full_origin_ab_requested then
        ui_full_origin_ab_start_present = nil
        ui_full_origin_ab_duplicate_active = false
        ui_full_origin_ab_complete = false
    end
    if ui_camera_freeze_requested then
        ui_camera_freeze_start_present = nil
        ui_camera_frozen_position = nil
        ui_camera_frozen_rotation = nil
    end
    if ui_rect_matrix_requested then
        ui_rect_matrix_start_present = nil
        ui_rect_matrix_phase = 0
        ui_rect_matrix_complete = false
    end
    if ui_rect_trace_requested then
        ui_rect_trace_phase = 0
        ui_rect_trace_phase_start_present = nil
        ui_rect_trace_sample_start_present = nil
        ui_rect_trace_sampling = false
        ui_rect_trace_complete = false
    end
    if ui_focused_ab_trace_requested then
        ui_focused_ab_trace_frame = 0
        ui_focused_ab_trace_complete = false
        ui_swap_viewport_halves_requested = false
        apply_ui_direct_sbs_rects(primary, right)
    end
    if ui_offscreen_trace_requested then
        ui_offscreen_trace_frame = 0
        ui_offscreen_trace_complete = false
    end
    apply_ui_eye_offsets(spawner)
    ui_native_capture.dtvr_set_projection_active(1)
    mod:info(
        "DARKTIDEVR_STEREO active target=ui_main_menu_world mode=%s half_ipd=%.3f layer=%s/2 primary_half=%s",
        ui_top_bottom_requested and "top_bottom_same_horizontal_center" or
            (ui_alternating_full_requested and "alternating_full_origin" or
            (ui_rich_center_sbs_remap_requested and "rich_center_native_sbs" or
            (ui_offscreen_active and "offscreen_full_origin" or
                "binding_census_baseline"))),
        half_ipd,
        tostring(viewport_layer),
        ui_swap_viewport_halves_requested and "right" or "left"
    )
end

local function update_stereo(manager)
    if not requested or failed then
        return
    end

    if active and manager ~= active_manager then
        teardown()
    end

    if not active and not setup(manager) then
        return
    end

    local world = active_world
    local primary_viewport = ScriptWorld.viewport(world, primary_viewport_name)
    local right_viewport = ScriptWorld.viewport(world, right_viewport_name)
    local primary_camera = ScriptViewport.camera(primary_viewport)
    local right_camera = ScriptViewport.camera(right_viewport)
    local clean_position = ScriptCamera.local_position(primary_camera)
    -- The game remains authoritative for camera translation, but VR owns the
    -- complete orientation. Reusing the live game rotation allowed orbital
    -- camera pitch/roll (and occasionally the prior tracked result) to feed
    -- back into the next headset pose when the player moved vertically.
    local clean_rotation = active_base_rotation:unbox()
    if game_rotation_mode == "yaw_only" then
        local live_rotation = ScriptCamera.local_rotation(primary_camera)
        local yaw_delta = Quaternion.yaw(live_rotation) -
            Quaternion.yaw(clean_rotation)
        clean_rotation = Quaternion.multiply(
            Quaternion.axis_angle(Vector3.up(), yaw_delta),
            clean_rotation
        )
    end
    clean_position, clean_rotation = apply_head_tracking(
        clean_position,
        clean_rotation
    )
    if ui_native_capture and (billboard_horizon_lock_requested or
            billboard_selector_probe_requested) then
        local horizon_rotation = Quaternion.axis_angle(
            Vector3.up(), Quaternion.yaw(clean_rotation))
        local billboard_right = Quaternion.right(horizon_rotation)
        local billboard_up = Quaternion.up(horizon_rotation)
        ui_native_capture.dtvr_set_billboard_view_basis(
            billboard_right.x, billboard_right.y, billboard_right.z,
            billboard_up.x, billboard_up.y, billboard_up.z,
            billboard_horizon_lock_requested and 1 or 2
        )
    end
    local eye_axis = Quaternion.right(clean_rotation)

    local runtime_projection_matches_target = head_render_vertical_fov and
        head_render_aspect_ratio and
        math.abs(head_render_aspect_ratio -
            (ui_eye_target_width / ui_eye_target_height)) < 0.001
    local left_optical_rotation = nil
    local right_optical_rotation = nil
    if runtime_projection_matches_target then
        Camera.set_near_range(right_camera, Camera.near_range(primary_camera))
        Camera.set_far_range(right_camera, Camera.far_range(primary_camera))
        left_optical_rotation, right_optical_rotation =
            apply_runtime_recentered_projection(primary_camera, right_camera)
        if not left_optical_rotation or not right_optical_rotation then
            Camera.set_vertical_fov(primary_camera, head_render_vertical_fov)
            Camera.set_vertical_fov(right_camera, head_render_vertical_fov)
        end
    end

    ScriptCamera.set_local_position(
        primary_camera,
        clean_position - eye_axis * half_ipd
    )
    ScriptCamera.set_local_rotation(
        primary_camera,
        left_optical_rotation and
            Quaternion.multiply(clean_rotation, left_optical_rotation) or
            clean_rotation
    )
    ScriptCamera.set_local_position(
        right_camera,
        clean_position + eye_axis * half_ipd
    )
    ScriptCamera.set_local_rotation(
        right_camera,
        right_optical_rotation and
            Quaternion.multiply(clean_rotation, right_optical_rotation) or
            clean_rotation
    )
    if not runtime_projection_matches_target then
        copy_projection(primary_camera, right_camera)
    end
    publish_render_projection(primary_camera)

    ScriptCamera.force_update(world, primary_camera)
    ScriptCamera.force_update(world, right_camera)
end

mod:hook_safe(
    require("scripts/managers/ui/ui_manager"),
    "update",
    function(self, _, t)
    presentation.reconcile_fullscreen_views(self)
    presentation.update_psykhanium(self, t or 0)
end)

-- Conventional tracked-controller aim seam. It is observation-only unless an
-- explicit test flag is present. The stereo camera remains HMD-owned in both
-- modes.
function presentation.observe_controller_aim(self, main_t, orientation_class)
    if main_t >= controller_observation.authoring_last_check_t + 1 then
        controller_observation.authoring_last_check_t = main_t
        local flag_path =
            "./../mods/darktidevr_stereo_probe/darktidevr_controller_aim_test.flag"
        local flag = Mods.lua.io.open(flag_path, "r")
        local enabled = false
        if flag then
            enabled = flag:read("*all"):match("^%s*enabled%s*$") ~= nil
            flag:close()
        end
        if enabled ~= controller_observation.authoring_enabled then
            controller_observation.authoring_enabled = enabled
            if not enabled then
                controller_observation.authoring_pose_active = false
            end
            mod:info(
                "DARKTIDEVR_AIM authoring=%s source=test_flag writes=%d",
                enabled and "enabled" or "disabled",
                controller_observation.authoring_writes
            )
        end
    end
    if not controller_observation.right_aim_usable or
            not controller_observation.right_aim_yaw then
        if controller_observation.authoring_enabled and
                controller_observation.authoring_pose_active then
            controller_observation.authoring_pose_active = false
            mod:warning(
                "DARKTIDEVR_AIM suspended reason=unusable sequence=%d flags=%d age_ms=%.3f",
                controller_observation.last_sequence,
                controller_observation.right_aim_flags,
                controller_observation.right_aim_age_ms
            )
        end
        return
    end
    if controller_observation.last_sequence ==
            controller_observation.first_person_seam_last_sequence then
        return
    end
    controller_observation.first_person_seam_last_sequence =
        controller_observation.last_sequence
    if not controller_observation.body_yaw_anchor then
        controller_observation.body_yaw_anchor = self._orientation.yaw
    end
    local world_aim_rotation = Quaternion.multiply(
        Quaternion.from_yaw_pitch_roll(
            controller_observation.body_yaw_anchor, 0, 0
        ),
        Quaternion.from_yaw_pitch_roll(
            controller_observation.right_aim_yaw,
            controller_observation.right_aim_pitch,
            controller_observation.right_aim_roll
        )
    )
    local target_yaw, target_pitch, target_roll =
        Quaternion.to_yaw_pitch_roll(world_aim_rotation)
    local game_yaw = self._orientation.yaw
    local game_pitch = self._orientation.pitch
    local game_roll = self._orientation.roll
    if controller_observation.authoring_enabled then
        -- Gameplay aim owns yaw/pitch only. Controller roll remains available
        -- for later weapon presentation but cannot roll the player or HMD.
        local authored_rotation = Quaternion.multiply(
            Quaternion.from_yaw_pitch_roll(
                controller_observation.body_yaw_anchor, 0, 0
            ),
            Quaternion.from_yaw_pitch_roll(
                controller_observation.right_aim_yaw,
                controller_observation.right_aim_pitch,
                0
            )
        )
        local authored_yaw, authored_pitch =
            Quaternion.to_yaw_pitch_roll(authored_rotation)
        self._orientation.yaw = authored_yaw
        self._orientation.pitch = authored_pitch
        self._orientation.roll = 0
        controller_observation.authoring_writes =
            controller_observation.authoring_writes + 1
        controller_observation.authoring_pose_active = true
    end
    if main_t < controller_observation.first_person_seam_last_log_t + 2 then
        return
    end
    controller_observation.first_person_seam_last_log_t = main_t
    mod:info(
        "DARKTIDEVR_AIM observation class=%s sequence=%d age_ms=%.3f controller_ypr=%.4f,%.4f,%.4f anchor_yaw=%.4f target_ypr=%.4f,%.4f,%.4f game_ypr=%.4f,%.4f,%.4f write=%s",
        orientation_class,
        controller_observation.last_sequence,
        controller_observation.right_aim_age_ms,
        controller_observation.right_aim_yaw,
        controller_observation.right_aim_pitch,
        controller_observation.right_aim_roll,
        controller_observation.body_yaw_anchor,
        target_yaw,
        target_pitch,
        target_roll,
        game_yaw,
        game_pitch,
        game_roll,
        controller_observation.authoring_enabled and "enabled" or "disabled"
    )
end

mod:hook_safe(
    require("scripts/extension_systems/first_person/character_state_orientation/default_player_orientation"),
    "pre_update",
    function(self, main_t)
    presentation.observe_controller_aim(self, main_t, "default")
end)

mod:hook_safe(
    require("scripts/extension_systems/first_person/character_state_orientation/hub_player_orientation"),
    "pre_update",
    function(self, main_t)
    presentation.observe_controller_aim(self, main_t, "hub")
    end)

-- Verify that the authored orientation reaches the shared first-person
-- component consumed by weapons, interactions and abilities. Convert engine
-- math values immediately; never retain their transient userdata.
mod:hook_safe(
    require("scripts/extension_systems/first_person/player_unit_first_person_extension"),
    "fixed_update",
    function(self)
        if not controller_observation.authoring_enabled or
                not controller_observation.right_aim_usable or
                controller_observation.last_sequence <
                    controller_observation.downstream_last_sequence + 120 then
            return
        end
        local component = self._first_person_component
        local rotation = component and component.rotation
        if not rotation then
            if not controller_observation.downstream_missing_logged then
                controller_observation.downstream_missing_logged = true
                mod:warning(
                    "DARKTIDEVR_AIM downstream unavailable component=first_person"
                )
            end
            return
        end
        local ok, yaw, pitch, roll = pcall(
            Quaternion.to_yaw_pitch_roll, rotation)
        if not ok then
            if not controller_observation.downstream_missing_logged then
                controller_observation.downstream_missing_logged = true
                mod:warning(
                    "DARKTIDEVR_AIM downstream unavailable rotation=%s",
                    tostring(yaw)
                )
            end
            return
        end
        local forward = Quaternion.forward(rotation)
        controller_observation.downstream_last_sequence =
            controller_observation.last_sequence
        mod:info(
            "DARKTIDEVR_AIM downstream sequence=%d component_ypr=%.4f,%.4f,%.4f forward=%.4f,%.4f,%.4f",
            controller_observation.last_sequence,
            yaw,
            pitch,
            roll,
            Vector3.x(forward),
            Vector3.y(forward),
            Vector3.z(forward)
        )
    end)

mod:hook_safe(
    require("scripts/managers/ui/ui_manager"),
    "open_view",
    function(self, view_name)
    presentation.on_view_open(self, view_name)
end)

mod:hook_safe(
    require("scripts/managers/ui/ui_manager"),
    "close_view",
    function(self, view_name)
    presentation.on_view_close(self, view_name)
end)

-- The current hub build opens its system menu through the preloaded
-- SystemView instance without traversing the UIManager methods or active-view
-- list used by loading/vendor views. Observe the lifecycle at the view class
-- as an explicit compatibility seam.
mod:hook_safe("SystemView", "on_enter", function()
    presentation.fullscreen_empty_updates = 0
    presentation.publish_mode(4, "SystemView.on_enter")
end)

mod:hook_safe("SystemView", "on_exit", function()
    presentation.mode = 4
    presentation.fullscreen_empty_updates = 0
end)

mod:hook_safe("CameraManager", "_update_camera", function(self, _, _, viewport_name)
    if viewport_name ~= primary_viewport_name then
        return
    end

    local ok, error_message = pcall(update_stereo, self)

    if not ok then
        failed = true
        requested = false
        pcall(teardown)
        mod:error("DARKTIDEVR_STEREO failed_closed error=%s", tostring(error_message))
    end
end)

local function retain_world_marker_command(destroy, owner, id)
    if world_marker_command_capture and id then
        world_marker_left_commands[#world_marker_left_commands + 1] = {
            destroy = destroy,
            owner = owner,
            id = id
        }
    end
end

local function retain_world_marker_commands(destroy, owner, ids)
    if type(ids) == "table" then
        for i = 1, #ids do
            retain_world_marker_command(destroy, owner, ids[i])
        end
    else
        retain_world_marker_command(destroy, owner, ids)
    end
end

local function destroy_marker_bitmap(renderer, id)
    UIRenderer.destroy_bitmap(renderer, id)
end

local function destroy_marker_text(renderer, id)
    UIRenderer.destroy_text(renderer, id)
end

local function destroy_marker_slug_icon(renderer, id)
    UIRenderer.destroy_slug_icon(renderer, id)
end

local function destroy_marker_slug_picture(renderer, id)
    UIRenderer.destroy_slug_picture(renderer, id)
end

local function destroy_marker_rect(renderer, id)
    Gui.destroy_rect(renderer.gui_retained, id)
end

local function destroy_marker_triangle(renderer, id)
    Gui.destroy_triangle(renderer.gui_retained, id)
end

-- UIRenderer caches its native Gui functions into locals when loaded, so the
-- renderer entry points are the narrow reliable interception seam. During the
-- original marker draw only, force otherwise-immediate primitives into the
-- retained GUI to obtain their IDs; callers still observe the normal nil
-- return. The IDs are destroyed after the left submission.
mod:hook(UIRenderer, "script_draw_bitmap", function(func, self, material,
        position, size, color, retained_id)
    if world_marker_command_capture and not retained_id then
        local id = func(self, material, position, size, color, true)
        retain_world_marker_command(destroy_marker_bitmap, self, id)
        return nil
    end
    return func(self, material, position, size, color, retained_id)
end)

mod:hook(UIRenderer, "script_draw_bitmap_uv", function(func, self, material,
        position, size, uvs, color, retained_id)
    if world_marker_command_capture and not retained_id then
        local id = func(self, material, position, size, uvs, color, true)
        retain_world_marker_command(destroy_marker_bitmap, self, id)
        return nil
    end
    return func(self, material, position, size, uvs, color, retained_id)
end)

mod:hook(UIRenderer, "script_draw_bitmap_3d", function(func, self, material,
        tm, position, layer, size, color, uvs, retained_id)
    if world_marker_command_capture and not retained_id then
        local id = func(
            self, material, tm, position, layer, size, color, uvs, true)
        retain_world_marker_command(destroy_marker_bitmap, self, id)
        return nil
    end
    return func(
        self, material, tm, position, layer, size, color, uvs, retained_id)
end)

mod:hook(UIRenderer, "script_draw_text", function(func, self, value,
        font_size, font_type, position, size, color, options, retained_id)
    if world_marker_command_capture and not retained_id then
        local id = func(
            self, value, font_size, font_type, position, size, color,
            options, true)
        retain_world_marker_command(destroy_marker_text, self, id)
        return nil
    end
    return func(
        self, value, font_size, font_type, position, size, color,
        options, retained_id)
end)

mod:hook(UIRenderer, "draw_slug_icon", function(func, self, resource, index,
        position, size, color, material, flags, retained_id)
    if world_marker_command_capture and not retained_id then
        local id = func(
            self, resource, index, position, size, color, material, flags, true)
        retain_world_marker_command(destroy_marker_slug_icon, self, id)
        return nil
    end
    return func(
        self, resource, index, position, size, color, material, flags,
        retained_id)
end)

mod:hook(UIRenderer, "draw_slug_icon_rotated", function(func, self, resource,
        index, size, position, angle, pivot, color, material, retained_id)
    if world_marker_command_capture and not retained_id then
        local id = func(
            self, resource, index, size, position, angle, pivot, color,
            material, true)
        retain_world_marker_command(destroy_marker_slug_icon, self, id)
        return nil
    end
    return func(
        self, resource, index, size, position, angle, pivot, color, material,
        retained_id)
end)

mod:hook(UIRenderer, "draw_slug_picture", function(func, self, resource,
        position, size, color, material, retained_id)
    if world_marker_command_capture and not retained_id then
        local id = func(self, resource, position, size, color, material, true)
        retain_world_marker_command(destroy_marker_slug_picture, self, id)
        return nil
    end
    return func(self, resource, position, size, color, material, retained_id)
end)

mod:hook(UIRenderer, "draw_slug_multi_icon", function(func, self, resource,
        index, position, size, color, axis, spacing, direction, count,
        material, retained_ids)
    if world_marker_command_capture and not retained_ids then
        local ids = func(
            self, resource, index, position, size, color, axis, spacing,
            direction, count, material, true)
        retain_world_marker_commands(destroy_marker_slug_icon, self, ids)
        return nil
    end
    return func(
        self, resource, index, position, size, color, axis, spacing,
        direction, count, material, retained_ids)
end)

mod:hook(UIRenderer, "draw_rect", function(func, self, position, size, color,
        retained_id)
    if world_marker_command_capture and not retained_id then
        local id = func(self, position, size, color, true)
        retain_world_marker_command(destroy_marker_rect, self, id)
        return nil
    end
    return func(self, position, size, color, retained_id)
end)

mod:hook(UIRenderer, "draw_triangle", function(func, self, position, size,
        style, retained_id)
    if world_marker_command_capture and not retained_id then
        local id = func(self, position, size, style, true)
        retain_world_marker_command(destroy_marker_triangle, self, id)
        return nil
    end
    return func(self, position, size, style, retained_id)
end)

local function tangent_projection(value, lower, upper)
    return (value - lower) / (upper - lower)
end

local function prepare_binocular_clamped_offsets(instance, inverse_scale)
    local offsets = {}
    if not head_render_frusta or not inverse_scale or inverse_scale == 0 then
        return offsets
    end

    -- Native capture's accepted logical-eye mapping submits the primary
    -- Darktide camera to OpenXR view 1 and the replay camera to view 0. Keep
    -- that resource identity here: assigning the runtime frusta by camera
    -- names reverses which physical eye must be inset at an overlap edge.
    local primary_frustum = head_render_frusta[2]
    local replay_frustum = head_render_frusta[1]
    local left_min = math.tan(primary_frustum.left)
    local left_max = math.tan(primary_frustum.right)
    local right_min = math.tan(replay_frustum.left)
    local right_max = math.tan(replay_frustum.right)
    local overlap_min = math.max(left_min, right_min)
    local overlap_max = math.min(left_max, right_max)
    if overlap_min >= overlap_max then
        return offsets
    end

    local root_size = UIScenegraph.size_scaled(
        instance._ui_scenegraph,
        "screen"
    )
    local root_width = root_size[1] * RESOLUTION_LOOKUP.scale
    if root_width <= 0 then
        return offsets
    end

    for _, markers in pairs(instance._markers_by_type) do
        for i = 1, #markers do
            local marker = markers[i]
            local angle = marker.angle
            if marker.draw and marker.is_clamped and angle and
                    (math.abs(angle) < 0.001 or
                        math.abs(math.abs(angle) - math.pi) < 0.001) then
                local offset = marker.widget.offset
                local original_x = offset[1]
                local original_y = offset[2]
                local pixel_x = original_x / inverse_scale
                local clamped_left = pixel_x < root_width * 0.5
                local margin_fraction = clamped_left and
                    pixel_x / root_width or
                    (root_width - pixel_x) / root_width
                margin_fraction = math.max(
                    0,
                    math.min(margin_fraction, 0.25)
                )
                local overlap_width = overlap_max - overlap_min
                local shared_tangent = clamped_left and
                    overlap_min + overlap_width * margin_fraction or
                    overlap_max - overlap_width * margin_fraction
                local left_x = tangent_projection(
                    shared_tangent,
                    left_min,
                    left_max
                ) * root_width * inverse_scale
                local right_x = tangent_projection(
                    shared_tangent,
                    right_min,
                    right_max
                ) * root_width * inverse_scale
                offsets[marker] = {
                    original_x = original_x,
                    original_y = original_y,
                    left_x = left_x,
                    right_x = right_x,
                    y = original_y
                }
                -- The first draw must also use the shared angular clamp. A
                -- numerically identical texture coordinate in both eyes is
                -- not binocular because the runtime eye frusta are
                -- asymmetric.
                offset[1] = left_x
            end
        end
    end
    return offsets
end

mod:hook(
    "HudElementWorldMarkers",
    "_draw_markers",
    function(func, self, dt, t, input_service, ui_renderer, render_settings)
        local capture = active and stereo_world_markers_requested and
            not world_marker_reprojecting
        local inverse_scale = ui_renderer.inverse_scale or
            render_settings.inverse_scale or 1
        local binocular_offsets = nil
        if capture then
            binocular_offsets = prepare_binocular_clamped_offsets(
                self,
                inverse_scale
            )
            world_marker_command_capture = true
        end

        local result = func(
            self,
            dt,
            t,
            input_service,
            ui_renderer,
            render_settings
        )

        if capture then
            world_marker_command_capture = false
            world_markers_context = {
                instance = self,
                dt = dt,
                t = t,
                input_service = input_service,
                ui_renderer = ui_renderer,
                render_settings = render_settings,
                -- UIRenderer.end_pass clears this transient field before the
                -- level-world submission hook runs, so retain the scalar now.
                inverse_scale = inverse_scale,
                binocular_offsets = binocular_offsets
            }
        end

        return result
    end
)

-- The interaction prompt (for example "[F] Inspect Operative") is a separate
-- HUD element, but its scenegraph pivot is copied from the active world-marker
-- widget. Capture its left-eye primitives into the same removable set and
-- replay it after the marker pivot has been reprojected for the right eye.
mod:hook(
    "HudElementInteraction",
    "_draw_widgets",
    function(func, self, dt, t, input_service, ui_renderer, render_settings)
        local capture = active and stereo_world_markers_requested and
            not world_marker_reprojecting
        if capture then
            local presentation = self._active_presentation_data
            if presentation and presentation.marker then
                -- HudElementInteraction copies its pivot during update, while
                -- HudElementWorldMarkers can project the source marker later
                -- in the same frame. Refresh at the draw boundary so the
                -- normal left-eye draw and the right-eye replay both consume
                -- a marker coordinate produced for their own camera.
                self:_update_interaction_hud_position(0, t)
                UIScenegraph.update_scenegraph(
                    self._ui_scenegraph,
                    render_settings.scale
                )
            end
        end
        if capture then
            world_marker_command_capture = true
        end

        local result = func(
            self,
            dt,
            t,
            input_service,
            ui_renderer,
            render_settings
        )

        if capture then
            world_marker_command_capture = false
            interaction_hud_context = {
                instance = self,
                dt = dt,
                t = t,
                input_service = input_service,
                ui_renderer = ui_renderer,
                render_settings = render_settings
            }
        end

        return result
    end
)

local function remove_left_world_marker_commands()
    local command_count = #world_marker_left_commands
    if not world_marker_capture_logged and command_count > 0 then
        mod:info(
            "DARKTIDEVR_STEREO marker_commands retained=%d",
            command_count
        )
        world_marker_capture_logged = true
    end
    for i = 1, #world_marker_left_commands do
        local command = world_marker_left_commands[i]
        command.destroy(command.owner, command.id)
    end
    table.clear(world_marker_left_commands)
end

local function enqueue_world_markers_for_camera(camera)
    local context = world_markers_context
    if not context or not camera then
        return false
    end

    local instance = context.instance
    local original_camera = instance._player_camera
    if not original_camera or original_camera == camera then
        return false
    end

    -- The normal HUD update already stored a world position and left-eye
    -- screen coordinate for every marker. Apply only the projection delta for
    -- the right eye. This avoids replaying lifetime, raycast, animation and
    -- template-update side effects outside their normal update scope.
    local inverse_scale = context.inverse_scale
    local adjusted_offsets = {}
    for _, markers in pairs(instance._markers_by_type) do
        for i = 1, #markers do
            local marker = markers[i]
            if marker.draw and marker.position then
                local world_position = Vector3Box.unbox(marker.position)
                local offset = marker.widget.offset
                local binocular = context.binocular_offsets and
                    context.binocular_offsets[marker]
                adjusted_offsets[#adjusted_offsets + 1] = {
                    offset = offset,
                    x = binocular and binocular.original_x or offset[1],
                    y = binocular and binocular.original_y or offset[2]
                }

                if binocular then
                    offset[1] = binocular.right_x
                    offset[2] = binocular.y
                else
                    local left_screen = Camera.world_to_screen(
                        original_camera,
                        world_position
                    )
                    local right_screen = Camera.world_to_screen(
                        camera,
                        world_position
                    )
                    offset[1] = offset[1] +
                        (right_screen.x - left_screen.x) * inverse_scale
                    offset[2] = offset[2] +
                        (right_screen.y - left_screen.y) * inverse_scale
                end
            end
        end
    end

    instance._player_camera = camera

    context.render_settings.start_layer = instance._draw_layer
    UIRenderer.begin_pass(
        context.ui_renderer,
        instance._ui_scenegraph,
        context.input_service,
        0,
        context.render_settings
    )
    world_marker_reprojecting = true
    instance:_draw_markers(
        0,
        context.t,
        context.input_service,
        context.ui_renderer,
        context.render_settings
    )
    world_marker_reprojecting = false
    UIRenderer.end_pass(context.ui_renderer)

    local interaction_context = interaction_hud_context
    if interaction_context then
        local interaction = interaction_context.instance
        local presentation = interaction._active_presentation_data
        if presentation and presentation.marker then
            -- The marker widget currently contains the right-eye coordinate.
            -- Rebuild only the dependent interaction pivot, then enqueue the
            -- interaction widgets through their normal draw implementation.
            interaction:_update_interaction_hud_position(
                0,
                interaction_context.t
            )
            UIScenegraph.update_scenegraph(
                interaction._ui_scenegraph,
                interaction_context.render_settings.scale
            )
            UIRenderer.begin_pass(
                interaction_context.ui_renderer,
                interaction._ui_scenegraph,
                interaction_context.input_service,
                0,
                interaction_context.render_settings
            )
            world_marker_reprojecting = true
            interaction:_draw_widgets(
                0,
                interaction_context.t,
                interaction_context.input_service,
                interaction_context.ui_renderer,
                interaction_context.render_settings
            )
            world_marker_reprojecting = false
            UIRenderer.end_pass(interaction_context.ui_renderer)
        end
    end
    instance._player_camera = original_camera

    -- Gui draw commands retain the positions passed above. Restore Darktide's
    -- left-eye widget state for the next normal HUD update and for any code
    -- that inspects markers after rendering.
    for i = 1, #adjusted_offsets do
        local saved = adjusted_offsets[i]
        saved.offset[1] = saved.x
        saved.offset[2] = saved.y
    end

    if interaction_context then
        local interaction = interaction_context.instance
        local presentation = interaction._active_presentation_data
        if presentation and presentation.marker then
            interaction:_update_interaction_hud_position(
                0,
                interaction_context.t
            )
            UIScenegraph.update_scenegraph(
                interaction._ui_scenegraph,
                interaction_context.render_settings.scale
            )
        end
    end
    return true
end

mod:hook(
    "UIWorldSpawner",
    "create_viewport",
    function(func, self, camera_unit, viewport_name, viewport_type,
            viewport_layer, shading_environment, shading_callback,
            render_targets)
        local key = tostring(self._world_name) .. ":" .. tostring(viewport_name)

        if not observed_ui_viewports[key] then
            observed_ui_viewports[key] = true
            mod:info(
                "DARKTIDEVR_UI_VIEWPORT world=%s viewport=%s type=%s layer=%s",
                tostring(self._world_name),
                tostring(viewport_name),
                tostring(viewport_type),
                tostring(viewport_layer)
            )
        end

        local target_main_menu = ui_stereo_requested and
            ui_offscreen_requested and
            ui_offscreen_primary_requested and
            self._world_name == "ui_main_menu_world" and
            viewport_name == "ui_main_menu_world_viewport"

        if target_main_menu then
            if ensure_ui_native_hooks() then
                refresh_xr_render_extent()
            end
            destroy_ui_offscreen_resources()
            ui_left_output_target = create_eye_render_target(
                "darktidevr_left_eye_output",
                ui_eye_target_width,
                ui_eye_target_height
            )
            ui_left_render_target = create_eye_render_target(
                "darktidevr_left_eye_final",
                ui_eye_target_width,
                ui_eye_target_height
            )
            render_targets = eye_render_target_mapping(
                ui_left_output_target,
                ui_left_render_target
            )
            viewport_type = "default_with_alpha"
        end

        local result = func(
            self,
            camera_unit,
            viewport_name,
            viewport_type,
            viewport_layer,
            shading_environment,
            shading_callback,
            render_targets
        )

        local target_main_menu_viewport =
            self._world_name == "ui_main_menu_world" and
            viewport_name == "ui_main_menu_world_viewport"

        if ui_native_observer_requested and target_main_menu_viewport then
            if ensure_ui_native_hooks() then
                local marker_result = ui_native_capture.dtvr_enable_marker_log()

                if marker_result ~= 0 then
                    mod:warning("DARKTIDEVR_STEREO marker_log code=%d", marker_result)
                end

                if ui_table4_alias_probe_requested then
                    ui_native_capture.dtvr_enable_table4_alias()
                end

                if ui_candidate_instance_clamp_requested then
                    local clamp_result =
                        ui_native_capture.dtvr_enable_candidate_instance_clamp()
                    mod:info(
                        "DARKTIDEVR_STEREO candidate_instance_clamp enabled result=%d",
                        tonumber(clamp_result)
                    )
                end

                if ui_candidate_table4_probe_requested then
                    local alias_result =
                        ui_native_capture.dtvr_enable_candidate_table4_alias()
                    local clamp_result =
                        ui_native_capture.dtvr_enable_candidate_instance_clamp()
                    mod:info(
                        "DARKTIDEVR_STEREO candidate_table4 enabled alias=%d clamp=%d",
                        tonumber(alias_result),
                        tonumber(clamp_result)
                    )
                end
            end
        end

        if ui_stereo_requested and
            target_main_menu_viewport then

            local native_ready = true
            if ui_native_capture_requested then
                native_ready = enable_ui_native_capture()
            end

            if native_ready and ui_present_capture_requested then
                native_ready = ensure_ui_native_hooks()
                if native_ready then
                    ui_native_capture.dtvr_enable_present_capture()
                end
            end

            local ok = native_ready
            local error_message = native_ready and nil or
                "native capture hooks unavailable"
            if native_ready then
                ok, error_message = pcall(setup_ui_stereo, self)
            end

            if not ok then
                mod:error(
                    "DARKTIDEVR_STEREO ui_setup_failed error=%s",
                    tostring(error_message)
                )
            end
        end


        return result
    end
)

mod:hook_safe("UIWorldSpawner", "_update_camera", function(self)
    if self == ui_stereo_spawner then
        local ok, error_message = pcall(apply_ui_eye_offsets, self)

        if not ok then
            mod:error(
                "DARKTIDEVR_STEREO ui_update_failed error=%s",
                tostring(error_message)
            )
            ui_stereo_spawner = nil
            ui_stereo_world = nil
            ui_stereo_right_viewport = nil
        end
    end
end)

local function update_ui_offscreen_trace()
    if not ui_offscreen_trace_requested or ui_offscreen_trace_complete or
            not ui_offscreen_active or not ui_native_capture then
        return
    end

    ui_offscreen_trace_frame = ui_offscreen_trace_frame + 1
    if ui_offscreen_trace_frame == ui_offscreen_trace_warmup_frames then
        local result = ui_native_capture.dtvr_set_focused_trace_phase(1)
        mod:info(
            "DARKTIDEVR_STEREO offscreen_trace sample_start result=%d",
            tonumber(result)
        )
    elseif ui_offscreen_trace_frame ==
            ui_offscreen_trace_warmup_frames +
                ui_offscreen_trace_sample_frames then
        ui_native_capture.dtvr_set_focused_trace_phase(0)
        ui_offscreen_trace_complete = true
        mod:info(
            "DARKTIDEVR_STEREO offscreen_trace complete records=%d",
            tonumber(ui_native_capture.dtvr_focused_trace_count())
        )
    end
end

-- Level stories can animate the menu camera after UIWorldSpawner.update. Copy
-- the final primary pose at the last reliable boundary before the world is
-- submitted, so the duplicate cannot lag or remain at its creation pose.
mod:hook(ScriptWorld, "render", function(func, world, ...)
    if world == ui_stereo_world and ui_stereo_spawner then
        update_ui_alternating_full()
        update_ui_full_origin_ab()
        update_ui_rect_matrix()
        update_ui_rect_trace()
        update_ui_focused_ab_trace()
        update_ui_offscreen_trace()
        local ok, error_message = pcall(apply_ui_eye_offsets, ui_stereo_spawner)

        if not ok then
            mod:error(
                "DARKTIDEVR_STEREO ui_pre_render_sync_failed error=%s",
                tostring(error_message)
            )
        end

    end

    if world == active_world and active and ui_native_capture_active and
            ui_native_capture then
        local primary = ScriptWorld.viewport(world, primary_viewport_name)
        local right = ScriptWorld.viewport(world, right_viewport_name)

        if ui_native_sync_requested and not ui_native_sync_initialized then
            ui_native_capture.dtvr_reset_eye_capture_tags()
            ui_native_sync_initialized = true
        end

        ScriptWorld.activate_viewport(world, primary)
        ScriptWorld.deactivate_viewport(world, right)
        if ui_reset_dlss_each_eye_requested then
            Application.reset_dlss()
        end
        local left_target = tonumber(
            ui_native_capture.dtvr_boundary_eye_capture_count(0)
        ) + 1
        report_native_capture_result(arm_eye_capture(0))
        local pair_start = performance_tick()
        local left_start = pair_start
        local result = func(world, ...)
        local left_end = performance_tick()
        if ui_direct_swapchain_capture_requested then
            report_native_capture_result(
                ui_native_capture.dtvr_capture_armed_swapchain_eye(0)
            )
        elseif ui_native_sync_requested then
            wait_for_eye_capture(0, left_target)
        end

        ScriptWorld.deactivate_viewport(world, primary)
        ScriptWorld.activate_viewport(world, right)
        if stereo_world_markers_requested then
            local marker_ok, marker_result = pcall(
                function()
                    remove_left_world_marker_commands()
                    enqueue_world_markers_for_camera(
                        ScriptViewport.camera(right)
                    )
                end
            )
            if not marker_ok then
                stereo_world_markers_requested = false
                mod:error(
                    "DARKTIDEVR_STEREO marker_reprojection_failed error=%s",
                    tostring(marker_result)
                )
            end
        end
        if ui_reset_dlss_each_eye_requested then
            Application.reset_dlss()
        end
        local right_target = tonumber(
            ui_native_capture.dtvr_boundary_eye_capture_count(1)
        ) + 1
        report_native_capture_result(arm_eye_capture(1))
        local right_start = performance_tick()
        if not render_second_eye_from_prepared_frame(
                world, primary, right) then
            func(world, ...)
        end
        local right_end = performance_tick()
        if ui_direct_swapchain_capture_requested then
            report_native_capture_result(
                ui_native_capture.dtvr_capture_armed_swapchain_eye(1)
            )
        elseif ui_native_sync_requested then
            wait_for_eye_capture(1, right_target)
        end

        -- Restore the normal active set for update code outside this hook.
        ScriptWorld.activate_viewport(world, primary)
        record_render_timings(
            "gameplay",
            left_start and left_end and left_end - left_start or nil,
            right_start and right_end and right_end - right_start or nil,
            pair_start and right_end and right_end - pair_start or nil
        )
        report_native_observer()
        return result
    end

    if world == ui_stereo_world and ui_stereo_spawner and
            ui_native_capture_active and ui_native_capture then
        local primary = ui_stereo_spawner._viewport
        local right = ui_stereo_right_viewport

        if ui_native_sync_requested and not ui_native_sync_initialized then
            ui_native_capture.dtvr_reset_eye_capture_tags()
            ui_native_sync_initialized = true
        end

        ScriptWorld.activate_viewport(world, primary)
        ScriptWorld.deactivate_viewport(world, right)
        if ui_reset_dlss_each_eye_requested then
            Application.reset_dlss()
        end
        local left_target = tonumber(
            ui_native_capture.dtvr_boundary_eye_capture_count(0)
        ) + 1
        report_native_capture_result(arm_eye_capture(0))
        local pair_start = performance_tick()
        local left_start = pair_start
        local result = func(world, ...)
        local left_end = performance_tick()
        if ui_direct_swapchain_capture_requested then
            report_native_capture_result(
                ui_native_capture.dtvr_capture_armed_swapchain_eye(0)
            )
        elseif ui_native_sync_requested then
            wait_for_eye_capture(0, left_target)
        end

        ScriptWorld.deactivate_viewport(world, primary)
        ScriptWorld.activate_viewport(world, right)
        if ui_reset_dlss_each_eye_requested then
            Application.reset_dlss()
        end
        local right_target = tonumber(
            ui_native_capture.dtvr_boundary_eye_capture_count(1)
        ) + 1
        report_native_capture_result(arm_eye_capture(1))
        local right_start = performance_tick()
        if not render_second_eye_from_prepared_frame(
                world, primary, right) then
            func(world, ...)
        end
        local right_end = performance_tick()
        if ui_direct_swapchain_capture_requested then
            report_native_capture_result(
                ui_native_capture.dtvr_capture_armed_swapchain_eye(1)
            )
        elseif ui_native_sync_requested then
            wait_for_eye_capture(1, right_target)
        end
        ScriptWorld.activate_viewport(world, primary)

        record_render_timings(
            "character_select",
            left_start and left_end and left_end - left_start or nil,
            right_start and right_end and right_end - right_start or nil,
            pair_start and right_end and right_end - pair_start or nil
        )

        report_native_observer()
        return result
    end

    -- Render each eye as its own world submission. Rendering both active
    -- viewports in a single submission lets view-dependent lighting, decals,
    -- and culling state from one eye leak into or be omitted from the other.
    -- Stingray accepts two submissions of this UI world in the same frame;
    -- keep a guarded fallback so a future engine update cannot take the game
    -- down if that contract changes.
    if world == ui_stereo_world and ui_stereo_spawner and
            ui_sequential_render_requested then
        local primary = ui_stereo_spawner._viewport
        local right = ui_stereo_right_viewport

        ScriptWorld.deactivate_viewport(world, right)
        ScriptWorld.activate_viewport(world, primary)
        local left_ok, left_result = pcall(func, world, ...)

        ScriptWorld.deactivate_viewport(world, primary)
        ScriptWorld.activate_viewport(world, right)
        local right_ok, right_error = pcall(func, world, ...)

        -- Restore the normal active set for update code outside this hook.
        ScriptWorld.activate_viewport(world, primary)

        if not left_ok or not right_ok then
            ui_sequential_render_requested = false
            ScriptWorld.activate_viewport(world, right)
            mod:error(
                "DARKTIDEVR_STEREO sequential_render_failed left=%s right=%s error=%s/%s",
                tostring(left_ok),
                tostring(right_ok),
                left_ok and "none" or tostring(left_result),
                right_ok and "none" or tostring(right_error)
            )

            if not left_ok then
                return func(world, ...)
            end
        end

        return left_result
    end

    if world == ui_stereo_world and ui_stereo_spawner and
            ui_double_render_probe_requested then
        local primary = ui_stereo_spawner._viewport
        local right = ui_stereo_right_viewport
        mod:info("DARKTIDEVR_STEREO double_render step=deactivate_right")
        local activation_ok, activation_error = pcall(
            ScriptWorld.deactivate_viewport,
            world,
            right
        )

        if not activation_ok then
            mod:error("DARKTIDEVR_STEREO double_render deactivate_right=%s", tostring(activation_error))
        end

        mod:info("DARKTIDEVR_STEREO double_render step=render_left")
        local left_ok, left_result = pcall(func, world, ...)
        mod:info(
            "DARKTIDEVR_STEREO double_render render_left_ok=%s error=%s",
            tostring(left_ok),
            left_ok and "none" or tostring(left_result)
        )
        mod:info("DARKTIDEVR_STEREO double_render step=switch_to_right")
        local switch_left_ok, switch_left_error = pcall(
            ScriptWorld.deactivate_viewport,
            world,
            primary
        )
        local switch_right_ok, switch_right_error = pcall(
            ScriptWorld.activate_viewport,
            world,
            right
        )
        mod:info(
            "DARKTIDEVR_STEREO double_render switch_ok=%s/%s error=%s/%s",
            tostring(switch_left_ok),
            tostring(switch_right_ok),
            tostring(switch_left_error),
            tostring(switch_right_error)
        )
        mod:info("DARKTIDEVR_STEREO double_render step=render_right")
        local right_ok, right_result = pcall(func, world, ...)
        mod:info(
            "DARKTIDEVR_STEREO double_render render_right_ok=%s error=%s",
            tostring(right_ok),
            right_ok and "none" or tostring(right_result)
        )

        pcall(ScriptWorld.activate_viewport, world, primary)
        apply_ui_direct_sbs_rects(primary, right)
        ui_double_render_probe_requested = false

        return left_result
    end

    local result = func(world, ...)
    report_native_observer()

    return result
end)

mod:hook_safe("UIWorldSpawner", "destroy", function(self)
    if self == ui_stereo_spawner then
        ui_stereo_spawner = nil
        ui_stereo_world = nil
        ui_stereo_right_viewport = nil
        ui_base_vertical_fov = nil
    end
end)

mod:hook("MainMenuView", "draw", function(func, self, dt, t, input_service, layer)
    if ui_offscreen_active and ui_left_render_target and ui_right_render_target then
        if not ui_compositor_package_loaded then
            if not ui_compositor_package_id and not ui_compositor_package_failed and
                    Managers.package then
                local function on_loaded()
                    ui_compositor_package_loaded = true
                    mod:info("DARKTIDEVR_STEREO compositor_package_loaded")
                end
                local ok, package_id = pcall(
                    Managers.package.load,
                    Managers.package,
                    ui_compositor_package,
                    ui_compositor_package_reference,
                    on_loaded
                )

                if ok then
                    ui_compositor_package_id = package_id
                    mod:info("DARKTIDEVR_STEREO compositor_package_requested")
                else
                    ui_compositor_package_failed = true
                    mod:error(
                        "DARKTIDEVR_STEREO compositor_package_failed error=%s",
                        tostring(package_id)
                    )
                end
            end

            return
        end

        local gui = self._ui_renderer.gui

        UIRenderer.clear_render_pass_queue(self._ui_renderer)
        UIRenderer.add_render_pass(self._ui_renderer, 1, "to_screen", false)

        if not ui_left_material then
            local material = Gui.create_material(
                gui,
                ui_compositor_material,
                GuiMaterialFlag.GUI_RENDER_PASS_LAYER
            )
            Material.set_resource(
                material,
                "source",
                ui_compositor_left_output_probe_requested and
                    ui_left_output_target or ui_left_render_target
            )
            ui_left_material = { gui = gui, material = material }
        end

        if not ui_right_material then
            local material = Gui.create_material(
                gui,
                ui_compositor_material,
                GuiMaterialFlag.GUI_RENDER_PASS_LAYER
            )
            Material.set_resource(material, "source", ui_right_render_target)
            ui_right_material = { gui = gui, material = material }
        end

        local width, height = Application.back_buffer_size()
        local half_width = width * 0.5
        -- Preserve one source row per destination row for the band-control
        -- probe. The desktop client crops the excess instead of resampling
        -- 2304 source rows into its 2135-row client area.
        local composite_height = ui_eye_target_height
        local composite_layer = (layer or 0) + 1000
        -- The blur-mask shader derives its default UVs from screen position.
        -- Explicit local UVs are therefore required when placing two complete
        -- render targets side by side; otherwise each half samples only the
        -- corresponding half of its source texture.
        local white = Color(255, 255, 255, 255)
        local bitmap_options = {
            color = white,
            render_pass = "to_screen",
            snap_pixel_positions = false
        }
        Gui2.bitmap_uv(
            gui,
            ui_left_material.material,
            0,
            Vector2(0, 0),
            Vector2(1, 1),
            Vector3(0, 0, composite_layer),
            Vector3(half_width, composite_height, 0),
            bitmap_options
        )
        Gui2.bitmap_uv(
            gui,
            ui_right_material.material,
            0,
            Vector2(0, 0),
            Vector2(1, 1),
            Vector3(half_width, 0, composite_layer),
            Vector3(half_width, composite_height, 0),
            bitmap_options
        )
        return
    end

    if main_menu_ui_hidden then
        return
    end

    return func(self, dt, t, input_service, layer)
end)

mod:command(
    "dtvr_ui_native_capture_on",
    "Disabled unsafe mid-frame native capture experiment",
    function()
        mod:error("Mid-frame capture is disabled; use the Present-boundary producer")
    end
)

mod:command(
    "dtvr_ui_native_capture_off",
    "Return to direct SBS rendering (native hooks remain inert)",
    function()
        ui_native_capture_requested = false
        ui_native_capture_active = false
        teardown_ui_stereo()
        mod:echo("DARKTIDEVR_STEREO native_capture=off")
    end
)

mod:command(
    "dtvr_present_capture_on",
    "Publish the direct SBS halves as shared D3D12 eye textures",
    function()
        if ensure_ui_native_hooks() then
            ui_present_capture_requested = true
            ui_native_capture.dtvr_enable_present_capture()
            mod:echo("DARKTIDEVR_STEREO present_capture=on")
        end
    end
)

mod:command(
    "dtvr_present_capture_off",
    "Stop publishing shared D3D12 eye textures",
    function()
        ui_present_capture_requested = false
        if ui_native_capture then
            ui_native_capture.dtvr_disable_present_capture()
        end
        mod:echo("DARKTIDEVR_STEREO present_capture=off")
    end
)

mod:command(
    "dtvr_ui_offscreen_on",
    "Use independent full-origin render targets after the next menu-world creation",
    function()
        ui_offscreen_requested = true
        mod:echo("Independent eye render targets armed for the next menu-world creation")
    end
)

mod:command(
    "dtvr_ui_offscreen_off",
    "Use the direct side-by-side back-buffer path after the next menu-world creation",
    function()
        ui_offscreen_requested = false
        mod:echo("Direct SBS rendering armed for the next menu-world creation")
    end
)

mod:command(
    "dtvr_ui_stereo_on",
    "Arm the unsafe character-select synchronized-stereo experiment",
    function()
        ui_stereo_requested = true
        mod:echo("Character-select stereo experiment armed for the next viewport creation")
    end
)

mod:command(
    "dtvr_ui_stereo_off",
    "Disarm character-select stereo and restore its mono viewport",
    function()
        ui_stereo_requested = false
        local ok, error_message = pcall(teardown_ui_stereo)

        if not ok then
            mod:error(
                "DARKTIDEVR_STEREO ui_teardown_failed error=%s",
                tostring(error_message)
            )
        end
    end
)

mod:command(
    "dtvr_ui_coincident_eyes_on",
    "Place both character-select eye cameras at the exact same pose",
    function()
        ui_eye_separation = 0

        if ui_stereo_spawner then
            apply_ui_eye_offsets(ui_stereo_spawner)
        end

        mod:echo("Character-select cameras are coincident for eye-diff diagnostics")
    end
)

mod:command(
    "dtvr_ui_coincident_eyes_off",
    "Restore the character-select cameras to 64 mm separation",
    function()
        ui_eye_separation = half_ipd * 2

        if ui_stereo_spawner then
            apply_ui_eye_offsets(ui_stereo_spawner)
        end

        mod:echo("Character-select camera separation restored to 64 mm")
    end
)

mod:command("dtvr_ui_hide_on", "Hide the character-select UI for stereo inspection", function()
    main_menu_ui_hidden = true
    mod:echo("Character-select UI hidden")
end)

mod:command("dtvr_ui_hide_off", "Restore the character-select UI", function()
    main_menu_ui_hidden = false
    mod:echo("Character-select UI restored")
end)

mod:command("dtvr_stereo_on", "Enable the guarded same-tick stereo probe", function()
    failed = false
    requested = true
    mod:echo("DarktideVR stereo probe armed; waiting for the player1 viewport")
end)

mod:command("dtvr_stereo_off", "Disable the stereo probe and restore mono", function()
    requested = false
    local ok, error_message = pcall(teardown)

    if not ok then
        mod:error("DARKTIDEVR_STEREO teardown_failed error=%s", tostring(error_message))
    end

    mod:echo("DarktideVR stereo probe disabled")
end)

mod:command(
    "dtvr_enter_psykhanium",
    "Enter the single-player Psykhanium through the normal training-ground UI",
    function()
        presentation.psykhanium.stage = "open_training_view"
        presentation.psykhanium.deadline = math.huge
        presentation.psykhanium.last_error = nil
        mod:echo("DARKTIDEVR_PSYKHANIUM armed")
    end
)

mod:command(
    "dtvr_psykhanium_status",
    "Report the guarded Psykhanium-entry state machine",
    function()
        mod:echo(
            "DARKTIDEVR_PSYKHANIUM stage=%s error=%s",
            tostring(presentation.psykhanium.stage),
            tostring(presentation.psykhanium.last_error)
        )
    end
)

mod.on_disabled = function()
    requested = false
    ui_stereo_requested = false
    pcall(teardown)
    pcall(teardown_ui_stereo)
    pcall(destroy_ui_offscreen_resources)
end

mod.on_unload = function()
    requested = false
    ui_stereo_requested = false
    pcall(teardown)
    pcall(teardown_ui_stereo)
    pcall(destroy_ui_offscreen_resources)
end
