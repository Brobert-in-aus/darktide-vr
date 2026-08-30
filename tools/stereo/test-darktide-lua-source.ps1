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
    'presentation.refresh_body_anchor_from_avatar(unit)')
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
if (-not $source.Contains(
        'scripts/extension_systems/aim/third_person_idle_fullbody_animation_control') -or
        -not $source.Contains('self._idle_fullbody_value = 0')) {
    throw 'Local VR hub body must suppress lateral full-body idle variants.'
}
if (-not $source.Contains(
        'function presentation.neck_compensated_vertical') -or
        -not $source.Contains('body_ik_neck_baseline_arc') -or
        -not $source.Contains('head_pose_values[23]')) {
    throw 'Crouch IK must subtract the calibrated neck-pivot arc and rebase on XR recenter.'
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

Write-Output "lua_source_check=pass file_scope_locals=$fileScopeLocals limit=$MaximumFileScopeLocals syntax=$syntaxMode source=$resolvedSource"
