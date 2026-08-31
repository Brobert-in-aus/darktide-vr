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
        'mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua'
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
if (-not $source.Contains('local shared_shadow_cull = true') -or
        -not $source.Contains(
            'Viewport.set_data(primary, "shadow_cull_camera", primary_camera)') -or
        -not $source.Contains(
            'Viewport.set_data(right, "shadow_cull_camera", primary_camera)')) {
    throw 'Both gameplay eyes must default to the same tracked render-camera culling decision.'
}
foreach ($shopTestView in @(
        'credits_vendor_background_view',
        'contracts_background_view',
        'live_events_view',
        'cosmetics_vendor_background_view',
        'barber_vendor_background_view',
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
foreach ($pollGuard in @(
        'system_menu_test_poll_updates',
        'vendor_menu_test_poll_updates',
        'input_inventory_poll_updates',
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
if (-not $calibrationViewSource.Contains('schema = 3') -or
        -not $calibrationViewSource.Contains('capture_forward') -or
        -not $calibrationViewSource.Contains('result.forward_reach')) {
    throw 'Calibration must retain a stable forward-reach capture after T-pose and neutral poses.'
}
$controllerAimSource = Get-Content -LiteralPath (
    Join-Path (Split-Path -Parent $resolvedSource) `
        'darktidevr_controller_aim.lua') -Raw
if (-not $controllerAimSource.Contains(
        'MultiFireModes.simultaneous') -or
        -not $controllerAimSource.Contains(
            '(action.num_shots_fired + 1) % #configurations == 1') -or
        -not $controllerAimSource.Contains(
            'controller_aim.reused_simultaneous_shots') -or
        -not $controllerAimSource.Contains(
            'fx_extension.vfx_spawner_unit_and_node') -or
        -not $controllerAimSource.Contains(
            'action.shooting_position = muzzle_position')) {
    throw 'Controller-authored fire must preserve simultaneous-shot ownership and use the live third-person weapon muzzle with a stock-origin fallback.'
}
if (-not $source.Contains(
        'function presentation.left_controller_aim_target()') -or
        -not $source.Contains(
            'controller_observation.values[0]') -or
        -not $controllerAimSource.Contains(
            'settings and settings.use_charge') -or
        -not $controllerAimSource.Contains(
            'return position, right_rotation, "staff_tip_right_aim"') -or
        -not $controllerAimSource.Contains(
            'return left_position, right_rotation, "left_origin_right_aim"') -or
        -not $controllerAimSource.Contains(
            'right_aim_direction=') -or
        -not $controllerAimSource.Contains(
            'action_spawn_projectile') -or
        -not $controllerAimSource.Contains(
            'chain_lightning_targeting_action_module') -or
        -not $controllerAimSource.Contains(
            'player_unit_smart_targeting_extension')) {
    throw 'Psyker ranged coverage must retain both controller poses, right-hand aiming, left-origin staff primary ownership, staff-tip charged ownership and controller-scoped lightning targeting.'
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
if (-not $hudPanelSource.Contains('enabled = false') -or
        -not $hudPanelSource.Contains('begin_immediate_replay') -or
        -not $hudPanelSource.Contains('pass.retained_mode = false') -or
        -not $hudPanelSource.Contains('end_immediate_replay(immediate_passes)')) {
    throw 'Fixed HUD replay must remain opt-in and force only its temporary offscreen draw through immediate widget passes.'
}
$luaCompiler = Get-Command luac -ErrorAction SilentlyContinue
if ($luaCompiler) {
    & $luaCompiler.Source -p $resolvedSource
    if ($LASTEXITCODE -ne 0) {
        throw "luac rejected the stereo mod source with exit code $LASTEXITCODE"
    }
    $syntaxMode = 'luac'
}
else {
    $pnpm = Get-Command pnpm -ErrorAction SilentlyContinue
    if (-not $pnpm) {
        throw 'Neither luac nor pnpm is available for fail-closed Lua syntax validation.'
    }
    $parseOutput = @(& $pnpm.Source dlx luaparse --quiet --file `
        $resolvedSource 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $details = ($parseOutput | ForEach-Object { [string] $_ }) -join "`n"
        throw "luaparse rejected the stereo mod source:`n$details"
    }
    $syntaxMode = 'luaparse'
}

$runtimeModules = @(
    'darktidevr_body_proxy.lua',
    'darktidevr_calibration.lua',
    'darktidevr_controller_aim.lua',
    'darktidevr_hud_panel.lua'
)
$moduleRoot = Split-Path -Parent $resolvedSource
foreach ($runtimeModule in $runtimeModules) {
    $moduleSource = Join-Path $moduleRoot $runtimeModule
    if (-not (Test-Path -LiteralPath $moduleSource)) {
        throw "Required isolated runtime module is missing: $runtimeModule"
    }
    if ($luaCompiler) {
        & $luaCompiler.Source -p $moduleSource
        if ($LASTEXITCODE -ne 0) {
            throw "luac rejected $runtimeModule with exit code $LASTEXITCODE"
        }
    }
    else {
        $parseOutput = @(& $pnpm.Source dlx luaparse --quiet --file `
            $moduleSource 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $details = ($parseOutput | ForEach-Object { [string] $_ }) -join "`n"
            throw "luaparse rejected ${runtimeModule}:`n$details"
        }
    }
}

Write-Output "lua_source_check=pass file_scope_locals=$fileScopeLocals limit=$MaximumFileScopeLocals syntax=$syntaxMode modules=$($runtimeModules.Count) source=$resolvedSource"
