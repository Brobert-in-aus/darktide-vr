[CmdletBinding()]
param(
    [string] $SourcePath,

    [ValidateRange(1, 200)]
    [int] $MaximumFileScopeLocals = 198
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $SourcePath) {
    $SourcePath = Join-Path $repoRoot `
        'mods\darktidevr\scripts\mods\darktidevr\darktidevr.lua'
}
$resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
$lines = @(Get-Content -LiteralPath $resolvedSource)

# The Darktide mod is one LuaJIT chunk. File-scope locals remain live for the
# rest of that chunk, and Lua rejects the chunk once its 200-local compiler
# ceiling is crossed. Count declarations at column zero; nested declarations
# are indented by the repository formatter and do not consume the chunk scope.
$fileScopeLocals = 0
foreach ($line in $lines) {
    if ($line -match '^local\s+function\s+[A-Za-z_][A-Za-z0-9_]*') {
        $fileScopeLocals++
        continue
    }
    if ($line -match '^local\s+(.+)$') {
        $declaration = ($Matches[1] -split '=', 2)[0]
        $names = @($declaration -split ',' | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*$' })
        $fileScopeLocals += $names.Count
    }
}
if ($fileScopeLocals -gt $MaximumFileScopeLocals) {
    throw "Lua file-scope local budget exceeded: $fileScopeLocals > $MaximumFileScopeLocals. Store new state on an existing table or split the chunk into modules."
}

# State-table members must not be initialized before the local table exists.
# This catches the exact class of load-time failure that otherwise degrades XR
# to its flat fallback while making the stereo mod appear to have launched.
$trackedTables = @('controller_observation', 'presentation')
foreach ($tableName in $trackedTables) {
    $declarationLine = $null
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match "^local\s+$tableName\s*=\s*{") {
            $declarationLine = $index
            break
        }
    }
    if ($null -eq $declarationLine) {
        throw "Required state table '$tableName' has no file-scope declaration."
    }
    for ($index = 0; $index -lt $declarationLine; $index++) {
        if ($lines[$index] -match "(^|[^A-Za-z0-9_])$tableName\s*\.") {
            throw "State table '$tableName' is referenced before declaration at line $($index + 1)."
        }
    }
}

# The post-animation body pass must finish authoring the avatar root heading
# before deriving the common camera/controller anchor. Sampling the calibrated,
# off-centre eye anchor while Darktide's root still faces travel makes both
# wrist targets trace a fixed-radius circle as the locomotion stick rotates.
$source = Get-Content -LiteralPath $resolvedSource -Raw
$spectatorModuleInit = $source.IndexOf('presentation.spectator_module = mod:io_dofile(')
$nativeHookDefinition = $source.IndexOf('local function ensure_ui_native_hooks()')
if ($spectatorModuleInit -lt 0 -or $nativeHookDefinition -lt 0 -or
        $spectatorModuleInit -gt $nativeHookDefinition) {
    throw 'Load the spectator module before native hooks can initialize its reader during mod loading.'
}
$bootstrapPath = Join-Path $repoRoot `
    'mods\darktidevr\darktidevr.mod'
$bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
foreach ($resource in @('mod_localization', 'mod_data', 'mod_script')) {
    if (-not $bootstrap.Contains($resource)) {
        throw "Darktide VR bootstrap must register DMF resource '$resource'."
    }
}
$syncPath = Join-Path $repoRoot 'tools\stereo\sync-darktide-vr-dev.ps1'
$syncSource = Get-Content -LiteralPath $syncPath -Raw
if (-not $syncSource.Contains('$sourceBootstrap') -or
        -not $syncSource.Contains("'darktidevr.mod'")) {
    throw 'Development sync must deploy the DMF bootstrap alongside Lua modules.'
}
$startPath = Join-Path $repoRoot 'tools\stereo\start-darktide-vr.ps1'
$startSource = Get-Content -LiteralPath $startPath -Raw
if (-not $startSource.Contains('[switch] $EnablePerformanceProfile') -or
        -not $startSource.Contains('[switch] $EnablePerformancePassTrace') -or
        -not $startSource.Contains(
            "Write-Output 'Restored the prior performance-profile flag.'") -or
        -not $startSource.Contains(
            "Write-Output 'Restored the prior performance-pass trace flag.'")) {
    throw 'Authenticated launcher must own and restore performance diagnostics for exactly one XR run.'
}
if (-not $startSource.Contains('$preLaunchGameProcessIds') -or
        -not $startSource.Contains('$_.Path -ieq $expectedGamePath') -or
        $startSource.Contains('$orphanedGames = @(Get-Process -Name Darktide `
                    -ErrorAction SilentlyContinue)')) {
    throw 'Authenticated launcher cleanup must preserve pre-existing processes and target only the configured game executable.'
}
$runnerPath = Join-Path $repoRoot 'tools\stereo\run-darktide-shared-eyes.ps1'
$runnerSource = Get-Content -LiteralPath $runnerPath -Raw
if (-not $runnerSource.Contains(
        '$resolvedGameExe = (Resolve-Path -LiteralPath $GameExe).Path') -or
        -not $runnerSource.Contains('$_.Path -ieq $resolvedGameExe')) {
    throw 'XR runner must authenticate the responsive Darktide window by executable path.'
}
$launcherPlayPath = Join-Path $repoRoot 'tools\stereo\invoke-darktide-launcher-play.ps1'
$launcherPlaySource = Get-Content -LiteralPath $launcherPlayPath -Raw
if (-not $launcherPlaySource.Contains('$_.Path -ieq $gamePath') -or
        -not $launcherPlaySource.Contains('$launchWindowHandle') -or
        -not $launcherPlaySource.Contains('IsOwnedWindow(') -or
        -not $launcherPlaySource.Contains('$nextPlayRetry')) {
    throw 'Launcher Play confirmation must authenticate the configured Darktide executable and retry only the original owned launcher window.'
}
$bodyIkStart = $source.IndexOf('function presentation.apply_body_ik')
$bodyIkEnd = $source.IndexOf(
    'function presentation.trace_body_ik', $bodyIkStart)
if ($bodyIkStart -lt 0 -or $bodyIkEnd -lt 0) {
    throw 'Could not locate the complete post-animation body IK function.'
}
$bodyIkSource = $source.Substring($bodyIkStart, $bodyIkEnd - $bodyIkStart)
$headingWrite = $bodyIkSource.IndexOf(
    'presentation.apply_body_heading(world, unit)')
$anchorRefresh = $bodyIkSource.IndexOf(
    'presentation.refresh_body_anchor_from_avatar(anchor_unit or unit)')
if ($headingWrite -lt 0 -or $anchorRefresh -lt 0 -or
        $anchorRefresh -lt $headingWrite) {
    throw 'Body IK must refresh its shared pose anchor after applying body heading.'
}

if ($source.Contains('server_correction mapped=hub_jog->walking') -or
        $source.Contains('server_correction incoming=hub_jog') -or
        $source.Contains('starting_state=walking source=hub_first_person')) {
    throw 'Public-hub locomotion must not replace the server-authoritative hub_jog state.'
}
if (-not $source.Contains(
        'function presentation.clamp_hub_head_horizontal(x, z)') -or
        -not $source.Contains('local limit = 0.25')) {
    throw 'Hub HMD translation must retain the 25 cm visual lean envelope.'
}
$bodyFollowStart = $source.IndexOf(
    'function presentation.refresh_body_follow_mode')
$bodyFollowEnd = $source.IndexOf(
    'function presentation.apply_body_follow_translation', $bodyFollowStart)
if ($bodyFollowStart -lt 0 -or $bodyFollowEnd -lt 0 -or
        -not $source.Substring(
            $bodyFollowStart, $bodyFollowEnd - $bodyFollowStart).Contains(
                'if game_mode_name == "hub"')) {
    throw 'Hub room-scale lean must not write the authoritative root/collision path.'
}
$gripTargetStart = $source.IndexOf(
    'function presentation.body_ik_controller_grip_target')
$gripTargetEnd = $source.IndexOf(
    'function presentation.controller_aim_target', $gripTargetStart)
if ($gripTargetStart -lt 0 -or $gripTargetEnd -lt 0) {
    throw 'Could not locate the complete body controller grip target function.'
}
$gripTargetSource = $source.Substring(
    $gripTargetStart, $gripTargetEnd - $gripTargetStart)
if ($gripTargetSource.Contains(
        'controller_observation.body_follow_x') -or
        -not $gripTargetSource.Contains(
            "Grip and camera poses share the bridge's sliding recenter space")) {
    throw 'Hub wrist targets must remain in the bridge sliding-recenter space and must not add cumulative body-follow travel.'
}
if (-not $source.Contains(
        'Hub locomotion continuously authors the replicated root orientation') -or
        -not $source.Contains(
            'if presentation.current_game_mode_name() == "hub" then')) {
    throw 'Hub locomotion must retain exclusive ownership of the root orientation.'
}
if (-not $source.Contains(
        'presentation.body_proxy.hides_source_slot(slot_name)') -or
        -not $source.Contains(
            'presentation.body_proxy.consume_ready_transition()') -or
        -not $source.Contains(
            'presentation.apply_body_ik(unit, sequence, world, anchor_unit)')) {
    throw 'Hub upper-body presentation must use the isolated local proxy while tracking remains anchored to the authoritative avatar.'
}
if (-not $source.Contains(
        'target_position - current_wrist') -or
        -not $source.Contains(
            'Unit.set_local_position(unit, forearm_node,') -or
        -not $source.Contains(
            'pose.forearm_position:unbox() - forearm_parent_position') -or
        $source.Contains('detached_hand_local') -or
        -not $source.Contains(
            'function presentation.hold_body_hand_proxy') -or
        -not $source.Contains(
            'pose.position:unbox() - parent_position') -or
        -not $source.Contains(
            'presentation.apply_tracked_arms(unit, sequence, world, anchor_unit)') -or
        -not $source.Contains(
            'function presentation.sync_equipment_hands_to_proxy') -or
        -not $source.Contains(
            'presentation.sync_equipment_hands_to_proxy(')) {
    throw 'Launch glove/bracer lower-arm subtrees and the hidden source attachment nodes for gameplay-owned equipment must follow controller-owned proxy effectors through valid tracking and world-pose hold.'
}
$bodyProxySourcePath = Join-Path (Split-Path -Parent $resolvedSource) `
    'darktidevr_body_proxy.lua'
$bodyProxySource = Get-Content -Raw -LiteralPath $bodyProxySourcePath
if (-not $bodyProxySource.Contains('state.hands_only') -or
        -not $bodyProxySource.Contains(
            'return slot_name == "slot_body_arms"') -or
        $bodyProxySource.Contains(
            '"j_leftforearmroll1", "j_leftforearmroll2", "j_lefthand"') -or
        $bodyProxySource.Contains(
            '"j_rightforearmroll1", "j_rightforearmroll2", "j_righthand"')) {
    throw 'The launch proxy must own only the hand slot, hide the source hands, and preserve its last authored wrist transforms across tracking loss.'
}
$eyeTransformHelperPath = Join-Path $repoRoot `
    'tools\stereo\set-coincident-eye-probe.ps1'
$eyeTransformHelperSource = Get-Content -Raw -LiteralPath $eyeTransformHelperPath
if (-not $source.Contains('eye_transform_probe_mode = "disabled"') -or
        -not $source.Contains('probe_value == "enabled" and "coincident"') -or
        -not $source.Contains('probe_mode ~= "zero_ipd"') -or
        -not $source.Contains('probe_mode ~= "matched_orientation"') -or
        -not $source.Contains('probe_mode ~= "visibility_padding"') -or
        -not $source.Contains(
            'DARKTIDEVR_STEREO eye_transform_probe=%s source=test_flag') -or
        -not $source.Contains(
            'presentation.eye_transform_probe_mode == "zero_ipd"') -or
        -not $source.Contains(
            'presentation.eye_transform_probe_mode == "matched_orientation"') -or
        -not $eyeTransformHelperSource.Contains("'ZeroIpd' { 'zero_ipd' }") -or
        -not $eyeTransformHelperSource.Contains(
            "'MatchedOrientation' { 'matched_orientation' }") -or
        -not $eyeTransformHelperSource.Contains(
            "'VisibilityPadding' { 'visibility_padding' }") -or
        -not $source.Contains(
            'presentation.eye_transform_probe_mode == "visibility_padding"') -or
        -not $source.Contains(
            'vertical_fov or Camera.vertical_fov(camera)')) {
    throw 'The eye-transform diagnostic must poll live and isolate IPD translation, recentered optical-axis rotation, and engine-frustum visibility padding.'
}
if (-not $bodyProxySource.Contains(
        'state.profile_spawner or state.unit_spawner or state.unit or') -or
        -not $bodyProxySource.Contains('state.failed_source_unit then')) {
    throw 'Disabling or invalidating the proxy owner must clear a cached streaming failure so the same player unit can reacquire.'
}
if (-not $bodyProxySource.Contains(
        'human/gear_hands/hmn_gloves_b_left_only') -or
        -not $bodyProxySource.Contains(
            'human/gear_hands/hmn_gloves_b_right_only') -or
        -not $bodyProxySource.Contains(
            '"DarktideVRRigidHand_" .. side') -or
        -not $bodyProxySource.Contains(
            'spawn_rigid_hand(world, source_unit, profile, "left")') -or
        -not $bodyProxySource.Contains(
            'spawn_rigid_hand(world, source_unit, profile, "right")') -or
        -not $bodyProxySource.Contains(
            'local function anatomical_hand_rotation(') -or
        -not $bodyProxySource.Contains(
            'Quaternion.right(target_rotation) * -1') -or
        -not $bodyProxySource.Contains(
            'Quaternion.forward(target_rotation)') -or
        -not $bodyProxySource.Contains(
            'desired_hand_rotation, inverse_quaternion(relative_rotation)') -or
        -not $bodyProxySource.Contains(
            'root_position + target_position - Unit.world_position(unit, hand_node)') -or
        -not $bodyProxySource.Contains(
            'function BodyProxy.place_rigid_hands(') -or
        -not $source.Contains(
            'presentation.body_proxy.rigid_hands_active()') -or
        -not $source.Contains(
            'presentation.body_proxy.place_rigid_hands(') -or
        -not $source.Contains(
            '"left", left_target, left_rotation)') -or
        -not $source.Contains(
            '"right", right_target, right_rotation)') -or
        -not $source.Contains(
            'left_unit,rigid_left_target,left_rotation,left_written)') -or
        -not $source.Contains(
            'right_unit,rigid_right_target,right_rotation,right_written)') -or
        -not $bodyProxySource.Contains('function BodyProxy.equipment_hand_rotation(')) {
    throw 'Tracked hands must keep independent anatomical glove profiles and calibrated physical wrist positions, with equipment using its authored basis and the selected destination placement.'
}
if (-not $source.Contains('"/gear_hands/"') -or
        -not $source.Contains(
            '(glove_attachment and not proxy_hidden)') -or
        -not $source.Contains('visible_glove_units')) {
    throw 'Source tracked-hands presentation must hide its glove attachment while the proxy owns the upper-body slot.'
}
if (-not $source.Contains('prior > ceiling') -or
        -not $source.Contains(
            'prior + (desired[side] - prior) * alpha, 0, ceiling')) {
    throw 'Shoulder reach smoothing state must remain anatomically bounded.'
}
if (-not $source.Contains('math.min(1.10,') -or
        -not $source.Contains('record.arm_length * 0.08') -or
        -not $source.Contains('reach_state[side] * 0.65')) {
    throw 'Forward calibration must preserve limb proportions and assign excess reach to bounded clavicle protraction.'
}
if (-not $source.Contains(
        'scripts/extension_systems/aim/third_person_idle_fullbody_animation_control') -or
        -not $source.Contains('self._idle_fullbody_value = 0')) {
    throw 'Local VR hub body must suppress lateral full-body idle variants.'
}
if (-not $source.Contains(
        'local pair_clamped_left = projected_tangent < overlap_min') -or
        -not $source.Contains(
            'local pair_clamped_right = projected_tangent > overlap_max') -or
        -not $source.Contains('local overlap_inset = overlap_width * 0.02')) {
    throw 'World markers must switch both eye draws to one inset binocular-overlap edge when either eye loses the marker.'
}
if (-not $source.Contains(
        'local billboard_shader_substitution_requested = true') -or
        -not $source.Contains(
            'local billboard_selector_probe_requested = false')) {
    throw 'Production cylindrical billboards must use shader substitution without the retired per-draw selector census.'
}
if (-not $source.Contains(
        'billboard_shader_substitution_requested or') -or
        -not $source.Contains(
            'billboard_selector_probe_requested or performance_profile_requested then')) {
    throw 'Production shader substitution must retain the early native-hook installation trigger.'
}
if (-not [regex]::IsMatch(
        $source,
        'dtvr_set_diagnostic_render_hooks\(\s*\(diagnostic_render_hooks_requested[\s\S]*?presentation\.performance_pass_trace_requested\)\s*and\s*1 or 0\)') -or
        [regex]::IsMatch(
            $source,
            'dtvr_set_diagnostic_render_hooks\([\s\S]{0,320}performance_profile_requested')) {
    throw 'Basic performance profiling must retain the production hook set; only explicit pass tracing may select broad diagnostic render hooks.'
}
if (-not $source.Contains('local shared_shadow_cull = true')) {
    throw 'Shared gameplay shadow/light culling must remain production-default with an explicit diagnostic opt-out.'
}
if (-not $source.Contains(
        'presentation.offline_dual_view_requested = startup.offline_dual_view') -or
        -not $source.Contains(
            'function presentation.apply_offline_benchmark_spin(rotation)') -or
        -not $source.Contains(
            'workload=hub_spin') -or
        -not $source.Contains(
            'clean_rotation = presentation.apply_offline_benchmark_spin(clean_rotation)')) {
    throw 'The no-headset performance fallback must retain exact dual-view rendering with a deterministic in-place hub spin.'
}
if (-not $source.Contains(
        'function presentation.update_stock_melee_animation_owner(self)') -or
        -not $source.Contains(
            'presentation.body_proxy.uses_stock_melee_animation(') -or
        -not $source.Contains(
            'controller_observation.stock_melee_animation_active') -or
        -not $source.Contains(
            'animation_owner=%s slot=%s action=%s kind=%s')) {
    throw 'Melee action ownership must use the behavior-tested policy and retain transition diagnostics.'
}
foreach ($shopTestView in @(
        'credits_vendor_background_view',
        'contracts_background_view',
        'live_events_view',
        'cosmetics_vendor_background_view',
        'barber_vendor_background_view',
        'penance_overview_view',
        'training_grounds_view',
        'training_grounds_options_view',
        'store_view')) {
    if (-not $source.Contains($shopTestView)) {
        throw "Guarded shop-family harness is missing $shopTestView."
    }
}
if (-not $source.Contains('native_aspect_shop_panel_views') -or
        -not $source.Contains('return 6, "native_aspect_shop_panel"') -or
        -not $source.Contains(
            'local shop_eye_layout = presentation.mode == 6 or')) {
    throw 'Native-aspect premium shops must keep landscape panel pixels separate from portrait widget coordinates.'
}
if (-not $source.Contains(
        'require("scripts/ui/views/store_view/store_view")') -or
        -not $source.Contains(
            'DARKTIDEVR_MENU_INPUT store_grid_activate') -or
        -not $source.Contains('interaction_hotspot.is_hover = true') -or
        -not $source.Contains(
            'input_service:null_service() or input_service')) {
    throw 'Premium store item cards must atomically retain portrait semantic focus without competing stock hover.'
}
if (-not $source.Contains(
        'function presentation.apply_menu_pointer_probe(pointer)') -or
        -not $source.Contains(
            '"^pointer_(%d+)_(%d+)_(%d+)_(%d+)$"') -or
        -not $source.Contains('probe.stage = "armed"')) {
    throw 'Unattended menu validation must retain a source-pixel pointer probe without Windows input injection.'
}
if (-not $source.Contains('local ui_mirror_client_width = 1920') -or
        -not $source.Contains('local ui_mirror_client_height = 1080')) {
    throw 'Interactive menu capture must retain a native 1080p 16:9 mirror source.'
}
if (-not $source.Contains('premium_currency_purchase_view = true')) {
    throw 'The 1920x1080 Aquila purchase child must retain the premium store native-aspect panel transform.'
}
if (-not $source.Contains('"attachment_item_name"') -or
        -not $source.Contains('attachment, "unit_name"')) {
    throw 'Garment inventory must retain attachment item and spawned resource identities.'
}
if (-not $source.Contains(
        'Viewport.set_data(primary, "shadow_cull_camera", primary_camera)') -or
        -not $source.Contains(
            'Viewport.set_data(right, "shadow_cull_camera", primary_camera)') -or
        $source.Contains('presentation.shared_visibility_camera_unit') -or
        $source.Contains('source=standalone_camera_unit')) {
    throw 'Both eyes must retain the measured tracked-primary shadow/light cull camera; the unproven standalone union camera must stay removed.'
}
if (-not $source.Contains(
        'SystemView is captured through a landscape client panel') -or
        -not $source.Contains(
            'local hit_pointer = presentation.vendor_eye_layout_pointer(pointer)') -or
        -not $source.Contains('self.view_name == "options_view"') -or
        -not $source.Contains(
            'self.view_name == "player_character_options_view"') -or
        -not $source.Contains(
            'widget.name == "grid_interaction" and') -or
        -not $source.Contains(
            'presentation.update_slider_drag(self, hit_pointer)')) {
    throw 'Escape-menu presentation pixels and portrait widget semantics must remain explicitly separated.'
}
if (-not $source.Contains(
        'tonumber(pointer.values[8]) or') -or
        -not $source.Contains(
            'permanently unconsumed press on every following UI pass')) {
    throw 'Synthetic menu probes must rejoin the native primary sequence after consumption.'
}
foreach ($pollGuard in @(
        'system_menu_test_poll_updates',
        'vendor_menu_test_poll_updates',
        'authoring_last_check_t',
        'movement_inventory_last_check_frame',
        'hotspot_inventory_last_poll_t')) {
    if (-not $source.Contains($pollGuard)) {
        throw "Diagnostic file polling must remain bounded: missing $pollGuard."
    }
}
foreach ($landingView in @(
        'contracts_background_view/contracts_background_view',
        'credits_vendor_background_view/credits_vendor_background_view',
        'cosmetics_vendor_background_view/cosmetics_vendor_background_view',
        'barber_vendor_background_view/barber_vendor_background_view')) {
    if (-not $source.Contains($landingView)) {
        throw "Missing concrete semantic XR-input hook for $landingView."
    }
}
if (-not $source.Contains(
        'function presentation.draw_vendor_landing_widgets(') -or
        -not $source.Contains('vendor_landing_activate')) {
    throw 'Shop landing views must retain the shared semantic XR-input owner.'
}
if (-not $source.Contains(
        'function presentation.neck_compensated_vertical') -or
        -not $source.Contains('body_ik_neck_baseline_arc') -or
        -not $source.Contains('body_ik_neck_anchor_local') -or
        -not $source.Contains('neutral_neck + tracked_shift') -or
        -not $source.Contains('head_pose_values[23]')) {
    throw 'Body IK must subtract the neck-pivot arc, rebase on XR recenter, and keep the hub torso attached to the tracked neck anchor.'
}
if ($source.Contains('Quaternion.right(anchor_rotation) * 0.06') -or
        $source.Contains('Quaternion.right(clean_rotation) * 0.06')) {
    throw 'Camera/body anchors must not carry the retired hardcoded 6 cm lateral calibration.'
}
if ($source.Contains('1.61 / 1.21') -or
        -not $source.Contains(
            'function presentation.calibrated_character_scale') -or
        -not $source.Contains(
            'function presentation.apply_calibrated_arm_length') -or
        -not $source.Contains('ffi.new("float[25]")') -or
        -not $source.Contains(
            'half_ipd = runtime_ipd * character_scale * 0.5')) {
    throw 'Avatar retargeting must preserve native human IPD, scale Ogryn tracking coherently, and apply a separate arm-bone residual.'
}
$calibrationSource = Get-Content -LiteralPath (
    Join-Path (Split-Path -Parent $resolvedSource) 'darktidevr_calibration.lua') -Raw
if (-not $calibrationSource.Contains(
        'service:set_character_height(character_id, target_scale)') -or
        -not $calibrationSource.Contains(
            'result.profile_height_status = "accepted"')) {
    throw 'Standing calibration must use the official backend profile-height path before visual residual scaling.'
}
$calibrationViewSource = Get-Content -LiteralPath (
    Join-Path (Split-Path -Parent $resolvedSource) `
        'darktidevr_calibration_view.lua') -Raw
if (-not $calibrationViewSource.Contains('schema = 4') -or
        -not $calibrationViewSource.Contains('capture_t_pose') -or
        -not $calibrationViewSource.Contains('capture_sides') -or
        $calibrationViewSource.Contains('capture_forward')) {
    throw 'Calibration must capture exactly the T-pose and arms-at-sides poses (schema 4); the forward-reach stage was retired with the third-person body.'
}
$controllerAimSource = Get-Content -LiteralPath (
    Join-Path (Split-Path -Parent $resolvedSource) `
        'darktidevr_controller_aim.lua') -Raw
if (-not $controllerAimSource.Contains(
        'MultiFireModes.simultaneous') -or
        -not $controllerAimSource.Contains(
            '(before + 1) % #configurations == 1') -or
        -not $controllerAimSource.Contains(
            'controller_aim.reused_simultaneous_shots') -or
        -not $controllerAimSource.Contains(
            'fx_extension.vfx_spawner_unit_and_node') -or
        -not $controllerAimSource.Contains(
            'return with_first_person_pose(action, position, rotation, func, ...)') -or
        -not $controllerAimSource.Contains(
            'local results = packed(controller_aim.with_ranged_pose(action, func, ...))')) {
    throw 'Controller-authored fire must preserve simultaneous-shot ownership and use the live third-person weapon muzzle with a stock-origin fallback.'
}
if (-not $source.Contains(
        'function presentation.left_controller_aim_target()') -or
        -not $source.Contains(
            'controller_observation.values[0]') -or
        -not $controllerAimSource.Contains(
            'settings and settings.use_charge') -or
        -not $controllerAimSource.Contains(
            'return position, rotation, "staff_tip_converged_aim"') -or
        -not $controllerAimSource.Contains(
            'return left_position, rotation, "support_origin_converged_aim"') -or
        -not $controllerAimSource.Contains(
            'controller_aim.reticle_world_point = Vector3Box(position + direction * distance)') -or
        -not $controllerAimSource.Contains(
            'local delta = point - origin') -or
        -not $controllerAimSource.Contains(
            'rotation = controller_aim.converged_rotation(') -or
        -not $controllerAimSource.Contains(
            'action_spawn_projectile') -or
        -not $controllerAimSource.Contains(
            'chain_lightning_targeting_action_module') -or
        -not $controllerAimSource.Contains(
            'player_unit_smart_targeting_extension')) {
    throw 'Psyker ranged coverage must retain both controller poses, a shared dominant-hand world aim point, converged support/staff-tip/muzzle origins and controller-scoped lightning targeting.'
}
$hudPanelSource = Get-Content -LiteralPath (
    Join-Path (Split-Path -Parent $resolvedSource) `
        'darktidevr_hud_panel.lua') -Raw
if (-not $hudPanelSource.Contains(
        'local scale = RESOLUTION_LOOKUP and RESOLUTION_LOOKUP.scale or 1') -or
        -not $hudPanelSource.Contains(
            'self._ui_renderer = resource_renderer') -or
        -not $hudPanelSource.Contains(
            'World.create_world_gui,') -or
        -not $hudPanelSource.Contains(
            'UIRenderer.create_viewport_renderer,') -or
        -not $hudPanelSource.Contains(
            'UIRenderer.create_resource_renderer,') -or
        -not $hudPanelSource.Contains(
            'UIRenderer.clear_render_pass_queue(state.queue_renderer)') -or
        -not $hudPanelSource.Contains(
            'UIRenderer.add_render_pass(state.queue_renderer, 0,') -or
        -not $hudPanelSource.Contains(
            'transfer_fixed_records(owner, source_renderer, resource_renderer, mod)') -or
        -not $hudPanelSource.Contains(
            'Renderer.copy_render_target_rect,') -or
        -not $hudPanelSource.Contains(
            'Material.set_resource(material, "render_target", display_target)') -or
        -not $hudPanelSource.Contains(
            'Gui2.bitmap_3d(') -or
        -not $hudPanelSource.Contains(
            'local height = HudPanel.height * HudPanel.scale') -or
        -not $hudPanelSource.Contains('state.panel_aspect = width / height')) {
    throw 'Fixed HUD must use one authoritative draw, preserve spatial elements on the stock renderer, retain dedicated queue/resource ownership and present the completed target with configured panel dimensions.'
}
if ($hudPanelSource -match 'Material\.set_resource\s*\(\s*material\s*,\s*"(?:source|render_target)"\s*,\s*resource_renderer\.render_target\s*\)') {
    throw 'Fixed HUD must never sample its in-flight render target; worn hardware proved that aliases the binocular world render into the panel.'
}
$advanceHelperPath = Join-Path $repoRoot `
    'tools\stereo\advance-darktide-to-hub.ps1'
$advanceHelperSource = Get-Content -LiteralPath $advanceHelperPath -Raw
if (-not $advanceHelperSource.Contains(
        'function Wait-DarktideLeavesTitle') -or
        -not $advanceHelperSource.Contains(
        'function Assert-DarktideStartupOwner') -or
        -not $advanceHelperSource.Contains('$_.Path -ieq $resolvedGameExe') -or
        -not $advanceHelperSource.Contains(
            'Wait-DarktideLeavesTitle -Process $title') -or
        -not $advanceHelperSource.Contains(
            "'Entering Game State StateLoading'") -or
        -not $advanceHelperSource.Contains(
            'DARKTIDEVR_STARTUP character_select=start_requested source=one_shot') -or
        $advanceHelperSource.Contains('Wait-DarktideLeavesCharacterSelect -Process $characterSelect')) {
    throw 'Authenticated unattended launch must retain process/log ownership, retry title Space and observe stock character-select readiness without replaying Enter.'
}
$startHelperPath = Join-Path $repoRoot 'tools\stereo\start-darktide-vr.ps1'
$startHelperSource = Get-Content -LiteralPath $startHelperPath -Raw
if (-not $startHelperSource.Contains('[switch] $OfflineDualViewBenchmark') -or
        -not $startHelperSource.Contains(
            'StateGameplay:on_enter\(\): hub_ship') -or
        -not $startHelperSource.Contains(
            'Restored the prior offline dual-view benchmark flag.')) {
    throw 'The launcher must retain a run-scoped, hub-gated no-headset dual-view benchmark and restore its flag.'
}
if ($startHelperSource -match
        'if \(\$OfflineDualViewBenchmark\)[\s\S]{0,420}\$EnablePerformanceProfile\s*=\s*\$true' -or
        $source -match
        'if presentation\.offline_dual_view_requested then\s*performance_profile_requested = true') {
    throw 'The offline dual-view baseline must not enable intrusive GPU profiling implicitly.'
}
$syncHelperPath = Join-Path $repoRoot 'tools\stereo\sync-darktide-vr-dev.ps1'
$syncHelperSource = Get-Content -LiteralPath $syncHelperPath -Raw
foreach ($diagnosticFlag in @(
        'darktidevr_body_ik_trace.flag',
        'darktidevr_coincident_eyes.flag',
        'darktidevr_full_second_eye.flag',
        'darktidevr_inherit_viewport_metadata.flag',
        'darktidevr_offline_dual_view.flag',
        'darktidevr_performance_pass_trace.flag',
        'darktidevr_performance_profile.flag',
        'darktidevr_reverse_eye_order.flag',
        'darktidevr_weapon_pose_trace.flag',
        'darktidevr_weapon_presentation.flag')) {
    if (-not $syncHelperSource.Contains("'$diagnosticFlag'")) {
        throw "Normal deployment must explicitly disable diagnostic flag $diagnosticFlag."
    }
}
if (-not $startHelperSource.Contains('[switch] $SyntheticRuntimeFrusta') -or
        -not $startHelperSource.Contains(
            "'-SyntheticRuntimeFrusta requires -OfflineDualViewBenchmark.'") -or
        -not $startHelperSource.Contains(
            'darktidevr-synthetic-head-publisher.exe') -or
        -not $startHelperSource.Contains(
            "'Stopped the run-owned synthetic head publisher.'")) {
    throw 'The asymmetric offline lighting probe must own a bounded synthetic runtime-frustum publisher.'
}
$syntheticHeadPublisherPath = Join-Path $repoRoot `
    'tests\xr_harness\synthetic_head_publisher.cpp'
$syntheticHeadPublisherSource = Get-Content -LiteralPath `
    $syntheticHeadPublisherPath -Raw
if (-not $syntheticHeadPublisherSource.Contains(
        '{-0.942478F, 0.698132F, -0.959931F, 0.767945F}') -or
        -not $syntheticHeadPublisherSource.Contains(
            '{-0.698132F, 0.942478F, -0.959931F, 0.767945F}') -or
        -not $syntheticHeadPublisherSource.Contains(
            'sample.render_aspect_ratio = 2112.0F / 2304.0F;')) {
    throw 'The synthetic lighting probe must retain the captured VirtualDesktopXR Medium asymmetric frusta and render aspect.'
}
if (-not $startHelperSource.Contains(
        '[switch] $CaptureBillboardPsoIdentities') -or
        -not $startHelperSource.Contains('$DiagnosticRenderHooks = $true') -or
        -not $startHelperSource.Contains(
            'darktidevr-billboard-pso-identity.tsv') -or
        -not $startHelperSource.Contains('$sourceStream.Seek(') -or
        -not $startHelperSource.Contains(
            'Captured run-scoped billboard PSO identities')) {
    throw 'Launcher must retain diagnostic-hook opt-in and non-destructive, byte-offset billboard identity slicing for scene comparisons.'
}
$nativeCapturePath = Join-Path $repoRoot 'src\producer\native_capture.cpp'
$nativeCaptureSource = Get-Content -LiteralPath $nativeCapturePath -Raw
$d3d12BootstrapPath = Join-Path $repoRoot 'src\producer\d3d12_bootstrap.cpp'
$d3d12BootstrapSource = Get-Content -LiteralPath $d3d12BootstrapPath -Raw
if (-not $source.Contains(
        'cluster_light_visibility_fix_active = false') -or
        -not $source.Contains(
            'dtvr_cluster_light_visibility_fix_active(void)') -or
        -not $source.Contains(
            'if presentation.cluster_light_visibility_fix_active then') -or
        -not $source.Contains(
            'presentation.projection_math.binocular_visibility_scale(left, right_eye)') -or
        -not $nativeCaptureSource.Contains(
            'constexpr std::uint64_t kClusterLightRasterVertexShader =') -or
        -not $nativeCaptureSource.Contains('0x5c6cd369626f261aULL') -or
        -not $nativeCaptureSource.Contains('0xbe559cb63c32aa02ULL') -or
        -not $nativeCaptureSource.Contains(
            'queue_cluster_light_visibility_fov_patches(commands)') -or
        -not $nativeCaptureSource.Contains(
            'pending.resource_offset + kRasterFovOffset') -or
        -not $nativeCaptureSource.Contains(
            'render_vertical_fov_radians.load(std::memory_order_relaxed)') -or
        -not $nativeCaptureSource.Contains(
            'cluster_light_visibility_fix_active.store(') -or
        -not $d3d12BootstrapSource.Contains(
            'darktidevr_cluster_light_visibility_fix.flag') -or
        -not $d3d12BootstrapSource.Contains(
            'dtvr_set_cluster_light_visibility_fix') -or
        -not $syncSource.Contains(
            '[bool] $ClusterLightVisibilityFix = $true') -or
        -not $syncSource.Contains(
            'darktidevr_cluster_light_visibility_fix.flag')) {
    throw 'Cluster-light visibility correction must remain a paired, exact-shader, bootstrap-gated engine-frustum and staged-FOV fix.'
}
$clusterRootBindingStart = $nativeCaptureSource.IndexOf(
    'void set_graphics_root_gpu_address(')
$clusterRootBindingEnd = $nativeCaptureSource.IndexOf(
    'void set_compute_root_gpu_address(', $clusterRootBindingStart)
if ($clusterRootBindingStart -lt 0 -or
        $clusterRootBindingEnd -le $clusterRootBindingStart -or
        -not $nativeCaptureSource.Substring(
            $clusterRootBindingStart,
            $clusterRootBindingEnd - $clusterRootBindingStart).Contains(
                'cluster_light_visibility_fix_active.load(')) {
    throw 'The production cluster-light hook must retain direct graphics CBV bindings for its exact target draw.'
}
$virtualSizeSetterStart = $nativeCaptureSource.IndexOf(
    'dtvr_set_virtual_size_message(')
$virtualSizeSetterEnd = $nativeCaptureSource.IndexOf(
    'dtvr_lock_swapchain_client_extent(', $virtualSizeSetterStart)
if ($virtualSizeSetterStart -lt 0 -or
        $virtualSizeSetterEnd -le $virtualSizeSetterStart) {
    throw 'Native virtual-size configuration export could not be located.'
}
$virtualSizeSetterSource = $nativeCaptureSource.Substring(
    $virtualSizeSetterStart,
    $virtualSizeSetterEnd - $virtualSizeSetterStart)
$virtualSizeEnableIndex = $virtualSizeSetterSource.IndexOf(
    'virtual_size_message_enabled.store(')
$virtualWndProcInstallIndex = $virtualSizeSetterSource.IndexOf(
    'ensure_virtual_window_proc(')
if ($virtualSizeEnableIndex -lt 0 -or
        $virtualWndProcInstallIndex -le $virtualSizeEnableIndex) {
    throw 'Enabling virtual WM_SIZE must install the game-window procedure immediately, before the startup client-area nudge can run.'
}
$questWatcherPath = Join-Path $repoRoot 'tools\quest\watch-quest-online.ps1'
$questProximityPath = Join-Path $repoRoot 'tools\quest\set-proximity-override.ps1'
$questWatcherSource = Get-Content -LiteralPath $questWatcherPath -Raw
$questProximitySource = Get-Content -LiteralPath $questProximityPath -Raw
if (-not $questWatcherSource.Contains('-AdbPath $activeAdb') -or
        -not $questProximitySource.Contains('[string] $AdbPath') -or
        -not $questProximitySource.Contains('$adb = $AdbPath')) {
    throw 'Quest detection and proximity override must use the same verified ADB client.'
}
$gameplayInputPath = Join-Path $repoRoot 'src\core\gameplay_input.cpp'
$gameplayInputSource = Get-Content -LiteralPath $gameplayInputPath -Raw
$headPosePath = Join-Path $repoRoot 'src\core\shared_head_pose.cpp'
$headPoseSource = Get-Content -LiteralPath $headPosePath -Raw
$headPoseEpochIndex = $headPoseSource.IndexOf(
    'InterlockedExchange64(&data.epoch, 1);')
$headPoseGenerationIndex = $headPoseSource.IndexOf(
    'InterlockedIncrement64(&data.writer_generation);')
if ($headPoseEpochIndex -lt 0 -or $headPoseGenerationIndex -lt 0 -or
        $headPoseEpochIndex -gt $headPoseGenerationIndex) {
    throw 'Head-pose writer restart must mark its seqlock odd before publishing a new writer generation.'
}
$executeHookStart = $nativeCaptureSource.IndexOf(
    'void STDMETHODCALLTYPE execute_command_lists_hook(')
$executeHookEnd = $nativeCaptureSource.IndexOf(
    'HRESULT STDMETHODCALLTYPE present_hook', $executeHookStart)
if ($executeHookStart -lt 0 -or $executeHookEnd -le $executeHookStart) {
    throw 'Native command-list execution hook could not be located.'
}
$executeHookSource = $nativeCaptureSource.Substring(
    $executeHookStart, $executeHookEnd - $executeHookStart)
if ($executeHookSource.Contains('direct_menu_render_lists.erase')) {
    throw 'Direct-menu resources must remain retained after submission until a successful command-list Reset proves the old recording was retired.'
}
$resetHookStart = $nativeCaptureSource.IndexOf(
    'HRESULT STDMETHODCALLTYPE reset_hook(')
$resetHookEnd = $nativeCaptureSource.IndexOf(
    'void STDMETHODCALLTYPE execute_bundle_hook', $resetHookStart)
if ($resetHookStart -lt 0 -or $resetHookEnd -le $resetHookStart) {
    throw 'Native command-list reset hook could not be located.'
}
$resetHookSource = $nativeCaptureSource.Substring(
    $resetHookStart, $resetHookEnd - $resetHookStart)
$resetCallIndex = $resetHookSource.IndexOf(
    'const auto reset_result = original_reset(')
$menuReleaseIndex = $resetHookSource.IndexOf(
    'direct_menu_render_lists.erase(commands)')
if ($resetCallIndex -lt 0 -or $menuReleaseIndex -le $resetCallIndex) {
    throw 'Direct-menu resources must only be released after command-list Reset succeeds.'
}
if ($resetHookSource.IndexOf('menu_output_resources.erase(commands)') -le
        $resetCallIndex -or
        $resetHookSource.IndexOf(
            'menu_output_source_states.erase(commands)') -le $resetCallIndex) {
    throw 'A successful command-list Reset must retire menu completion state from the discarded recording.'
}
if (-not $nativeCaptureSource.Contains(
        'std::atomic<bool> game_swapchain_metadata_ready{};') -or
        -not $nativeCaptureSource.Contains(
            'const bool refresh_swapchain_metadata =') -or
        -not $nativeCaptureSource.Contains(
            'game_swapchain_metadata_ready.store(false, std::memory_order_release);') -or
        -not $nativeCaptureSource.Contains(
            'const bool complete_buffer_set =')) {
    throw 'Present must retain its resize-invalidated swapchain metadata cache and reject partial back-buffer enumeration.'
}
if (-not $nativeCaptureSource.Contains('if (present == 1 || present % 30 == 0)')) {
    throw 'Focused trace request files must be polled at diagnostic cadence, not on every Present.'
}
if (-not $startHelperSource.Contains('[switch] $StreamlineProbe') -or
        -not $startHelperSource.Contains('[switch] $StreamlineCopyProbe') -or
        -not $startHelperSource.Contains(
            '[switch] $StreamlineTransportProbe') -or
        -not $startHelperSource.Contains(
            '[switch] $StreamlineInputSnapshotProbe') -or
        -not $startHelperSource.Contains(
            '[switch] $StreamlineTargetTokenProbe') -or
        -not $startHelperSource.Contains(
            '[switch] $StreamlineStereoSwapchainProbe') -or
        -not $startHelperSource.Contains(
            '$streamlineTargetTokenProbeFlagPath = $null') -or
        -not $startHelperSource.Contains(
            '$streamlineStereoSwapchainProbeFlagPath = $null') -or
        -not $startHelperSource.Contains(
            'darktidevr_streamline_probe.flag') -or
        -not $startHelperSource.Contains(
            'darktidevr_streamline_copy_probe.flag') -or
        -not $startHelperSource.Contains(
            'darktidevr_streamline_transport_probe.flag') -or
        -not $startHelperSource.Contains(
            'darktidevr_streamline_input_snapshot_probe.flag') -or
        -not $startHelperSource.Contains(
            'darktidevr_streamline_target_token_probe.flag') -or
        -not $startHelperSource.Contains(
            'darktidevr_streamline_stereo_swapchain_probe.flag') -or
        -not $nativeCaptureSource.Contains(
            'PROBE\tmode=%s\tsdk_abi=2.7.30') -or
        -not $nativeCaptureSource.Contains(
            'dlssg_state_query=existing_calls_plus_bounded_present_probe') -or
        -not $nativeCaptureSource.Contains(
            'independent_state_call_budget=%u') -or
        -not $nativeCaptureSource.Contains(
            'initialize_streamline_probe(swapchain_vtable[8],') -or
        -not $nativeCaptureSource.Contains(
            'result = original(viewport, state, options);') -or
        -not $nativeCaptureSource.Contains(
            'DLSSG_STATE\tcall=%llu\tpresent_frame=%llu') -or
        -not $nativeCaptureSource.Contains(
            'result = original(viewport, options);') -or
        -not $nativeCaptureSource.Contains(
            'DLSSG_OPTIONS\tcall=%llu\tpresent_frame=%llu') -or
        -not $nativeCaptureSource.Contains(
            'NATIVE_PRESENT_TARGET\taddress=%p\tmodule=%p\tversion=%s') -or
        -not $nativeCaptureSource.Contains(
            'NATIVE_PRESENT_BEGIN\tcall=%llu\touter_frame=%llu') -or
        -not $nativeCaptureSource.Contains(
            '\tclass=%s\tactive_outer_frame=%llu') -or
        -not $nativeCaptureSource.Contains(
            'streamline_native_burst_until_call.compare_exchange_strong(') -or
        -not $nativeCaptureSource.Contains(
            'FRAME_TOKEN\tcall=%llu\tpresent_frame=%llu\tthread=%lu') -or
        -not $nativeCaptureSource.Contains(
            'SET_CONSTANTS\tcall=%llu\tpresent_frame=%llu\tthread=%lu') -or
        -not $nativeCaptureSource.Contains(
            'MH_CreateHook(streamline_get_new_frame_token_target,') -or
        -not $nativeCaptureSource.Contains(
            'MH_CreateHook(streamline_set_constants_target,') -or
        -not $nativeCaptureSource.Contains(
            '\tframe_token_call=%llu\tframe_token=%p\tframe_index=%u') -or
        -not $nativeCaptureSource.Contains(
            '\tgenerated_candidate=%u\tgenerator_execute_call=%llu') -or
        -not $nativeCaptureSource.Contains(
            '\tgenerator_queue=%p\tgenerator_execute_delta_us=%lld') -or
        -not $nativeCaptureSource.Contains(
            'is_streamline_generated_present_candidate(') -or
        -not $nativeCaptureSource.Contains(
            '\tback_buffer_index=%u\tback_buffer=%p\twidth=%llu') -or
        -not $nativeCaptureSource.Contains(
            '\tlast_execute_queue=%p\tlast_execute_queue_type=%u') -or
        -not $nativeCaptureSource.Contains(
            '\tlast_execute_list_count=%u\tlast_execute_delta_us=%lld') -or
        -not $nativeCaptureSource.Contains(
            'EXECUTE_PRECURSOR\tnative_call=%llu\touter_frame=%llu') -or
        -not $nativeCaptureSource.Contains(
            '\tpresent_transition=%u\tdelta_us=%lld') -or
        -not $nativeCaptureSource.Contains(
            'GENERATED_COPY_SCHEDULE\tresult=submitted') -or
        -not $nativeCaptureSource.Contains(
            '\tqueue_source=swapchain_present_transition') -or
        -not $nativeCaptureSource.Contains(
            'observed_present_queue = swapchain_present_queue;') -or
        -not $nativeCaptureSource.Contains(
            'GENERATED_COPY_COMPLETE\tresult=success') -or
        -not $nativeCaptureSource.Contains(
            'darktidevr::core::kSharedGeneratedFrameSlotCount;') -or
        -not $nativeCaptureSource.Contains(
            'constexpr std::uint64_t kStreamlineTransportSubmissionLimit = 120;') -or
        -not $nativeCaptureSource.Contains(
            'GENERATED_TRANSPORT_SUBMIT\tslot=%zu\tnative_call=%llu') -or
        -not $nativeCaptureSource.Contains(
            'GENERATED_TRANSPORT_COMPLETE\tslot=%zu\tnative_call=%llu') -or
        -not $nativeCaptureSource.Contains(
            'GENERATED_TRANSPORT_DROP\treason=ring_full') -or
        -not $nativeCaptureSource.Contains(
            'schedule_streamline_transport_probe(') -or
        -not $nativeCaptureSource.Contains(
            'D3D12_HEAP_FLAG_SHARED, &destination') -or
        -not $nativeCaptureSource.Contains(
            'streamline_transport_consumed_fence->GetCompletedValue()') -or
        -not $nativeCaptureSource.Contains(
            'publish_streamline_transport_metadata(') -or
        -not $nativeCaptureSource.Contains(
            'GetProcAddress(interposer, "slSetTagForFrame")') -or
        -not $nativeCaptureSource.Contains(
            'log_streamline_resource_tags(') -or
        -not $nativeCaptureSource.Contains(
            'original_sl_set_tag_for_frame(') -or
        -not $nativeCaptureSource.Contains(
            'SET_CONSTANTS_MATRIX\tcall=%llu\tviewport=%u\ttoken=%p') -or
        -not $nativeCaptureSource.Contains(
            '\tdepth_inverted=%d\tcamera_motion_included=%d\tmvec_3d=%d') -or
        -not $nativeCaptureSource.Contains(
            '\tframe_index=%u\tviewport=%u\tconstants=%p') -or
        -not $nativeCaptureSource.Contains(
            'constexpr std::size_t kStreamlineFrameTokenHistorySize = 16;') -or
        -not $nativeCaptureSource.Contains(
            'first_call == second_call && candidate == frame') -or
        -not $nativeCaptureSource.Contains(
            'original_sl_set_constants(constants, frame, viewport)') -or
        -not $nativeCaptureSource.Contains(
            'if (constants_state && armed_eye >= 0) {') -or
        -not $nativeCaptureSource.Contains(
            'EYE_OUTPUT_BOUNDARY\tphase=execute_begin') -or
        -not $nativeCaptureSource.Contains(
            'EYE_OUTPUT_BOUNDARY\tphase=capture_complete') -or
        -not $nativeCaptureSource.Contains(
            'INPUT_SNAPSHOT\tphase=complete') -or
        -not $nativeCaptureSource.Contains(
            'INPUT_SNAPSHOT_BINDING\tpresent_frame=%llu') -or
        -not $nativeCaptureSource.Contains(
            'INPUT_SNAPSHOT_READBACK\tphase=complete') -or
        -not $nativeCaptureSource.Contains(
            'INPUT_SNAPSHOT_SAMPLE\tpresent_frame=%llu') -or
        -not $nativeCaptureSource.Contains(
            'STEREO_BACKBUFFER\tphase=complete') -or
        -not $nativeCaptureSource.Contains(
            'STEREO_TRANSPORT_RESERVATION\tphase=reserved') -or
        -not $nativeCaptureSource.Contains(
            'STEREO_TARGET_TOKEN\tphase=allocated') -or
        -not $nativeCaptureSource.Contains(
            'generation_present_submitted=0') -or
        -not $nativeCaptureSource.Contains(
            'const auto result = original_sl_get_new_frame_token(') -or
        -not $nativeCaptureSource.Contains(
            'evaluate_streamline_stereo_inputs(') -or
        -not $nativeCaptureSource.Contains(
            'original_execute_command_lists(queue, 1, lists);') -or
        -not $nativeCaptureSource.Contains(
            'streamline_native_present_count.load(std::memory_order_relaxed)') -or
        -not $nativeCaptureSource.Contains(
            '(present <= 5 || present % 120 == 0)')) {
    throw 'The Streamline diagnostics must remain launch-scoped with bounded independent state probes, forward stock calls and retain generated-frame transport ownership.'
}
if (-not $nativeCaptureSource.Contains(
        'std::atomic<bool> named_camera_outputs_ready_hint{};') -or
        -not $nativeCaptureSource.Contains(
            '!named_camera_outputs_ready_hint.load(std::memory_order_acquire)') -or
        -not $nativeCaptureSource.Contains(
            'named_camera_outputs_ready_hint.store(false, std::memory_order_release);')) {
    throw 'Production RTV binding inspection must stop after explicit eye outputs are learned and resume after resize.'
}
# The enhanced-barrier interest test moved into enhanced_barrier_interest.h
# (7dfa753); the legacy hook keeps its own transition-only gate.
if (-not $nativeCaptureSource.Contains('bool has_transition_barrier{};') -or
        -not $nativeCaptureSource.Contains('if (has_transition_barrier) {') -or
        -not $nativeCaptureSource.Contains('#include "producer/enhanced_barrier_interest.h"') -or
        -not $nativeCaptureSource.Contains('enhanced_barriers_need_capture_lock(')) {
    throw 'Native barrier hooks must avoid the shared capture mutex for legacy non-transition and enhanced non-texture-only batches.'
}
if (-not $nativeCaptureSource.Contains(
        'std::atomic<ID3D12CommandQueue*> game_queue_identity{};') -or
        -not $nativeCaptureSource.Contains('queue == known_game_queue') -or
        -not $nativeCaptureSource.Contains(
            'game_queue_identity.store(queue, std::memory_order_release);') -or
        $nativeCaptureSource.Contains('swapchain_write_resources')) {
    throw 'ExecuteCommandLists must cache the retained direct queue identity and must not maintain an unread swapchain-write map.'
}
if (-not $nativeCaptureSource.Contains(
        'if (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed)) {') -or
        -not $nativeCaptureSource.Contains(
            'execute_call_count.fetch_add(1, std::memory_order_relaxed);')) {
    throw 'Production queue and barrier telemetry atomics must remain disabled when diagnostic render hooks were not selected.'
}
if (-not [regex]::IsMatch(
        $nativeCaptureSource,
        '\(\(kInstallDiagnosticRenderHooks\s*\|\|\s*install_cluster_trace_hooks\s*\|\|\s*install_cluster_light_visibility_fix_hooks\)\s*&&\s*MH_CreateHook\(command_list_vtable\[13\],\s*&draw_indexed_instanced_hook,')) {
    throw 'Indexed-draw interception must remain limited to broad diagnostics, the explicit cluster trace, or the exact cluster-light correction; never stock menu capture alone.'
}
if (-not $source.Contains('last_mode_publish_t = -math.huge') -or
        -not $source.Contains('now - presentation.last_mode_publish_t >= 0.5') -or
        -not $source.Contains('distinguish a healthy mod from a stopped') -or
        -not $nativeCaptureSource.Contains('publish_presentation_state(state)')) {
    throw 'Presentation state must retain an unchanged-mode heartbeat for stale-consumer failover.'
}
if (-not $source.Contains('dtvr_read_controller_state_v2') -or
        -not $source.Contains('last_transport_generation = controller_generation')) {
    throw 'Controller state must use an explicit writer generation across XR restarts.'
}
if (-not $source.Contains('dtvr_read_head_pose_v2') -or
        -not $source.Contains('head_pose_last_transport_generation') -or
        -not $source.Contains('presentation.read_head_pose()') -or
        -not $nativeCaptureSource.Contains('dtvr_read_head_pose_v2(')) {
    throw 'Head-pose state must expose and consume a writer generation so equal restart sequences reset capture tags.'
}
if (-not $gameplayInputSource.Contains(
        'const auto transport_changed = controllers.transport_generation != 0') -or
        -not $gameplayInputSource.Contains(
            'if (!active_ || transport_changed) blocked_until_release_ = next;') -or
        -not $gameplayInputSource.Contains('blocked_until_release_ &= next;') -or
        -not $gameplayInputSource.Contains('next &= ~blocked_until_release_;')) {
    throw 'Gameplay input must baseline held buttons across a controller-writer generation change without synthesizing press edges.'
}
# The off hand, not the left one: the saved setting still stores "left_hand"
# but the code behind it asks for the role (handedness audit, 16 September).
if (-not $source.Contains(
        'function presentation.off_hand_movement_rotation()') -or
        -not $source.Contains(
            'presentation.hand_aim_usable("support")') -or
        -not $source.Contains(
            'function presentation.movement_reference_rotation()') -or
        -not $source.Contains(
            'function presentation.rotate_controller_movement(x, y)') -or
        -not $source.Contains(
            'Vector3.length_squared(flat_forward) < 0.0025') -or
        -not $source.Contains(
            'mod:get("movement_reference") or "head"') -or
        -not $source.Contains(
            'Quaternion.inverse(presentation.flat_movement_rotation(')) {
    throw 'Configurable VR locomotion must preserve headset-relative default, use the flattened live off-hand basis without an Euler round-trip, reject near-vertical rays and rotate only controller movement into the selected frame.'
}
if (-not $source.Contains(
        'presentation.menu_pointer.values = ffi.new("unsigned int[13]")') -or
        -not $source.Contains('dtvr_read_menu_pointer_state_v3(') -or
        -not $source.Contains(
            'pointer.secondary_consumed_sequence = secondary_press_sequence') -or
        -not $source.Contains('dtvr_read_menu_pointer_state_v2(') -or
        -not $source.Contains(
            'menu_pointer_v2 or library.dtvr_read_menu_pointer_state') -or
        -not $source.Contains(
            'transport_generation_unavailable fallback=v1') -or
        -not $source.Contains(
            'transport_generation ~= pointer.transport_generation') -or
        -not $source.Contains(
            'pointer.primary_consumed_sequence = primary_press_sequence') -or
        -not $source.Contains(
            'pointer.back_consumed_sequence = back_press_sequence') -or
        -not $source.Contains(
            'pointer.scroll_consumed_sequence = scroll_sequence')) {
    throw 'Menu pointer transport restarts must baseline edge counters instead of synthesizing input.'
}
if (-not $source.Contains(
        'Quaternion.right(clean_rotation) * local_x') -or
        -not $source.Contains(
            'Quaternion.forward(clean_rotation) * local_y') -or
        $source.Contains('head_translation_basis_qw')) {
    throw 'Room-scale translation must preserve the proven clean-camera local basis and must not rotate the already-local OpenXR delta through a second cached yaw.'
}
if (-not $source.Contains(
        'active_base_rotation:unbox() or locomotion_component.rotation') -or
        $source.Contains(
            'local body_rotation = locomotion_component.rotation')) {
    throw 'Collision/body-follow transfer must use the same immutable XR scene basis as camera translation.'
}

# The lateral term is zeroed inside presentation.cyclopean_eye_offset, which
# measures in the avatar's own aim yaw frame so the eye's forward depth is not
# lost when the avatar faces across the recenter basis (animation audit K).
if (-not $source.Contains(
        'return Vector3(0, Vector3.y(local_offset), Vector3.z(local_offset))') -or
        -not $source.Contains('presentation.cyclopean_eye_offset(') -or
        -not $source.Contains('presentation.inverse_quaternion(yaw_only), offset)')) {
    throw 'The cyclopean body camera must remain on the avatar sagittal plane, measured in the aim yaw frame.'
}
if ($controllerAimSource.Contains('component.position = position') -or
        $controllerAimSource.Contains('component.rotation = rotation') -or
        -not $controllerAimSource.Contains(
            'action._first_person_component = proxy') -or
        -not $controllerAimSource.Contains(
            'action._first_person_component = component')) {
    throw 'Controller aim must never mutate Darktide read-only first_person components; use a scoped action-local read proxy and restore it.'
}
$hudPanelSource = Get-Content -LiteralPath (
    Join-Path (Split-Path -Parent $resolvedSource) `
        'darktidevr_hud_panel.lua') -Raw
if (-not $hudPanelSource.Contains('enabled = true,') -or
        -not $hudPanelSource.Contains('HudPanel.set_enabled(command ~= "disable")') -or
        -not $hudPanelSource.Contains(
            'transfer_fixed_records(state.owner, state.resource_renderer,') -or
        $hudPanelSource.Contains('begin_immediate_replay') -or
        $hudPanelSource.Contains('pass.retained_mode = false')) {
    throw 'Fixed HUD world rendering is the play default with a flag-file override, and must not replay or mutate retained widget modes.'
}
if (-not $source.Contains(
        'presentation.read_head_pose() ~= 0 then') -or
        -not $source.Contains(
            'return nil')) {
    throw 'Calibration must reject unavailable or stale native head-pose samples instead of reusing its FFI buffer.'
}

# Every mod:hook handler must be variadic, and every forward to the stock
# function must pass the tail on. A handler that names the stock signature
# silently drops anything the engine adds beyond it: the controller bindings
# lost the ninth argument of their sample that way and the item radial's stick
# claim went with it for a day (17 September).
#
# Two earlier versions of this check passed the defects it exists for, each
# time because it matched one spelling or one shape (reviews, 18 September).
# What it does now, and why each part is there:
#
#  * spacing is normalised, including before a bracket, because the modules
#    disagree about both;
#  * a handler is any function whose FIRST parameter is `func`, named or
#    anonymous, whatever the second is called, and its parameter list may
#    begin on the line after the bracket;
#  * a handler's body runs to where its Lua block depth returns to zero, not
#    to the first `end` at some indent -- a body indented level with its own
#    signature ended the scan after two lines;
#  * a forward is `func(...)`, `pcall(func, ...)`, or `func` handed to
#    ANYTHING as a bare argument, because the marker routing passes it to a
#    profiler section which passes it on again;
#  * and a forward is flagged whenever it carries no literal and does not end
#    in `...`, whatever its length or order. Requiring the argument count to
#    match the parameter list exempted dropping an argument AND the tail,
#    which is precisely the bug this exists for.
#
# The exemption is literals only: `func(location, false)` in the visual
# settings deliberately overrides the value it was handed, and forwarding a
# tail after it would pass the value being overridden. A guard that blocks a
# legitimate change is worse than none.
#
# tools/lua/mutate-hook-arity.py puts the real failures through this and every
# one must be caught.
$hookedSources = @($resolvedSource)
$hookedSources += @(Get-ChildItem -LiteralPath (Split-Path -Parent $resolvedSource) `
    -Filter 'darktidevr_*.lua' | ForEach-Object { $_.FullName })
$fixedArity = @()
$droppedTail = @()

function Get-CallArguments {
    # The argument list of the call opening at $at in $text, brackets balanced,
    # or $null when it never closes.
    param([string] $Text, [int] $At)
    $open = $Text.IndexOf('(', $At)
    if ($open -lt 0) { return $null }
    $depth = 1
    for ($k = $open + 1; $k -lt $Text.Length; $k++) {
        $ch = $Text[$k]
        if ($ch -eq '(') { $depth++ }
        elseif ($ch -eq ')') {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($open + 1, $k - $open - 1) }
        }
    }
    return $null
}

function Split-Arguments {
    # Top-level commas only: an argument may itself be a call.
    param([string] $Text)
    $parts = @()
    $depth = 0
    $current = ''
    foreach ($ch in $Text.ToCharArray()) {
        if ($ch -eq '(' -or $ch -eq '{' -or $ch -eq '[') { $depth++ }
        elseif ($ch -eq ')' -or $ch -eq '}' -or $ch -eq ']') { $depth-- }
        if ($ch -eq ',' -and $depth -eq 0) {
            $parts += $current.Trim()
            $current = ''
        }
        else { $current += $ch }
    }
    if ($current.Trim() -ne '') { $parts += $current.Trim() }
    return ,$parts
}

function Test-IsLiteral {
    # A value the author wrote in place of what they were handed, rather than
    # a name they are passing along.
    param([string] $Argument)
    if ($Argument -in @('true', 'false', 'nil')) { return $true }
    if ($Argument -match '^-?[0-9]') { return $true }
    if ($Argument.StartsWith('"') -or $Argument.StartsWith("'")) { return $true }
    if ($Argument.StartsWith('{') -or $Argument.StartsWith('[')) { return $true }
    return $false
}

function Measure-BlockDelta {
    # Lua block openers minus closers on one line. `do` covers `for`/`while`,
    # `if` covers itself (elseif continues a block rather than opening one).
    param([string] $Line)
    $text = $Line -replace '\belseif\b', ' '
    $open = ([regex]::Matches($text, '\bfunction\b')).Count +
            ([regex]::Matches($text, '\bdo\b')).Count +
            ([regex]::Matches($text, '\bif\b')).Count +
            ([regex]::Matches($text, '\brepeat\b')).Count
    $close = ([regex]::Matches($text, '\bend\b')).Count +
             ([regex]::Matches($text, '\buntil\b')).Count
    return $open - $close
}

foreach ($hookedSource in $hookedSources) {
    $where = Split-Path -Leaf $hookedSource
    $raw = @(Get-Content -LiteralPath $hookedSource)
    # Strip line comments so prose is not a finding, collapse the space after a
    # comma and before a bracket so both house styles match.
    $flat = @($raw | ForEach-Object {
        $withoutComment = $_ -replace '--.*$', ''
        # Empty every string literal. `if type(callback) == "function" then`
        # counted as two block openers, so one handler's body ran on for 3886
        # lines and swallowed every handler inside it -- three real mutations
        # passed because of it (review, 18 September). It also keeps a bracket
        # inside a string out of the balancer.
        $withoutComment = $withoutComment -replace '"[^"]*"', '""'
        $withoutComment = $withoutComment -replace "'[^']*'", "''"
        $withoutComment = $withoutComment -replace ',\s+', ','
        $withoutComment -replace '([A-Za-z_][A-Za-z0-9_]*)\s+\(', '$1('
    })
    for ($i = 0; $i -lt $flat.Count; $i++) {
        # The parameter list may start on the next line.
        $opener = $flat[$i]
        $joined = 0
        while ($opener -match 'function\s*[A-Za-z0-9_.:]*\s*\($' -and
                $joined -lt 2 -and ($i + $joined + 1) -lt $flat.Count) {
            $joined++
            $opener = $opener + $flat[$i + $joined]
        }
        # `func` leads. A helper that takes it later is not matched, so any
        # helper forwarding to the stock function puts `func` first -- see
        # `run` and `run_tag` in the input modules, which were reordered for
        # exactly this (18 September).
        if ($opener -notmatch 'function\s*[A-Za-z0-9_.:]*\s*\(func,') { continue }
        $signatureText = $opener
        $signature = Get-CallArguments -Text $signatureText -At $signatureText.IndexOf('(func,')
        $span = $joined
        while ($null -eq $signature -and $span -lt 5 -and ($i + $span + 1) -lt $flat.Count) {
            $span++
            $signatureText = $signatureText + ' ' + $flat[$i + $span]
            $signature = Get-CallArguments -Text $signatureText -At $signatureText.IndexOf('(func,')
        }
        if ($null -eq $signature) {
            throw ("A hook handler's signature never closes its brackets, so this check cannot read it: {0}:{1}" -f $where, ($i + 1))
        }
        # Everything after `func` itself: what the stock function is handed.
        $signatureParts = Split-Arguments -Text $signature
        $funcAt = [array]::IndexOf($signatureParts, 'func')
        if ($funcAt -lt 0) { continue }
        $parameters = if ($funcAt -eq ($signatureParts.Count - 1)) { '' }
            else { ($signatureParts[($funcAt + 1)..($signatureParts.Count - 1)]) -join ',' }
        if ($parameters -ne '' -and $parameters -notmatch '\.\.\.\s*$') {
            $fixedArity += ('{0}:{1}: function(...func,{2})' -f $where, ($i + 1), $parameters)
        }

        # The body, by Lua block depth: a handler whose body is indented level
        # with its own signature ended an indentation scan after two lines.
        $depth = 0
        $end = $i
        for ($j = $i; $j -lt $flat.Count; $j++) {
            # Never run into the next handler, whatever the depth count does:
            # a miscount there silently stops every later handler being seen.
            if ($j -gt $i -and $flat[$j] -match 'function\s*[A-Za-z0-9_.:]*\s*\(func,') {
                $end = $j - 1
                break
            }
            $depth += Measure-BlockDelta -Line $flat[$j]
            if ($j -gt $i -and $depth -le 0) { $end = $j; break }
            $end = $j
        }
        $body = ($flat[$i..$end] -join ' ')
        # A handler may say that a truncation is deliberate, for the case the
        # literal test cannot see: a value substituted by a NAME, where the
        # tail begins at the value being replaced and forwarding it would pass
        # the very thing being overridden. It has to be written down, because
        # it is indistinguishable from the bug otherwise (review,
        # 18 September).
        $annotated = (($raw[$i..$end] -join ' ') -match 'arity: deliberate')

        # Forwards: func(...), pcall(func,...), and func handed to anything as
        # a bare argument, which is how the marker routing reaches it.
        $forwards = @()
        $from = 0
        while ($true) {
            $at = $body.IndexOf('func(', $from)
            if ($at -lt 0) { break }
            $from = $at + 5
            if ($at -gt 0 -and $body[$at - 1] -match '[A-Za-z0-9_.]') { continue }
            $arguments = Get-CallArguments -Text $body -At $at
            if ($null -ne $arguments) { $forwards += $arguments }
        }
        $from = 0
        while ($true) {
            $at = [regex]::Match($body.Substring($from), '[,(]func[,)]')
            if (-not $at.Success) { break }
            $absolute = $from + $at.Index
            $from = $absolute + 1
            # The call this `func` is an argument of: walk back to its bracket.
            $depthBack = 0
            $callAt = -1
            for ($k = $absolute; $k -ge 0; $k--) {
                if ($body[$k] -eq ')') { $depthBack++ }
                elseif ($body[$k] -eq '(') {
                    if ($depthBack -eq 0) { $callAt = $k; break }
                    $depthBack--
                }
            }
            if ($callAt -lt 0) { continue }
            $callArguments = Get-CallArguments -Text $body -At $callAt
            if ($null -eq $callArguments) { continue }
            $parts = Split-Arguments -Text $callArguments
            $index = [array]::IndexOf($parts, 'func')
            if ($index -lt 0 -or $index -eq ($parts.Count - 1)) { continue }
            $forwards += (($parts[($index + 1)..($parts.Count - 1)]) -join ',')
        }

        foreach ($arguments in $forwards) {
            if ($annotated) { continue }
            if ($arguments -match '\.\.\.\s*$') { continue }
            $parts = Split-Arguments -Text $arguments
            if ($parts.Count -eq 0) { continue }
            $hasLiteral = $false
            foreach ($part in $parts) {
                if (Test-IsLiteral -Argument $part) { $hasLiteral = $true }
            }
            if (-not $hasLiteral) {
                $droppedTail += ('{0}:{1}: func({2})' -f $where, ($i + 1), $arguments)
            }
        }
        $i = $end
    }
}
if ($fixedArity.Count -gt 0) {
    throw ("A mod:hook handler names the stock signature and would drop anything added beyond it. Append ', ...' and forward it:`n  " +
        ($fixedArity -join "`n  "))
}
if ($droppedTail.Count -gt 0) {
    throw ("A forward to the stock function passes a fixed list and drops the rest. Append ', ...':`n  " +
        ($droppedTail -join "`n  "))
}

# The eye target's dimensions are a bootstrap default, replaced by whatever
# the runtime reports (darktidevr.lua: "these values must never select a
# render resolution"). Virtual Desktop's FOV tangent makes the real target
# 1908x2076 rather than 2112x2304, and every layout that assumed the larger
# one spilled into its neighbour -- twice, both found only after the user saw
# it (16 and 17 September). A copy of either number anywhere else is that bug
# waiting to happen, so there may be exactly one of each: its declaration.
$eyeTargetLiterals = @()
foreach ($hookedSource in $hookedSources) {
    $where = Split-Path -Leaf $hookedSource
    $lineNumber = 0
    foreach ($line in (Get-Content -LiteralPath $hookedSource)) {
        $lineNumber++
        $code = ($line -replace '--.*$', '')
        foreach ($literal in @('2112', '2304', '1908', '2076')) {
            if ($code -match ('(?<![0-9.])' + $literal + '(?![0-9.])')) {
                $eyeTargetLiterals += ('{0}:{1}: {2}' -f $where, $lineNumber, $line.Trim())
            }
        }
    }
}
# The two declarations in the main chunk are the whole allowance.
$allowedEyeTargetLiterals = 2
if ($eyeTargetLiterals.Count -gt $allowedEyeTargetLiterals) {
    throw ("The eye target's dimensions are a bootstrap default and must be read from the runtime, not written down. Expected {0} declaration(s), found {1}:`n  {2}" -f
        $allowedEyeTargetLiterals, $eyeTargetLiterals.Count, ($eyeTargetLiterals -join "`n  "))
}

# tests/tooling/test-marker-atlas.lua sizes the atlas cell by DERIVING how far
# the interaction popup reaches, and that derivation depends on a constant
# that lives in a different file: the mod lowers the popup by
# `presentation.interaction_popup_drop` of its own height. Change the drop and
# the cell is being judged against a popup that is no longer where it sits --
# silently, with the test still green. The first cut of that test asserted a
# drop of 5/6 that was never in the source at all, and it endorsed a cell that
# would have clipped. So the two must be checked against each other.
$dropSource = $resolvedSource
$dropTest = Join-Path $repoRoot 'tests/tooling/test-marker-atlas.lua'
if ((Test-Path -LiteralPath $dropSource) -and (Test-Path -LiteralPath $dropTest)) {
    $dropDeclared = $null
    foreach ($line in (Get-Content -LiteralPath $dropSource)) {
        if (($line -replace '--.*$', '') -match
                'presentation\.interaction_popup_drop\s*=\s*([0-9]+)\s*/\s*([0-9]+)') {
            $dropDeclared = '{0}/{1}' -f $Matches[1], $Matches[2]
        }
    }
    if (-not $dropDeclared) {
        throw "presentation.interaction_popup_drop is no longer declared as a fraction in darktidevr.lua; tests/tooling/test-marker-atlas.lua derives the atlas cell size from it."
    }
    $dropAsserted = $null
    foreach ($line in (Get-Content -LiteralPath $dropTest)) {
        if ($line -match 'local\s+POPUP_DROP\s*=\s*([0-9]+)\s*/\s*([0-9]+)') {
            $dropAsserted = '{0}/{1}' -f $Matches[1], $Matches[2]
        }
    }
    if (-not $dropAsserted) {
        throw "tests/tooling/test-marker-atlas.lua no longer names POPUP_DROP, so nothing ties its cell-size derivation to the mod's own drop."
    }
    if ($dropDeclared -ne $dropAsserted) {
        throw ("The atlas cell is sized against a popup drop of {0}, but darktidevr.lua drops it by {1}. One of the two has moved: tests/tooling/test-marker-atlas.lua POPUP_DROP, or presentation.interaction_popup_drop." -f
            $dropAsserted, $dropDeclared)
    }
}

# The marker extents instrument buckets by claimant, and a claimant is one of
# Darktide's own world-marker template names -- nameplate, objective, beacon,
# and among them "interaction", which is the icon in the world and NOT
# HudElementInteraction's popup. The two HUD elements that claim a cell whole
# are prefixed `hud_` so they cannot land in a template's bucket; without the
# prefix the popup shares its measurement with a different, smaller thing and
# the cell is sized from the pair -- which is the 18 September failure exactly.
$claimantOffenders = @()
$scopeText = [string]::Join("`n", $lines)
foreach ($match in [regex]::Matches($scopeText,
        'marker_plane_scope\s*\((?:[^()"]|\([^()]*\))*,\s*"([^"]+)"')) {
    $claimant = $match.Groups[1].Value
    if (-not $claimant.StartsWith('hud_')) {
        $claimantOffenders += $claimant
    }
}
if ($claimantOffenders.Count -gt 0) {
    throw ("A HUD element claims a marker-atlas cell under the bare name(s) '{0}'. Darktide has world-marker templates called nameplate, objective and interaction, so a bare name shares a bucket with one of them and the extents instrument conflates two different things. Prefix it `hud_`." -f
        ($claimantOffenders -join "', '"))
}

Write-Output "lua_source_assertions=pass"
