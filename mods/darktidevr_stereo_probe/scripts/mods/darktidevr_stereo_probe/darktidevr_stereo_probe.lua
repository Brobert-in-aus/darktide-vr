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
local ui_offscreen_trace_requested = false
local ui_offscreen_trace_frame = 0
local ui_offscreen_trace_complete = false
local ui_offscreen_trace_warmup_frames = 180
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
-- Screen-space views have a separate 16:9 design surface. Publishing the
-- portrait eye extent for menus stretched both pixels and pointer coordinates
-- and was the common cause of half-height UI and a duplicate hover that drifted
-- farther from the ray as it moved down the panel.
local ui_runtime_extent_logged = false
local ui_native_capture_requested = true -- copy each completed full-origin eye
local ui_camera_output_candidate_probe_index = -1
local ui_native_observer_requested = false
local diagnostic_render_hooks_requested = false
local vertex_shader_dump_requested = false
-- PSO-time, whitelist-only substitution. Replacement shaders are validated
-- against the live shader interface before D3D12 ever sees them.
local billboard_shader_substitution_requested = true
-- Bounded ownership probe: replace only the pixel-shader partners observed on
-- live c_billboard draws with interface-identical constant-magenta shaders.
-- All five reflected billboard VS variants consume c_billboard[0].xy as the
-- normalized horizontal facing direction. The exact-CBV writer is limited to
-- exactly those two floats; registers 1-3 are unused by those VS variants and
-- registers 4-7 are the complete world-to-clip matrix.
-- The direct constant-buffer candidate was exercised in-headset on
-- 2026-08-26 and did not change the visible billboard orientation.  Keep the
-- hook available for diagnostics, but do not patch production draws while we
-- isolate the head-tracking regression.
local billboard_horizon_lock_requested = false
local billboard_direct_write_requested = true
local billboard_selector_probe_requested = true
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
-- The resource-renderer replay path duplicated only its own background and
-- diagnostics; paired D3D12 traces showed no SystemView-specific draws in the
-- target. Keep it disabled while the untouched to_screen path is traced.
local ui_menu_resource_redirect_requested = false
-- The stock menu PSO/resource boundary is known. Keep the former focused
-- D3D12 trace opt-in only: its post-exit baseline used to remain armed because
-- SystemView.update no longer runs after on_exit, halving subsequent cadence.
local ui_menu_trace_requested = false
-- Bounded causal probe: Darktide exposes only a global DLSS history reset.
-- Reset before both sequential eyes to prevent either camera consuming the
-- other eye's history. This intentionally sacrifices temporal accumulation.
local ui_reset_dlss_each_eye_requested = false
-- Native/no-upscaler probe: after each sequential world submission, copy the
-- directly rendered swapchain before the following eye can overwrite it.
local ui_direct_swapchain_capture_requested = false
local ui_boundary_census_requested = false -- expensive diagnostic logging only
-- Keep the cheap desktop mirror in the same 16:9 coordinate space used by
-- screen GUI. A 1280x768 (5:3) client forced non-uniform scaling and made the
-- engine hover and XR ray disagree increasingly with vertical position.
local ui_mirror_client_width = 1280
local ui_mirror_client_height = 720
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
    gameplay_pressed = nil,
    gameplay_held = nil,
    gameplay_released = nil,
    gameplay_sequence = nil,
    gameplay_movement = nil,
    gameplay_input_enabled = false,
    gameplay_input_active = false,
    gameplay_input_last_check_t = -math.huge,
    gameplay_input_last_sequence = 0,
    gameplay_locomotion_last_frame = -math.huge,
    gameplay_stick_active = false,
    movement_inventory_done = false,
    movement_inventory_last_check_frame = -math.huge,
    last_sequence = 0,
    first_tracked_logged = false,
    right_aim_usable = false,
    right_aim_age_ms = math.huge,
    right_aim_flags = 0,
    right_aim_yaw = nil,
    right_aim_pitch = nil,
    right_aim_roll = nil,
    right_trigger = 0,
    left_stick_x = 0,
    left_stick_y = 0,
    right_stick_x = 0,
    right_stick_y = 0,
    right_grip_usable = false,
    right_grip_flags = 0,
    right_grip_x = nil,
    right_grip_y = nil,
    right_grip_z = nil,
    right_grip_qx = nil,
    right_grip_qy = nil,
    right_grip_qz = nil,
    right_grip_qw = nil,
    left_grip_usable = false,
    left_grip_flags = 0,
    left_grip_x = nil,
    left_grip_y = nil,
    left_grip_z = nil,
    left_grip_qx = nil,
    left_grip_qy = nil,
    left_grip_qz = nil,
    left_grip_qw = nil,
    body_anchor_x = nil,
    body_anchor_y = nil,
    body_anchor_z = nil,
    body_anchor_qx = nil,
    body_anchor_qy = nil,
    body_anchor_qz = nil,
    body_anchor_qw = nil,
    body_head_yaw = nil,
    physical_head_yaw = nil,
    body_visual_yaw = nil,
    body_visual_yaw_last_t = nil,
    body_heading_last_head_yaw = nil,
    body_heading_last_motion_t = -math.huge,
    body_yaw_anchor = nil,
    body_follow_x = 0,
    body_follow_y = 0,
    body_follow_z = 0,
    body_follow_mode = "disabled",
    body_follow_last_check_t = -math.huge,
    body_follow_last_log_t = -math.huge,
    body_follow_last_sequence = 0,
    body_follow_last_x = 0,
    body_follow_last_z = 0,
    body_follow_last_position_x = nil,
    body_follow_last_position_y = nil,
    body_follow_last_position_z = nil,
    body_follow_writes = 0,
    authoring_enabled = false,
    authoring_pose_active = false,
    authoring_unusable_last_flags = nil,
    authoring_unusable_last_log_t = -math.huge,
    authoring_last_check_t = -math.huge,
    authoring_writes = 0,
    epoch_block_sequence = -1,
    downstream_last_sequence = 0,
    downstream_missing_logged = false,
    downstream_forward_x = nil,
    downstream_forward_y = nil,
    downstream_forward_z = nil,
    first_person_seam_last_sequence = 0,
    first_person_seam_last_log_t = -math.huge,
    primary_action_armed = false,
    primary_action_injected = false,
    primary_action_cache_observed = false,
    primary_action_sequence = 0,
    primary_action_cache_frame = nil,
    primary_action_weapon_context_logged = false,
    primary_action_weapon_observed = false,
    primary_action_shot_observed = false,
    primary_action_projectile_observed = false,
    primary_action_stage = "idle",
    primary_action_last_check_t = -math.huge,
    weapon_inventory_done = false,
    weapon_inventory_last_check_frame = -math.huge,
    weapon_pose_trace_enabled = false,
    weapon_pose_trace_last_check_frame = -math.huge,
    weapon_pose_trace_last_log_frame = -math.huge,
    weapon_presentation_enabled = false,
    weapon_presentation_last_check_frame = -math.huge,
    weapon_presentation_last_log_frame = -math.huge,
    weapon_presentation_writes = 0,
    weapon_presentation_clamps = 0,
    weapon_presentation_max_post_error = 0,
    weapon_presentation_block_reason = nil,
    body_rig_inventory_done = false,
    body_rig_inventory_last_check_frame = -math.huge,
    body_visibility_enabled = false,
    body_visibility_update_frame = 0,
    body_visibility_last_check_frame = -math.huge,
    body_visibility_last_apply_frame = -math.huge,
    body_visibility_logged_slots = false,
    body_visibility_faulted = false,
    body_fade_override_logged = false,
    body_camera_anchor_logged = false,
    body_eye_anchor_logged = false,
    body_eye_anchor_unit = nil,
    body_eye_anchor_local_x = nil,
    body_eye_anchor_local_y = nil,
    body_eye_anchor_local_z = nil,
    body_eye_anchor_source = nil,
    body_camera_sweep_start_t = nil,
    body_camera_sweep_last_bucket = -1,
    body_head_visible = true,
    force_hub_first_person_enabled = false,
    body_ik_trace_enabled = false,
    body_ik_trace_last_check_frame = -math.huge,
    body_ik_trace_last_log_frame = -math.huge,
    body_ik_presentation_enabled = false,
    body_ik_presentation_update_frame = 0,
    body_ik_presentation_last_check_frame = -math.huge,
    body_ik_presentation_last_log_frame = -math.huge,
    body_ik_presentation_writes = 0,
    body_ik_presentation_max_error = 0,
    body_ik_presentation_max_angle_error = 0,
    body_ik_basis_last_log_frame = -math.huge,
    body_ik_hand_offsets = {},
    body_ik_hand_anatomy = {},
    body_ik_spine_trace_frame = -math.huge,
    body_ik_torso_axis_unit = nil,
    body_ik_torso_axis_local = nil,
    body_ik_torso_block_reason = false,
    body_ik_torso_residual = nil,
    body_ik_shoulder_block_reason = false,
    body_ik_presentation_faulted = false,
    body_ik_presentation_block_reason = nil,
    ik_input = nil,
    ik_output = nil,
    ik_flags = nil
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
    flat_target_width = 1920,
    flat_target_height = 1080,
    full_second_eye_probe_requested = false,
    full_second_eye_probe_check_frame = 0,
    full_second_eye_probe_last_check_frame = -math.huge,
    head_translation_trace_requested = false,
    head_translation_trace_last_sequence = 0,
    head_translation_trace_interval = 600,
    sequence = 0,
    mode = nil,
    menu_resource_renderer = nil,
    menu_resource_gui = nil,
    menu_resource_clear_time = nil,
    menu_resource_pass_states = setmetatable({}, { __mode = "k" }),
    menu_resource_gui_mismatches = setmetatable({}, { __mode = "k" }),
    menu_resource_invalidated_views = setmetatable({}, { __mode = "k" }),
    world_menu_views = {},
    world_menu_gui = nil,
    world_menu_gui_world = nil,
    world_menu_material = nil,
    world_menu_anchor = nil,
    world_menu_draw_logged = false,
    -- Temporary target-boundary proof for the engine-world menu path. These
    -- opaque marks are authored into the same render pass as the menu. If they
    -- appear on the world panel, target population and sampling are both
    -- proven independently of the SystemView widget draw. Remove after that
    -- live gate. This belongs in the state table rather than a file-scope
    -- local because the mod chunk is at LuaJIT's local-variable ceiling.
    world_menu_target_probe_requested = false,
    -- Temporary boundary diagnostic: composite the redirected menu resource
    -- through Darktide's documented resource-renderer `to_screen` path. This
    -- distinguishes an empty target from a valid target that the world GUI
    -- cannot sample at the required render-graph point.
    world_menu_target_desktop_probe = false,
    fullscreen_view_signature = "",
    fullscreen_empty_updates = 0,
    fullscreen_restore_delay_updates = 12,
    logged_view_classification = {},
    input_inventory_done = false,
    active_menu_view_instance = nil,
    active_menu_input_service = nil,
    system_view_hovered_widget = nil,
    system_view_source_widget = nil,
    dropdown_open_pending = nil,
    dropdown_close_pending = nil,
    options_modal_instance = nil,
    options_modal_widget = nil,
    slider_drag = nil,
    menu_pointer = {
        values = nil,
        sequence = nil,
        timestamp_ns = nil,
        last_sequence = 0,
        available = false,
        active = false,
        x = 0,
        y = 0,
        source_width = 0,
        source_height = 0,
        primary_down = false,
        primary_pressed = false,
        back_down = false,
        back_pressed = false,
        scroll_steps = 0,
        event_sequences_initialized = false,
        primary_press_sequence = 0,
        primary_consumed_sequence = 0,
        back_press_sequence = 0,
        back_consumed_sequence = 0,
        scroll_sequence = 0,
        scroll_consumed_sequence = 0,
        diagnostic_miss_sequence = 0,
    },
    menu_input_probe = {
        stage = "idle",
        poll_updates = 0,
        action = nil,
        hovered_widget = nil,
    },
    vendor_menu_test_view = nil,
    vendor_anchor = {
        valid = false,
        view_name = nil,
        revision = 0,
        published_revision = -1,
        x = 0,
        y = 0,
        z = 0,
        qx = 0,
        qy = 0,
        qz = 0,
        qw = 1,
    },
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
        splash_view = true,
        title_view = true,
        loading_view = true,
        mission_intro_view = true,
        video_view = true,
        splash_video_view = true,
        cutscene_view = true,
    },
    non_gameplay_views = {
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
        int dtvr_set_presentation_state_v2(unsigned int mode,
            unsigned long long sequence, unsigned int source_width,
            unsigned int source_height, unsigned int crop_x,
            unsigned int crop_y, unsigned int crop_width,
            unsigned int crop_height, float maximum_panel_width_metres,
            float maximum_panel_height_metres, int body_panel_pose_valid,
            float panel_x, float panel_y, float panel_z, float panel_qx,
            float panel_qy, float panel_qz, float panel_qw);
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
        int dtvr_set_billboard_pixel_shader_probe(int enabled);
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
        int dtvr_set_billboard_direct_view_direction(float right_x,
            float right_y, int enabled);
        int dtvr_solve_two_bone_ik(const float *input,
            unsigned int input_count, float *output,
            unsigned int output_count, unsigned int *flags);
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
        unsigned long long dtvr_billboard_direct_patch_count(void);
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
        unsigned long long dtvr_billboard_candidate_pair_vertex_shader(
            unsigned int rank);
        unsigned long long dtvr_billboard_candidate_pair_pixel_shader(
            unsigned int rank);
        unsigned long long dtvr_billboard_candidate_pair_count(unsigned int rank);
        unsigned int dtvr_billboard_candidate_pair_vertex_low(unsigned int rank);
        unsigned int dtvr_billboard_candidate_pair_vertex_high(unsigned int rank);
        unsigned int dtvr_billboard_candidate_pair_pixel_low(unsigned int rank);
        unsigned int dtvr_billboard_candidate_pair_pixel_high(unsigned int rank);
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
        int dtvr_read_menu_pointer_state(unsigned int *values,
            unsigned long long *sequence,
            unsigned long long *timestamp_ns);
        int dtvr_read_gameplay_input(int gameplay_active,
            unsigned long long *pressed, unsigned long long *held,
            unsigned long long *released, unsigned long long *sequence,
            float *movement);
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

    local pixel_probe_result = library.dtvr_set_billboard_pixel_shader_probe(
        false and 1 or 0)
    if pixel_probe_result ~= 0 then
        mod:error("DARKTIDEVR_STEREO billboard_pixel_shader_probe_select_failed code=%d",
            pixel_probe_result)
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
        -- Darktide is Z-up. Only c_billboard[0].xy is the shader-proven
        -- horizontal facing direction; the native writer leaves every other
        -- word byte-for-byte unchanged.
        library.dtvr_set_billboard_direct_view_direction(
            1, 0, billboard_direct_write_requested and 1 or 0)
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
    head_pose_values = ffi.new("float[23]")
    head_pose_sequence = ffi.new("unsigned long long[1]")
    controller_observation.values = ffi.new("float[36]")
    controller_observation.tracking_flags = ffi.new("unsigned int[4]")
    controller_observation.buttons = ffi.new("unsigned int[2]")
    controller_observation.sequence = ffi.new("unsigned long long[1]")
    controller_observation.timestamp_ns = ffi.new("unsigned long long[1]")
    presentation.menu_pointer.values = ffi.new("unsigned int[11]")
    presentation.menu_pointer.sequence =
        ffi.new("unsigned long long[1]")
    presentation.menu_pointer.timestamp_ns =
        ffi.new("unsigned long long[1]")
    controller_observation.gameplay_pressed =
        ffi.new("unsigned long long[1]")
    controller_observation.gameplay_held = ffi.new("unsigned long long[1]")
    controller_observation.gameplay_released =
        ffi.new("unsigned long long[1]")
    controller_observation.gameplay_sequence =
        ffi.new("unsigned long long[1]")
    controller_observation.gameplay_movement = ffi.new("float[2]")
    controller_observation.ik_input = ffi.new("float[17]")
    controller_observation.ik_output = ffi.new("float[14]")
    controller_observation.ik_flags = ffi.new("unsigned int[1]")
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
            "13e04962148fc216", "42f73c7d12e99db7",
            "c403cfbf17d9fc49", "30408e39c8028272",
            "e18a274cd89282e8", "f0c85040e349f799",
            "fe64037664924d52", "9edf5361a4db2da1",
            "6a0153ef1f6c56fd", "42e436fb1ef1b392"
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
    local vendor_anchor = presentation.vendor_anchor
    local anchor_changed = mode == 3 and vendor_anchor.valid and
        vendor_anchor.published_revision ~= vendor_anchor.revision
    if not ui_native_capture or
            (presentation.mode == mode and not anchor_changed) then
        return
    end
    presentation.sequence = presentation.sequence + 1
    local flat_mode = mode == 2 or mode == 3 or mode == 4
    -- UI layout is authored at 1920x1080 logical pixels and then multiplied
    -- by RESOLUTION_LOOKUP.scale. The old fixed 1920x1080 crop truncated the
    -- scaled menu and made the XR pointer diverge from engine hotspots.
    local ui_scale = RESOLUTION_LOOKUP and RESOLUTION_LOOKUP.scale or 1
    local scaled_flat_width = math.floor(
        presentation.flat_target_width * ui_scale + 0.5)
    local scaled_flat_height = math.floor(
        presentation.flat_target_height * ui_scale + 0.5)
    local direct_menu_target = mode == 3 or mode == 4
    -- Interactive menus now have a dedicated RGBA source. Loading screens
    -- still use the portrait window/eye source until they receive their own
    -- resource renderer.
    local source_width = direct_menu_target and math.min(
        scaled_flat_width, ui_eye_target_width) or ui_eye_target_width
    -- The direct D3D12 menu target is created from the full eye-sized render
    -- target. Publish that physical resource extent even though the authored
    -- 16:9 menu occupies only the crop below; otherwise the XR process rejects
    -- the valid shared handle as an extent mismatch.
    local source_height = ui_eye_target_height
    local crop_width = flat_mode and math.min(
        scaled_flat_width, source_width) or source_width
    local crop_height = flat_mode and math.min(
        scaled_flat_height, source_height) or source_height
    -- The stock fullscreen UI is centered vertically inside the portrait eye
    -- target. Its non-transparent bounds were measured at y=735..1512 in a
    -- 2112x2304 resource, so a centered 2112x1188 crop contains the complete
    -- menu instead of the former empty-top/trimmed-bottom region.
    local crop_y = direct_menu_target and math.floor(
        (source_height - crop_height) * 0.5 + 0.5) or 0
    -- Never resize the renderer on a presentation transition. The producer's
    -- shared-eye resources are bound to a swapchain generation; resizing for a
    -- loading panel and restoring on gameplay leaves the harness attached to
    -- the retired generation and silently stops fresh stereo. Flat content is
    -- fitted in the capture/compositor path instead.
    local result = nil
    if mode == 3 and vendor_anchor.valid then
        result = tonumber(ui_native_capture.dtvr_set_presentation_state_v2(
            mode,
            presentation.sequence,
            source_width,
            source_height,
            0,
            crop_y,
            crop_width,
            crop_height,
            2,
            2,
            1,
            vendor_anchor.x,
            vendor_anchor.y,
            vendor_anchor.z,
            vendor_anchor.qx,
            vendor_anchor.qy,
            vendor_anchor.qz,
            vendor_anchor.qw
        ))
    else
        result = tonumber(ui_native_capture.dtvr_set_presentation_state(
            mode,
            presentation.sequence,
            source_width,
            source_height,
            0,
            crop_y,
            crop_width,
            crop_height,
            2,
            2
        ))
    end
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
    if mode == 3 then
        vendor_anchor.published_revision = vendor_anchor.revision
    end
    mod:info(
        "DARKTIDEVR_PRESENTATION mode=%d sequence=%d reason=%s source=%dx%d crop=0,%d,%dx%d",
        mode,
        presentation.sequence,
        tostring(reason),
        source_width,
        source_height,
        crop_y,
        crop_width,
        crop_height
    )
end

function presentation.menu_resource_extent()
    local scale = RESOLUTION_LOOKUP and RESOLUTION_LOOKUP.scale or 1
    return math.min(
            math.floor(presentation.flat_target_width * scale + 0.5),
            ui_eye_target_width),
        math.min(
            math.floor(presentation.flat_target_height * scale + 0.5),
            ui_eye_target_height)
end

function presentation.world_menu_active()
    return presentation.active_menu_view_instance ~= nil or
        next(presentation.world_menu_views) ~= nil
end

function presentation.destroy_world_menu_surface()
    local world = presentation.world_menu_gui_world
    local gui = presentation.world_menu_gui
    if world and gui then
        pcall(World.destroy_gui, world, gui)
    end
    presentation.world_menu_gui = nil
    presentation.world_menu_gui_world = nil
    presentation.world_menu_material = nil
    presentation.world_menu_anchor = nil
    presentation.world_menu_draw_logged = false
end

function presentation.destroy_menu_resource()
    presentation.destroy_world_menu_surface()
    local renderer = presentation.menu_resource_renderer
    local gui = presentation.menu_resource_gui
    if renderer then
        if gui and renderer.render_target_material then
            pcall(Gui.destroy_material, gui, renderer.render_target_material)
        end
        if renderer.render_target then
            pcall(Renderer.destroy_resource, renderer.render_target)
        end
    end
    presentation.menu_resource_renderer = nil
    presentation.menu_resource_gui = nil
    presentation.menu_resource_clear_time = nil
    presentation.menu_resource_pass_states = setmetatable({}, { __mode = "k" })
    presentation.menu_resource_gui_mismatches =
        setmetatable({}, { __mode = "k" })
    presentation.menu_resource_invalidated_views =
        setmetatable({}, { __mode = "k" })
end

function presentation.invalidate_retained_widgets(widgets)
    local count = 0
    if type(widgets) ~= "table" then
        return count
    end
    for i = 1, #widgets do
        local widget = widgets[i]
        if widget then
            widget.dirty = true
            local passes = widget.passes
            if type(passes) == "table" then
                for j = 1, #passes do
                    local pass = passes[j]
                    if pass and pass.retained_mode and pass.data then
                        pass.data.dirty = true
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

function presentation.ensure_menu_resource(source_renderer)
    local resource_renderer = presentation.menu_resource_renderer
    if resource_renderer then
        return resource_renderer
    end
    local width, height = presentation.menu_resource_extent()
    local ok, created = pcall(
        UIRenderer.create_resource_renderer,
        source_renderer.world,
        source_renderer.gui,
        source_renderer.gui_retained,
        "darktidevr_menu_ui",
        "content/ui/materials/render_target_masks/ui_render_target_straight_blur",
        width,
        height,
        true
    )
    if not ok then
        mod:error(
            "DARKTIDEVR_MENU_TARGET create_failed renderer=%s error=%s",
            tostring(source_renderer.name),
            tostring(created))
        return nil
    end
    presentation.menu_resource_renderer = created
    presentation.menu_resource_gui = source_renderer.gui
    mod:info(
        "DARKTIDEVR_MENU_TARGET created width=%d height=%d renderer=%s",
        width,
        height,
        tostring(source_renderer.name))
    return created
end

function presentation.draw_world_menu_surface(world, position, rotation)
    if not presentation.world_menu_active() then
        if presentation.world_menu_gui then
            presentation.destroy_menu_resource()
        end
        return
    end
    local resource_renderer = presentation.menu_resource_renderer
    local render_target = resource_renderer and resource_renderer.render_target
    if not render_target then
        return
    end
    if presentation.world_menu_gui_world ~= world then
        presentation.destroy_world_menu_surface()
    end
    if not presentation.world_menu_gui then
        local gui = World.create_world_gui(
            world, Matrix4x4.identity(), 1, 1)
        local material = Gui.create_material(
            gui,
            ui_compositor_material,
            GuiMaterialFlag.GUI_RENDER_PASS_LAYER)
        Material.set_resource(material, "source", render_target)
        presentation.world_menu_gui = gui
        presentation.world_menu_gui_world = world
        presentation.world_menu_material = material
    end
    if not presentation.world_menu_anchor then
        local yaw_rotation = Quaternion.axis_angle(
            Vector3.up(), Quaternion.yaw(rotation))
        local forward = Quaternion.forward(yaw_rotation)
        local tm = Matrix4x4.identity()
        -- Darktide's Gui 2D coordinates occupy transform X/Z (see
        -- UIRenderer.draw_rect_rotated, which maps screen Y to translation Z).
        -- The previous basis put transform Z along -camera-forward and made
        -- the menu lie on the floor. Keep X camera-right, Z world-up and the
        -- transform normal on horizontal camera-forward.
        Matrix4x4.set_right(tm, Quaternion.right(yaw_rotation))
        Matrix4x4.set_forward(tm, forward)
        Matrix4x4.set_up(tm, Vector3.up())
        Matrix4x4.set_translation(tm, position + forward * 2)
        presentation.world_menu_anchor = Matrix4x4Box(tm)
    end
    local tm = presentation.world_menu_anchor:unbox()
    local width = 2
    local height = width * 9 / 16
    -- The render-target mask material normally derives UVs from screen
    -- position.  That is correct for a fullscreen 2D composite, but a world
    -- GUI has no corresponding screen-space rectangle and sampled black in
    -- the previous Gui.bitmap_3d path.  Gui2's 3D overload exposes the same
    -- explicit local UV contract used by the working SBS compositor.
    Gui2.bitmap_3d(
        presentation.world_menu_gui,
        presentation.world_menu_material,
        GuiMaterialFlag.GUI_RENDER_PASS_LAYER,
        tm,
        1000,
        {
            color = Color(255, 255, 255, 255),
            position_offset = Vector3(-width * 0.5, -height * 0.5, 0),
            size = Vector2(width, height),
            uv00 = Vector2(0, 0),
            uv11 = Vector2(1, 1),
        })
    -- A world-owned opaque backing plane makes the geometry independently
    -- observable if the menu render target is transparent or not yet ready.
    -- It also prevents the live scene from reducing menu legibility without
    -- applying any post-process blur to either eye.
    Gui.rect_3d(
        presentation.world_menu_gui,
        tm,
        Vector2(-width * 0.5, -height * 0.5),
        999,
        Vector2(width, height),
        Color(255, 8, 10, 12))
    if not presentation.world_menu_draw_logged then
        presentation.world_menu_draw_logged = true
        mod:info(
            "DARKTIDEVR_WORLD_MENU active width=%.3f height=%.3f distance=2.000",
            width,
            height)
    end
end

function presentation.classify_active_view(manager, view_name)
    if presentation.non_gameplay_views[view_name] then
        return nil, "non_gameplay"
    end
    if presentation.flat_loading_views[view_name] then
        return 2, "loading_or_cinematic"
    end
    if presentation.vendor_anchor.valid and
            presentation.vendor_anchor.view_name == view_name then
        return 3, "interacted_world_anchor"
    end
    if presentation.world_menu_views[view_name] then
        return 4, "world_preserved_menu"
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
    local observed_world_menu_views = {}
    for i = 1, #views do
        local view_name = views[i]
        local mode, reason = presentation.classify_active_view(manager, view_name)
        if mode then
            classified[#classified + 1] = tostring(view_name) .. ":" .. reason
            if mode == 2 then
                desired_mode = mode
            elseif mode == 3 or mode == 4 then
                observed_world_menu_views[view_name] = true
                -- Interactive menus keep the stereo projection alive, but the
                -- compositor still needs their distinct presentation mode in
                -- order to attach the additive shared-menu quad.  Recording
                -- the view without selecting its mode left the producer
                -- publishing menu frames that no consumer ever opened.
                desired_mode = mode
            end
        end
    end
    presentation.world_menu_views = observed_world_menu_views
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
            if mode == 2 then
                presentation.publish_mode(mode, tostring(view_name) .. ":" .. reason)
            else
                presentation.world_menu_views[view_name] = true
                presentation.publish_mode(
                    mode, tostring(view_name) .. ":world_space_menu")
            end
        end
    end
end

function presentation.on_view_close(manager, view_name)
    mod:info(
        "DARKTIDEVR_PRESENTATION close view=%s",
        tostring(view_name)
    )
    local vendor_anchor = presentation.vendor_anchor
    presentation.world_menu_views[view_name] = nil
    if vendor_anchor.valid and vendor_anchor.view_name == view_name then
        vendor_anchor.valid = false
        vendor_anchor.view_name = nil
        vendor_anchor.revision = vendor_anchor.revision + 1
        mod:info(
            "DARKTIDEVR_PRESENTATION world_anchor cleared view=%s revision=%d",
            tostring(view_name),
            vendor_anchor.revision
        )
    end
    if not presentation.world_menu_active() then
        presentation.destroy_menu_resource()
    end
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

function presentation.trigger_option(manager, view_name, display_name)
    local view = manager:view_instance(view_name)
    local definitions = view and view._base_definitions
    local options = definitions and definitions.button_options_definitions
    if type(options) ~= "table" then
        return false, "option_definitions_not_ready"
    end
    for index = 1, #options do
        local option = options[index]
        if option and option.display_name == display_name then
            local widget_name = "option_button_" .. tostring(index)
            local ok, reason = presentation.trigger_widget(
                manager, view_name, widget_name)
            if ok then
                mod:info(
                    "DARKTIDEVR_PSYKHANIUM selected option=%s index=%d widget=%s",
                    tostring(display_name), index, widget_name)
            end
            return ok, reason
        end
    end
    return false, "semantic_option_missing"
end

function presentation.update_psykhanium(manager, t)
    local state = presentation.psykhanium
    if (state.stage == "idle" or state.stage == "blocked" or
            state.stage == "complete") and Mods and Mods.lua and Mods.lua.io then
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
                -- Steam/launcher/login startup can exceed five minutes during
                -- unattended runs. Keep the one-shot armed until the hub is
                -- genuinely ready; later stages retain their short deadlines.
                state.deadline = t + 1200
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
        local ok, reason = presentation.trigger_option(
            manager,
            "training_grounds_view",
            "loc_training_grounds_view_shooting_range_text")
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
        local options_view = manager:view_instance("training_grounds_options_view")
        local mechanism_context = options_view and options_view._context and
            options_view._context.mechanism_context
        local mission_name = mechanism_context and mechanism_context.mission_name
        if mission_name ~= "tg_shooting_range" then
            state.stage = "blocked"
            state.last_error = "unexpected_mission:" .. tostring(mission_name)
            mod:error(
                "DARKTIDEVR_PSYKHANIUM blocked stage=verify_options mission=%s",
                tostring(mission_name))
            return
        end
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
        local mission_ok, mission_name = false, nil
        if Managers.state.mission and
                type(Managers.state.mission.mission_name) == "function" then
            mission_ok, mission_name = pcall(
                Managers.state.mission.mission_name,
                Managers.state.mission)
        end
        if ok and mission_ok and mission_name == "tg_shooting_range" then
            state.stage = "complete"
            state.last_error = nil
            mod:info(
                "DARKTIDEVR_PSYKHANIUM result=pass game_mode=%s mission=%s",
                tostring(game_mode), tostring(mission_name))
        end
    end
end

function presentation.update_system_menu_test(manager)
    if not Mods or not Mods.lua or not Mods.lua.io then
        return
    end

    local flag_path =
        "./../mods/darktidevr_stereo_probe/darktidevr_open_system_menu.flag"
    local flag = Mods.lua.io.open(flag_path, "r")
    if not flag then
        return
    end

    local request = flag:read("*all")
    flag:close()
    local command = string.match(request or "", "^%s*(%a+)")
    if command ~= "open" and command ~= "close" then
        return
    end

    local consumed = Mods.lua.io.open(flag_path, "w")
    if consumed then
        consumed:write("consumed\n")
        consumed:close()
    end

    local active = manager:view_active("system_view")
    if command == "close" then
        if not active then
            mod:info(
                "DARKTIDEVR_MENU_INPUT system_menu_test result=already_closed")
            return
        end
        local ok, result = pcall(manager.close_view, manager, "system_view")
        if ok then
            mod:info(
                "DARKTIDEVR_MENU_INPUT system_menu_test result=close_requested")
        else
            mod:error(
                "DARKTIDEVR_MENU_INPUT system_menu_test result=close_failed error=%s",
                tostring(result))
        end
        return
    end

    if active then
        mod:info(
            "DARKTIDEVR_MENU_INPUT system_menu_test result=already_active")
        return
    end

    local ok, result = pcall(manager.open_view, manager, "system_view")
    if ok then
        mod:info(
            "DARKTIDEVR_MENU_INPUT system_menu_test result=requested")
    else
        mod:error(
            "DARKTIDEVR_MENU_INPUT system_menu_test result=failed error=%s",
            tostring(result))
    end
end

function presentation.update_vendor_menu_test(manager)
    if not Mods or not Mods.lua or not Mods.lua.io then
        return
    end

    local flag_path =
        "./../mods/darktidevr_stereo_probe/darktidevr_open_vendor_menu.flag"
    local flag = Mods.lua.io.open(flag_path, "r")
    if not flag then
        return
    end
    local request = flag:read("*all")
    flag:close()
    local command = string.match(request or "", "^%s*([%a_]+)")
    local allowed = {
        crafting = "crafting_view",
        contracts = "contracts_background_view",
    }
    if command ~= "close" and not allowed[command] then
        return
    end

    local consumed = Mods.lua.io.open(flag_path, "w")
    if consumed then
        consumed:write("consumed\n")
        consumed:close()
    end

    if command == "close" then
        local view_name = presentation.vendor_menu_test_view
        if not view_name or not manager:view_active(view_name) then
            mod:info(
                "DARKTIDEVR_MENU_INPUT vendor_menu_test result=already_closed")
            presentation.vendor_menu_test_view = nil
            return
        end
        local ok, result = pcall(manager.close_view, manager, view_name)
        mod:info(
            "DARKTIDEVR_MENU_INPUT vendor_menu_test result=%s view=%s detail=%s",
            ok and "close_requested" or "close_failed",
            tostring(view_name), tostring(result))
        if ok then
            presentation.vendor_menu_test_view = nil
        end
        return
    end

    local view_name = allowed[command]
    if manager:view_active(view_name) then
        mod:info(
            "DARKTIDEVR_MENU_INPUT vendor_menu_test result=already_active view=%s",
            view_name)
        presentation.vendor_menu_test_view = view_name
        return
    end

    -- This guarded diagnostic has no physical interactee from which to derive
    -- a vendor anchor. Keep it on the generic horizon-locked board while the
    -- view's native shader batch is traced; real ViewInteraction opens still
    -- use the NPC-relative mode-3 anchor.
    presentation.world_menu_views[view_name] = true
    presentation.vendor_menu_test_view = view_name
    local ok, result = pcall(manager.open_view, manager, view_name)
    if ok then
        mod:info(
            "DARKTIDEVR_MENU_INPUT vendor_menu_test result=requested view=%s",
            view_name)
    else
        presentation.world_menu_views[view_name] = nil
        presentation.vendor_menu_test_view = nil
        mod:error(
            "DARKTIDEVR_MENU_INPUT vendor_menu_test result=failed view=%s error=%s",
            view_name, tostring(result))
    end
end

function presentation.scan_input_services(manager)
    if presentation.input_inventory_done or not Mods or not Mods.lua or
            not Mods.lua.io then
        return
    end
    local flag_path =
        "./../mods/darktidevr_stereo_probe/darktidevr_input_inventory.flag"
    local flag = Mods.lua.io.open(flag_path, "r")
    if not flag then
        return
    end
    local request = flag:read("*all")
    flag:close()
    if not string.find(request or "", "scan", 1, true) then
        return
    end
    local consumed = Mods.lua.io.open(flag_path, "w")
    if consumed then
        consumed:write("consumed\n")
        consumed:close()
    end
    presentation.input_inventory_done = true
    local services = manager and manager._input_services or {}
    for service_name, service in pairs(services) do
        local fields = {}
        for key, value in pairs(service) do
            fields[#fields + 1] = tostring(key) .. ":" .. type(value)
        end
        table.sort(fields)
        while #fields > 80 do
            table.remove(fields)
        end
        mod:info(
            "DARKTIDEVR_INPUT inventory service=%s fields=%s",
            tostring(service_name),
            table.concat(fields, ",")
        )
        for field_name, values in pairs(service) do
            local lower_name = string.lower(tostring(field_name))
            if type(values) == "table" and
                    (string.find(lower_name, "action", 1, true) or
                     string.find(lower_name, "alias", 1, true)) then
                local names = {}
                for name in pairs(values) do
                    local lower = string.lower(tostring(name))
                    if string.find(lower, "action", 1, true) or
                            string.find(lower, "attack", 1, true) or
                            string.find(lower, "weapon", 1, true) or
                            string.find(lower, "shoot", 1, true) then
                        names[#names + 1] = tostring(name)
                    end
                end
                table.sort(names)
                while #names > 100 do
                    table.remove(names)
                end
                mod:info(
                    "DARKTIDEVR_INPUT inventory service=%s table=%s names=%s",
                    tostring(service_name),
                    tostring(field_name),
                    table.concat(names, ",")
                )
            end
        end
    end
    mod:info("DARKTIDEVR_INPUT inventory result=complete")
end

-- Diagnostic one-shot actions retained from menu-input localization. The
-- production path below no longer depends on Windows cursor or raw-input
-- coordinates: OpenXR publishes source pixels and Lua activates the matching
-- engine widget through force_input_pressed.
function presentation.update_menu_input_probe(manager)
    local probe = presentation.menu_input_probe
    probe.poll_updates = (probe.poll_updates or 0) + 1
    if probe.stage == "idle" and probe.poll_updates >= 15 and
            Mods and Mods.lua and Mods.lua.io then
        probe.poll_updates = 0
        local flag_path =
            "./../mods/darktidevr_stereo_probe/darktidevr_menu_input_probe.flag"
        local flag = Mods.lua.io.open(flag_path, "r")
        if flag then
            local request = flag:read("*all")
            flag:close()
            local action = request and request:match("^%s*([%w_]+)%s*$")
            if action and action ~= "consumed" then
                local consumed = Mods.lua.io.open(flag_path, "w")
                if consumed then
                    consumed:write("consumed\n")
                    consumed:close()
                end
                probe.action = action
                probe.stage = "press"
                mod:info(
                    "DARKTIDEVR_MENU_INPUT probe armed action=%s",
                    tostring(action))
            end
        end
    end
end

function presentation.read_menu_pointer()
    local pointer = presentation.menu_pointer
    pointer.available = false
    pointer.active = false
    pointer.primary_pressed = false
    pointer.back_pressed = false
    pointer.scroll_steps = 0
    if not ui_native_capture or not pointer.values or
            ui_native_capture.dtvr_read_menu_pointer_state(
                pointer.values,
                pointer.sequence,
                pointer.timestamp_ns) ~= 0 then
        return pointer
    end
    local sequence = tonumber(pointer.sequence[0])
    local timestamp_ns = tonumber(pointer.timestamp_ns[0])
    local qpc_frequency = tonumber(ui_native_capture.dtvr_qpc_frequency())
    local age_ns = math.huge
    if qpc_frequency > 0 then
        age_ns = tonumber(ui_native_capture.dtvr_qpc_ticks()) *
            1000000000 / qpc_frequency - timestamp_ns
    end
    local is_new = sequence ~= pointer.last_sequence
    pointer.x = tonumber(pointer.values[1])
    pointer.y = tonumber(pointer.values[2])
    pointer.source_width = tonumber(pointer.values[3])
    pointer.source_height = tonumber(pointer.values[4])
    pointer.available = age_ns >= -5000000 and age_ns <= 100000000
    pointer.active = pointer.available and tonumber(pointer.values[0]) ~= 0 and
        pointer.source_width > 0 and pointer.source_height > 0 and
        pointer.x >= 0 and pointer.x < pointer.source_width and
        pointer.y >= 0 and pointer.y < pointer.source_height
    if is_new then
        local primary_down = tonumber(pointer.values[5]) ~= 0
        local back_down = tonumber(pointer.values[6]) ~= 0
        local scroll_steps = tonumber(pointer.values[7])
        if scroll_steps >= 2147483648 then
            scroll_steps = scroll_steps - 4294967296
        end
        local primary_press_sequence = tonumber(pointer.values[8])
        local back_press_sequence = tonumber(pointer.values[9])
        local scroll_sequence = tonumber(pointer.values[10])
        if not pointer.event_sequences_initialized then
            pointer.event_sequences_initialized = true
            mod:info(
                "DARKTIDEVR_MENU_INPUT event_transport_initialized primary=%d back=%d scroll=%d",
                primary_press_sequence,
                back_press_sequence,
                scroll_sequence)
        elseif primary_press_sequence ~= pointer.primary_press_sequence or
                back_press_sequence ~= pointer.back_press_sequence or
                scroll_sequence ~= pointer.scroll_sequence then
            mod:info(
                "DARKTIDEVR_MENU_INPUT event_transport_changed primary=%d back=%d scroll=%d",
                primary_press_sequence,
                back_press_sequence,
                scroll_sequence)
        end
        pointer.primary_press_sequence = primary_press_sequence
        pointer.back_press_sequence = back_press_sequence
        pointer.scroll_sequence = scroll_sequence
        pointer.primary_down = primary_down
        pointer.back_down = back_down
        pointer.last_sequence = sequence
    end
    pointer.primary_pressed = pointer.active and
        pointer.primary_press_sequence ~= pointer.primary_consumed_sequence
    pointer.back_pressed = pointer.available and
        pointer.back_press_sequence ~= pointer.back_consumed_sequence
    if pointer.available and
            pointer.scroll_sequence ~= pointer.scroll_consumed_sequence then
        local scroll_steps = tonumber(pointer.values[7])
        if scroll_steps >= 2147483648 then
            scroll_steps = scroll_steps - 4294967296
        end
        pointer.scroll_steps = scroll_steps
    end
    return pointer
end

function presentation.consume_menu_primary(pointer)
    pointer.primary_consumed_sequence = pointer.primary_press_sequence
    pointer.primary_pressed = false
end

function presentation.consume_menu_back(pointer)
    pointer.back_consumed_sequence = pointer.back_press_sequence
    pointer.back_pressed = false
end

function presentation.consume_menu_scroll(pointer)
    pointer.scroll_consumed_sequence = pointer.scroll_sequence
    pointer.scroll_steps = 0
end

function presentation.scroll_menu_grid(grid, steps)
    if not grid then
        return false, "missing_grid"
    end
    if steps == 0 then
        return false, "no_steps"
    end
    if not grid.can_scroll then
        return false, "missing_can_scroll"
    end
    if not grid:can_scroll() then
        return false, "not_scrollable"
    end
    if not grid.scrollbar_progress then
        return false, "missing_scrollbar_progress"
    end
    if not grid.set_scrollbar_progress then
        return false, "missing_set_scrollbar_progress"
    end
    local progress = grid:scrollbar_progress()
    if type(progress) ~= "number" then
        return false, "invalid_scrollbar_progress"
    end
    grid:set_scrollbar_progress(
        math.clamp(progress - steps * 0.1, 0, 1),
        true)
    if grid._update_scroll_progress then
        grid:_update_scroll_progress(true)
    end
    return true, "scrolled"
end

function presentation.is_top_menu_view(instance)
    local manager = Managers and Managers.ui
    if manager and manager.active_views and manager.view_instance then
        local ok, views = pcall(manager.active_views, manager)
        if ok and type(views) == "table" then
            for i = #views, 1, -1 do
                local view_ok, view = pcall(
                    manager.view_instance, manager, views[i])
                if view_ok and view then
                    return view == instance
                end
            end
        end
    end
    return presentation.active_menu_view_instance == instance
end

function presentation.aligned_pass_origin(base_left, base_top, base_width,
        base_height, pass_style)
    if not pass_style then
        return base_left, base_top
    end
    local size = pass_style.size or { base_width, base_height }
    local width = size[1] or base_width
    local height = size[2] or base_height
    local left = base_left
    local top = base_top
    if pass_style.horizontal_alignment == "right" then
        left = left + base_width - width
    elseif pass_style.horizontal_alignment == "center" then
        left = left + (base_width - width) * 0.5
    end
    if pass_style.vertical_alignment == "bottom" then
        top = top + base_height - height
    elseif pass_style.vertical_alignment == "center" then
        top = top + (base_height - height) * 0.5
    end
    local offset = pass_style.offset or { 0, 0, 0 }
    return left + (offset[1] or 0), top + (offset[2] or 0)
end

function presentation.widget_contains_menu_pointer(instance, widget, pointer,
        pass_style)
    if not pointer.active or not instance or not instance._ui_scenegraph or
            not widget then
        return false, nil
    end
    local scenegraph_id = widget.scenegraph_id
    local scene = scenegraph_id and instance._ui_scenegraph[scenegraph_id]
    local world = scene and scene.world_position
    local offset = widget.offset or { 0, 0, 0 }
    local base_size = widget.content and widget.content.size
    if not base_size and widget.style and widget.style.hotspot then
        base_size = widget.style.hotspot.size
    end
    base_size = base_size or (scene and scene.size)
    local size = pass_style and pass_style.size or base_size
    if not world or not base_size or not base_size[1] or not base_size[2] or
            not size or not size[1] or not size[2] then
        return false, nil
    end
    local scale = RESOLUTION_LOOKUP.scale or 1
    local resolution_width = RESOLUTION_LOOKUP.width
    local resolution_height = RESOLUTION_LOOKUP.height
    local pointer_x = pointer.x * resolution_width / pointer.source_width
    local pointer_y = pointer.y * resolution_height / pointer.source_height
    local base_left = world[1] + (offset[1] or 0)
    local base_top = world[2] + (offset[2] or 0)
    local left, top = presentation.aligned_pass_origin(
        base_left, base_top, base_size[1], base_size[2], pass_style)
    left = left * scale
    top = top * scale
    local width = size[1] * scale
    local height = size[2] * scale
    return pointer_x >= left and pointer_x <= left + width and
        pointer_y >= top and pointer_y <= top + height,
        {
            pointer_x = pointer_x,
            pointer_y = pointer_y,
            left = left,
            top = top,
            width = width,
            height = height,
        }
end

function presentation.is_dropdown_widget(widget)
    local content = widget and widget.content
    return widget and (widget.type == "dropdown" or
        (content and type(content.options) == "table" and
            content.option_hotspot_1 ~= nil))
end

function presentation.is_slider_widget(widget)
    local content = widget and widget.content
    return content and type(content.slider_value) == "number" and
        type(content.entry) == "table"
end

function presentation.widget_hotspot_entries(widget, include_dropdown_options)
    local content = widget and widget.content
    if not content then
        return {}
    end
    local entries = {}
    local seen = {}
    local passes = widget.passes or {}
    for i = 1, #passes do
        local pass = passes[i]
        if pass.pass_type == "hotspot" then
            local content_id = pass.content_id or "hotspot"
            local hotspot = pass.content_id and content[pass.content_id] or
                content.hotspot or content
            local style_id = pass.style_id or content_id
            local style = widget.style and widget.style[style_id] or pass.style
            local visible = not style or style.visible ~= false
            if visible and type(pass.visibility_function) == "function" then
                local ok, result = pcall(
                    pass.visibility_function, content, style)
                visible = ok and result and true or false
            end
            if visible and presentation.is_dropdown_widget(widget) and
                    string.match(content_id, "^option_hotspot_%d+$") then
                visible = include_dropdown_options and
                    content.exclusive_focus and true or false
            end
            if visible and type(hotspot) == "table" and not seen[hotspot] then
                seen[hotspot] = true
                entries[#entries + 1] = {
                    hotspot = hotspot,
                    content_id = content_id,
                    style_id = style_id,
                    style = style,
                }
            end
        end
    end
    -- DMF's dropdown blueprint materializes option_hotspot_N and the matching
    -- styles directly on the widget. In the current runtime build those
    -- entries are not retained in widget.passes, even though the renderer uses
    -- them and the blueprint update consumes their on_pressed state. Enumerate
    -- the authored fields themselves so the visible overlay, rather than the
    -- collapsed rows behind it, owns XR input.
    if include_dropdown_options and presentation.is_dropdown_widget(widget) and
            content.exclusive_focus then
        local count = tonumber(content.num_visible_options) or 0
        for i = 1, count do
            local content_id = "option_hotspot_" .. tostring(i)
            local hotspot = content[content_id]
            local style = widget.style and widget.style[content_id]
            if type(hotspot) == "table" and style and
                    style.visible ~= false and not seen[hotspot] then
                seen[hotspot] = true
                entries[#entries + 1] = {
                    hotspot = hotspot,
                    content_id = content_id,
                    style_id = content_id,
                    style = style,
                }
            end
        end
    end
    if content.hotspot and not seen[content.hotspot] then
        entries[#entries + 1] = {
            hotspot = content.hotspot,
            content_id = "hotspot",
            style_id = "hotspot",
            style = widget.style and widget.style.hotspot,
        }
    end
    return entries
end

function presentation.widget_hotspot(widget)
    local content = widget and widget.content
    if content and content.hotspot then
        return content.hotspot
    end
    local entries = presentation.widget_hotspot_entries(widget)
    return entries[1] and entries[1].hotspot or nil
end

function presentation.clear_widget_hotspot_forces(widget)
    -- Clear even stale authored dropdown option fields. They are deliberately
    -- excluded from normal hit-testing unless the owning OptionsView says this
    -- is its one authoritative selected widget.
    local entries = presentation.widget_hotspot_entries(widget, true)
    for i = 1, #entries do
        entries[i].hotspot.force_hover = false
        entries[i].hotspot.force_input_pressed = false
    end
end

function presentation.widget_hotspot_at_pointer(instance, widget, pointer,
        include_dropdown_options)
    local entries = presentation.widget_hotspot_entries(
        widget, include_dropdown_options)
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if not entry.hotspot.disabled then
            local hit = presentation.widget_contains_menu_pointer(
                instance, widget, pointer, entry.style)
            if hit then
                return entry
            end
        end
    end
    return nil
end

function presentation.log_focused_dropdown_geometry(instance, widget, pointer)
    if not pointer.primary_pressed or not widget or
            not presentation.is_dropdown_widget(widget) or
            not widget.content or not widget.content.exclusive_focus then
        return
    end
    local entries = presentation.widget_hotspot_entries(widget, true)
    for i = 1, #entries do
        local entry = entries[i]
        local hit, geometry = presentation.widget_contains_menu_pointer(
            instance, widget, pointer, entry.style)
        if geometry then
            mod:info(
                "DARKTIDEVR_MENU_INPUT dropdown_geometry widget=%s hotspot=%s hit=%s pointer=%.1f,%.1f bounds=%.1f,%.1f,%.1f,%.1f",
                tostring(widget.name),
                tostring(entry.content_id),
                tostring(hit),
                geometry.pointer_x,
                geometry.pointer_y,
                geometry.left,
                geometry.top,
                geometry.width,
                geometry.height)
        end
    end
end

function presentation.log_slider_geometry(instance, widget, pointer)
    if not pointer.primary_pressed or
            not presentation.is_slider_widget(widget) then
        return
    end

    local entries = {}
    local seen = {}
    local passes = widget.passes or {}
    for i = 1, #passes do
        local pass = passes[i]
        local style_id = pass.style_id or pass.content_id
        local style_name = string.lower(tostring(style_id or ""))
        if (string.find(style_name, "slider", 1, true) or
                string.find(style_name, "hotspot", 1, true)) and
                not seen[style_name] then
            seen[style_name] = true
            local style = widget.style and widget.style[style_id] or pass.style
            local hit, geometry = presentation.widget_contains_menu_pointer(
                instance, widget, pointer, style)
            if geometry then
                entries[#entries + 1] = string.format(
                    "%s:%s:%.1f,%.1f,%.1f,%.1f",
                    tostring(style_id),
                    hit and "hit" or "miss",
                    geometry.left,
                    geometry.top,
                    geometry.width,
                    geometry.height)
            end
        end
    end

    mod:info(
        "DARKTIDEVR_MENU_INPUT slider_geometry widget=%s type=%s value=%.4f step=%s pointer=%d,%d passes=%s",
        tostring(widget.name),
        tostring(widget.type),
        widget.content.slider_value,
        tostring(widget.content.step_size),
        pointer.x,
        pointer.y,
        #entries > 0 and table.concat(entries, "|") or "none")
end

function presentation.slider_track_geometry(instance, widget, pointer)
    local style = widget and widget.style
    if not style then
        return false, nil
    end
    local track_style = style.track_hotspot or
        style.slider_track_background
    if not track_style then
        return false, nil
    end
    return presentation.widget_contains_menu_pointer(
        instance, widget, pointer, track_style)
end

function presentation.set_slider_from_pointer(instance, widget, pointer)
    local _, geometry = presentation.slider_track_geometry(
        instance, widget, pointer)
    if not geometry or geometry.width <= 0 then
        return false
    end
    local value = math.clamp(
        (geometry.pointer_x - geometry.left) / geometry.width, 0, 1)
    local step = widget.content.step_size
    if type(step) == "number" and step > 0 then
        value = math.clamp(
            math.floor(value / step + 0.5) * step, 0, 1)
    end
    widget.content.slider_value = value
    return true, value
end

function presentation.update_slider_drag(instance, pointer)
    local drag = presentation.slider_drag
    if not drag or drag.instance ~= instance then
        return false
    end
    local widget = drag.widget
    if not pointer.available then
        -- A missing transport sample is not a release. Preserve the last XR
        -- value until a fresh sample explicitly reports button-up.
        widget.content.drag_active = true
        widget.content.slider_value = drag.value
        return true
    end
    if pointer.primary_down then
        widget.content.drag_active = true
        if pointer.active then
            local updated, value = presentation.set_slider_from_pointer(
                instance, widget, pointer)
            if updated then
                drag.value = value
            end
        else
            widget.content.slider_value = drag.value
        end
        return true
    end
    -- Engine updates between the two eye draws may resynchronize content from
    -- the old setting. Restore the last XR-authored value before releasing so
    -- the blueprint's drag_previously_active path commits that value.
    widget.content.slider_value = drag.value
    widget.content.drag_active = false
    mod:info(
        "DARKTIDEVR_MENU_INPUT slider_drag_end widget=%s value=%.4f sequence=%d",
        tostring(widget.name),
        drag.value,
        pointer.last_sequence)
    presentation.slider_drag = nil
    return false
end

function presentation.begin_slider_drag(instance, widget, pointer)
    local hit = presentation.slider_track_geometry(instance, widget, pointer)
    if not hit then
        return false
    end
    local updated, value = presentation.set_slider_from_pointer(
        instance, widget, pointer)
    if not updated then
        return false
    end
    widget.content.drag_active = true
    presentation.slider_drag = {
        instance = instance,
        widget = widget,
        value = value,
    }
    mod:info(
        "DARKTIDEVR_MENU_INPUT slider_drag_begin widget=%s value=%.4f sequence=%d",
        tostring(widget.name), value, pointer.last_sequence)
    return true
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
    if head_pose_last_sequence ~= 0 and sequence < head_pose_last_sequence then
        -- The OpenXR bridge owns the shared head-pose writer and restarts its
        -- sequence at one.  Darktide can outlive that process, leaving native
        -- eye-capture tags from the previous bridge session queued ahead of
        -- the new sequence.  Since producer and consumer then advance at the
        -- same rate, the new bridge can never catch that old tag stream and
        -- rejects every otherwise-fresh pair as pose-mismatched.  Drop those
        -- obsolete tags at the observed epoch boundary before either camera
        -- is armed for this frame.
        ui_native_capture.dtvr_reset_eye_capture_tags()
        mod:info(
            "DARKTIDEVR_STEREO bridge_restart old_sequence=%d new_sequence=%d action=reset_capture_tags",
            head_pose_last_sequence,
            sequence)
        presentation.head_translation_trace_last_sequence = 0
        controller_observation.body_follow_last_sequence = sequence
    end
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
    controller_observation.body_follow_x = tonumber(head_pose_values[20])
    controller_observation.body_follow_y = tonumber(head_pose_values[21])
    controller_observation.body_follow_z = tonumber(head_pose_values[22])
    -- The native reader rejects stale snapshots. Clear usability before each
    -- attempt so a failed read can never leave the previous pose live.
    controller_observation.right_aim_usable = false
    controller_observation.right_grip_usable = false
    controller_observation.left_grip_usable = false
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
        local left_grip_flags =
            tonumber(controller_observation.tracking_flags[1])
        local right_aim_flags = tonumber(controller_observation.tracking_flags[2])
        local right_grip_flags =
            tonumber(controller_observation.tracking_flags[3])
        controller_observation.right_aim_flags = right_aim_flags
        controller_observation.left_grip_flags = left_grip_flags
        controller_observation.right_grip_flags = right_grip_flags
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
        controller_observation.right_grip_usable =
            bit.band(right_grip_flags, 5) == 5 and
            controller_age_ns >= -5000000 and
            controller_age_ns <= 100000000 and
            controller_sequence ~= controller_observation.epoch_block_sequence
        controller_observation.left_grip_usable =
            bit.band(left_grip_flags, 5) == 5 and
            controller_age_ns >= -5000000 and
            controller_age_ns <= 100000000 and
            controller_sequence ~= controller_observation.epoch_block_sequence
        controller_observation.left_grip_x =
            tonumber(controller_observation.values[7])
        controller_observation.left_grip_y =
            tonumber(controller_observation.values[8])
        controller_observation.left_grip_z =
            tonumber(controller_observation.values[9])
        controller_observation.left_grip_qx =
            tonumber(controller_observation.values[10])
        controller_observation.left_grip_qy =
            tonumber(controller_observation.values[11])
        controller_observation.left_grip_qz =
            tonumber(controller_observation.values[12])
        controller_observation.left_grip_qw =
            tonumber(controller_observation.values[13])
        controller_observation.right_grip_x =
            tonumber(controller_observation.values[25])
        controller_observation.right_grip_y =
            tonumber(controller_observation.values[26])
        controller_observation.right_grip_z =
            tonumber(controller_observation.values[27])
        controller_observation.right_grip_qx =
            tonumber(controller_observation.values[28])
        controller_observation.right_grip_qy =
            tonumber(controller_observation.values[29])
        controller_observation.right_grip_qz =
            tonumber(controller_observation.values[30])
        controller_observation.right_grip_qw =
            tonumber(controller_observation.values[31])
        controller_observation.right_trigger =
            tonumber(controller_observation.values[32])
        controller_observation.left_stick_x =
            tonumber(controller_observation.values[16])
        controller_observation.left_stick_y =
            tonumber(controller_observation.values[17])
        controller_observation.right_stick_x =
            tonumber(controller_observation.values[34])
        controller_observation.right_stick_y =
            tonumber(controller_observation.values[35])
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
            mod:info("DARKTIDEVR_CONTROLLER observed sequence=%d left_aim_flags=%d right_aim_flags=%d right_aim_age_ms=%.3f usable=%s left_stick=%.3f,%.3f right_stick=%.3f,%.3f",
                controller_sequence,
                left_aim_flags,
                right_aim_flags,
                controller_observation.right_aim_age_ms,
                tostring(controller_observation.right_aim_usable),
                controller_observation.left_stick_x,
                controller_observation.left_stick_y,
                controller_observation.right_stick_x,
                controller_observation.right_stick_y)
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
    controller_observation.physical_head_yaw =
        Quaternion.yaw(head_rotation)
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

    if presentation.head_translation_trace_requested and
            (presentation.head_translation_trace_last_sequence == 0 or
             sequence < presentation.head_translation_trace_last_sequence or
             sequence - presentation.head_translation_trace_last_sequence >=
                presentation.head_translation_trace_interval) then
        mod:info(
            "DARKTIDEVR_STEREO head_translation sequence=%d delta=%.5f,%.5f,%.5f body_follow=%.5f,%.5f,%.5f clean=%.5f,%.5f,%.5f tracked=%.5f,%.5f,%.5f",
            sequence,
            tonumber(head_pose_values[0]) * character_scale,
            tonumber(head_pose_values[1]) * character_scale,
            tonumber(head_pose_values[2]) * character_scale,
            controller_observation.body_follow_x * character_scale,
            controller_observation.body_follow_y * character_scale,
            controller_observation.body_follow_z * character_scale,
            Vector3.x(clean_position), Vector3.y(clean_position),
            Vector3.z(clean_position), Vector3.x(tracked_position),
            Vector3.y(tracked_position), Vector3.z(tracked_position))
        presentation.head_translation_trace_last_sequence = sequence
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
                "DARKTIDEVR_STEREO billboard state=%d hook_draws=%d observed=%d slot0=%s slot1=%s particle_layout=%d exact_pso=%d cl_types=%s registers=%s cbv_slots=%s table_slots=%s selected_tables=%s descriptor_offsets=%s table_spans=%s cbv_desc=%d buffers=%d heaps=%s map=%d/%d tracked_maps=%d/%d/%d producer_stacks=%d upload_flush=%d/%d direct_patches=%d selected=%d/%d shadow_stages=%s root_meta=%d direct_cbv=%d table_cbv=%d table_cbv_bound=%d patches=%d",
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
                tonumber(ui_native_capture.dtvr_billboard_direct_patch_count()),
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
            local candidate_pairs = {}
            for rank = 0, 15 do
                local vertex_low = tonumber(
                    ui_native_capture.dtvr_billboard_candidate_pair_vertex_low(rank))
                local vertex_high = tonumber(
                    ui_native_capture.dtvr_billboard_candidate_pair_vertex_high(rank))
                local pixel_low = tonumber(
                    ui_native_capture.dtvr_billboard_candidate_pair_pixel_low(rank))
                local pixel_high = tonumber(
                    ui_native_capture.dtvr_billboard_candidate_pair_pixel_high(rank))
                local count = tonumber(
                    ui_native_capture.dtvr_billboard_candidate_pair_count(rank))
                if count > 0 then
                    candidate_pairs[#candidate_pairs + 1] = string.format(
                        "%08x%08x/%08x%08x:%d",
                        vertex_high, vertex_low, pixel_high, pixel_low, count)
                end
            end
            mod:info("DARKTIDEVR_STEREO billboard_pairs %s",
                table.concat(candidate_pairs, ","))
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
    presentation.full_second_eye_probe_check_frame =
        presentation.full_second_eye_probe_check_frame + 1
    if presentation.full_second_eye_probe_check_frame >=
            presentation.full_second_eye_probe_last_check_frame + 120 and
            Mods and Mods.lua and Mods.lua.io then
        presentation.full_second_eye_probe_last_check_frame =
            presentation.full_second_eye_probe_check_frame
        local flag = Mods.lua.io.open(
            "./../mods/darktidevr_stereo_probe/darktidevr_full_second_eye.flag",
            "r")
        local enabled = false
        if flag then
            enabled = flag:read("*all"):match("^%s*enabled%s*$") ~= nil
            flag:close()
        end
        if enabled ~= presentation.full_second_eye_probe_requested then
            presentation.full_second_eye_probe_requested = enabled
            mod:info(
                "DARKTIDEVR_RENDER second_eye_path=%s source=test_flag",
                enabled and "full_wrapper" or "prepared_frame")
        end
    end
    if presentation.full_second_eye_probe_requested then
        return false
    end
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
    -- The engine owns objects allocated in the world being torn down.  Do not
    -- call into that invalid world here; only discard our handles.
    presentation.world_menu_gui = nil
    presentation.world_menu_gui_world = nil
    presentation.world_menu_material = nil
    presentation.world_menu_anchor = nil
    presentation.world_menu_draw_logged = false
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
        -- Character-select and gameplay stereo sources overlap during world
        -- transitions. The old UI world can be destroyed after CameraManager
        -- has already activated the gameplay producer; unconditionally
        -- clearing this process-wide flag then silently stops fresh eye pairs.
        -- Release projection only when no gameplay stereo owner remains.
        ui_native_capture.dtvr_set_projection_active(active and 1 or 0)
        mod:info(
            "DARKTIDEVR_STEREO ui_teardown projection_owner=%s",
            active and "gameplay" or "none")
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
    if false then
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

function presentation.body_model_eye_anchor(unit)
    if not unit or not Unit.alive(unit) then
        return nil, "unit_unavailable"
    end
    local candidates = { unit }
    local visual_loadout = ScriptUnit.has_extension(
        unit, "visual_loadout_system")
    if visual_loadout then
        local face_ok, face_unit = pcall(
            visual_loadout.unit_3p_from_slot,
            visual_loadout,
            "slot_body_face")
        if face_ok and face_unit and Unit.alive(face_unit) then
            candidates[#candidates + 1] = face_unit
        end
    end
    for i = 1, #candidates do
        local candidate = candidates[i]
        if Unit.has_node(candidate, "j_lefteye") and
                Unit.has_node(candidate, "j_righteye") then
            local left = Unit.world_position(
                candidate, Unit.node(candidate, "j_lefteye"))
            local right = Unit.world_position(
                candidate, Unit.node(candidate, "j_righteye"))
            return (left + right) * 0.5,
                candidate == unit and "player_rig" or "face_attachment",
                left,
                right
        end
    end
    return nil, "eye_nodes_missing"
end

-- Eye bones are calibration landmarks, not a live camera parent. Their world
-- transforms include facial/head animation, which would inject authored bob
-- and look motion into an otherwise runtime-owned 6DoF head pose. Capture the
-- midpoint once in the character root's coordinates, then move that stable
-- offset only with the locomotion/root transform. OpenXR supplies all motion
-- of the real viewer relative to this neutral model-eye origin.
function presentation.body_stable_eye_anchor(unit)
    if not unit or not Unit.alive(unit) then
        return nil, "unit_unavailable"
    end
    local observation = controller_observation
    local needs_capture = observation.body_eye_anchor_unit ~= unit or
        observation.body_eye_anchor_local_x == nil
    local measured_eye = nil
    local measured_source = observation.body_eye_anchor_source
    local measured_left = nil
    local measured_right = nil
    local root_position = Unit.world_position(unit, 1)
    local root_rotation = Unit.world_rotation(unit, 1)
    if needs_capture then
        measured_eye, measured_source, measured_left, measured_right =
            presentation.body_model_eye_anchor(unit)
        if not measured_eye then
            return nil, measured_source
        end
        local root_inverse = presentation.inverse_quaternion(root_rotation)
        local local_eye = presentation.rotate_vector(
            root_inverse, measured_eye - root_position)
        observation.body_eye_anchor_unit = unit
        observation.body_eye_anchor_local_x = Vector3.x(local_eye)
        observation.body_eye_anchor_local_y = Vector3.y(local_eye)
        observation.body_eye_anchor_local_z = Vector3.z(local_eye)
        observation.body_eye_anchor_source = measured_source
    end
    local local_eye = Vector3(
        observation.body_eye_anchor_local_x,
        observation.body_eye_anchor_local_y,
        observation.body_eye_anchor_local_z)
    return root_position +
            presentation.rotate_vector(root_rotation, local_eye),
        observation.body_eye_anchor_source,
        measured_left,
        measured_right,
        needs_capture
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
    local body_anchor_position = clean_position
    -- Keep Darktide's genuine 3P camera tree active so its skinned-local-player
    -- submission policy remains active, but replace the tree's final render
    -- origin with the first-person head anchor. Choosing the 1P camera tree
    -- itself suppresses the skinned body even when every unit/slot is visible.
    if controller_observation.body_visibility_enabled then
        local local_player = Managers and Managers.player and
            Managers.player:local_player(1)
        local player_unit = local_player and local_player.player_unit
        local first_person_extension = player_unit and
            ScriptUnit.has_extension(player_unit, "first_person_system")
        local first_person_component = first_person_extension and
            first_person_extension._first_person_component
        if first_person_component and first_person_component.position then
            local head_position = first_person_component.position
            local model_eye_position, eye_source, left_eye, right_eye,
                eye_anchor_captured =
                    presentation.body_stable_eye_anchor(player_unit)
            clean_position = model_eye_position or
                (head_position + Vector3.up() * 0.05)
            body_anchor_position = clean_position
            if not controller_observation.body_camera_anchor_logged then
                controller_observation.body_camera_anchor_logged = true
                mod:info(
                    "DARKTIDEVR_BODY camera_origin=%s camera=%.4f,%.4f,%.4f first_person=%.4f,%.4f,%.4f tree_preserved=third_person",
                    tostring(model_eye_position and eye_source or
                        "head_fallback"),
                    Vector3.x(clean_position),
                    Vector3.y(clean_position),
                    Vector3.z(clean_position),
                    Vector3.x(head_position),
                    Vector3.y(head_position),
                    Vector3.z(head_position))
                if model_eye_position and eye_anchor_captured then
                    mod:info(
                        "DARKTIDEVR_BODY model_eyes calibration=stable_root_space left=%.4f,%.4f,%.4f right=%.4f,%.4f,%.4f ipd=%.4f first_person_delta=%.4f,%.4f,%.4f",
                        Vector3.x(left_eye), Vector3.y(left_eye),
                        Vector3.z(left_eye), Vector3.x(right_eye),
                        Vector3.y(right_eye), Vector3.z(right_eye),
                        presentation.vector_distance(left_eye, right_eye),
                        Vector3.x(model_eye_position - head_position),
                        Vector3.y(model_eye_position - head_position),
                        Vector3.z(model_eye_position - head_position))
                end
            end
        end
    end
    -- The game remains authoritative for camera translation, but VR owns the
    -- complete orientation. Reusing the live game rotation allowed orbital
    -- camera pitch/roll (and occasionally the prior tracked result) to feed
    -- back into the next headset pose when the player moved vertically.
    local clean_rotation = active_base_rotation:unbox()
    if controller_observation.body_visibility_enabled then
        -- Headset calibration from the first complete body pass: the tracked
        -- viewpoint initially felt about 6 cm right and 10-15 cm behind the
        -- avatar eye centre. The first live correction overshot forward by
        -- roughly 5 cm, leaving a net 7.5 cm forward calibration. Keep this
        -- correction in the immutable recenter frame so the
        -- camera and both controllers translate together; do not bake it into
        -- animated eye/head bones.
        clean_position = clean_position -
            Quaternion.right(clean_rotation) * 0.06 +
            Quaternion.forward(clean_rotation) * 0.075
        body_anchor_position = clean_position
    end
    if game_rotation_mode == "yaw_only" then
        local live_rotation = ScriptCamera.local_rotation(primary_camera)
        local yaw_delta = Quaternion.yaw(live_rotation) -
            Quaternion.yaw(clean_rotation)
        clean_rotation = Quaternion.multiply(
            Quaternion.axis_angle(Vector3.up(), yaw_delta),
            clean_rotation
        )
    end
    controller_observation.body_anchor_x = Vector3.x(body_anchor_position)
    controller_observation.body_anchor_y = Vector3.y(body_anchor_position)
    controller_observation.body_anchor_z = Vector3.z(body_anchor_position)
    controller_observation.body_anchor_qx,
        controller_observation.body_anchor_qy,
    controller_observation.body_anchor_qz,
        controller_observation.body_anchor_qw =
            Quaternion.to_elements(clean_rotation)
    clean_position, clean_rotation = apply_head_tracking(
        clean_position,
        clean_rotation
    )
    -- Gameplay aim deliberately authors Darktide's first-person orientation
    -- from the right controller so projectiles follow the weapon. That yaw is
    -- also present in the live game camera and must not drive the avatar's
    -- torso. Body heading comes from the immutable scene heading plus physical
    -- HMD yaw; a future thumbstick-turn accumulator belongs between those two.
    controller_observation.body_head_yaw =
        Quaternion.yaw(active_base_rotation:unbox()) +
        (controller_observation.physical_head_yaw or 0)
    if ui_native_capture and (billboard_horizon_lock_requested or
            billboard_selector_probe_requested) then
        local horizon_rotation = Quaternion.axis_angle(
            Vector3.up(), Quaternion.yaw(clean_rotation))
        local billboard_right = Quaternion.right(horizon_rotation)
        local billboard_up = Quaternion.up(horizon_rotation)
        if billboard_horizon_lock_requested and
                billboard_direct_write_requested then
            ui_native_capture.dtvr_set_billboard_direct_view_direction(
                billboard_right.x, billboard_right.y, 1)
        else
            ui_native_capture.dtvr_set_billboard_view_basis(
                billboard_right.x, billboard_right.y, billboard_right.z,
                billboard_up.x, billboard_up.y, billboard_up.z,
                2
            )
        end
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

    presentation.draw_world_menu_surface(
        world, clean_position, clean_rotation)

    ScriptCamera.force_update(world, primary_camera)
    ScriptCamera.force_update(world, right_camera)
end

mod:hook_safe(
    require("scripts/managers/ui/ui_manager"),
    "update",
    function(self, _, t)
    presentation.reconcile_fullscreen_views(self)
    presentation.update_system_menu_test(self)
    presentation.update_vendor_menu_test(self)
    presentation.update_psykhanium(self, t or 0)
end)

-- Darktide's ordinary system/options views explicitly keep the game world
-- enabled (`disable_game_world = false`) and request `game_world_blur = 1.1`.
-- In stereo that post effect is applied to the stock player1 viewport only,
-- which is why menu open originally blurred the left eye. Spatial XR menus do
-- not use that world blur: the live projection remains untouched behind the
-- separate menu quad.
mod:hook(
    require("scripts/managers/ui/ui_manager"),
    "use_fullscreen_blur",
    function(func, self, ...)
        local apply_blur, blur_amount = func(self, ...)
        if presentation.world_menu_active() then
            return false, 0
        end
        return apply_blur, blur_amount
    end)

mod:hook_safe("InputManager", "update", function(self)
    presentation.scan_input_services(self)
    presentation.update_menu_input_probe(self)
    if presentation.system_view_trace_pending and ui_native_capture then
        presentation.system_view_trace_pending = nil
        presentation.system_view_trace_phase = 1
        presentation.system_view_trace_frames = 4
        local marker_result = ui_native_capture.dtvr_enable_marker_log()
        local trace_result = ui_native_capture.dtvr_set_focused_trace_phase(1)
        mod:info(
            "DARKTIDEVR_MENU_TRACE started_deferred frames=%d marker_result=%s trace_result=%s",
            presentation.system_view_trace_frames,
            tostring(marker_result),
            tostring(trace_result))
    end
    local trace_frames = presentation.system_view_trace_frames
    if trace_frames and presentation.system_view_trace_phase == 2 then
        trace_frames = trace_frames - 1
        presentation.system_view_trace_frames = trace_frames
        if trace_frames <= 0 then
            presentation.system_view_trace_frames = nil
            presentation.system_view_trace_phase = nil
            if ui_native_capture then
                ui_native_capture.dtvr_set_focused_trace_phase(0)
            end
            mod:info("DARKTIDEVR_MENU_TRACE stopped reason=baseline_budget")
        end
    end
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
            local flags = controller_observation.right_aim_flags
            if flags ~= controller_observation.authoring_unusable_last_flags or
                    main_t >=
                        controller_observation.authoring_unusable_last_log_t +
                            30 then
                controller_observation.authoring_unusable_last_flags = flags
                controller_observation.authoring_unusable_last_log_t = main_t
                mod:warning(
                    "DARKTIDEVR_AIM suspended reason=unusable sequence=%d flags=%d age_ms=%.3f",
                    controller_observation.last_sequence,
                    flags,
                    controller_observation.right_aim_age_ms
                )
            end
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

local function active_game_mode_name()
    local game_mode = Managers and Managers.state and Managers.state.game_mode
    if not game_mode or type(game_mode.game_mode_name) ~= "function" then
        return nil
    end
    local ok, name = pcall(game_mode.game_mode_name, game_mode)
    return ok and name or nil
end

function presentation.inject_primary_action(self, main_t)
    if not Mods or not Mods.lua or not Mods.lua.io then
        return
    end
    if not controller_observation.primary_action_armed and
            main_t >= controller_observation.primary_action_last_check_t + 0.25 then
        controller_observation.primary_action_last_check_t = main_t
        local flag_path =
            "./../mods/darktidevr_stereo_probe/darktidevr_primary_action_test.flag"
        local flag = Mods.lua.io.open(flag_path, "r")
        if flag then
            local request = flag:read("*all")
            flag:close()
            if request and request:match("^%s*fire_once%s*$") then
                local consumed = Mods.lua.io.open(flag_path, "w")
                if consumed then
                    consumed:write("consumed\n")
                    consumed:close()
                end
                controller_observation.primary_action_armed = true
                mod:info("DARKTIDEVR_INPUT primary_action armed")
            end
        end
    end
    if controller_observation.primary_action_stage == "held" then
        local actions = self._ephemeral_actions
        local cache = self._ephemeral_action_cache
        if type(actions) == "table" and type(cache) == "table" then
            for i = 1, #actions do
                if actions[i] == "action_one_release" then
                    cache[i] = true
                    controller_observation.primary_action_stage = "release"
                    mod:info(
                        "DARKTIDEVR_INPUT primary_action release_queued sequence=%d",
                        controller_observation.primary_action_sequence
                    )
                    break
                end
            end
        end
    end
    if not controller_observation.primary_action_armed or
            controller_observation.primary_action_injected then
        return
    end
    local game_mode_name = active_game_mode_name()
    if game_mode_name ~= "shooting_range" and
            game_mode_name ~= "training_grounds" then
        return
    end
    if not controller_observation.authoring_enabled or
            not controller_observation.right_aim_usable or
            controller_observation.last_sequence <= 0 then
        return
    end
    local actions = self._ephemeral_actions
    local cache = self._ephemeral_action_cache
    if type(actions) ~= "table" or type(cache) ~= "table" then
        mod:warning(
            "DARKTIDEVR_INPUT primary_action blocked reason=missing_ephemeral_cache"
        )
        controller_observation.primary_action_armed = false
        return
    end
    local action_index = nil
    for i = 1, #actions do
        if actions[i] == "action_one_pressed" then
            action_index = i
            break
        end
    end
    if not action_index then
        mod:warning(
            "DARKTIDEVR_INPUT primary_action blocked reason=missing_action"
        )
        controller_observation.primary_action_armed = false
        return
    end
    cache[action_index] = true
    controller_observation.primary_action_armed = false
    controller_observation.primary_action_injected = true
    controller_observation.primary_action_stage = "press"
    controller_observation.primary_action_sequence =
        controller_observation.last_sequence
    mod:info(
        "DARKTIDEVR_INPUT primary_action injected action=action_one_pressed sequence=%d age_ms=%.3f forward=%.4f,%.4f,%.4f",
        controller_observation.primary_action_sequence,
        controller_observation.right_aim_age_ms,
        controller_observation.downstream_forward_x or 0,
        controller_observation.downstream_forward_y or 0,
        controller_observation.downstream_forward_z or 0
    )
end

presentation.gameplay_input_bindings = {
    {
        mask = 1,
        pressed = { "action_one_pressed" },
        held = { "action_one_hold" },
        released = { "action_one_release" }
    },
    {
        mask = 2,
        pressed = { "action_two_pressed" },
        held = { "action_two_hold" },
        released = { "action_two_release" }
    },
    {
        mask = 4,
        pressed = { "weapon_extra_pressed" },
        held = { "weapon_extra_hold" },
        released = { "weapon_extra_release" }
    },
    {
        mask = 8,
        pressed = { "interact_pressed", "weapon_reload_pressed" },
        held = { "interact_hold", "weapon_reload_hold" },
        released = {}
    },
    {
        mask = 16,
        pressed = { "quick_wield" },
        held = {},
        released = {}
    },
    {
        mask = 32,
        pressed = { "jump", "dodge" },
        held = { "jump_held" },
        released = {}
    },
    {
        mask = 64,
        pressed = { "crouch" },
        held = { "crouching" },
        released = {}
    },
    {
        mask = 128,
        pressed = { "sprint" },
        held = { "sprinting" },
        released = {}
    },
    {
        mask = 512,
        pressed = { "grenade_ability_pressed" },
        held = { "grenade_ability_hold" },
        released = { "grenade_ability_release" }
    }
}

function presentation.inject_ephemeral_action_names(
        actions, cache, names, delivered, missing)
    for name_index = 1, #names do
        local requested_name = names[name_index]
        local found = false
        for action_index = 1, #actions do
            if actions[action_index] == requested_name then
                cache[action_index] = true
                found = true
                break
            end
        end
        local destination = found and delivered or missing
        destination[#destination + 1] = requested_name
    end
end

function presentation.inject_gameplay_input(self, main_t)
    if not ui_native_capture or not Mods or not Mods.lua or not Mods.lua.io or
            not controller_observation.gameplay_pressed then
        return
    end
    if main_t >= controller_observation.gameplay_input_last_check_t + 0.25 then
        controller_observation.gameplay_input_last_check_t = main_t
        local flag = Mods.lua.io.open(
            "./../mods/darktidevr_stereo_probe/darktidevr_gameplay_input_test.flag",
            "r")
        local requested = false
        if flag then
            local value = flag:read("*all")
            flag:close()
            requested = value and value:match("^%s*enabled%s*$") ~= nil
        end
        if requested ~= controller_observation.gameplay_input_enabled then
            controller_observation.gameplay_input_enabled = requested
            mod:info(
                "DARKTIDEVR_INPUT gameplay_adapter enabled=%s",
                tostring(requested))
        end
    end

    local game_mode_name = active_game_mode_name()
    local ui_inputs_in_use = false
    if Managers and Managers.ui and
            type(Managers.ui.inputs_in_use) == "function" then
        local ok, value = pcall(Managers.ui.inputs_in_use, Managers.ui)
        ui_inputs_in_use = ok and value == true
    end
    local active = controller_observation.gameplay_input_enabled and
        (game_mode_name == "shooting_range" or
            game_mode_name == "training_grounds") and
        presentation.mode == 1 and not ui_inputs_in_use
    local result = ui_native_capture.dtvr_read_gameplay_input(
        active and 1 or 0,
        controller_observation.gameplay_pressed,
        controller_observation.gameplay_held,
        controller_observation.gameplay_released,
        controller_observation.gameplay_sequence,
        controller_observation.gameplay_movement)
    controller_observation.gameplay_input_active = active and result == 0
    local pressed = tonumber(controller_observation.gameplay_pressed[0])
    local held = tonumber(controller_observation.gameplay_held[0])
    local released = tonumber(controller_observation.gameplay_released[0])
    controller_observation.gameplay_input_last_sequence =
        tonumber(controller_observation.gameplay_sequence[0])
    if result ~= 0 and pressed == 0 and held == 0 and released == 0 then
        return
    end
    if pressed ~= 0 or released ~= 0 then
        mod:info(
            "DARKTIDEVR_INPUT gameplay_edges sequence=%d pressed=%d held=%d released=%d move=%.3f,%.3f",
            controller_observation.gameplay_input_last_sequence,
            pressed, held, released,
            tonumber(controller_observation.gameplay_movement[0]),
            tonumber(controller_observation.gameplay_movement[1]))
    end

    local actions = self._ephemeral_actions
    local cache = self._ephemeral_action_cache
    if type(actions) ~= "table" or type(cache) ~= "table" then
        return
    end
    local delivered = {}
    local missing = {}
    for binding_index = 1, #presentation.gameplay_input_bindings do
        local binding = presentation.gameplay_input_bindings[binding_index]
        local names = nil
        if bit.band(pressed, binding.mask) ~= 0 then
            names = binding.pressed
        end
        if names then
            presentation.inject_ephemeral_action_names(
                actions, cache, names, delivered, missing)
        end
        if bit.band(released, binding.mask) ~= 0 then
            names = binding.released
            presentation.inject_ephemeral_action_names(
                actions, cache, names, delivered, missing)
        end
    end
    if pressed ~= 0 or released ~= 0 then
        mod:info(
            "DARKTIDEVR_INPUT gameplay_delivery sequence=%d delivered=%s missing=%s",
            controller_observation.gameplay_input_last_sequence,
            #delivered > 0 and table.concat(delivered, ",") or "none",
            #missing > 0 and table.concat(missing, ",") or "none")
    end
end

mod:hook_safe(
    require("scripts/managers/player/player_game_states/human_input_handler"),
    "pre_update",
    function(self, _, main_t)
        presentation.inject_primary_action(self, main_t or 0)
        presentation.inject_gameplay_input(self, main_t or 0)
    end)

mod:hook_safe(
    require("scripts/managers/player/player_game_states/human_input_handler"),
    "fixed_update",
    function(self, _, _, frame)
        presentation.scan_movement_inventory(self, frame)
        controller_observation.gameplay_stick_active = false
        local gameplay_held = controller_observation.gameplay_input_enabled and
            tonumber(controller_observation.gameplay_held[0]) or 0
        if controller_observation.gameplay_input_active and
                self._action_lookup and self._input_cache then
            local cache_index = self._buffer_index and self:_buffer_index(frame)
            if cache_index then
                local move_x = tonumber(
                    controller_observation.gameplay_movement[0])
                local move_y = tonumber(
                    controller_observation.gameplay_movement[1])
                local movement_names = {
                    "move_right", "move_left",
                    "move_forward", "move_backward"
                }
                local movement_values = {}
                for name_index = 1, #movement_names do
                    local action_name = movement_names[name_index]
                    local action_index = self._action_lookup[action_name]
                    local action_cache = action_index and
                        self._input_cache[action_index]
                    movement_values[action_name] = tonumber(
                        action_cache and action_cache[cache_index]) or 0
                end
                local existing_x = movement_values.move_right -
                    movement_values.move_left
                local existing_y = movement_values.move_forward -
                    movement_values.move_backward
                local stick_active = math.abs(move_x) > 0.0001 or
                    math.abs(move_y) > 0.0001
                controller_observation.gameplay_stick_active = stick_active
                local combined_x = math.max(-1, math.min(
                    1, existing_x + move_x))
                local combined_y = math.max(-1, math.min(
                    1, existing_y + move_y))
                local movement = {
                    move_right = math.max(combined_x, 0),
                    move_left = math.max(-combined_x, 0),
                    move_forward = math.max(combined_y, 0),
                    move_backward = math.max(-combined_y, 0)
                }
                -- A neutral or unavailable VR stick must not claim locomotion
                -- ownership. Leaving the cache untouched preserves keyboard,
                -- gamepad and accessibility inputs sampled by Darktide.
                if stick_active then
                    for action_name, value in pairs(movement) do
                        local action_index = self._action_lookup[action_name]
                        if action_index and self._input_cache[action_index] then
                            self._input_cache[action_index][cache_index] = value
                        end
                    end
                end
                if type(frame) == "number" and
                        frame - controller_observation.gameplay_locomotion_last_frame >= 60 then
                    controller_observation.gameplay_locomotion_last_frame = frame
                    local local_player = Managers and Managers.player and
                        Managers.player:local_player(1)
                    local player_unit = local_player and local_player.player_unit
                    if player_unit and Unit.alive(player_unit) then
                        local player_position = Unit.world_position(player_unit, 1)
                        mod:info(
                            "DARKTIDEVR_INPUT locomotion frame=%d move=%.3f,%.3f raw_left=%.3f,%.3f raw_right=%.3f,%.3f existing=%.3f,%.3f combined=%.3f,%.3f stick_active=%s cache=%.3f,%.3f,%.3f,%.3f player=%.4f,%.4f,%.4f",
                            frame, move_x, move_y,
                            controller_observation.left_stick_x,
                            controller_observation.left_stick_y,
                            controller_observation.right_stick_x,
                            controller_observation.right_stick_y,
                            existing_x, existing_y,
                            combined_x, combined_y,
                            tostring(stick_active),
                            movement.move_right, movement.move_left,
                            movement.move_forward, movement.move_backward,
                            Vector3.x(player_position), Vector3.y(player_position),
                            Vector3.z(player_position))
                    end
                end
                for binding_index = 1,
                        #presentation.gameplay_input_bindings do
                    local binding =
                        presentation.gameplay_input_bindings[binding_index]
                    if bit.band(gameplay_held, binding.mask) ~= 0 then
                        for name_index = 1, #binding.held do
                            local action_index =
                                self._action_lookup[binding.held[name_index]]
                            if action_index and self._input_cache[action_index] then
                                self._input_cache[action_index][cache_index] = true
                            end
                        end
                    end
                end
            end
        end
        if not controller_observation.primary_action_injected then
            return
        end
        local stage = controller_observation.primary_action_stage
        if stage == "press" then
            local action_index = self._action_lookup and
                self._action_lookup.action_one_hold
            local cache_index = self._buffer_index and
                self:_buffer_index(frame)
            if not action_index or not cache_index or not self._input_cache or
                    not self._input_cache[action_index] then
                mod:warning(
                    "DARKTIDEVR_INPUT primary_action blocked reason=missing_hold_cache"
                )
                controller_observation.primary_action_stage = "failed"
                return
            end
            self._input_cache[action_index][cache_index] = true
            local pressed = self:get("action_one_pressed", frame)
            local held = self:get("action_one_hold", frame)
            controller_observation.primary_action_cache_observed = true
            controller_observation.primary_action_cache_frame = frame
            controller_observation.primary_action_stage = "held"
            mod:info(
                "DARKTIDEVR_INPUT primary_action fixed_cache pressed=%s held=%s frame=%s sequence=%d",
                tostring(pressed),
                tostring(held),
                tostring(frame),
                controller_observation.primary_action_sequence
            )
        elseif stage == "release" then
            local released = self:get("action_one_release", frame)
            local held = self:get("action_one_hold", frame)
            controller_observation.primary_action_stage = "complete"
            mod:info(
                "DARKTIDEVR_INPUT primary_action release_cache=%s held=%s frame=%s sequence=%d",
                tostring(released),
                tostring(held),
                tostring(frame),
                controller_observation.primary_action_sequence
            )
        end
    end)

function presentation.log_unit_pose(label, unit, node)
    if not unit or not Unit.alive(unit) then
        mod:info("DARKTIDEVR_WEAPON %s unit=missing", tostring(label))
        return
    end
    local node_index = node or 1
    local ok, error_message = pcall(function()
        local position = Unit.world_position(unit, node_index)
        local rotation = Unit.world_rotation(unit, node_index)
        local yaw, pitch, roll = Quaternion.to_yaw_pitch_roll(rotation)
        mod:info(
            "DARKTIDEVR_WEAPON %s node=%s position=%.4f,%.4f,%.4f ypr=%.4f,%.4f,%.4f",
            tostring(label), tostring(node_index),
            Vector3.x(position), Vector3.y(position), Vector3.z(position),
            yaw, pitch, roll
        )
    end)
    if not ok then
        mod:warning(
            "DARKTIDEVR_WEAPON %s pose_error=%s",
            tostring(label), tostring(error_message))
    end
end

function presentation.scan_movement_inventory(self, fixed_frame)
    if controller_observation.movement_inventory_done or
            not Mods or not Mods.lua or not Mods.lua.io then
        return
    end
    local flag_path =
        "./../mods/darktidevr_stereo_probe/darktidevr_movement_inventory.flag"
    local flag = Mods.lua.io.open(flag_path, "r")
    if not flag then
        return
    end
    local request = flag:read("*all")
    flag:close()
    if not request or not request:match("^%s*scan%s*$") then
        return
    end
    local local_player = Managers and Managers.player and
        Managers.player:local_player(1)
    local player_unit = local_player and local_player.player_unit
    -- HumanInputHandler owns input caches rather than the player unit. Unlike
    -- the weapon/animation extensions it has no reliable `_unit` member, and
    -- the fixed-update frame is not part of every shipped handler signature.
    -- The one-shot file itself provides the necessary throttle.
    if not player_unit or not Unit.alive(player_unit) then
        return
    end
    local consumed = Mods.lua.io.open(flag_path, "w")
    if consumed then
        consumed:write("consumed\n")
        consumed:close()
    end
    controller_observation.movement_inventory_done = true

    local function relevant_name(value)
        return type(value) == "string" and
            (value:find("move", 1, true) or
             value:find("locomotion", 1, true) or
             value:find("position", 1, true) or
             value:find("velocity", 1, true) or
             value:find("teleport", 1, true) or
             value:find("mover", 1, true) or
             value:find("input", 1, true))
    end
    local function collect_keys(value)
        local found = {}
        local seen = {}
        local function visit(candidate)
            if type(candidate) ~= "table" or seen[candidate] then
                return
            end
            seen[candidate] = true
            for key in pairs(candidate) do
                if relevant_name(key) then
                    found[#found + 1] = tostring(key)
                end
            end
        end
        visit(value)
        local mt = type(value) == "table" and getmetatable(value) or nil
        visit(mt)
        visit(mt and mt.__index)
        table.sort(found)
        return #found > 0 and table.concat(found, ",") or "none"
    end
    local function collect_members(value)
        if type(value) ~= "table" then
            return "type=" .. type(value) .. ":" .. tostring(value)
        end
        local found = {}
        local ok, error_message = pcall(function()
            for key, member in pairs(value) do
                local member_type = type(member)
                local rendered = member_type
                if member_type == "number" or member_type == "boolean" or
                        member_type == "string" then
                    rendered = member_type .. ":" .. tostring(member)
                end
                found[#found + 1] = tostring(key) .. "=" .. rendered
                if #found >= 96 then
                    found[#found + 1] = "..."
                    break
                end
            end
        end)
        if not ok then
            return "pairs_error=" .. tostring(error_message)
        end
        table.sort(found)
        return #found > 0 and table.concat(found, ",") or "none"
    end
    local function render_vector(value)
        local ok, rendered = pcall(function()
            return string.format(
                "%.5f,%.5f,%.5f",
                Vector3.x(value), Vector3.y(value), Vector3.z(value))
        end)
        return ok and rendered or "unavailable:" .. tostring(rendered)
    end

    mod:info(
        "DARKTIDEVR_MOVEMENT inventory handler=%s fixed_frame=%s",
        collect_keys(self), tostring(fixed_frame))
    local extension_names = {
        "locomotion_system", "movement_state_machine_system",
        "unit_data_system", "first_person_system", "input_system",
        "weapon_system", "mover_system", "navigation_system"
    }
    for index = 1, #extension_names do
        local name = extension_names[index]
        local ok, extension = pcall(ScriptUnit.has_extension, player_unit, name)
        mod:info(
            "DARKTIDEVR_MOVEMENT extension=%s present=%s keys=%s",
            name, tostring(ok and extension ~= nil),
            ok and extension and collect_keys(extension) or "none")
    end
    local locomotion_extension =
        ScriptUnit.has_extension(player_unit, "locomotion_system")
    if locomotion_extension then
        local component_names = {
            "_locomotion_component",
            "_locomotion_force_translation_component",
            "_locomotion_force_rotation_component",
            "_locomotion_steering_component",
            "_movement_settings_component",
            "_movement_state_component"
        }
        for index = 1, #component_names do
            local component_name = component_names[index]
            local component = locomotion_extension[component_name]
            mod:info(
                "DARKTIDEVR_MOVEMENT component=%s members=%s",
                component_name,
                collect_members(component))
            if type(component) == "table" then
                local storage_names = {
                    "__config", "__data", "__blackboard", "__additional_data"
                }
                for storage_index = 1, #storage_names do
                    local storage_name = storage_names[storage_index]
                    -- Component proxies interpret unknown indexed fields as
                    -- generated schema fields and throw. Inventory metadata
                    -- lives directly on the wrapper, so bypass __index.
                    local storage = rawget(component, storage_name)
                    mod:info(
                        "DARKTIDEVR_MOVEMENT component=%s storage=%s members=%s",
                        component_name, storage_name, collect_members(storage))
                    if type(storage) == "table" then
                        local nested_count = 0
                        for key, member in pairs(storage) do
                            if type(member) == "table" then
                                nested_count = nested_count + 1
                                mod:info(
                                    "DARKTIDEVR_MOVEMENT component=%s storage=%s key=%s nested=%s",
                                    component_name, storage_name, tostring(key),
                                    collect_members(member))
                                if nested_count >= 16 then
                                    break
                                end
                            end
                        end
                    end
                end
                local vector_fields = {
                    "position", "velocity_current", "start_translation",
                    "target_translation", "velocity_wanted"
                }
                for field_index = 1, #vector_fields do
                    local field_name = vector_fields[field_index]
                    if rawget(component, "__config") and
                            rawget(component, "__config")[field_name] then
                        mod:info(
                            "DARKTIDEVR_MOVEMENT component=%s field=%s value=%s",
                            component_name, field_name,
                            render_vector(component[field_name]))
                    end
                end
            end
        end
        local method_names = {
            "_update_movement", "_update_script_driven_hub_movement",
            "_update_script_driven_movement"
        }
        for index = 1, #method_names do
            local method_name = method_names[index]
            local method = locomotion_extension[method_name]
            local info = debug and debug.getinfo and type(method) == "function" and
                debug.getinfo(method, "Snu") or nil
            mod:info(
                "DARKTIDEVR_MOVEMENT method=%s source=%s line=%s params=%s upvalues=%s",
                method_name,
                tostring(info and (info.short_src or info.source) or "unavailable"),
                tostring(info and info.linedefined or "unavailable"),
                tostring(info and info.nparams or "unavailable"),
                tostring(info and info.nups or "unavailable"))
            if info and debug and debug.getupvalue then
                if debug.getlocal then
                    local parameter_names = {}
                    for parameter_index = 1, info.nparams do
                        local parameter_name =
                            debug.getlocal(method, parameter_index)
                        parameter_names[#parameter_names + 1] =
                            tostring(parameter_name)
                    end
                    mod:info(
                        "DARKTIDEVR_MOVEMENT method=%s parameters=%s",
                        method_name, table.concat(parameter_names, ","))
                end
                for upvalue_index = 1, info.nups do
                    local upvalue_name, upvalue =
                        debug.getupvalue(method, upvalue_index)
                    mod:info(
                        "DARKTIDEVR_MOVEMENT method=%s upvalue=%s type=%s members=%s",
                        method_name, tostring(upvalue_name), type(upvalue),
                        collect_members(upvalue))
                end
            end
        end
    end
end

function presentation.refresh_body_follow_mode(t)
    if t < controller_observation.body_follow_last_check_t + 1 or
            not Mods or not Mods.lua or not Mods.lua.io then
        return
    end
    controller_observation.body_follow_last_check_t = t
    local flag_path =
        "./../mods/darktidevr_stereo_probe/darktidevr_body_follow_test.flag"
    local flag = Mods.lua.io.open(flag_path, "r")
    local mode = "disabled"
    if flag then
        local request = flag:read("*all")
        flag:close()
        if request and request:match("^%s*trace%s*$") then
            mode = "trace"
        elseif request and request:match("^%s*enabled%s*$") then
            mode = "enabled"
        end
    end
    local game_mode_name = active_game_mode_name()
    if game_mode_name ~= "shooting_range" and
            game_mode_name ~= "training_grounds" then
        mode = "disabled"
    end
    if mode ~= controller_observation.body_follow_mode then
        controller_observation.body_follow_mode = mode
        controller_observation.body_follow_last_sequence = head_pose_last_sequence
        controller_observation.body_follow_last_x =
            controller_observation.body_follow_x
        controller_observation.body_follow_last_z =
            controller_observation.body_follow_z
        controller_observation.body_follow_last_position_x = nil
        controller_observation.body_follow_last_position_y = nil
        controller_observation.body_follow_last_position_z = nil
        mod:info(
            "DARKTIDEVR_MOVEMENT body_follow mode=%s source=test_flag",
            mode)
    end
end

function presentation.apply_body_follow_translation(
        unit, dt, t, locomotion_component, steering_component,
        current_position)
    presentation.refresh_body_follow_mode(t)
    local mode = controller_observation.body_follow_mode
    if mode == "disabled" then
        return nil
    end
    local local_player = Managers and Managers.player and
        Managers.player:local_player(1)
    if not local_player or unit ~= local_player.player_unit or
            not Unit.alive(unit) then
        return nil
    end

    local sequence = head_pose_last_sequence
    local body_x = controller_observation.body_follow_x
    local body_z = controller_observation.body_follow_z
    local delta_x = 0
    local delta_z = 0
    if sequence ~= controller_observation.body_follow_last_sequence then
        if sequence > controller_observation.body_follow_last_sequence then
            delta_x = body_x - controller_observation.body_follow_last_x
            delta_z = body_z - controller_observation.body_follow_last_z
        end
        controller_observation.body_follow_last_sequence = sequence
        controller_observation.body_follow_last_x = body_x
        controller_observation.body_follow_last_z = body_z
    end

    local character_scale = 1
    if local_player:archetype_name() == "ogryn" then
        character_scale = 1.61 / 1.21
    end
    local world_delta = Vector3.zero()
    local original_velocity = nil
    if delta_x ~= 0 or delta_z ~= 0 then
        local body_rotation = locomotion_component.rotation
        world_delta =
            Quaternion.right(body_rotation) * (delta_x * character_scale) +
            Quaternion.forward(body_rotation) * (-delta_z * character_scale)
        if mode == "enabled" and dt > 0 then
            -- Normal script-driven locomotion never reads target_translation.
            -- Feed the physical displacement through the exact velocity input
            -- consumed by the mover/collision path for this fixed update only.
            -- Restoring the original steering value after the wrapped call
            -- keeps stick acceleration/deceleration state independent.
            original_velocity = steering_component.velocity_wanted
            steering_component.velocity_wanted =
                original_velocity + world_delta / dt
            controller_observation.body_follow_writes =
                controller_observation.body_follow_writes + 1
        end
    end

    if t >= controller_observation.body_follow_last_log_t + 0.5 then
        local target = steering_component.target_translation
        local velocity = steering_component.velocity_wanted
        local position_dx = 0
        local position_dy = 0
        local position_dz = 0
        if controller_observation.body_follow_last_position_x then
            position_dx = Vector3.x(current_position) -
                controller_observation.body_follow_last_position_x
            position_dy = Vector3.y(current_position) -
                controller_observation.body_follow_last_position_y
            position_dz = Vector3.z(current_position) -
                controller_observation.body_follow_last_position_z
        end
        controller_observation.body_follow_last_position_x =
            Vector3.x(current_position)
        controller_observation.body_follow_last_position_y =
            Vector3.y(current_position)
        controller_observation.body_follow_last_position_z =
            Vector3.z(current_position)
        controller_observation.body_follow_last_log_t = t
        mod:info(
            "DARKTIDEVR_MOVEMENT body_follow mode=%s sequence=%d cumulative=%.5f,%.5f delta=%.5f,%.5f world_delta=%.5f,%.5f,%.5f target=%.5f,%.5f,%.5f velocity=%.5f,%.5f,%.5f position_delta=%.5f,%.5f,%.5f local_move=%.3f,%.3f writes=%d",
            mode, sequence, body_x, body_z, delta_x, delta_z,
            Vector3.x(world_delta), Vector3.y(world_delta),
            Vector3.z(world_delta), Vector3.x(target), Vector3.y(target),
            Vector3.z(target), Vector3.x(velocity), Vector3.y(velocity),
            Vector3.z(velocity), position_dx, position_dy, position_dz,
            steering_component.local_move_x,
            steering_component.local_move_y,
            controller_observation.body_follow_writes)
    end
    return original_velocity
end

mod:hook(
    require(
        "scripts/extension_systems/locomotion/player_unit_locomotion_extension"),
    "_update_script_driven_movement",
    function(func, self, unit, dt, t, locomotion_component,
            steering_component, current_position, calculate_fall_velocity,
            on_ground, mover)
        local original_velocity = presentation.apply_body_follow_translation(
            unit, dt, t, locomotion_component, steering_component,
            current_position)
        local result = func(
            self, unit, dt, t, locomotion_component, steering_component,
            current_position, calculate_fall_velocity, on_ground, mover)
        if original_velocity then
            steering_component.velocity_wanted = original_velocity
        end
        return result
    end)

function presentation.scan_named_nodes(label, unit, node_names)
    if not unit or not Unit.alive(unit) then
        return
    end
    local count_ok, count = pcall(Unit.num_scene_graph_items, unit)
    mod:info(
        "DARKTIDEVR_WEAPON unit=%s scene_graph_items=%s",
        tostring(label), tostring(count_ok and count or "unavailable")
    )
    for i = 1, #node_names do
        local node_name = node_names[i]
        if Unit.has_node(unit, node_name) then
            presentation.log_unit_pose(
                tostring(label) .. ":" .. node_name,
                unit,
                Unit.node(unit, node_name))
        end
    end
end

function presentation.scan_body_rig(self, fixed_frame)
    if controller_observation.body_rig_inventory_done or not fixed_frame or
            fixed_frame <
                controller_observation.body_rig_inventory_last_check_frame + 60 or
            not Mods or not Mods.lua or not Mods.lua.io then
        return
    end
    controller_observation.body_rig_inventory_last_check_frame = fixed_frame
    local flag_path =
        "./../mods/darktidevr_stereo_probe/darktidevr_body_rig_inventory.flag"
    local flag = Mods.lua.io.open(flag_path, "r")
    if not flag then
        return
    end
    local request = flag:read("*all")
    flag:close()
    if not request or not request:match("^%s*scan%s*$") then
        return
    end
    local local_player = Managers and Managers.player and
        Managers.player:local_player(1)
    local player_unit = local_player and local_player.player_unit
    if not player_unit or self._unit ~= player_unit or
            not Unit.alive(player_unit) then
        return
    end
    local consumed = Mods.lua.io.open(flag_path, "w")
    if consumed then
        consumed:write("consumed\n")
        consumed:close()
    end
    controller_observation.body_rig_inventory_done = true
    local unit_data = ScriptUnit.has_extension(player_unit, "unit_data_system")
    local breed_ok, breed_name = pcall(function()
        return unit_data and unit_data:breed_name()
    end)
    local nodes = {
        "j_hips_handle", "j_hips", "j_spine", "j_spine1", "j_spine2",
        "j_spine3", "j_neck", "j_head", "j_leftshoulder",
        "j_leftarm", "j_leftupperarm", "j_leftforearm", "j_lefthand",
        "j_left_hand_ik_handle", "j_rightshoulder", "j_rightupperarm",
        "j_rightarm", "j_rightforearm", "j_righthand",
        "j_right_hand_ik_handle",
        "j_leftupleg", "j_leftleg", "j_leftfoot", "j_rightupleg",
        "j_rightleg", "j_rightfoot", "j_left_foot_ik_handle",
        "j_right_foot_ik_handle", "j_left_foot_orient_handle",
        "j_right_foot_orient_handle"
    }
    local count_ok, count = pcall(Unit.num_scene_graph_items, player_unit)
    mod:info(
        "DARKTIDEVR_IK inventory breed=%s scene_graph_items=%s frame=%s",
        tostring(breed_ok and breed_name or "unavailable"),
        tostring(count_ok and count or "unavailable"),
        tostring(fixed_frame))
    for i = 1, #nodes do
        local name = nodes[i]
        if Unit.has_node(player_unit, name) then
            local node = Unit.node(player_unit, name)
            local parent = Unit.scene_graph_parent(player_unit, node)
            local local_position = Unit.local_position(player_unit, node)
            local world_position = Unit.world_position(player_unit, node)
            mod:info(
                "DARKTIDEVR_IK node name=%s index=%s parent=%s local=%.4f,%.4f,%.4f world=%.4f,%.4f,%.4f",
                name, tostring(node), tostring(parent),
                Vector3.x(local_position), Vector3.y(local_position),
                Vector3.z(local_position), Vector3.x(world_position),
                Vector3.y(world_position), Vector3.z(world_position))
        end
    end
    local constraints = {
        "aim_constraint_target", "look_constraint_target",
        "left_hand_constraint_target", "right_hand_constraint_target"
    }
    for i = 1, #constraints do
        local name = constraints[i]
        local found_ok, target = pcall(
            Unit.animation_find_constraint_target, player_unit, name)
        if found_ok and target ~= nil then
            local pose_ok, pose = pcall(
                Unit.animation_get_constraint_target, player_unit, target)
            if pose_ok and pose then
                local position = Matrix4x4.translation(pose)
                mod:info(
                    "DARKTIDEVR_IK constraint name=%s index=%s position=%.4f,%.4f,%.4f",
                    name, tostring(target), Vector3.x(position),
                    Vector3.y(position), Vector3.z(position))
            else
                mod:info(
                    "DARKTIDEVR_IK constraint name=%s index=%s pose=unavailable",
                    name, tostring(target))
            end
        end
    end
end

presentation.headless_body_slots = {
    "slot_body_face",
    "slot_body_face_tattoo",
    "slot_body_face_scar",
    "slot_body_face_hair",
    "slot_body_face_makeup",
    "slot_body_hair",
    "slot_body_eye_color",
    "slot_body_eye_color_secondary",
    "slot_body_hair_color",
    "slot_body_face_hair_color",
    "slot_gear_head"
}

presentation.headless_body_hidden_slot_lookup = {
    slot_body_face = true,
    slot_body_face_tattoo = true,
    slot_body_face_scar = true,
    slot_body_face_hair = true,
    slot_body_face_makeup = true,
    slot_body_hair = true,
    slot_body_eye_color = true,
    slot_body_eye_color_secondary = true,
    slot_body_hair_color = true,
    slot_body_face_hair_color = true,
    slot_gear_head = true
}

function presentation.update_body_visibility_gate(frame)
    if frame <
            controller_observation.body_visibility_last_check_frame + 60 then
        return false
    end
    controller_observation.body_visibility_last_check_frame = frame
    local path =
        "./../mods/darktidevr_stereo_probe/darktidevr_headless_body.flag"
    local flag = Mods and Mods.lua and Mods.lua.io and
        Mods.lua.io.open(path, "r")
    local enabled = false
    if flag then
        enabled = flag:read("*all"):match("^%s*enabled%s*$") ~= nil
        flag:close()
    end
    local hub_path =
        "./../mods/darktidevr_stereo_probe/darktidevr_force_hub_first_person.flag"
    local hub_flag = Mods and Mods.lua and Mods.lua.io and
        Mods.lua.io.open(hub_path, "r")
    local force_hub_first_person = false
    if hub_flag then
        force_hub_first_person =
            hub_flag:read("*all"):match("^%s*enabled%s*$") ~= nil
        hub_flag:close()
    end
    if force_hub_first_person ~=
            controller_observation.force_hub_first_person_enabled then
        controller_observation.force_hub_first_person_enabled =
            force_hub_first_person
        mod:info(
            "DARKTIDEVR_BODY hub_presentation=%s source=test_flag",
            force_hub_first_person and "forced_1p" or "stock_3p")
    end
    if not enabled then
        controller_observation.body_visibility_faulted = false
    end
    enabled = enabled and
        not controller_observation.body_visibility_faulted
    if enabled == controller_observation.body_visibility_enabled then
        return false
    end
    controller_observation.body_visibility_enabled = enabled
    controller_observation.body_visibility_logged_slots = false
    controller_observation.body_fade_override_logged = false
    controller_observation.body_camera_anchor_logged = false
    controller_observation.body_eye_anchor_logged = false
    controller_observation.body_eye_anchor_unit = nil
    controller_observation.body_eye_anchor_local_x = nil
    controller_observation.body_eye_anchor_local_y = nil
    controller_observation.body_eye_anchor_local_z = nil
    controller_observation.body_eye_anchor_source = nil
    controller_observation.body_camera_sweep_start_t = nil
    controller_observation.body_camera_sweep_last_bucket = -1
    controller_observation.body_head_visible = not enabled
    controller_observation.body_visual_yaw = nil
    controller_observation.body_visual_yaw_last_t = nil
    controller_observation.body_heading_last_head_yaw = nil
    controller_observation.body_heading_last_motion_t = -math.huge
    controller_observation.body_ik_torso_axis_unit = nil
    controller_observation.body_ik_torso_axis_local = nil
    controller_observation.body_ik_torso_block_reason = false
    controller_observation.body_ik_torso_residual = nil
    mod:info(
        "DARKTIDEVR_BODY visibility=%s source=test_flag",
        enabled and "headless_3p" or "stock_1p")
    return true
end

function presentation.is_local_visual_loadout(self)
    local local_player = Managers and Managers.player and
        Managers.player:local_player(1)
    return local_player and local_player.player_unit and
        self._unit == local_player.player_unit
end

function presentation.apply_body_visibility(self, frame, force)
    if not presentation.is_local_visual_loadout(self) then
        return
    end
    local mode = active_game_mode_name()
    local range_mode = mode == "shooting_range" or
        mode == "training_grounds"
    local active = controller_observation.body_visibility_enabled and
        range_mode
    if not force and frame <
            controller_observation.body_visibility_last_apply_frame + 60 then
        return
    end
    controller_observation.body_visibility_last_apply_frame = frame

    local EquipmentComponent = require(
        "scripts/extension_systems/visual_loadout/equipment_component")
    local equipment = self._equipment
    local inventory = self._inventory_component
    local unit_3p = self._unit
    local unit_1p = self._first_person_unit
    if type(equipment) ~= "table" or not inventory or
            not unit_3p or not Unit.alive(unit_3p) then
        return
    end

    -- Activate the engine's genuine 3P presentation and retain its camera tree
    -- so the renderer continues submitting the local skinned actor. The stereo
    -- update replaces that tree's final origin with the 1P head anchor.
    local first_person_extension = self._first_person_extension
    if first_person_extension then
        first_person_extension._force_third_person_mode = active
        if active then
            first_person_extension._show_1p_equipment = false
            first_person_extension._wants_1p_camera = false
        end
    end

    -- This is Darktide's stock visual swap, invoked with a visual-only 3P
    -- selection. The gameplay/camera first-person component remains unchanged.
    local visibility_first_person_mode = self._is_in_first_person_mode
    if active then
        visibility_first_person_mode = false
    end
    EquipmentComponent.update_item_visibility(
        equipment,
        inventory.wielded_slot,
        unit_3p,
        unit_1p,
        visibility_first_person_mode,
        self._item_definitions)

    -- Darktide's native FadeSystem makes player breeds transparent as the
    -- active camera approaches j_spine (human 0.3-0.9 m, ogryn 0.5-1.2 m).
    -- min_fade is a lower bound on the *fade effect* (stealth raises it), not
    -- an opacity floor, so keep it at the stock zero. The range-only update
    -- hook below suppresses camera-proximity fading without deregistering the
    -- unit from the native extension lifecycle.
    local fade_system = Managers and Managers.state and
        Managers.state.extension and
        Managers.state.extension:system("fade_system")
    if fade_system then
        fade_system:set_min_fade(unit_3p, 0)
        if not controller_observation.body_fade_override_logged then
            controller_observation.body_fade_override_logged = true
            mod:info(
                "DARKTIDEVR_BODY fade_override min_fade=0 distant_update=%s",
                tostring(active))
        end
    end

    if not active then
        -- Reassert the stock root-unit selection along with the equipment
        -- selection when the range-only gate is disabled. This keeps rollback
        -- symmetric even if a later engine version changes helper ownership.
        if unit_1p and Unit.alive(unit_1p) then
            Unit.set_unit_visibility(
                unit_1p, self._is_in_first_person_mode, true)
        end
        Unit.set_unit_visibility(
            unit_3p, not self._is_in_first_person_mode, true)
        return
    end

    -- The native 3P presentation has already selected the root and stock 3P
    -- slot set. Remove only geometry that can intersect the eye cameras. Do
    -- not force arbitrary slot units visible here: hidden gadgets and
    -- unwielded equipment have independent authored visibility policy.
    local player_visibility = ScriptUnit.has_extension(
        unit_3p, "player_visibility_system")
    local visible_3p_units = 0
    local hidden_3p_units = 0
    local hidden = {}
    for slot_name, slot in pairs(equipment) do
        if type(slot_name) == "string" and type(slot) == "table" then
            local slot_unit_3p = slot.unit_3p
            if slot_unit_3p and Unit.alive(slot_unit_3p) then
                if presentation.headless_body_hidden_slot_lookup[slot_name] then
                    local show_head =
                        controller_observation.body_head_visible and
                        not slot.hidden_3p
                    Unit.flow_event(
                        slot_unit_3p,
                        show_head and "lua_visible" or "lua_hidden")
                    Unit.set_unit_visibility(slot_unit_3p, show_head, true)
                    local attachments = slot.attachments_by_unit_3p and
                        slot.attachments_by_unit_3p[slot_unit_3p]
                    if attachments then
                        for i = 1, #attachments do
                            local attachment = attachments[i]
                            if attachment and Unit.alive(attachment) then
                                Unit.flow_event(
                                    attachment,
                                    show_head and "lua_visible" or
                                        "lua_hidden")
                                Unit.set_unit_visibility(
                                    attachment, show_head, true)
                            end
                        end
                    end
                    if show_head then
                        visible_3p_units = visible_3p_units + 1
                    else
                        hidden[#hidden + 1] = slot_name
                        hidden_3p_units = hidden_3p_units + 1
                    end
                elseif slot.hidden_3p then
                    hidden_3p_units = hidden_3p_units + 1
                else
                    visible_3p_units = visible_3p_units + 1
                end
            end
        end
    end

    if not controller_observation.body_visibility_logged_slots then
        local slot_names = {}
        for slot_name, slot in pairs(equipment) do
            if type(slot_name) == "string" and type(slot) == "table" and
                    (slot.unit_1p or slot.unit_3p) then
                slot_names[#slot_names + 1] = slot_name
            end
        end
        table.sort(slot_names)
        for i = 1, #slot_names do
            local slot_name = slot_names[i]
            local slot = equipment[slot_name]
            local item = slot.item
            mod:info(
                "DARKTIDEVR_BODY slot=%s item=%s unit_1p=%s unit_3p=%s wielded=%s hide_unit=%s hidden_3p=%s attach=%s wielded_attach=%s unwielded_attach=%s",
                slot_name,
                tostring(item and item.name),
                tostring(slot.unit_1p and Unit.alive(slot.unit_1p) or false),
                tostring(slot.unit_3p and Unit.alive(slot.unit_3p) or false),
                tostring(slot_name == inventory.wielded_slot),
                tostring(slot.hide_unit_in_slot == true),
                tostring(slot.hidden_3p),
                tostring(item and item.attach_node),
                tostring(item and item.wielded_attach_node),
                tostring(item and item.unwielded_attach_node))
        end
        controller_observation.body_visibility_logged_slots = true
        mod:info(
            "DARKTIDEVR_BODY headless_3p applied mode=%s force_engine_3p=%s player_visible=%s hidden_slots=%s visible_3p_units=%d hidden_3p_units=%d unit_1p=%s wielded=%s",
            tostring(mode),
            tostring(first_person_extension and
                first_person_extension._force_third_person_mode),
            tostring(player_visibility and player_visibility:visible()),
            #hidden > 0 and table.concat(hidden, ",") or "none",
            visible_3p_units,
            hidden_3p_units,
            tostring(unit_1p and Unit.alive(unit_1p) or false),
            tostring(inventory.wielded_slot))
    end
end

function presentation.scan_weapon_inventory(self, fixed_frame)
    if controller_observation.weapon_inventory_done or not fixed_frame or
            fixed_frame <
                controller_observation.weapon_inventory_last_check_frame + 60 or
            not Mods or not Mods.lua or not Mods.lua.io then
        return
    end
    controller_observation.weapon_inventory_last_check_frame = fixed_frame
    local flag_path =
        "./../mods/darktidevr_stereo_probe/darktidevr_weapon_inventory.flag"
    local flag = Mods.lua.io.open(flag_path, "r")
    if not flag then
        return
    end
    local request = flag:read("*all")
    flag:close()
    if not request or not request:match("^%s*scan%s*$") then
        return
    end
    local local_player = Managers and Managers.player and
        Managers.player:local_player(1)
    if not local_player or self._unit ~= local_player.player_unit then
        return
    end
    local consumed = Mods.lua.io.open(flag_path, "w")
    if consumed then
        consumed:write("consumed\n")
        consumed:close()
    end
    local slot_name = self._inventory_component and
        self._inventory_component.wielded_slot
    local weapon = slot_name and self._weapons and self._weapons[slot_name]
    local template = weapon and weapon.weapon_template
    local weapon_unit = weapon and weapon.weapon_unit
    local visual_loadout = self._visual_loadout_extension
    controller_observation.weapon_inventory_done = true
    mod:info(
        "DARKTIDEVR_WEAPON inventory slot=%s template=%s weapon_unit_alive=%s first_person_unit_alive=%s",
        tostring(slot_name), tostring(template and template.name),
        tostring(weapon_unit and Unit.alive(weapon_unit) or false),
        tostring(self._first_person_unit and
            Unit.alive(self._first_person_unit) or false)
    )
    presentation.log_unit_pose("weapon_root", weapon_unit, 1)
    presentation.log_unit_pose("first_person_root", self._first_person_unit, 1)
    local candidate_nodes = {
        "j_righthand",
        "j_lefthand",
        "j_right_hand",
        "j_left_hand",
        "j_rightweaponattach",
        "j_leftweaponattach",
        "j_right_hand_ik_handle",
        "j_left_hand_ik_handle",
        "fx_right_hand",
        "fx_left_hand",
        "fx_overheat"
    }
    presentation.scan_named_nodes(
        "first_person", self._first_person_unit, candidate_nodes)
    presentation.scan_named_nodes("weapon", weapon_unit, candidate_nodes)
    if visual_loadout and slot_name then
        local _, _, attachments_by_unit_1p =
            visual_loadout:unit_and_attachments_from_slot(slot_name)
        local attachment_index = 0
        if type(attachments_by_unit_1p) == "table" then
            for _, attachments in pairs(attachments_by_unit_1p) do
                if type(attachments) == "table" then
                    for i = 1, #attachments do
                        attachment_index = attachment_index + 1
                        local attachment = attachments[i]
                        presentation.log_unit_pose(
                            "attachment_1p_" .. tostring(attachment_index) ..
                                "_root",
                            attachment,
                            1)
                        presentation.scan_named_nodes(
                            "attachment_1p_" .. tostring(attachment_index),
                            attachment,
                            candidate_nodes)
                    end
                end
            end
        end
        mod:info(
            "DARKTIDEVR_WEAPON attachment_1p_count=%d",
            attachment_index)
    end
    if template and type(template.fx_sources) == "table" and visual_loadout then
        for source_key, node_name in pairs(template.fx_sources) do
            local unit_1p, node_1p =
                visual_loadout:unit_and_node_from_node_name(
                    slot_name, node_name)
            mod:info(
                "DARKTIDEVR_WEAPON fx_source=%s node_name=%s resolved_1p=%s node=%s",
                tostring(source_key), tostring(node_name),
                tostring(unit_1p and Unit.alive(unit_1p) or false),
                tostring(node_1p)
            )
            if unit_1p and node_1p then
                presentation.log_unit_pose(
                    "fx:" .. tostring(source_key), unit_1p, node_1p)
            end
        end
    end
end

function presentation.vector_distance(left, right)
    local x = Vector3.x(left) - Vector3.x(right)
    local y = Vector3.y(left) - Vector3.y(right)
    local z = Vector3.z(left) - Vector3.z(right)
    return math.sqrt(x * x + y * y + z * z)
end

function presentation.rotate_vector(rotation, value)
    return Quaternion.right(rotation) * Vector3.x(value) +
        Quaternion.forward(rotation) * Vector3.y(value) +
        Quaternion.up(rotation) * Vector3.z(value)
end

function presentation.inverse_quaternion(rotation)
    local x, y, z, w = Quaternion.to_elements(rotation)
    return Quaternion.from_elements(-x, -y, -z, w)
end

function presentation.vector_cross(left, right)
    return Vector3(
        Vector3.y(left) * Vector3.z(right) -
            Vector3.z(left) * Vector3.y(right),
        Vector3.z(left) * Vector3.x(right) -
            Vector3.x(left) * Vector3.z(right),
        Vector3.x(left) * Vector3.y(right) -
            Vector3.y(left) * Vector3.x(right))
end

function presentation.vector_dot(left, right)
    return Vector3.x(left) * Vector3.x(right) +
        Vector3.y(left) * Vector3.y(right) +
        Vector3.z(left) * Vector3.z(right)
end

function presentation.align_vectors_rotation(from, to)
    local from_length = Vector3.length(from)
    local to_length = Vector3.length(to)
    if from_length < 0.000001 or to_length < 0.000001 then
        return nil
    end
    local source = from / from_length
    local destination = to / to_length
    local dot = math.max(-1, math.min(1,
        presentation.vector_dot(source, destination)))
    if dot > 0.999999 then
        return Quaternion.from_elements(0, 0, 0, 1)
    end
    local axis = presentation.vector_cross(source, destination)
    local axis_length = Vector3.length(axis)
    if axis_length < 0.000001 then
        axis = presentation.vector_cross(source, Vector3.up())
        axis_length = Vector3.length(axis)
        if axis_length < 0.000001 then
            axis = presentation.vector_cross(source, Vector3(1, 0, 0))
            axis_length = Vector3.length(axis)
        end
    end
    if axis_length < 0.000001 then
        return nil
    end
    return Quaternion.axis_angle(axis / axis_length, math.acos(dot))
end

function presentation.quaternion_angle_error(left, right)
    local lx, ly, lz, lw = Quaternion.to_elements(left)
    local rx, ry, rz, rw = Quaternion.to_elements(right)
    local dot = math.abs(lx * rx + ly * ry + lz * rz + lw * rw)
    return 2 * math.acos(math.max(-1, math.min(1, dot)))
end

-- Freeze a hub interaction panel in the same body-relative coordinates used
-- by tracked controllers. The clean camera is the game-world pose of the
-- immutable OpenXR recenter; applying its inverse here is the exact inverse of
-- controller_grip_target(), rather than an independent world/XR transform.
function presentation.capture_vendor_anchor(view_name, interactee_unit)
    if not active or not interactee_unit or not Unit.alive(interactee_unit) or
            not controller_observation.body_anchor_qw then
        return false, "stereo_or_pose_unavailable"
    end
    local marker_node = Unit.has_node(interactee_unit,
        "ui_interaction_marker") and
        Unit.node(interactee_unit, "ui_interaction_marker") or 1
    local marker_position = Unit.world_position(interactee_unit, marker_node)
    local anchor_position = Vector3(
        controller_observation.body_anchor_x,
        controller_observation.body_anchor_y,
        controller_observation.body_anchor_z)
    local anchor_rotation = Quaternion.from_elements(
        controller_observation.body_anchor_qx,
        controller_observation.body_anchor_qy,
        controller_observation.body_anchor_qz,
        controller_observation.body_anchor_qw)
    local from_camera = marker_position - anchor_position
    local dx = Vector3.x(from_camera)
    local dy = Vector3.y(from_camera)
    local horizontal_distance = math.sqrt(dx * dx + dy * dy)
    if horizontal_distance < 0.25 or horizontal_distance > 10 then
        return false, "interaction_distance_out_of_range"
    end

    -- Pull the two-metre board slightly toward the player so it occupies the
    -- interaction space in front of the NPC instead of intersecting its mesh.
    local horizontal_direction = Vector3(
        dx / horizontal_distance,
        dy / horizontal_distance,
        0)
    local panel_position = marker_position - horizontal_direction * 0.25
    local panel_world_rotation = Quaternion.look(
        horizontal_direction,
        Vector3.up())
    local inverse_anchor = presentation.inverse_quaternion(anchor_rotation)
    local body_position = presentation.rotate_vector(
        inverse_anchor,
        panel_position - anchor_position)
    local body_rotation = Quaternion.normalize(Quaternion.multiply(
        inverse_anchor,
        panel_world_rotation))
    local anchor = presentation.vendor_anchor
    anchor.x = Vector3.x(body_position)
    anchor.y = Vector3.y(body_position)
    anchor.z = Vector3.z(body_position)
    anchor.qx, anchor.qy, anchor.qz, anchor.qw =
        Quaternion.to_elements(body_rotation)
    anchor.valid = true
    anchor.view_name = view_name
    anchor.revision = anchor.revision + 1
    mod:info(
        "DARKTIDEVR_PRESENTATION world_anchor captured view=%s revision=%d body_pos=%.3f,%.3f,%.3f",
        tostring(view_name),
        anchor.revision,
        anchor.x,
        anchor.y,
        anchor.z
    )
    return true, "captured"
end

function presentation.scene_graph_root(unit, node)
    local current = node
    local parent = Unit.scene_graph_parent(unit, current)
    local depth = 0
    while parent ~= nil and depth < 256 do
        current = parent
        parent = Unit.scene_graph_parent(unit, current)
        depth = depth + 1
    end
    return current, depth
end

function presentation.controller_grip_target()
    if not controller_observation.right_grip_usable or
            not controller_observation.body_anchor_qw then
        return nil, nil
    end
    local anchor_position = Vector3(
        controller_observation.body_anchor_x,
        controller_observation.body_anchor_y,
        controller_observation.body_anchor_z)
    local anchor_rotation = Quaternion.from_elements(
        controller_observation.body_anchor_qx,
        controller_observation.body_anchor_qy,
        controller_observation.body_anchor_qz,
        controller_observation.body_anchor_qw)
    local grip_position = Vector3(
        controller_observation.right_grip_x,
        controller_observation.right_grip_y,
        controller_observation.right_grip_z)
    local grip_rotation = Quaternion.from_elements(
        controller_observation.right_grip_qx,
        controller_observation.right_grip_qy,
        controller_observation.right_grip_qz,
        controller_observation.right_grip_qw)
    local target_position = anchor_position +
        presentation.rotate_vector(anchor_rotation, grip_position)
    local target_rotation = Quaternion.multiply(anchor_rotation, grip_rotation)
    return target_position, target_rotation
end

function presentation.left_controller_grip_target()
    if not controller_observation.left_grip_usable or
            not controller_observation.body_anchor_qw then
        return nil, nil
    end
    local anchor_position = Vector3(
        controller_observation.body_anchor_x,
        controller_observation.body_anchor_y,
        controller_observation.body_anchor_z)
    local anchor_rotation = Quaternion.from_elements(
        controller_observation.body_anchor_qx,
        controller_observation.body_anchor_qy,
        controller_observation.body_anchor_qz,
        controller_observation.body_anchor_qw)
    local grip_position = Vector3(
        controller_observation.left_grip_x,
        controller_observation.left_grip_y,
        controller_observation.left_grip_z)
    local grip_rotation = Quaternion.from_elements(
        controller_observation.left_grip_qx,
        controller_observation.left_grip_qy,
        controller_observation.left_grip_qz,
        controller_observation.left_grip_qw)
    return anchor_position +
            presentation.rotate_vector(anchor_rotation, grip_position),
        Quaternion.multiply(anchor_rotation, grip_rotation)
end

-- Controller body poses are already relative to the immutable OpenXR head
-- recenter origin. Map them through the matching clean game-camera anchor.
-- Adding that complete relative pose to the *live* avatar head double-counts
-- the tracked head displacement and can put the requested wrist beyond the
-- arm's reach, where the two-bone solver necessarily clamps it.
function presentation.body_ik_controller_grip_target(unit, side)
    if not unit or not Unit.alive(unit) or
            not controller_observation.body_anchor_qw or
            not Unit.has_node(unit, "j_head") then
        return nil
    end
    local is_left = side == "left"
    if is_left and not controller_observation.left_grip_usable then
        return nil
    end
    if not is_left and not controller_observation.right_grip_usable then
        return nil
    end
    local grip_position = is_left and Vector3(
        controller_observation.left_grip_x,
        controller_observation.left_grip_y,
        controller_observation.left_grip_z) or Vector3(
        controller_observation.right_grip_x,
        controller_observation.right_grip_y,
        controller_observation.right_grip_z)
    local grip_rotation = is_left and Quaternion.from_elements(
        controller_observation.left_grip_qx,
        controller_observation.left_grip_qy,
        controller_observation.left_grip_qz,
        controller_observation.left_grip_qw) or Quaternion.from_elements(
        controller_observation.right_grip_qx,
        controller_observation.right_grip_qy,
        controller_observation.right_grip_qz,
        controller_observation.right_grip_qw)
    local anchor_rotation = Quaternion.from_elements(
        controller_observation.body_anchor_qx,
        controller_observation.body_anchor_qy,
        controller_observation.body_anchor_qz,
        controller_observation.body_anchor_qw)
    local anchor_position = Vector3(
        controller_observation.body_anchor_x,
        controller_observation.body_anchor_y,
        controller_observation.body_anchor_z)
    return anchor_position +
            presentation.rotate_vector(anchor_rotation, grip_position),
        Quaternion.normalize(Quaternion.multiply(
            anchor_rotation, grip_rotation))
end

function presentation.update_body_ik_trace_gate(fixed_frame)
    if fixed_frame <
            controller_observation.body_ik_trace_last_check_frame + 60 then
        return
    end
    controller_observation.body_ik_trace_last_check_frame = fixed_frame
    local path =
        "./../mods/darktidevr_stereo_probe/darktidevr_body_ik_trace.flag"
    local flag = Mods.lua.io.open(path, "r")
    local enabled = false
    if flag then
        enabled = flag:read("*all"):match("^%s*enabled%s*$") ~= nil
        flag:close()
    end
    if enabled ~= controller_observation.body_ik_trace_enabled then
        controller_observation.body_ik_trace_enabled = enabled
        mod:info("DARKTIDEVR_IK trace=%s source=test_flag",
            enabled and "enabled" or "disabled")
    end
end

function presentation.trace_body_arm(unit, side, target_position, emit_log)
    local arm_name = side == "left" and "j_leftarm" or "j_rightarm"
    local forearm_name = side == "left" and
        "j_leftforearm" or "j_rightforearm"
    local hand_name = side == "left" and "j_lefthand" or "j_righthand"
    if not Unit.has_node(unit, arm_name) or
            not Unit.has_node(unit, forearm_name) or
            not Unit.has_node(unit, hand_name) then
        return false, "nodes_missing"
    end
    local shoulder = Unit.world_position(unit, Unit.node(unit, arm_name))
    local elbow = Unit.world_position(unit, Unit.node(unit, forearm_name))
    local wrist = Unit.world_position(unit, Unit.node(unit, hand_name))
    local upper_length = presentation.vector_distance(shoulder, elbow)
    local lower_length = presentation.vector_distance(elbow, wrist)
    local reach = wrist - shoulder
    local bend = elbow - shoulder
    local input = controller_observation.ik_input
    local output = controller_observation.ik_output
    local flags = controller_observation.ik_flags
    input[0], input[1], input[2] =
        Vector3.x(shoulder), Vector3.y(shoulder), Vector3.z(shoulder)
    input[3], input[4], input[5] = Vector3.x(target_position),
        Vector3.y(target_position), Vector3.z(target_position)
    input[6], input[7], input[8] =
        Vector3.x(elbow), Vector3.y(elbow), Vector3.z(elbow)
    input[9], input[10], input[11] =
        Vector3.x(reach), Vector3.y(reach), Vector3.z(reach)
    input[12], input[13], input[14] =
        Vector3.x(bend), Vector3.y(bend), Vector3.z(bend)
    input[15], input[16] = upper_length, lower_length
    local result = ui_native_capture.dtvr_solve_two_bone_ik(
        input, 17, output, 14, flags)
    if result ~= 0 then
        return false, "native_" .. tostring(result)
    end
    local solved_elbow = Vector3(output[0], output[1], output[2])
    local solved_wrist = Vector3(output[3], output[4], output[5])
    if emit_log ~= false then
        mod:info(
            "DARKTIDEVR_IK solve side=%s sequence=%d upper_m=%.4f lower_m=%.4f requested_m=%.4f solved_m=%.4f flags=%d elbow_delta_m=%.4f wrist_target_error_m=%.4f solved_elbow=%.4f,%.4f,%.4f solved_wrist=%.4f,%.4f,%.4f",
            side, controller_observation.last_sequence, upper_length,
            lower_length, tonumber(output[12]), tonumber(output[13]),
            tonumber(flags[0]),
            presentation.vector_distance(elbow, solved_elbow),
            presentation.vector_distance(target_position, solved_wrist),
            Vector3.x(solved_elbow), Vector3.y(solved_elbow),
            Vector3.z(solved_elbow), Vector3.x(solved_wrist),
            Vector3.y(solved_wrist), Vector3.z(solved_wrist))
    end
    return true, "solved", solved_elbow, solved_wrist
end

function presentation.update_body_ik_presentation_gate(fixed_frame)
    if fixed_frame <
            controller_observation.body_ik_presentation_last_check_frame + 60 then
        return
    end
    controller_observation.body_ik_presentation_last_check_frame = fixed_frame
    local path =
        "./../mods/darktidevr_stereo_probe/darktidevr_body_ik_presentation.flag"
    local flag = Mods.lua.io.open(path, "r")
    local enabled = false
    if flag then
        enabled = flag:read("*all"):match("^%s*enabled%s*$") ~= nil
        flag:close()
    end
    if not enabled then
        controller_observation.body_ik_presentation_faulted = false
    end
    enabled = enabled and
        not controller_observation.body_ik_presentation_faulted
    if enabled ~= controller_observation.body_ik_presentation_enabled then
        controller_observation.body_ik_presentation_enabled = enabled
        controller_observation.body_ik_presentation_block_reason = nil
        controller_observation.body_ik_hand_offsets = {}
        controller_observation.body_ik_hand_anatomy = {}
        mod:info("DARKTIDEVR_IK presentation=%s source=test_flag",
            enabled and "enabled" or "disabled")
    end
end

function presentation.apply_body_arm_ik(
        world, unit, side, target_position, target_rotation)
    -- OpenXR locates the grip pose inside the held controller, while Darktide's
    -- hand node is the anatomical wrist. The calibrated visible finger axis is
    -- -grip-up, so placing the wrist 5 cm along +grip-up puts the controller
    -- origin in the palm instead of at the wrist joint.
    target_position = target_position +
        Quaternion.up(target_rotation) * 0.05
    local solved, reason, solved_elbow, solved_wrist =
        presentation.trace_body_arm(unit, side, target_position, false)
    if not solved then
        return false, reason
    end
    local arm_name = side == "left" and "j_leftarm" or "j_rightarm"
    local forearm_name = side == "left" and
        "j_leftforearm" or "j_rightforearm"
    local hand_name = side == "left" and "j_lefthand" or "j_righthand"
    local arm_node = Unit.node(unit, arm_name)
    local forearm_node = Unit.node(unit, forearm_name)
    local hand_node = Unit.node(unit, hand_name)
    local arm_parent = Unit.scene_graph_parent(unit, arm_node)
    local forearm_parent = Unit.scene_graph_parent(unit, forearm_node)
    local hand_parent = Unit.scene_graph_parent(unit, hand_node)
    if arm_parent == nil then
        return false, "arm_parent_missing"
    end
    -- The local-rotation solve below is exact only for this authored chain.
    -- Fail closed on a different breed/rig instead of rotating an unrelated
    -- branch or dragging its linked equipment through a bogus transform.
    if forearm_parent ~= arm_node then
        return false, "forearm_parent_mismatch"
    end
    if hand_parent ~= forearm_node then
        return false, "hand_parent_mismatch"
    end

    local shoulder = Unit.world_position(unit, arm_node)
    local elbow = Unit.world_position(unit, forearm_node)
    local wrist = Unit.world_position(unit, hand_node)
    local arm_world = Unit.world_rotation(unit, arm_node)
    local forearm_world = Unit.world_rotation(unit, forearm_node)
    local hand_world = Unit.world_rotation(unit, hand_node)
    if not controller_observation.body_ik_hand_anatomy[side] then
        local middle_name = side == "left" and
            "j_lefthandmiddle1" or "j_righthandmiddle1"
        local index_name = side == "left" and
            "j_lefthandindex1" or "j_righthandindex1"
        local pinky_name = side == "left" and
            "j_lefthandpinky1" or "j_righthandpinky1"
        if Unit.has_node(unit, middle_name) and
                Unit.has_node(unit, index_name) and
                Unit.has_node(unit, pinky_name) then
            local inverse_hand = presentation.inverse_quaternion(hand_world)
            local longitudinal = presentation.rotate_vector(
                inverse_hand,
                Unit.world_position(unit, Unit.node(unit, middle_name)) -
                    wrist)
            local across = presentation.rotate_vector(
                inverse_hand,
                Unit.world_position(unit, Unit.node(unit, index_name)) -
                    Unit.world_position(unit, Unit.node(unit, pinky_name)))
            longitudinal = Vector3.normalize(longitudinal)
            across = Vector3.normalize(across)
            local palm = Vector3.normalize(
                Vector3.cross(across, longitudinal))
            controller_observation.body_ik_hand_anatomy[side] = {
                longitudinal = Vector3Box(longitudinal),
                across = Vector3Box(across),
                palm = Vector3Box(palm)
            }
            mod:info(
                "DARKTIDEVR_IK anatomy_calibration side=%s stage=prewrite longitudinal_local=%.4f,%.4f,%.4f across_local=%.4f,%.4f,%.4f palm_local=%.4f,%.4f,%.4f",
                side,
                Vector3.x(longitudinal), Vector3.y(longitudinal),
                Vector3.z(longitudinal), Vector3.x(across),
                Vector3.y(across), Vector3.z(across), Vector3.x(palm),
                Vector3.y(palm), Vector3.z(palm))
        end
    end
    local arm_delta = presentation.align_vectors_rotation(
        elbow - shoulder, solved_elbow - shoulder)
    if not arm_delta then
        return false, "upper_alignment_invalid"
    end
    local solved_arm_world = Quaternion.multiply(arm_delta, arm_world)
    local solved_arm_local = Quaternion.multiply(
        presentation.inverse_quaternion(
            Unit.world_rotation(unit, arm_parent)),
        solved_arm_world)

    -- Rotating the upper arm also rotates the existing lower-arm basis. Build
    -- that provisional world pose analytically, then apply a second shortest-
    -- arc correction to the solved lower segment.
    local provisional_forearm_world = Quaternion.multiply(
        arm_delta, forearm_world)
    local provisional_lower = presentation.rotate_vector(
        arm_delta, wrist - elbow)
    local forearm_delta = presentation.align_vectors_rotation(
        provisional_lower, solved_wrist - solved_elbow)
    if not forearm_delta then
        return false, "lower_alignment_invalid"
    end
    local solved_forearm_world = Quaternion.multiply(
        forearm_delta, provisional_forearm_world)
    local solved_forearm_local = Quaternion.multiply(
        presentation.inverse_quaternion(solved_arm_world),
        solved_forearm_world)
    -- Convert the measured, pre-write hand anatomy into the tracked controller
    -- frame rather than assuming mirrored bone axes. Touch's grip +Y points
    -- down the physical handle: the live profile measurement places it 150
    -- degrees from the aim ray. A visible hand's wrist-to-fingertips direction
    -- is therefore -grip-Y, while little-to-index remains grip-forward. The
    -- corresponding palm normal is -grip-X. The source frame absorbs the
    -- rig's actual left/right mirroring and any breed-specific bone basis.
    local anatomy = controller_observation.body_ik_hand_anatomy[side]
    if not anatomy then
        return false, "hand_anatomy_unavailable"
    end
    local source_frame = Quaternion.look(
        anatomy.palm:unbox(), anatomy.across:unbox())
    local target_frame = Quaternion.look(
        Quaternion.right(target_rotation) * -1,
        Quaternion.forward(target_rotation))
    local solved_hand_world = Quaternion.multiply(
        target_frame,
        presentation.inverse_quaternion(source_frame))
    local solved_hand_local = Quaternion.multiply(
        presentation.inverse_quaternion(solved_forearm_world),
        solved_hand_world)
    Unit.set_local_rotation(unit, arm_node, solved_arm_local)
    Unit.set_local_rotation(unit, forearm_node, solved_forearm_local)
    Unit.set_local_rotation(unit, hand_node, solved_hand_local)
    World.update_unit_and_children(world, unit)
    return true, "written",
        presentation.vector_distance(
            Unit.world_position(unit, hand_node), solved_wrist),
        presentation.quaternion_angle_error(
            Unit.world_rotation(unit, hand_node), solved_hand_world)
end

-- Render-only body heading: the HMD drives the torso, while controller pitch,
-- roll and yaw remain confined to the independently solved arms/gameplay aim.
-- A 30-degree head/body dead zone with exponential catch-up is the conventional
-- VR full-body compromise: small glances do not shuffle the avatar, but a
-- sustained head turn brings the shoulders around smoothly.
function presentation.apply_body_heading(world, unit)
    local head_yaw = controller_observation.body_head_yaw
    if not head_yaw then
        return
    end
    local now = Managers and Managers.time and Managers.time:time("main") or 0
    local visual_yaw = controller_observation.body_visual_yaw
    if not visual_yaw then
        visual_yaw = Quaternion.yaw(Unit.local_rotation(unit, 1))
    end
    local prior_head_yaw =
        controller_observation.body_heading_last_head_yaw or head_yaw
    local head_motion = math.abs(math.atan2(
        math.sin(head_yaw - prior_head_yaw),
        math.cos(head_yaw - prior_head_yaw)))
    if head_motion > math.pi / 360 then
        controller_observation.body_heading_last_motion_t = now
    end
    controller_observation.body_heading_last_head_yaw = head_yaw
    local delta = math.atan2(
        math.sin(head_yaw - visual_yaw),
        math.cos(head_yaw - visual_yaw))
    local dead_zone = math.pi / 6
    local desired_yaw = nil
    local convergence = nil
    if controller_observation.gameplay_stick_active then
        -- During artificial locomotion the body should face the travel/head
        -- frame promptly; retaining a large stationary dead zone here makes
        -- strafing/jog animation visibly shear under the tracked upper body.
        desired_yaw = head_yaw
        convergence = 6
    elseif math.abs(delta) > dead_zone then
        desired_yaw = head_yaw - math.sign(delta) * dead_zone
        convergence = 8
    elseif now - controller_observation.body_heading_last_motion_t > 0.75 then
        -- Hybrid avatar-heading behavior: preserve the comfort dead zone for a
        -- glance, then let a stationary body settle unobtrusively underneath
        -- the user's sustained physical heading.
        desired_yaw = head_yaw
        convergence = 0.5
    end
    if desired_yaw then
        local desired_delta = math.atan2(
            math.sin(desired_yaw - visual_yaw),
            math.cos(desired_yaw - visual_yaw))
        local last_t = controller_observation.body_visual_yaw_last_t or now
        local dt = math.clamp(now - last_t, 0, 0.1)
        local alpha = 1 - math.exp(-convergence * dt)
        visual_yaw = visual_yaw + desired_delta * alpha
    end
    controller_observation.body_visual_yaw = visual_yaw
    controller_observation.body_visual_yaw_last_t = now
    Unit.set_local_rotation(
        unit, 1, Quaternion.axis_angle(Vector3.up(), visual_yaw))
    World.update_unit_and_children(world, unit)
end

function presentation.align_body_torso_neutral(world, unit)
    if not Unit.has_node(unit, "j_spine2") or
            not Unit.has_node(unit, "j_neck") then
        return false, "torso_nodes_missing"
    end
    local spine = Unit.node(unit, "j_spine2")
    local neck = Unit.node(unit, "j_neck")
    local current = Unit.scene_graph_parent(unit, neck)
    local ancestry_valid = false
    local depth = 0
    while current ~= nil and depth < 64 do
        if current == spine then
            ancestry_valid = true
            break
        end
        current = Unit.scene_graph_parent(unit, current)
        depth = depth + 1
    end
    if not ancestry_valid then
        return false, "spine2_not_neck_ancestor"
    end
    local spine_position = Unit.world_position(unit, spine)
    local torso_axis = Unit.world_position(unit, neck) - spine_position
    if Vector3.length(torso_axis) < 0.001 then
        return false, "torso_axis_degenerate"
    end
    torso_axis = Vector3.normalize(torso_axis)
    if controller_observation.body_ik_torso_axis_unit ~= unit or
            not controller_observation.body_ik_torso_axis_local then
        local root_inverse = presentation.inverse_quaternion(
            Unit.world_rotation(unit, 1))
        controller_observation.body_ik_torso_axis_unit = unit
        controller_observation.body_ik_torso_axis_local = Vector3Box(
            presentation.rotate_vector(root_inverse, torso_axis))
        mod:info(
            "DARKTIDEVR_IK torso_neutral captured axis_local=%.4f,%.4f,%.4f",
            Vector3.x(controller_observation.body_ik_torso_axis_local:unbox()),
            Vector3.y(controller_observation.body_ik_torso_axis_local:unbox()),
            Vector3.z(controller_observation.body_ik_torso_axis_local:unbox()))
        return true, 0
    end
    local target_axis = presentation.rotate_vector(
        Unit.world_rotation(unit, 1),
        controller_observation.body_ik_torso_axis_local:unbox())
    local correction = presentation.align_vectors_rotation(
        torso_axis, target_axis)
    if not correction then
        return false, "torso_alignment_invalid"
    end
    local spine_parent = Unit.scene_graph_parent(unit, spine)
    if spine_parent == nil then
        return false, "torso_parent_missing"
    end
    local corrected_world = Quaternion.multiply(
        correction, Unit.world_rotation(unit, spine))
    local corrected_local = Quaternion.multiply(
        presentation.inverse_quaternion(
            Unit.world_rotation(unit, spine_parent)),
        corrected_world)
    Unit.set_local_rotation(unit, spine, corrected_local)
    World.update_unit_and_children(world, unit)
    local corrected_axis = Vector3.normalize(
        Unit.world_position(unit, neck) - Unit.world_position(unit, spine))
    local dot = math.max(-1, math.min(
        1, Vector3.dot(corrected_axis, target_axis)))
    return true, math.acos(dot)
end

function presentation.align_body_shoulders(world, unit)
    local spine_name = "j_spine2"
    local left_name = "j_leftarm"
    local right_name = "j_rightarm"
    if not Unit.has_node(unit, spine_name) or
            not Unit.has_node(unit, left_name) or
            not Unit.has_node(unit, right_name) or
            not controller_observation.body_visual_yaw then
        return false, "nodes_or_heading_unavailable"
    end
    local spine = Unit.node(unit, spine_name)
    local left = Unit.node(unit, left_name)
    local right = Unit.node(unit, right_name)
    local function is_ancestor(ancestor, child)
        local current = Unit.scene_graph_parent(unit, child)
        local depth = 0
        while current ~= nil and depth < 64 do
            if current == ancestor then
                return true
            end
            current = Unit.scene_graph_parent(unit, current)
            depth = depth + 1
        end
        return false
    end
    if not is_ancestor(spine, left) or not is_ancestor(spine, right) then
        return false, "spine2_not_common_arm_ancestor"
    end
    local shoulder_right = Vector3.normalize(
        Unit.world_position(unit, right) - Unit.world_position(unit, left))
    local torso_forward = Vector3.normalize(
        Vector3.cross(Vector3.up(), shoulder_right))
    local desired = Quaternion.axis_angle(
        Vector3.up(), controller_observation.body_visual_yaw)
    local error = math.atan2(
        Vector3.dot(torso_forward, Quaternion.right(desired)),
        Vector3.dot(torso_forward, Quaternion.forward(desired)))
    local spine_parent = Unit.scene_graph_parent(unit, spine)
    if spine_parent == nil then
        return false, "spine2_parent_missing"
    end
    local corrected_world = Quaternion.multiply(
        Quaternion.axis_angle(Vector3.up(), error),
        Unit.world_rotation(unit, spine))
    local corrected_local = Quaternion.multiply(
        presentation.inverse_quaternion(
            Unit.world_rotation(unit, spine_parent)),
        corrected_world)
    Unit.set_local_rotation(unit, spine, corrected_local)
    World.update_unit_and_children(world, unit)
    local corrected_shoulder_right = Vector3.normalize(
        Unit.world_position(unit, right) - Unit.world_position(unit, left))
    local corrected_torso_forward = Vector3.normalize(
        Vector3.cross(Vector3.up(), corrected_shoulder_right))
    local residual = math.atan2(
        Vector3.dot(corrected_torso_forward, Quaternion.right(desired)),
        Vector3.dot(corrected_torso_forward, Quaternion.forward(desired)))
    return true, residual
end

function presentation.log_body_hand_basis(
        unit, side, target_position, target_rotation)
    local hand_name = side == "left" and "j_lefthand" or "j_righthand"
    local hand_node = Unit.node(unit, hand_name)
    local hand_position = Unit.world_position(unit, hand_node)
    local hand_rotation = Unit.world_rotation(unit, hand_node)
    local target_right = Quaternion.right(target_rotation)
    local target_forward = Quaternion.forward(target_rotation)
    local target_up = Quaternion.up(target_rotation)
    local hand_right = Quaternion.right(hand_rotation)
    local hand_forward = Quaternion.forward(hand_rotation)
    local hand_up = Quaternion.up(hand_rotation)
    mod:info(
        "DARKTIDEVR_IK basis side=%s target_pos=%.4f,%.4f,%.4f hand_pos=%.4f,%.4f,%.4f target_rfu=%.3f,%.3f,%.3f/%.3f,%.3f,%.3f/%.3f,%.3f,%.3f hand_rfu=%.3f,%.3f,%.3f/%.3f,%.3f,%.3f/%.3f,%.3f,%.3f",
        side,
        Vector3.x(target_position), Vector3.y(target_position),
        Vector3.z(target_position), Vector3.x(hand_position),
        Vector3.y(hand_position), Vector3.z(hand_position),
        Vector3.x(target_right), Vector3.y(target_right),
        Vector3.z(target_right), Vector3.x(target_forward),
        Vector3.y(target_forward), Vector3.z(target_forward),
        Vector3.x(target_up), Vector3.y(target_up), Vector3.z(target_up),
        Vector3.x(hand_right), Vector3.y(hand_right), Vector3.z(hand_right),
        Vector3.x(hand_forward), Vector3.y(hand_forward),
        Vector3.z(hand_forward), Vector3.x(hand_up),
        Vector3.y(hand_up), Vector3.z(hand_up))
    local landmark_names = side == "left" and {
        "j_lefthandindex1", "j_lefthandmiddle1", "j_lefthandring1",
        "j_lefthandpinky1", "j_leftthumb1", "j_lefthandthumb1",
        "j_leftthumb01", "j_lefthandthumb01", "j_leftweaponattach"
    } or {
        "j_righthandindex1", "j_righthandmiddle1", "j_righthandring1",
        "j_righthandpinky1", "j_rightthumb1", "j_righthandthumb1",
        "j_rightthumb01", "j_righthandthumb01", "j_rightweaponattach"
    }
    for i = 1, #landmark_names do
        local name = landmark_names[i]
        if Unit.has_node(unit, name) then
            local position = Unit.world_position(unit, Unit.node(unit, name))
            mod:info(
                "DARKTIDEVR_IK landmark side=%s name=%s position=%.4f,%.4f,%.4f",
                side, name, Vector3.x(position), Vector3.y(position),
                Vector3.z(position))
        end
    end
    local calibration =
        controller_observation.body_ik_hand_anatomy[side]
    if calibration then
        local longitudinal = presentation.rotate_vector(
            hand_rotation, calibration.longitudinal:unbox())
        local across = presentation.rotate_vector(
            hand_rotation, calibration.across:unbox())
        local palm = presentation.rotate_vector(
            hand_rotation, calibration.palm:unbox())
        local aim_offset = side == "left" and 0 or 18
        local values = controller_observation.values
        local anchor_rotation = Quaternion.from_elements(
            controller_observation.body_anchor_qx,
            controller_observation.body_anchor_qy,
            controller_observation.body_anchor_qz,
            controller_observation.body_anchor_qw)
        local aim_rotation = Quaternion.multiply(
            anchor_rotation,
            Quaternion.from_elements(
                values[aim_offset + 3], values[aim_offset + 4],
                values[aim_offset + 5], values[aim_offset + 6]))
        local aim_forward = Quaternion.forward(aim_rotation)
        mod:info(
            "DARKTIDEVR_IK anatomy side=%s palm_to_grip_right=%.4f across_to_grip_forward=%.4f longitudinal_to_grip_up=%.4f grip_up_to_aim_forward=%.4f grip_forward_to_aim_forward=%.4f",
            side,
            Vector3.dot(palm, target_right),
            Vector3.dot(across, target_forward),
            Vector3.dot(longitudinal, target_up),
            Vector3.dot(target_up, aim_forward),
            Vector3.dot(target_forward, aim_forward))
        if QuickDrawer then
            local length = 0.18
            QuickDrawer:line(hand_position,
                hand_position + palm * length, Color.red())
            QuickDrawer:line(hand_position,
                hand_position + across * length, Color.green())
            QuickDrawer:line(hand_position,
                hand_position + longitudinal * length, Color.blue())
        end
    end
end

function presentation.log_body_spine_chain(unit, phase)
    local node_names = {
        "j_hips", "j_spine", "j_spine1", "j_spine2", "j_spine3",
        "j_neck", "j_head", "j_leftarm", "j_rightarm"
    }
    local values = {}
    local root_yaw = Quaternion.yaw(Unit.world_rotation(unit, 1))
    for i = 1, #node_names do
        local name = node_names[i]
        if Unit.has_node(unit, name) then
            local node = Unit.node(unit, name)
            local local_yaw = Quaternion.yaw(Unit.local_rotation(unit, node))
            local world_yaw = Quaternion.yaw(Unit.world_rotation(unit, node))
            values[#values + 1] = string.format(
                "%s=%.2f/%.2f/%.2f",
                name,
                local_yaw * 180 / math.pi,
                world_yaw * 180 / math.pi,
                math.atan2(math.sin(world_yaw - root_yaw),
                    math.cos(world_yaw - root_yaw)) * 180 / math.pi)
        end
    end
    mod:info(
        "DARKTIDEVR_IK spine phase=%s root_deg=%.2f desired_deg=%.2f nodes_local_world_relative=%s",
        phase,
        root_yaw * 180 / math.pi,
        (controller_observation.body_head_yaw or 0) * 180 / math.pi,
        table.concat(values, ","))
end

function presentation.log_body_alignment(unit)
    if not Unit.has_node(unit, "j_leftarm") or
            not Unit.has_node(unit, "j_rightarm") or
            not Unit.has_node(unit, "j_head") or
            not controller_observation.body_head_yaw then
        return
    end
    local left = Unit.world_position(unit, Unit.node(unit, "j_leftarm"))
    local right = Unit.world_position(unit, Unit.node(unit, "j_rightarm"))
    local head = Unit.world_position(unit, Unit.node(unit, "j_head"))
    local shoulder_right = Vector3.normalize(right - left)
    local torso_forward = Vector3.normalize(
        Vector3.cross(Vector3.up(), shoulder_right))
    local desired = Quaternion.axis_angle(
        Vector3.up(), controller_observation.body_head_yaw)
    local desired_forward = Quaternion.forward(desired)
    local desired_right = Quaternion.right(desired)
    local torso_offset = math.atan2(
        Vector3.dot(torso_forward, desired_right),
        Vector3.dot(torso_forward, desired_forward))
    local model_eye, eye_source =
        presentation.body_model_eye_anchor(unit)
    mod:info(
        "DARKTIDEVR_IK alignment torso_offset_deg=%.2f torso_residual_deg=%.3f shoulder_residual_deg=%.3f head=%.4f,%.4f,%.4f model_eye_source=%s model_eye=%.4f,%.4f,%.4f head_to_eye=%.4f,%.4f,%.4f root_yaw=%.4f desired_yaw=%.4f visual_yaw=%.4f",
        torso_offset * 180 / math.pi,
        (controller_observation.body_ik_torso_residual or 0) *
            180 / math.pi,
        (controller_observation.body_ik_shoulder_residual or 0) *
            180 / math.pi,
        Vector3.x(head), Vector3.y(head), Vector3.z(head),
        tostring(eye_source),
        model_eye and Vector3.x(model_eye) or 0,
        model_eye and Vector3.y(model_eye) or 0,
        model_eye and Vector3.z(model_eye) or 0,
        model_eye and Vector3.x(model_eye - head) or 0,
        model_eye and Vector3.y(model_eye - head) or 0,
        model_eye and Vector3.z(model_eye - head) or 0,
        Quaternion.yaw(Unit.local_rotation(unit, 1)),
        controller_observation.body_head_yaw,
        controller_observation.body_visual_yaw or 0)
end

function presentation.apply_body_ik(unit, sequence, world)
    controller_observation.body_ik_presentation_update_frame =
        controller_observation.body_ik_presentation_update_frame + 1
    local update_frame =
        controller_observation.body_ik_presentation_update_frame
    presentation.update_body_ik_presentation_gate(update_frame)
    if not controller_observation.body_ik_presentation_enabled then
        return
    end
    local mode = active_game_mode_name()
    if mode ~= "shooting_range" and mode ~= "training_grounds" then
        if controller_observation.body_ik_presentation_block_reason ~=
                "not_first_person_training" then
            controller_observation.body_ik_presentation_block_reason =
                "not_first_person_training"
            mod:info(
                "DARKTIDEVR_IK presentation_blocked reason=not_first_person_training mode=%s",
                tostring(mode))
        end
        return
    end
    if not world or not unit or not Unit.alive(unit) then
        controller_observation.body_ik_presentation_block_reason =
            not world and "world_unavailable" or "unit_unavailable"
        return
    end
    local emit_spine_trace = update_frame >=
        controller_observation.body_ik_spine_trace_frame + 60
    if emit_spine_trace then
        controller_observation.body_ik_spine_trace_frame = update_frame
        presentation.log_body_spine_chain(unit, "before")
    end
    presentation.apply_body_heading(world, unit)
    local torso_aligned, torso_result =
        presentation.align_body_torso_neutral(world, unit)
    controller_observation.body_ik_torso_residual =
        torso_aligned and torso_result or nil
    local torso_reason = not torso_aligned and tostring(torso_result) or nil
    if torso_reason ~= controller_observation.body_ik_torso_block_reason then
        controller_observation.body_ik_torso_block_reason = torso_reason
        if torso_reason then
            mod:warning(
                "DARKTIDEVR_IK torso_alignment_blocked reason=%s",
                torso_reason)
        else
            mod:info(
                "DARKTIDEVR_IK torso_alignment=active residual_deg=%.3f",
                torso_result * 180 / math.pi)
        end
    end
    local shoulder_aligned, shoulder_result =
        presentation.align_body_shoulders(world, unit)
    controller_observation.body_ik_shoulder_residual =
        shoulder_aligned and shoulder_result or nil
    local shoulder_reason = not shoulder_aligned and
        tostring(shoulder_result) or nil
    if shoulder_reason ~=
            controller_observation.body_ik_shoulder_block_reason then
        controller_observation.body_ik_shoulder_block_reason = shoulder_reason
        if shoulder_reason then
            mod:warning(
                "DARKTIDEVR_IK shoulder_alignment_blocked reason=%s",
                shoulder_reason)
        else
            mod:info(
                "DARKTIDEVR_IK shoulder_alignment=active residual_deg=%.3f",
                shoulder_result * 180 / math.pi)
        end
    end
    local left_target, left_rotation =
        presentation.body_ik_controller_grip_target(
        unit, "left")
    local right_target, right_rotation =
        presentation.body_ik_controller_grip_target(
        unit, "right")
    local wrote = false
    local max_error = 0
    local max_angle_error = 0
    local block_reason = nil
    if left_target then
        local ok, reason, error_metres, angle_error =
            presentation.apply_body_arm_ik(
                world, unit, "left", left_target, left_rotation)
        wrote = wrote or ok
        block_reason = not ok and "left_" .. tostring(reason) or block_reason
        max_error = math.max(max_error, error_metres or 0)
        max_angle_error = math.max(max_angle_error, angle_error or 0)
    end
    if right_target then
        local ok, reason, error_metres, angle_error =
            presentation.apply_body_arm_ik(
                world, unit, "right", right_target, right_rotation)
        wrote = wrote or ok
        block_reason = not ok and "right_" .. tostring(reason) or block_reason
        max_error = math.max(max_error, error_metres or 0)
        max_angle_error = math.max(max_angle_error, angle_error or 0)
    end
    if emit_spine_trace then
        presentation.log_body_spine_chain(unit, "after")
    end
    if wrote then
        controller_observation.body_ik_presentation_writes =
            controller_observation.body_ik_presentation_writes + 1
        controller_observation.body_ik_presentation_max_error = math.max(
            controller_observation.body_ik_presentation_max_error, max_error)
        controller_observation.body_ik_presentation_max_angle_error = math.max(
            controller_observation.body_ik_presentation_max_angle_error,
            max_angle_error)
        block_reason = nil
    end
    if block_reason ~= controller_observation.body_ik_presentation_block_reason then
        controller_observation.body_ik_presentation_block_reason = block_reason
        if block_reason then
            mod:warning("DARKTIDEVR_IK presentation_blocked reason=%s",
                block_reason)
        end
    end
    if wrote and update_frame >=
            controller_observation.body_ik_presentation_last_log_frame + 60 then
        controller_observation.body_ik_presentation_last_log_frame =
            update_frame
        mod:info(
            "DARKTIDEVR_IK presentation_writes=%d post_error_m=%.6f max_post_error_m=%.6f angle_error_rad=%.6f max_angle_error_rad=%.6f sequence=%d",
            controller_observation.body_ik_presentation_writes,
            max_error,
            controller_observation.body_ik_presentation_max_error,
            max_angle_error,
            controller_observation.body_ik_presentation_max_angle_error,
            sequence or controller_observation.last_sequence)
        if left_target and left_rotation then
            presentation.log_body_hand_basis(
                unit, "left", left_target, left_rotation)
        end
        if right_target and right_rotation then
            presentation.log_body_hand_basis(
                unit, "right", right_target, right_rotation)
        end
        presentation.log_body_alignment(unit)
    end
end

function presentation.trace_body_ik(self, fixed_frame)
    if not fixed_frame or not Mods or not Mods.lua or not Mods.lua.io or
            not ui_native_capture then
        return
    end
    presentation.update_body_ik_trace_gate(fixed_frame)
    if not controller_observation.body_ik_trace_enabled or
            fixed_frame < controller_observation.body_ik_trace_last_log_frame + 15 then
        return
    end
    local local_player = Managers and Managers.player and
        Managers.player:local_player(1)
    if not local_player or self._unit ~= local_player.player_unit or
            not Unit.alive(self._unit) then
        return
    end
    local left_target = presentation.body_ik_controller_grip_target(
        self._unit, "left")
    local right_target = presentation.body_ik_controller_grip_target(
        self._unit, "right")
    if not left_target and not right_target then
        return
    end
    controller_observation.body_ik_trace_last_log_frame = fixed_frame
    if left_target then
        presentation.trace_body_arm(self._unit, "left", left_target)
    end
    if right_target then
        presentation.trace_body_arm(self._unit, "right", right_target)
    end
end

function presentation.trace_weapon_pose(self, fixed_frame)
    if not fixed_frame or not Mods or not Mods.lua or not Mods.lua.io then
        return
    end
    if fixed_frame >=
            controller_observation.weapon_pose_trace_last_check_frame + 60 then
        controller_observation.weapon_pose_trace_last_check_frame = fixed_frame
        local flag_path =
            "./../mods/darktidevr_stereo_probe/darktidevr_weapon_pose_trace.flag"
        local flag = Mods.lua.io.open(flag_path, "r")
        local enabled = false
        if flag then
            enabled = flag:read("*all"):match("^%s*enabled%s*$") ~= nil
            flag:close()
        end
        if enabled ~= controller_observation.weapon_pose_trace_enabled then
            controller_observation.weapon_pose_trace_enabled = enabled
            mod:info(
                "DARKTIDEVR_WEAPON pose_trace=%s source=test_flag",
                enabled and "enabled" or "disabled")
        end
    end
    if not controller_observation.weapon_pose_trace_enabled or
            fixed_frame <
                controller_observation.weapon_pose_trace_last_log_frame + 15 then
        return
    end
    local local_player = Managers and Managers.player and
        Managers.player:local_player(1)
    if not local_player or self._unit ~= local_player.player_unit or
            not controller_observation.right_grip_usable or
            not controller_observation.body_anchor_qw then
        return
    end
    local first_person_unit = self._first_person_unit
    if not first_person_unit or not Unit.alive(first_person_unit) or
            not Unit.has_node(first_person_unit, "j_righthand") or
            not Unit.has_node(first_person_unit, "j_rightweaponattach") then
        return
    end
    local slot_name = self._inventory_component and
        self._inventory_component.wielded_slot
    local weapon = slot_name and self._weapons and self._weapons[slot_name]
    local weapon_unit = weapon and weapon.weapon_unit
    if not weapon_unit or not Unit.alive(weapon_unit) then
        return
    end
    controller_observation.weapon_pose_trace_last_log_frame = fixed_frame
    local target_position, target_rotation =
        presentation.controller_grip_target()
    local hand_node = Unit.node(first_person_unit, "j_righthand")
    local attach_node = Unit.node(first_person_unit, "j_rightweaponattach")
    local hand_position = Unit.world_position(first_person_unit, hand_node)
    local attach_position = Unit.world_position(first_person_unit, attach_node)
    local weapon_position = Unit.world_position(weapon_unit, 1)
    local target_yaw, target_pitch, target_roll =
        Quaternion.to_yaw_pitch_roll(target_rotation)
    mod:info(
        "DARKTIDEVR_WEAPON pose frame=%s sequence=%d target=%.4f,%.4f,%.4f target_ypr=%.4f,%.4f,%.4f hand=%.4f,%.4f,%.4f attach=%.4f,%.4f,%.4f weapon=%.4f,%.4f,%.4f target_hand_m=%.4f target_weapon_m=%.4f attach_weapon_m=%.6f",
        tostring(fixed_frame), controller_observation.last_sequence,
        Vector3.x(target_position), Vector3.y(target_position),
        Vector3.z(target_position), target_yaw, target_pitch, target_roll,
        Vector3.x(hand_position), Vector3.y(hand_position),
        Vector3.z(hand_position), Vector3.x(attach_position),
        Vector3.y(attach_position), Vector3.z(attach_position),
        Vector3.x(weapon_position), Vector3.y(weapon_position),
        Vector3.z(weapon_position),
        presentation.vector_distance(target_position, hand_position),
        presentation.vector_distance(target_position, weapon_position),
        presentation.vector_distance(attach_position, weapon_position))
end

function presentation.update_weapon_presentation_gate(fixed_frame)
    if fixed_frame <
            controller_observation.weapon_presentation_last_check_frame + 60 then
        return
    end
    controller_observation.weapon_presentation_last_check_frame = fixed_frame
    local flag_path =
        "./../mods/darktidevr_stereo_probe/darktidevr_weapon_presentation.flag"
    local flag = Mods.lua.io.open(flag_path, "r")
    local enabled = false
    if flag then
        enabled = flag:read("*all"):match("^%s*enabled%s*$") ~= nil
        flag:close()
    end
    if enabled ~= controller_observation.weapon_presentation_enabled then
        controller_observation.weapon_presentation_enabled = enabled
        controller_observation.weapon_presentation_block_reason = nil
        mod:info(
            "DARKTIDEVR_WEAPON presentation=%s source=test_flag writes=%d",
            enabled and "enabled" or "disabled",
            controller_observation.weapon_presentation_writes)
    end
end

function presentation.author_weapon_pose(self, fixed_frame, world)
    if not fixed_frame or not Mods or not Mods.lua or not Mods.lua.io then
        return
    end
    presentation.update_weapon_presentation_gate(fixed_frame)
    if not controller_observation.weapon_presentation_enabled then
        return
    end
    local local_player = Managers and Managers.player and
        Managers.player:local_player(1)
    local mode = active_game_mode_name()
    if not local_player or self._unit ~= local_player.player_unit or
            (mode ~= "shooting_range" and mode ~= "training_grounds") then
        return
    end
    local first_person_unit = self._first_person_unit
    if not first_person_unit or not Unit.alive(first_person_unit) or
            not Unit.has_node(first_person_unit, "j_righthand") then
        return
    end
    local target_position, target_rotation =
        presentation.controller_grip_target()
    if not target_position or not target_rotation then
        return
    end
    local hand_node = Unit.node(first_person_unit, "j_righthand")
    local root_node, root_depth =
        presentation.scene_graph_root(first_person_unit, hand_node)
    local root_position = Unit.world_position(first_person_unit, root_node)
    local root_local_position = Unit.local_position(first_person_unit, root_node)
    local hand_position = Unit.world_position(first_person_unit, hand_node)
    local hand_rotation = Unit.world_rotation(first_person_unit, hand_node)
    local requested_displacement =
        presentation.vector_distance(target_position, hand_position)
    local root_space_error =
        presentation.vector_distance(root_position, root_local_position)
    local block_reason = nil
    if root_space_error > 0.001 then
        block_reason = "parented_root"
    end
    if block_reason then
        if block_reason ~=
                controller_observation.weapon_presentation_block_reason then
            controller_observation.weapon_presentation_block_reason = block_reason
            mod:warning(
                "DARKTIDEVR_WEAPON presentation_blocked reason=%s displacement_m=%.4f root_space_error_m=%.6f sequence=%d",
                block_reason, requested_displacement, root_space_error,
                controller_observation.last_sequence)
        end
        return
    end
    controller_observation.weapon_presentation_block_reason = nil
    -- Synthetic and real controller tracking can place the grip outside the
    -- avatar's reachable envelope. Dropping the write made the weapon snap to
    -- its stock animation for those frames. Clamp only the rendered 1P rig to
    -- a continuous boundary; gameplay aim/origin/reach remain engine-owned.
    local visual_reach_limit = 0.75
    local clamped = requested_displacement > visual_reach_limit
    if clamped then
        target_position = hand_position +
            (target_position - hand_position) *
                (visual_reach_limit / requested_displacement)
        controller_observation.weapon_presentation_clamps =
            controller_observation.weapon_presentation_clamps + 1
    end
    local displacement = math.min(requested_displacement, visual_reach_limit)
    local delta_rotation = Quaternion.multiply(
        target_rotation,
        presentation.inverse_quaternion(hand_rotation))
    local hand_from_root = hand_position - root_position
    local new_root_position = target_position -
        presentation.rotate_vector(delta_rotation, hand_from_root)
    local root_rotation = Unit.world_rotation(first_person_unit, root_node)
    local new_root_rotation = Quaternion.multiply(delta_rotation, root_rotation)
    Unit.set_local_position(first_person_unit, root_node, new_root_position)
    Unit.set_local_rotation(first_person_unit, root_node, new_root_rotation)
    if world then
        World.update_unit_and_children(world, first_person_unit)
    end
    local post_hand_position = Unit.world_position(first_person_unit, hand_node)
    local post_hand_rotation = Unit.world_rotation(first_person_unit, hand_node)
    local post_error =
        presentation.vector_distance(target_position, post_hand_position)
    controller_observation.weapon_presentation_max_post_error = math.max(
        controller_observation.weapon_presentation_max_post_error,
        post_error)
    controller_observation.weapon_presentation_writes =
        controller_observation.weapon_presentation_writes + 1
    if fixed_frame >=
            controller_observation.weapon_presentation_last_log_frame + 60 then
        controller_observation.weapon_presentation_last_log_frame = fixed_frame
        local target_yaw, target_pitch, target_roll =
            Quaternion.to_yaw_pitch_roll(target_rotation)
        local post_yaw, post_pitch, post_roll =
            Quaternion.to_yaw_pitch_roll(post_hand_rotation)
        local slot_name = self._inventory_component and
            self._inventory_component.wielded_slot
        local weapon = slot_name and self._weapons and self._weapons[slot_name]
        local weapon_unit = weapon and weapon.weapon_unit
        local attach_weapon_error = -1
        if weapon_unit and Unit.alive(weapon_unit) and
                Unit.has_node(first_person_unit, "j_rightweaponattach") then
            local attach_position = Unit.world_position(
                first_person_unit,
                Unit.node(first_person_unit, "j_rightweaponattach"))
            attach_weapon_error = presentation.vector_distance(
                attach_position, Unit.world_position(weapon_unit, 1))
        end
        mod:info(
            "DARKTIDEVR_WEAPON presentation_write frame=%s sequence=%d root_node=%s root_depth=%d requested_m=%.4f displacement_m=%.4f clamped=%s clamps=%d post_error_m=%.6f max_post_error_m=%.6f attach_weapon_m=%.6f target_ypr=%.4f,%.4f,%.4f post_ypr=%.4f,%.4f,%.4f root_space_error_m=%.6f writes=%d",
            tostring(fixed_frame), controller_observation.last_sequence,
            tostring(root_node), root_depth, requested_displacement,
            displacement, tostring(clamped),
            controller_observation.weapon_presentation_clamps, post_error,
            controller_observation.weapon_presentation_max_post_error,
            attach_weapon_error,
            target_yaw, target_pitch, target_roll,
            post_yaw, post_pitch, post_roll,
            root_space_error,
            controller_observation.weapon_presentation_writes)
    end
end

mod:hook_safe(
    "PlayerUnitWeaponExtension",
    "fixed_update",
    function(self, _, _, _, fixed_frame)
        presentation.scan_weapon_inventory(self, fixed_frame)
        presentation.trace_weapon_pose(self, fixed_frame)
        if not controller_observation.primary_action_cache_observed then
            return
        end
        local cache_frame = controller_observation.primary_action_cache_frame
        if not cache_frame or fixed_frame < cache_frame or
                fixed_frame > cache_frame + 30 then
            return
        end
        local local_player = Managers and Managers.player and
            Managers.player:local_player(1)
        if not local_player or self._unit ~= local_player.player_unit then
            return
        end
        local action_component = self._weapon_action_component
        local action_name = action_component and
            action_component.current_action_name
        if not controller_observation.primary_action_weapon_context_logged then
            local slot = self._inventory_component and
                self._inventory_component.wielded_slot
            local weapon = slot and self._weapons and self._weapons[slot]
            local template = weapon and weapon.weapon_template
            controller_observation.primary_action_weapon_context_logged = true
            mod:info(
                "DARKTIDEVR_INPUT primary_action context slot=%s template=%s action=%s frame=%s sequence=%d",
                tostring(slot),
                tostring(template and template.name),
                tostring(action_name),
                tostring(fixed_frame),
                controller_observation.primary_action_sequence
            )
        end
        if action_name and action_name ~= "none" and
                not controller_observation.primary_action_weapon_observed then
            controller_observation.primary_action_weapon_observed = true
            mod:info(
                "DARKTIDEVR_INPUT primary_action weapon_action=%s frame=%s start_t=%.4f sequence=%d",
                tostring(action_name),
                tostring(fixed_frame),
                tonumber(action_component.start_t) or 0,
                controller_observation.primary_action_sequence
            )
        end
        if controller_observation.primary_action_shot_observed then
            return
        end
        local shoot_component = self._action_shoot_component
        local shots = shoot_component and shoot_component.num_shots_fired or 0
        if shots <= 0 or not shoot_component.shooting_rotation then
            return
        end
        local ok, yaw, pitch, roll = pcall(
            Quaternion.to_yaw_pitch_roll,
            shoot_component.shooting_rotation
        )
        if not ok then
            mod:warning(
                "DARKTIDEVR_INPUT primary_action shot_rotation_unavailable=%s",
                tostring(yaw)
            )
            return
        end
        local forward = Quaternion.forward(shoot_component.shooting_rotation)
        local position = shoot_component.shooting_position
        controller_observation.primary_action_shot_observed = true
        mod:info(
            "DARKTIDEVR_INPUT primary_action shot frame=%s shots=%d shooting_ypr=%.4f,%.4f,%.4f shooting_forward=%.4f,%.4f,%.4f shooting_position=%.4f,%.4f,%.4f authored_forward=%.4f,%.4f,%.4f sequence=%d",
            tostring(fixed_frame),
            shots,
            yaw,
            pitch,
            roll,
            Vector3.x(forward),
            Vector3.y(forward),
            Vector3.z(forward),
            Vector3.x(position),
            Vector3.y(position),
            Vector3.z(position),
            controller_observation.downstream_forward_x or 0,
            controller_observation.downstream_forward_y or 0,
            controller_observation.downstream_forward_z or 0,
            controller_observation.primary_action_sequence
        )
    end)

mod:hook_safe(
    "PlayerUnitAnimationExtension",
    "fixed_update",
    function(self, _, _, _, fixed_frame)
        presentation.scan_body_rig(self, fixed_frame)
        presentation.trace_body_ik(self, fixed_frame)
    end)

function presentation.observe_primary_projectile(self, direction, source)
    if not controller_observation.primary_action_cache_observed or
            controller_observation.primary_action_projectile_observed or
            not direction then
        return
    end
    local local_player = Managers and Managers.player and
        Managers.player:local_player(1)
    if not local_player or self._owner_unit ~= local_player.player_unit then
        return
    end
    local ok, x, y, z = pcall(function()
        local length = Vector3.length(direction)
        if length <= 0 then
            return nil
        end
        local normalized = direction / length
        return Vector3.x(normalized), Vector3.y(normalized), Vector3.z(normalized)
    end)
    if not ok or x == nil then
        mod:warning(
            "DARKTIDEVR_INPUT primary_action projectile_direction_unavailable source=%s error=%s",
            tostring(source), tostring(x))
        return
    end
    controller_observation.primary_action_projectile_observed = true
    mod:info(
        "DARKTIDEVR_INPUT primary_action projectile source=%s direction=%.4f,%.4f,%.4f authored_forward=%.4f,%.4f,%.4f sequence=%d",
        tostring(source), x, y, z,
        controller_observation.downstream_forward_x or 0,
        controller_observation.downstream_forward_y or 0,
        controller_observation.downstream_forward_z or 0,
        controller_observation.primary_action_sequence
    )
end

mod:hook_safe(
    "ProjectileUnitLocomotionExtension",
    "switch_to_manual_physics",
    function(self, _, _, direction)
        presentation.observe_primary_projectile(
            self, direction, "manual_physics")
    end)

mod:hook_safe(
    "ProjectileUnitLocomotionExtension",
    "switch_to_true_flight",
    function(self, _, _, direction)
        presentation.observe_primary_projectile(
            self, direction, "true_flight")
    end)

mod:hook_safe(
    "ProjectileUnitLocomotionExtension",
    "switch_to_engine_physics",
    function(self, _, _, velocity)
        presentation.observe_primary_projectile(
            self, velocity, "engine_physics")
    end)

presentation.player_unit_visual_loadout_extension = require(
    "scripts/extension_systems/visual_loadout/player_unit_visual_loadout_extension")

-- Complementary presentation diagnostic. The hub normally requests a 3P
-- camera and 3P equipment. Returning both 1P values here proves whether that
-- presentation can be selected independently of the hub gameplay mode. XR
-- still owns the final view transform, so this is intentionally scoped to the
-- local hub and guarded by a separate normal-off flag.
mod:hook(
    require("scripts/extension_systems/first_person/player_unit_first_person_extension"),
    "_update_first_person_mode",
    function(func, self, t)
        local show_1p_equipment, wants_1p_camera = func(self, t)
        if controller_observation.force_hub_first_person_enabled and
                active_game_mode_name() == "hub" then
            return true, true
        end
        return show_1p_equipment, wants_1p_camera
    end)

-- Preserve FadeSystem ownership/registration but move its observation point
-- far outside the playable world during the normal-off range body diagnostic.
-- This disables camera-proximity fading for the test without risking a stale
-- native registration or a double-unregister during mission teardown.
mod:hook(
    require("scripts/extension_systems/fade/fade_system"),
    "update",
    function(func, self, context, dt, t, ...)
        if controller_observation.body_visibility_enabled then
            Fade.update(
                self._fade_system,
                Vector3(1000000, 1000000, 1000000))
            return
        end
        return func(self, context, dt, t, ...)
    end)

function presentation.safe_apply_body_visibility(self, frame, force)
    local ok, error_message = pcall(
        presentation.apply_body_visibility, self, frame, force)
    if not ok and controller_observation.body_visibility_enabled then
        controller_observation.body_visibility_enabled = false
        controller_observation.body_visibility_faulted = true
        mod:error(
            "DARKTIDEVR_BODY visibility_disabled reason=lua_error error=%s",
            tostring(error_message))
    end
end

-- Poll the normal-off range test gate after the stock loadout update. This
-- catches both a newly created player unit and late attachment streaming.
mod:hook_safe(
    presentation.player_unit_visual_loadout_extension,
    "update",
    function(self)
        controller_observation.body_visibility_update_frame =
            controller_observation.body_visibility_update_frame + 1
        local frame = controller_observation.body_visibility_update_frame
        local changed = presentation.update_body_visibility_gate(frame)
        presentation.safe_apply_body_visibility(self, frame, changed)
    end)

-- Any later game-driven visibility refresh (weapon swap, attachment spawn or
-- first-person transition) is followed immediately by the visual-only body
-- override. Gameplay remains in first person throughout.
mod:hook_safe(
    presentation.player_unit_visual_loadout_extension,
    "_update_item_visibility",
    function(self)
        if controller_observation.body_visibility_enabled then
            presentation.safe_apply_body_visibility(
                self,
                controller_observation.body_visibility_update_frame,
                true)
        end
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
        controller_observation.downstream_forward_x = Vector3.x(forward)
        controller_observation.downstream_forward_y = Vector3.y(forward)
        controller_observation.downstream_forward_z = Vector3.z(forward)
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

-- `update_unit_position` is the production post-animation seam. The game has
-- already restored the stock 1P root, updated animation variables and called
-- `World.update_unit_and_children` before this safe hook runs. Applying the
-- normal-off presentation delta here makes it visible to the render without
-- feeding back into fixed-frame gameplay state.
mod:hook_safe(
    require("scripts/extension_systems/aim/third_person_look_delta_animation_control"),
    "update",
    function(self)
        if not controller_observation.body_ik_presentation_enabled then
            return
        end
        self._look_delta_x = 0
        self._look_delta_y = 0
        if self._look_delta_x_variable then
            Unit.animation_set_variable(
                self._unit, self._look_delta_x_variable, 0)
        end
        if self._look_delta_y_variable then
            Unit.animation_set_variable(
                self._unit, self._look_delta_y_variable, 0)
        end
        if self._world_look_delta_y_variable then
            Unit.animation_set_variable(
                self._unit, self._world_look_delta_y_variable, 0)
        end
    end)

mod:hook_safe(
    require("scripts/extension_systems/aim/third_person_aim_animation_control"),
    "update",
    function(self)
        if not controller_observation.body_ik_presentation_enabled then
            return
        end
        local variable = self._animation_extension:anim_variable_id(
            self._look_direction_anim_var)
        Unit.animation_set_variable(self._unit, variable, 0)
    end)

mod:hook_safe(
    require("scripts/extension_systems/aim/player_unit_aim_extension"),
    "update",
    function(self, unit)
        if not controller_observation.body_ik_presentation_enabled or
                not controller_observation.body_head_yaw or
                not self._aim_constraint_variable or
                not unit or not Unit.alive(unit) then
            return
        end
        local height = self._first_person_extension:
            extrapolated_character_height()
        local root_position = Unit.local_position(unit, 1) +
            height * Vector3.up()
        local horizon_rotation = Quaternion.axis_angle(
            Vector3.up(), controller_observation.body_head_yaw)
        local neutral_target = root_position +
            Quaternion.forward(horizon_rotation) *
                self._aim_contraint_distance
        Unit.animation_set_constraint_target(
            unit, self._aim_constraint_variable, neutral_target)
    end)

mod:hook_safe(
    require("scripts/extension_systems/first_person/player_unit_first_person_extension"),
    "update_unit_position",
    function(self)
        local weapon_extension = self._weapon_extension
        if weapon_extension then
            presentation.author_weapon_pose(
                weapon_extension,
                controller_observation.last_sequence,
                self._world)
        end
        local local_player = Managers and Managers.player and
            Managers.player:local_player(1)
        local player_unit = local_player and local_player.player_unit
        local ok, error_message = pcall(
            presentation.apply_body_ik,
            player_unit,
            controller_observation.last_sequence,
            self._world)
        if not ok and controller_observation.body_ik_presentation_enabled then
            controller_observation.body_ik_presentation_enabled = false
            controller_observation.body_ik_presentation_faulted = true
            mod:error(
                "DARKTIDEVR_IK presentation_disabled reason=lua_error error=%s",
                tostring(error_message))
        end
    end)

-- ViewInteraction is the authoritative hub seam: it preserves the exact
-- interactee that opened a vendor/facility view. Capture only after the stock
-- start completed and only when that exact view became active; first-visit
-- cinematics therefore remain on the ordinary flat-loading fallback.
mod:hook_safe(
    require("scripts/extension_systems/interaction/interactions/view_interaction"),
    "_start",
    function(self, _, interactee_unit)
        local ui_interaction = self:_ui_interaction(interactee_unit)
        local manager = Managers and Managers.ui
        local active_ok, view_active = manager and
            pcall(manager.view_active, manager, ui_interaction)
        if not active_ok or not view_active then
            return
        end
        local ok, captured, reason = pcall(
            presentation.capture_vendor_anchor,
            ui_interaction,
            interactee_unit)
        if not ok or not captured then
            mod:warning(
                "DARKTIDEVR_PRESENTATION world_anchor unavailable view=%s reason=%s",
                tostring(ui_interaction),
                tostring(ok and reason or captured)
            )
            return
        end
        presentation.world_menu_views[ui_interaction] = true
        presentation.world_menu_anchor = nil
        presentation.world_menu_draw_logged = false
        presentation.fullscreen_empty_updates = 0
        presentation.publish_mode(
            3,
            tostring(ui_interaction) .. ":engine_world_menu")
    end)

mod:hook(
    require("scripts/managers/ui/ui_manager"),
    "open_view",
    function(func, self, view_name, ...)
        -- Interactive menus must never replace the gameplay world.  Vendor
        -- views commonly request disable_game_world even though their UI can
        -- be rendered into our world-owned panel.  Change that setting before
        -- the view handler performs its transition, not after the freeze has
        -- already occurred.
        local handler = self._view_handler
        local settings = nil
        if handler and handler.settings_by_view_name then
            local ok, value = pcall(
                handler.settings_by_view_name, handler, view_name)
            if ok then
                settings = value
            end
        end
        if settings and settings.disable_game_world == true and
                not presentation.flat_loading_views[view_name] and
                not presentation.non_gameplay_views[view_name] then
            settings.disable_game_world = false
            presentation.world_menu_views[view_name] = true
            mod:info(
                "DARKTIDEVR_WORLD_MENU preserve_world view=%s",
                tostring(view_name))
        end
        local result = func(self, view_name, ...)
        presentation.on_view_open(self, view_name)
        return result
    end)

mod:hook_safe(
    require("scripts/managers/ui/ui_manager"),
    "close_view",
    function(self, view_name)
    presentation.on_view_close(self, view_name)
end)

-- Interactive fullscreen UI is rendered into one named RGBA resource instead
-- of being recovered from the desktop window. Capturing the window also
-- captured its mono eye mirror; putting that image in both headset eyes made
-- the live stereo world appear to freeze/flicker between mono and stereo.
-- Reusing the view's own Gui keeps retained widgets, engine hotspot geometry,
-- and the exported texture in exactly the same coordinate space. Intercept at
-- UIRenderer rather than BaseView: SystemView and vendor views own specialized
-- draw methods and renderer fields, but all of them converge here.
mod:hook(UIRenderer, "begin_pass", function(func, self, ...)
    if not ui_menu_resource_redirect_requested then
        return func(self, ...)
    end
    if not presentation.world_menu_active() then
        return func(self, ...)
    end
    if self == presentation.menu_resource_renderer then
        return func(self, ...)
    end

    local renderer_name = string.lower(tostring(self.name or ""))
    if self.world == active_world or
            string.find(renderer_name, "hud", 1, true) or
            string.find(renderer_name, "constant", 1, true) or
            string.find(renderer_name, "world_marker", 1, true) then
        return func(self, ...)
    end

    local resource_renderer = presentation.ensure_menu_resource(self)
    if not resource_renderer then
        return func(self, ...)
    end

    local states = presentation.menu_resource_pass_states[self]
    if not states then
        states = {}
        presentation.menu_resource_pass_states[self] = states
    end
    states[#states + 1] = {
        base_render_pass = self.base_render_pass,
        render_pass_flag = self.render_pass_flag,
    }

    local frame_time = Managers.time and Managers.time:time("ui") or 0
    if presentation.menu_resource_clear_time ~= frame_time then
        presentation.menu_resource_clear_time = frame_time
        UIRenderer.clear_render_pass_queue(self)
        UIRenderer.add_render_pass(
            self,
            0,
            resource_renderer.base_render_pass,
            true,
            resource_renderer.render_target
        )
        if presentation.world_menu_target_desktop_probe then
            UIRenderer.add_render_pass(self, 1, "to_screen", false)
        end
    end
    self.base_render_pass = resource_renderer.base_render_pass
    self.render_pass_flag = resource_renderer.render_pass_flag
    -- Register and select the resource pass before the renderer begins its
    -- widget pass. Darktide's own resource-backed grids follow this ordering;
    -- doing it after begin_pass left the pass valid in Lua but produced an
    -- untouched (black) target in the engine.
    return func(self, ...)
end)

-- SystemView creates its materials and retained widgets against one renderer.
-- Merely changing that renderer's pass-name fields does not migrate those
-- retained draw records. Darktide's own resource-backed grids instead draw
-- with the resource renderer object while registering its pass on the shared
-- Gui. Follow that exact contract for the Escape menu.
mod:hook(
    require("scripts/ui/views/system_view/system_view"),
    "draw",
    function(func, self, ...)
        if not ui_menu_resource_redirect_requested then
            return func(self, ...)
        end
        local dt, _, input_service = ...
        if not presentation.world_menu_active() then
            return func(self, ...)
        end
        local source_renderer = self._ui_default_renderer
        local resource_renderer =
            presentation.ensure_menu_resource(source_renderer)
        if not resource_renderer then
            return func(self, ...)
        end

        UIRenderer.clear_render_pass_queue(source_renderer)
        UIRenderer.add_render_pass(
            source_renderer,
            0,
            resource_renderer.base_render_pass,
            true,
            resource_renderer.render_target)
        if presentation.world_menu_target_desktop_probe then
            UIRenderer.add_render_pass(source_renderer, 1, "to_screen", false)
        end

        if not presentation.menu_resource_invalidated_views[self] then
            presentation.menu_resource_invalidated_views[self] = true
            local retained_count =
                presentation.invalidate_retained_widgets(self._widgets) +
                presentation.invalidate_retained_widgets(
                    self._content_widgets)
            mod:info(
                "DARKTIDEVR_MENU_TARGET renderer_swap view=%s retained=%d widgets=%d content=%d",
                tostring(self.view_name or self.__class_name),
                retained_count,
                type(self._widgets) == "table" and #self._widgets or 0,
                type(self._content_widgets) == "table" and
                    #self._content_widgets or 0)
        end

        self._ui_default_renderer = resource_renderer
        local result = func(self, ...)
        self._ui_default_renderer = source_renderer

        if presentation.world_menu_target_probe_requested then
            UIRenderer.begin_pass(
                resource_renderer,
                self._ui_scenegraph,
                input_service,
                dt,
                self._render_settings)
            local ui_widget =
                require("scripts/managers/ui/ui_widget")
            local base_widgets = self._widgets or {}
            for i = 1, #base_widgets do
                ui_widget.draw(base_widgets[i], resource_renderer)
            end
            local content_widgets = self._content_widgets or {}
            for i = 1, #content_widgets do
                ui_widget.draw(content_widgets[i], resource_renderer)
            end
            UIRenderer.draw_rect(
                resource_renderer,
                Vector3(0, 0, 10000),
                Vector3(600, 32, 0),
                Color(255, 255, 0, 255))
            UIRenderer.draw_rect(
                resource_renderer,
                Vector3(0, 0, 10001),
                Vector3(32, 600, 0),
                Color(255, 0, 255, 255))
            UIRenderer.end_pass(resource_renderer)
        end
        if presentation.world_menu_target_desktop_probe then
            local width, height = presentation.menu_resource_extent()
            Gui.bitmap(
                source_renderer.gui,
                resource_renderer.render_target_material,
                "render_pass",
                "to_screen",
                Vector3(0, 0, 20000),
                Vector3(width, height, 0),
                Color(255, 255, 255, 255))
        end
        return result
    end)

mod:hook(UIRenderer, "end_pass", function(func, self, ...)
    if not ui_menu_resource_redirect_requested then
        return func(self, ...)
    end
    local states = presentation.menu_resource_pass_states[self]
    local state = states and states[#states] or nil
    if state and presentation.world_menu_target_probe_requested then
        -- Opaque L-shaped registration mark. Magenta is the top edge in UI
        -- coordinates; cyan is the left edge. Their presence and orientation
        -- distinguish target/sample failure from a transform-axis failure.
        UIRenderer.draw_rect(
            self,
            Vector3(0, 0, 10000),
            Vector3(600, 32, 0),
            Color(255, 255, 0, 255))
        UIRenderer.draw_rect(
            self,
            Vector3(0, 0, 10001),
            Vector3(32, 600, 0),
            Color(255, 0, 255, 255))
    end
    if state and presentation.world_menu_target_desktop_probe then
        local resource_renderer = presentation.menu_resource_renderer
        local width, height = presentation.menu_resource_extent()
        Gui.bitmap(
            self.gui,
            resource_renderer.render_target_material,
            "render_pass",
            "to_screen",
            Vector3(0, 0, 20000),
            Vector3(width, height, 0),
            Color(255, 255, 255, 255))
    end
    local result = func(self, ...)
    if state then
        states[#states] = nil
        self.base_render_pass = state.base_render_pass
        self.render_pass_flag = state.render_pass_flag
    end
    return result
end)

-- Keep controller/menu back semantic rather than synthesizing Escape. The
-- engine's top view is authoritative: OptionsView, for example, first closes
-- an expanded setting or moves back a navigation column before closing the
-- view itself. Only the topmost instance may consume a shared button edge.
mod:hook(
    "BaseView",
    "update",
    function(func, self, dt, t, input_service, ...)
        local pointer = presentation.read_menu_pointer()
        if pointer.available and pointer.back_pressed and
                presentation.is_top_menu_view(self) then
            local callback = self.cb_on_back_pressed or
                self.cb_on_close_pressed
            if type(callback) == "function" then
                presentation.consume_menu_back(pointer)
                mod:info(
                    "DARKTIDEVR_MENU_INPUT source_back view=%s sequence=%d",
                    tostring(self.view_name or self.__class_name),
                    pointer.last_sequence)
                callback(self)
            end
        end
        return func(self, dt, t, input_service, ...)
    end)

-- BaseView owns the common full-screen widget draw path used by options and
-- most conventional menus. Resolve the XR ray against those engine-authored
-- widget rectangles before their hotspot pass runs, then use the same
-- force_input_pressed seam as BaseView.trigger_widget_pressed. Subclasses with
-- custom dynamic grids (including SystemView below) retain dedicated hooks.
mod:hook(
    "BaseView",
    "_draw_widgets",
    function(func, self, dt, t, input_service, ui_renderer, ...)
        local pointer = presentation.read_menu_pointer()
        local widgets = self._widgets or {}
        local source_widget = nil
        local source_entry = nil
        local modal_dropdown =
            presentation.options_modal_instance == self and
            presentation.options_modal_widget or nil
        local modal_active = modal_dropdown and modal_dropdown.content and
            modal_dropdown.content.exclusive_focus
        for i = #widgets, 1, -1 do
            local widget = widgets[i]
            if pointer.available then
                presentation.clear_widget_hotspot_forces(widget)
            end
            -- OptionsView's dynamic grids own their interaction overlays. In
            -- particular, BaseView must not force a second grid/row hover
            -- behind an expanded dropdown which is already handled by
            -- OptionsView._draw_grid.
            local dynamic_grid_interaction =
                widget and (widget.name == "settings_grid_interaction" or
                    widget.name == "category_grid_interaction")
            if not modal_active and not dynamic_grid_interaction and
                    pointer.available and not source_widget and pointer.active and
                    widget then
                local entry = presentation.widget_hotspot_at_pointer(
                    self, widget, pointer)
                if entry then
                    source_widget = widget
                    source_entry = entry
                end
            end
        end
        if pointer.primary_pressed and not source_widget and
                pointer.primary_press_sequence ~=
                    pointer.diagnostic_miss_sequence then
            pointer.diagnostic_miss_sequence =
                pointer.primary_press_sequence
            local diagnostics = {}
            for i = #widgets, 1, -1 do
                local widget = widgets[i]
                local entries = presentation.widget_hotspot_entries(widget)
                for j = #entries, 1, -1 do
                    local entry = entries[j]
                    local hit, geometry =
                        presentation.widget_contains_menu_pointer(
                            self, widget, pointer, entry.style)
                    if geometry and #diagnostics < 32 then
                        diagnostics[#diagnostics + 1] = string.format(
                            "%s:%s:%s:%.1f,%.1f,%.1f,%.1f",
                            tostring(widget.name),
                            tostring(entry.content_id),
                            hit and "hit" or "miss",
                            geometry.left,
                            geometry.top,
                            geometry.width,
                            geometry.height)
                    end
                end
            end
            mod:info(
                "DARKTIDEVR_MENU_INPUT base_source_miss view=%s sequence=%d source=%d,%d/%dx%d pointer=%.1f,%.1f widgets=%s",
                tostring(self.view_name or self.__class_name),
                pointer.last_sequence,
                pointer.x,
                pointer.y,
                pointer.source_width,
                pointer.source_height,
                pointer.x * RESOLUTION_LOOKUP.width / pointer.source_width,
                pointer.y * RESOLUTION_LOOKUP.height / pointer.source_height,
                #diagnostics > 0 and table.concat(diagnostics, "|") or
                    "none")
        end
        if source_widget and source_entry then
            local hotspot = source_entry.hotspot
            hotspot.force_hover = true
            if pointer.scroll_steps ~= 0 then
                local scroll_grid = nil
                if source_widget.name == "settings_grid_interaction" then
                    scroll_grid = self._settings_content_grid
                elseif source_widget.name == "category_grid_interaction" then
                    scroll_grid = self._category_content_grid
                end
                local scrolled, reason = presentation.scroll_menu_grid(
                    scroll_grid, pointer.scroll_steps)
                if scrolled then
                    mod:info(
                        "DARKTIDEVR_MENU_INPUT options_source_scroll widget=%s steps=%d sequence=%d",
                        tostring(source_widget.name),
                        pointer.scroll_steps,
                        pointer.last_sequence)
                    presentation.consume_menu_scroll(pointer)
                else
                    pointer.scroll_diagnostic_keys =
                        pointer.scroll_diagnostic_keys or {}
                    local role = scroll_grid == self._settings_content_grid and
                        "settings" or
                        (scroll_grid == self._category_content_grid and
                            "category" or "other")
                    local key = tostring(pointer.scroll_sequence) .. ":" ..
                        role .. ":" .. tostring(scroll_grid)
                    if not pointer.scroll_diagnostic_keys[key] then
                        pointer.scroll_diagnostic_keys[key] = true
                        local length = scroll_grid and
                            scroll_grid.scroll_length and
                            scroll_grid:scroll_length() or -1
                        mod:info(
                            "DARKTIDEVR_MENU_INPUT options_scroll_skipped widget=%s role=%s reason=%s length=%s",
                            tostring(source_widget.name),
                            role,
                            tostring(reason),
                            tostring(length))
                    end
                end
            end
            if pointer.primary_pressed then
                hotspot.force_input_pressed = true
                presentation.consume_menu_primary(pointer)
                mod:info(
                    "DARKTIDEVR_MENU_INPUT base_source_activate view=%s widget=%s sequence=%d source=%d,%d/%dx%d",
                    tostring(self.view_name or self.__class_name),
                    tostring(source_widget.name) .. ":" ..
                        tostring(source_entry.content_id),
                    pointer.last_sequence,
                    pointer.x,
                    pointer.y,
                    pointer.source_width,
                    pointer.source_height)
            end
        end
        return func(self, dt, t, input_service, ui_renderer, ...)
    end)

-- OptionsView draws its category and settings widgets through two custom
-- UIWidgetGrid passes before BaseView draws its static chrome. Arm the exact
-- visible grid widget before that pass, and consume the edge only after a hit
-- so stacked views cannot steal it merely by reading the shared sample.
mod:hook(
    "OptionsView",
    "_draw_grid",
    function(func, self, grid, widgets, interaction_widget, dt, t,
            input_service, ...)
        local pointer = presentation.read_menu_pointer()
        presentation.update_slider_drag(self, pointer)
        local source_widget = nil
        local source_entry = nil
        if pointer.available then
            for i = 1, #widgets do
                presentation.clear_widget_hotspot_forces(widgets[i])
            end
        end
        if pointer.active then
            -- OptionsView already owns the authoritative modal selection.
            -- Do not infer it by scanning content.exclusive_focus: stale flags
            -- can exist on more than one widget while a dynamic grid rebuilds.
            local focused_dropdown = nil
            local selected_widget = self._selected_settings_widget
            if presentation.is_dropdown_widget(selected_widget) then
                for i = 1, #widgets do
                    if widgets[i] == selected_widget then
                        focused_dropdown = selected_widget
                        break
                    end
                end
            end
            local function consider_widget(widget)
                local visible = not grid or
                    grid:is_widget_visible(widget)
                if visible then
                    if widget == focused_dropdown then
                        presentation.log_focused_dropdown_geometry(
                            self, widget, pointer)
                    end
                    presentation.log_slider_geometry(
                        self, widget, pointer)
                end
                local entry = visible and
                    presentation.widget_hotspot_at_pointer(
                        self, widget, pointer,
                        widget == focused_dropdown)
                if entry then
                    source_widget = widget
                    source_entry = entry
                    return true
                end
                return false
            end
            if focused_dropdown then
                -- Exclusive focus is also visual/modal ownership. Its option
                -- passes are drawn over later grid rows, so they must receive
                -- the ray before (and instead of) widgets geometrically behind
                -- the expanded list.
                consider_widget(focused_dropdown)
                presentation.options_modal_instance = self
                presentation.options_modal_widget = focused_dropdown
            else
                if presentation.options_modal_instance == self then
                    presentation.options_modal_instance = nil
                    presentation.options_modal_widget = nil
                end
                for i = #widgets, 1, -1 do
                    if consider_widget(widgets[i]) then
                        break
                    end
                end
            end
        end
        local interaction_hotspot =
            presentation.widget_hotspot(interaction_widget)
        if pointer.available and interaction_hotspot then
            -- This is a grid-sized input catcher, not the row under the ray.
            -- Forcing it hovered alongside source_widget makes the grid's first
            -- entry (Audio in the current options layout) look hovered too.
            interaction_hotspot.force_hover = false
        end
        if pointer.scroll_steps ~= 0 and pointer.active and
                interaction_widget then
            local interaction_hit =
                presentation.widget_contains_menu_pointer(
                    self, interaction_widget, pointer)
            if interaction_hit then
                local scrolled, reason = presentation.scroll_menu_grid(
                    grid, pointer.scroll_steps)
                if scrolled then
                    presentation.consume_menu_scroll(pointer)
                    mod:info(
                        "DARKTIDEVR_MENU_INPUT options_grid_scroll grid=%s steps=%d sequence=%d",
                        tostring(interaction_widget.name),
                        pointer.scroll_steps,
                        pointer.last_sequence)
                else
                    mod:info(
                        "DARKTIDEVR_MENU_INPUT options_grid_scroll_skipped grid=%s steps=%d reason=%s",
                        tostring(interaction_widget.name),
                        pointer.scroll_steps,
                        tostring(reason))
                end
            end
        end
        if source_widget and source_entry then
            local hotspot = source_entry.hotspot
            hotspot.force_hover = true
            if pointer.primary_pressed then
                local started_slider = false
                local opening_dropdown = false
                if presentation.is_slider_widget(source_widget) then
                    started_slider = presentation.begin_slider_drag(
                        self, source_widget, pointer)
                elseif presentation.is_dropdown_widget(source_widget) and
                        source_entry.content_id == "hotspot" and
                        source_widget ~= self._selected_settings_widget then
                    -- Opening through the ordinary pressed_callback makes the
                    -- same physical trigger edge visible to OptionsView as a
                    -- native left_pressed click-away on its following update.
                    -- Defer only the native coordinator call until that edge
                    -- has drained. Modal ownership thereafter remains the
                    -- engine's authoritative _selected_settings_widget.
                    presentation.dropdown_open_pending = {
                        instance = self,
                        widget_name = source_widget.name,
                        frames = 2,
                    }
                    opening_dropdown = true
                end
                if not started_slider and not opening_dropdown then
                    hotspot.force_input_pressed = true
                    if presentation.is_dropdown_widget(source_widget) and
                            string.match(
                                source_entry.content_id,
                                "^option_hotspot_%d+$") then
                        presentation.dropdown_close_pending = {
                            instance = self,
                            -- The option's on_pressed bit is consumed by the
                            -- next blueprint update. The hook-safe update below
                            -- also runs once at the end of this current update,
                            -- so two ticks are required before closing focus.
                            frames = 2,
                        }
                    end
                end
                presentation.consume_menu_primary(pointer)
                mod:info(
                    "DARKTIDEVR_MENU_INPUT options_source_activate widget=%s hotspot=%s sequence=%d source=%d,%d/%dx%d",
                    tostring(source_widget.name),
                    tostring(source_entry.content_id),
                    pointer.last_sequence,
                    pointer.x,
                    pointer.y,
                    pointer.source_width,
                    pointer.source_height)
            end
        end
        return func(self, grid, widgets, interaction_widget, dt, t,
            input_service, ...)
    end)

-- A cursor dropdown normally releases exclusive focus from the engine mouse
-- edge. XR supplies the option pressed edge directly, so close focus only
-- after the following blueprint update has applied the selected value.
mod:hook_safe("OptionsView", "update", function(self)
    local open_pending = presentation.dropdown_open_pending
    if open_pending and open_pending.instance == self then
        open_pending.frames = open_pending.frames - 1
        if open_pending.frames <= 0 then
            if type(self._set_exclusive_focus_on_grid_widget) == "function" then
                self:_set_exclusive_focus_on_grid_widget(
                    open_pending.widget_name)
            end
            presentation.dropdown_open_pending = nil
            mod:info(
                "DARKTIDEVR_MENU_INPUT dropdown_focus_opened source=xr widget=%s",
                tostring(open_pending.widget_name))
        end
    end
    local pending = presentation.dropdown_close_pending
    if not pending or pending.instance ~= self then
        return
    end
    pending.frames = pending.frames - 1
    if pending.frames <= 0 then
        if type(self._set_exclusive_focus_on_grid_widget) == "function" then
            self:_set_exclusive_focus_on_grid_widget(nil)
        end
        presentation.dropdown_close_pending = nil
        mod:info("DARKTIDEVR_MENU_INPUT dropdown_focus_closed source=xr")
    end
end)

-- The current hub build opens its system menu through the preloaded
-- SystemView instance without traversing the UIManager methods or active-view
-- list used by loading/vendor views. Observe the lifecycle at the view class
-- as an explicit compatibility seam.
mod:hook_safe(
    require("scripts/ui/views/system_view/system_view"),
    "on_enter",
    function(self)
    presentation.active_menu_view_instance = self
    presentation.world_menu_anchor = nil
    presentation.world_menu_draw_logged = false
    -- SystemView creates a dedicated overlay viewport whose only purpose is
    -- to shade/blur the desktop back buffer.  It is not menu content and it
    -- acts on player1 only, so remove it while leaving the actual menu
    -- renderer alive for offscreen capture.
    if self._ui_background_renderer and
            type(self._destroy_background) == "function" then
        self:_destroy_background()
    end
    local input_fields = {}
    for key, value in pairs(self) do
        if string.find(string.lower(tostring(key)), "input", 1, true) then
            input_fields[#input_fields + 1] = tostring(key) .. ":" .. type(value)
        end
    end
    table.sort(input_fields)
    mod:info(
        "DARKTIDEVR_MENU_INPUT system_view fields=%s",
        #input_fields > 0 and table.concat(input_fields, ",") or "none")
    presentation.fullscreen_empty_updates = 0
    presentation.world_menu_views.system_view = true
    presentation.publish_mode(4, "SystemView.on_enter:world_space_menu")
    -- Focused command tracing is diagnostic-only now that the stock menu PSO
    -- and completed swapchain boundary are known.
    presentation.system_view_trace_pending =
        ui_menu_trace_requested and true or nil
    presentation.system_view_trace_phase = nil
    presentation.system_view_trace_frames = nil
end)

mod:hook(
    require("scripts/ui/views/system_view/system_view"),
    "on_exit",
    function(func, self, ...)
    -- The stereo projection remains active for the entire menu lifetime. Let
    -- the engine finish closing the view, then remove only its XR quad; there
    -- is no flat-to-stereo handoff and no renderer or camera-mode transition.
    local result = func(self, ...)
    presentation.active_menu_view_instance = nil
    presentation.active_menu_input_service = nil
    presentation.system_view_hovered_widget = nil
    presentation.system_view_source_widget = nil
    presentation.system_view_trace_pending = nil
    presentation.system_view_trace_seen = nil
    presentation.system_view_trace_phase = nil
    presentation.system_view_trace_frames = nil
    if ui_native_capture then
        ui_native_capture.dtvr_set_focused_trace_phase(0)
    end
    presentation.fullscreen_empty_updates = 0
    presentation.destroy_menu_resource()
    presentation.publish_mode(1, "SystemView.on_exit:complete")
    return result
end)

mod:hook_safe(
    require("scripts/ui/views/system_view/system_view"),
    "update",
    function(_, _, _, input_service)
        presentation.active_menu_input_service = input_service
        if ui_menu_trace_requested and
                not presentation.system_view_trace_seen and ui_native_capture then
            presentation.system_view_trace_seen = true
            presentation.system_view_trace_pending = nil
            presentation.system_view_trace_phase = 1
            presentation.system_view_trace_frames = 4
            local marker_result = ui_native_capture.dtvr_enable_marker_log()
            local trace_result =
                ui_native_capture.dtvr_set_focused_trace_phase(1)
            mod:info(
                "DARKTIDEVR_MENU_TRACE started_update frames=%d marker_result=%s trace_result=%s",
                presentation.system_view_trace_frames,
                tostring(marker_result),
                tostring(trace_result))
        end
        local trace_frames = presentation.system_view_trace_frames
        if trace_frames and presentation.system_view_trace_phase == 1 then
            trace_frames = trace_frames - 1
            presentation.system_view_trace_frames = trace_frames
            if trace_frames <= 0 then
                presentation.system_view_trace_frames = nil
                presentation.system_view_trace_phase = nil
                if ui_native_capture then
                    ui_native_capture.dtvr_set_focused_trace_phase(0)
                end
                mod:info("DARKTIDEVR_MENU_TRACE stopped reason=frame_budget")
            end
        end
    end)

-- SystemView owns a dynamic grid outside BaseView._widgets. Resolve the XR
-- source pixel before its hotspot pass and arm only the matching callback on
-- the same atomic pointer/button sample.
mod:hook(
    "SystemView",
    "_draw_widgets",
    function(func, self, dt, t, input_service, ui_renderer, ...)
        presentation.system_view_hovered_widget = nil
        presentation.system_view_source_widget = nil
        local pointer = presentation.read_menu_pointer()
        local widgets = self._content_widgets or {}
        for i = 1, #widgets do
            local widget = widgets[i]
            local hotspot = widget and widget.content and
                widget.content.hotspot
            local source_hit =
                presentation.widget_contains_menu_pointer(
                    self, widget, pointer)
            if pointer.available and hotspot then
                hotspot.force_hover = false
            end
            if source_hit and hotspot and not hotspot.disabled and
                    not presentation.system_view_source_widget then
                presentation.system_view_source_widget = widget
                hotspot.force_hover = true
                if pointer.scroll_steps ~= 0 and
                        presentation.scroll_menu_grid(
                            self._content_grid, pointer.scroll_steps) then
                    mod:info(
                        "DARKTIDEVR_MENU_INPUT source_scroll widget=%s steps=%d sequence=%d",
                        tostring(widget.name),
                        pointer.scroll_steps,
                        pointer.last_sequence)
                    presentation.consume_menu_scroll(pointer)
                end
                if pointer.primary_pressed then
                    hotspot.force_input_pressed = true
                    presentation.consume_menu_primary(pointer)
                    mod:info(
                        "DARKTIDEVR_MENU_INPUT source_activate widget=%s sequence=%d source=%d,%d/%dx%d",
                        tostring(widget.name),
                        pointer.last_sequence,
                        pointer.x,
                        pointer.y,
                        pointer.source_width,
                        pointer.source_height)
                end
            end
        end
        local result = func(self, dt, t, input_service, ui_renderer, ...)
        local inventory_requested = false
        local inventory_path =
            "./../mods/darktidevr_stereo_probe/darktidevr_hotspot_inventory.flag"
        if Mods and Mods.lua and Mods.lua.io then
            local flag = Mods.lua.io.open(inventory_path, "r")
            if flag then
                local request = flag:read("*all")
                flag:close()
                inventory_requested = request and
                    string.find(request, "scan", 1, true) ~= nil
                if inventory_requested then
                    local consumed = Mods.lua.io.open(inventory_path, "w")
                    if consumed then
                        consumed:write("consumed\n")
                        consumed:close()
                    end
                end
            end
        end
        for i = 1, #widgets do
            local widget = widgets[i]
            local hotspot = widget and widget.content and
                widget.content.hotspot
            local source_hit, geometry =
                presentation.widget_contains_menu_pointer(
                    self, widget, pointer)
            if inventory_requested and hotspot then
                local fields = {}
                for key, value in pairs(hotspot) do
                    local lower = string.lower(tostring(key))
                    if type(value) == "boolean" or
                            string.find(lower, "hover", 1, true) or
                            string.find(lower, "focus", 1, true) or
                            string.find(lower, "press", 1, true) or
                            string.find(lower, "select", 1, true) then
                        fields[#fields + 1] =
                            tostring(key) .. "=" .. tostring(value)
                    end
                end
                table.sort(fields)
                mod:info(
                    "DARKTIDEVR_MENU_INPUT hotspot widget=%s index=%d text=%s fields=%s source_hit=%s geometry=%s",
                    tostring(widget.name),
                    i,
                    tostring(widget.content.text),
                    table.concat(fields, ","),
                    tostring(source_hit),
                    geometry and string.format(
                        "pointer=%.1f,%.1f rect=%.1f,%.1f,%.1f,%.1f source=%d,%d/%dx%d",
                        geometry.pointer_x,
                        geometry.pointer_y,
                        geometry.left,
                        geometry.top,
                        geometry.width,
                        geometry.height,
                        pointer.x,
                        pointer.y,
                        pointer.source_width,
                        pointer.source_height) or "unavailable")
            end
            if hotspot and hotspot.is_hover and not hotspot.disabled and
                    not presentation.system_view_hovered_widget then
                presentation.system_view_hovered_widget = widget
            end
        end
        return result
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
                4 then
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
                false and
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
