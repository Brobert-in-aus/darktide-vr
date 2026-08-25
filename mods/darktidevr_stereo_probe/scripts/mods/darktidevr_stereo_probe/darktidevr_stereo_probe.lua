local mod = get_mod("darktidevr_stereo_probe")

local ScriptCamera = require("scripts/foundation/utilities/script_camera")
local ScriptViewport = require("scripts/foundation/utilities/script_viewport")
local ScriptWorld = require("scripts/foundation/utilities/script_world")
local UIRenderer = require("scripts/managers/ui/ui_renderer")

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
-- Render exactly the per-eye extent recommended by VirtualDesktopXR Medium.
-- The physical mirror is decoupled by swapchain-window WM_SIZE virtualization;
-- the remaining projection work must use an asymmetric per-eye frustum rather
-- than increasing this render extent for a symmetric overscan workaround.
local ui_eye_target_width = 2112
local ui_eye_target_height = 2304
local ui_native_capture_requested = true -- copy each completed full-origin eye
local ui_camera_output_candidate_probe_index = -1
local ui_native_observer_requested = false
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
local ui_boundary_census_requested = true
local ui_mirror_client_width = 0
local ui_mirror_client_height = 0
local ui_virtual_client_extent_requested = false
local ui_virtual_size_message_requested = true
local head_pose_values = nil
local head_pose_sequence = nil
local head_tracking_requested = true
local head_translation_requested = false -- enable after the 3DoF gate
local head_pose_last_sequence = 0
local head_render_vertical_fov = nil
local head_render_aspect_ratio = nil
local head_render_frusta = nil
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
        int dtvr_read_head_pose(float *values, unsigned long long *sequence);
    ]])

    local ok, library = pcall(
        ffi.load,
        "../mods/darktidevr_stereo_probe/bin/darktidevr_native_capture.dll"
    )

    if not ok then
        mod:error("DARKTIDEVR_STEREO native_capture load_failed error=%s", tostring(library))
        return false
    end

    local install_result = library.dtvr_install()

    if install_result ~= 0 then
        mod:error("DARKTIDEVR_STEREO native_capture install_failed code=%d", install_result)
        return false
    end

    ui_native_capture = library
    head_pose_values = ffi.new("float[17]")
    head_pose_sequence = ffi.new("unsigned long long[1]")
    mod:info("DARKTIDEVR_STEREO native_hooks installed")

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
    local head_rotation = Quaternion.from_elements(
        head_pose_values[3],
        -head_pose_values[5],
        head_pose_values[4],
        head_pose_values[6]
    )
    local tracked_rotation = Quaternion.multiply(clean_rotation, head_rotation)
    local tracked_position = clean_position

    if head_translation_requested then
        local local_x = head_pose_values[0]
        local local_y = -head_pose_values[2]
        local local_z = head_pose_values[1]
        tracked_position = clean_position +
            Quaternion.right(clean_rotation) * local_x +
            Quaternion.forward(clean_rotation) * local_y +
            Quaternion.up(clean_rotation) * local_z
    end

    if head_pose_last_sequence == 0 then
        mod:info("DARKTIDEVR_STEREO head_tracking active mode=%s sequence=%d",
            head_translation_requested and "6dof" or "3dof",
            sequence)
    end
    head_pose_last_sequence = sequence

    return tracked_position, tracked_rotation
end

if ui_native_observer_requested then
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
    if active_world then
        local primary = ScriptWorld.has_viewport(active_world, primary_viewport_name) and
            ScriptWorld.viewport(active_world, primary_viewport_name)

        if primary then
            Viewport.set_rect(primary, 0, 0, 1, 1)
        end

        if ScriptWorld.has_viewport(active_world, right_viewport_name) then
            ScriptWorld.destroy_viewport(active_world, right_viewport_name)
        end
    end

    active = false
    active_manager = nil
    active_world = nil
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
            not ui_stereo_right_viewport then
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
    local clean_rotation = ScriptCamera.local_rotation(primary_camera)
    clean_position, clean_rotation = apply_head_tracking(
        clean_position,
        clean_rotation
    )
    local eye_axis = Quaternion.right(clean_rotation)

    local runtime_projection_matches_target = head_render_vertical_fov and
        head_render_aspect_ratio and
        math.abs(head_render_aspect_ratio -
            (ui_eye_target_width / ui_eye_target_height)) < 0.001
    if runtime_projection_matches_target then
        Camera.set_near_range(right_camera, Camera.near_range(primary_camera))
        Camera.set_far_range(right_camera, Camera.far_range(primary_camera))
        if not apply_runtime_frusta(primary_camera, right_camera) then
            Camera.set_vertical_fov(primary_camera, head_render_vertical_fov)
            Camera.set_vertical_fov(right_camera, head_render_vertical_fov)
        end
    end

    ScriptCamera.set_local_position(
        primary_camera,
        clean_position - eye_axis * half_ipd
    )
    ScriptCamera.set_local_rotation(primary_camera, clean_rotation)
    ScriptCamera.set_local_position(
        right_camera,
        clean_position + eye_axis * half_ipd
    )
    ScriptCamera.set_local_rotation(right_camera, clean_rotation)
    if not runtime_projection_matches_target then
        copy_projection(primary_camera, right_camera)
    end
    publish_render_projection(primary_camera)

    ScriptCamera.force_update(world, primary_camera)
    ScriptCamera.force_update(world, right_camera)
end

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

            if ui_native_capture_requested then
                enable_ui_native_capture()
            end

            if ui_present_capture_requested and ensure_ui_native_hooks() then
                ui_native_capture.dtvr_enable_present_capture()
            end

            local ok, error_message = pcall(setup_ui_stereo, self)

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
        local result = func(world, ...)
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
        func(world, ...)
        if ui_direct_swapchain_capture_requested then
            report_native_capture_result(
                ui_native_capture.dtvr_capture_armed_swapchain_eye(1)
            )
        elseif ui_native_sync_requested then
            wait_for_eye_capture(1, right_target)
        end

        -- Restore the normal active set for update code outside this hook.
        ScriptWorld.activate_viewport(world, primary)
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
        local result = func(world, ...)
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
        func(world, ...)
        if ui_direct_swapchain_capture_requested then
            report_native_capture_result(
                ui_native_capture.dtvr_capture_armed_swapchain_eye(1)
            )
        elseif ui_native_sync_requested then
            wait_for_eye_capture(1, right_target)
        end
        ScriptWorld.activate_viewport(world, primary)

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
