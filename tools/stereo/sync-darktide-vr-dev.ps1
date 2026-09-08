[CmdletBinding()]
param(
    [string] $GameRoot,

    [switch] $InitializeInstall,

    [switch] $UsePrebuiltProductionShader,

    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Release',

    [switch] $ParticleHorizonLock,

    [switch] $ParticleDiagnosticMagenta,

    [switch] $DiagnosticRenderHooks,

    [bool] $BillboardShaderSubstitution = $true,

    [switch] $VertexShaderDump,

    [switch] $ClusterLightTrace,

    [bool] $ClusterLightVisibilityFix = $true,

    [switch] $FullBodyExperimental,

    [bool] $EnableGameplayInput = $true,

    [bool] $EnableControllerAim = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop

if (Get-Process Darktide -ErrorAction SilentlyContinue) {
    throw 'Darktide must be fully closed before synchronizing development files.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'resolve-darktide-game-root.ps1')
$gameRootPath = Resolve-DarktideGameRoot -GameRoot $GameRoot
$modRoot = Join-Path $gameRootPath 'mods\darktidevr_stereo_probe'
if ($InitializeInstall) {
    foreach ($required in @('binaries\mod_loader', 'mods\base\mod_manager.lua', 'mods\dmf\dmf.mod', 'mods\mod_load_order.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $gameRootPath $required) -PathType Leaf)) {
            throw "Install the Darktide Mod Loader and Framework first. Missing: $required"
        }
    }
}
if ($UsePrebuiltProductionShader -and (-not $BillboardShaderSubstitution -or $ParticleHorizonLock -or $ParticleDiagnosticMagenta)) {
    throw 'Prebuilt production shader mode requires ordinary billboard substitution without particle diagnostic switches.'
}
$sourceLua = Join-Path $repoRoot `
    'mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua'
$sourceLuaRoot = Split-Path -Parent $sourceLua
$sourceBootstrap = Join-Path $repoRoot `
    'mods\darktidevr_stereo_probe\darktidevr_stereo_probe.mod'
$sourceNative = Join-Path $repoRoot `
    "build\windows-vs2022\src\producer\$Configuration\darktidevr_native_capture.dll"
$sourceD3D12Bootstrap = Join-Path $repoRoot `
    "build\windows-vs2022\src\producer\$Configuration\d3d12.dll"
$luaSourceCheck = Join-Path $PSScriptRoot 'test-darktide-lua-source.ps1'
if (-not (Test-Path -LiteralPath $luaSourceCheck -PathType Leaf)) {
    throw "Lua source check not found: $luaSourceCheck"
}
& $luaSourceCheck -SourcePath $sourceLua
$destinations = @(
    [pscustomobject]@{
        Source = $sourceLua
        Destination = Join-Path $modRoot `
            'scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua'
    },
    [pscustomobject]@{
        Source = $sourceBootstrap
        Destination = Join-Path $modRoot 'darktidevr_stereo_probe.mod'
    },
    [pscustomobject]@{
        Source = $sourceNative
        Destination = Join-Path $modRoot 'bin\darktidevr_native_capture.dll'
    },
    [pscustomobject]@{
        Source = $sourceNative
        Destination = Join-Path $gameRootPath `
            'binaries\darktidevr_native_capture.dll'
    },
    [pscustomobject]@{
        Source = $sourceD3D12Bootstrap
        Destination = Join-Path $gameRootPath 'binaries\d3d12.dll'
    }
)

# Native reflection loads this exact app-local DLL even when using prebuilt
# shaders. Include it and its notices in the same recoverable transaction.
. (Join-Path $PSScriptRoot 'dxc-runtime.ps1')
foreach ($runtimeFile in @(Get-VerifiedDxcRuntimeFiles)) {
    $destinations += [pscustomobject]@{
        Source = $runtimeFile.Source
        Destination = Join-Path $modRoot ('bin\' + $runtimeFile.InstalledName)
    }
}

# Required Lua modules are separate LuaJIT chunks, which keeps the production
# probe below its hard local-variable ceiling. Deploy and syntax-check every
# module alongside the entry chunk so a clean game install cannot retain stale
# calibration code.
$moduleFiles = Get-ChildItem -LiteralPath $sourceLuaRoot -Filter '*.lua' |
    Where-Object FullName -ne $sourceLua
foreach ($moduleFile in $moduleFiles) {
    $destinations += [pscustomobject]@{
        Source = $moduleFile.FullName
        Destination = Join-Path (Split-Path -Parent $destinations[0].Destination) `
            $moduleFile.Name
    }
}

$billboardShaderDestination = Join-Path $modRoot 'bin\billboard_shaders'
$billboardVertexSource = Join-Path $repoRoot `
    'build\generated\billboard_shaders\vs-42e436fb1ef1b392.dxil'
$billboardPixelDiagnosticDestination = Join-Path $billboardShaderDestination `
    'ps-6020f2548f29fd47.dxil'
if ($UsePrebuiltProductionShader) {
    . (Join-Path $PSScriptRoot 'production-billboard-shader.ps1')
    Assert-ProductionBillboardShader -ShaderPath $billboardVertexSource `
        -SourcePath (Join-Path $PSScriptRoot 'particle-horizon-lock.vs.hlsl')
} elseif ($BillboardShaderSubstitution -and -not $ParticleHorizonLock) {
    # An ordinary production sync must be self-contained.  Previously the
    # bootstrap flag was enabled while the replacement shader was copied only
    # by an explicit diagnostic switch, allowing a clean install to run stock
    # spherical particles or retain a prior 10x diagnostic vertex shader.
    $buildHorizonLock = Join-Path $PSScriptRoot `
        'build-particle-horizon-lock.ps1'
    if (-not (Test-Path -LiteralPath $buildHorizonLock -PathType Leaf)) {
        throw "Particle horizon-lock build script not found: $buildHorizonLock"
    }
    & $buildHorizonLock
}
if ($BillboardShaderSubstitution) {
    $destinations += [pscustomobject]@{
        Source = $billboardVertexSource
        Destination = Join-Path $billboardShaderDestination `
            'vs-42e436fb1ef1b392.dxil'
    }
}
if ($ParticleDiagnosticMagenta) {
    $destinations += [pscustomobject]@{
        Source = Join-Path $repoRoot `
            'build\generated\billboard_shaders\ps-6020f2548f29fd47.dxil'
        Destination = Join-Path $billboardShaderDestination `
            'ps-6020f2548f29fd47.dxil'
    }
}

foreach ($entry in $destinations) {
    if (-not (Test-Path -LiteralPath $entry.Source -PathType Leaf)) {
        throw "Development source file not found: $($entry.Source)"
    }
    $destinationParent = Split-Path -Parent $entry.Destination
    if (-not $InitializeInstall -and -not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
        throw "Installed Darktide VR directory not found: $destinationParent"
    }
}

$deploymentEntries = @($destinations | ForEach-Object {
    @{ Source = $_.Source; Destination = $_.Destination }
})

# Magenta is an ownership diagnostic, never a production default.  Remove its
# exact deployed shader when the current sync did not request it so a prior
# colour-search run cannot leak into later launches.
if (-not $ParticleDiagnosticMagenta -and
        (Test-Path -LiteralPath $billboardPixelDiagnosticDestination `
            -PathType Leaf)) {
    $deploymentEntries += @{ Destination = $billboardPixelDiagnosticDestination; Remove = $true }
}

# d3d12.dll loads the native capture DLL before Lua can configure it. Keep the
# bootstrap flags authoritative on every deployment so a retired diagnostic
# session cannot silently force the expensive hook set (or make Lua's
# fail-closed configuration reject the launch).
$bootstrapFlags = @(
    [pscustomobject]@{
        Path = Join-Path $modRoot 'bin\darktidevr_diagnostic_render_hooks.flag'
        Enabled = [bool] $DiagnosticRenderHooks
    },
    [pscustomobject]@{
        Path = Join-Path $modRoot 'bin\darktidevr_billboard_shader_substitution.flag'
        Enabled = $BillboardShaderSubstitution
    },
    [pscustomobject]@{
        Path = Join-Path $modRoot 'bin\darktidevr_vertex_shader_dump.flag'
        Enabled = [bool] $VertexShaderDump
    },
    [pscustomobject]@{
        Path = Join-Path $modRoot 'bin\darktidevr_cluster_trace.flag'
        Enabled = [bool] $ClusterLightTrace
    },
    [pscustomobject]@{
        Path = Join-Path $modRoot `
            'bin\darktidevr_cluster_light_visibility_fix.flag'
        Enabled = $ClusterLightVisibilityFix
    }
)
foreach ($flag in $bootstrapFlags) {
    if ($flag.Enabled) {
        if (-not (Test-Path -LiteralPath $flag.Path -PathType Leaf)) {
            $deploymentEntries += @{ Destination = $flag.Path; Content = '' }
        }
    } elseif (Test-Path -LiteralPath $flag.Path -PathType Leaf) {
        $deploymentEntries += @{ Destination = $flag.Path; Remove = $true }
    }
}

# Tracked 3P arms are the launch embodiment.  Full-body mesh/IK remains a
# post-launch experiment and must never leak forward from an earlier local
# test merely because its runtime flag was left behind.
$fullBodyFlag = Join-Path $modRoot 'darktidevr_full_body_experimental.flag'
$fullBodyFlagValue = if ($FullBodyExperimental) { 'enabled' } else { 'disabled' }
$deploymentEntries += @{ Destination = $fullBodyFlag; Content = $fullBodyFlagValue + [Environment]::NewLine }

# Controller locomotion and right-hand aiming are production behavior, not
# diagnostics.  Every normal deployment reasserts them so a helper that
# temporarily restored an old test flag cannot leave a subsequent VR launch
# without controls or the convergence path.
$productionRuntimeFlags = @(
    [pscustomobject]@{
        Path = Join-Path $modRoot 'darktidevr_gameplay_input_test.flag'
        Enabled = $EnableGameplayInput
    },
    [pscustomobject]@{
        Path = Join-Path $modRoot 'darktidevr_controller_aim_test.flag'
        Enabled = $EnableControllerAim
    }
)
foreach ($runtimeFlag in $productionRuntimeFlags) {
    $runtimeValue = if ($runtimeFlag.Enabled) { 'enabled' } else { 'disabled' }
    $deploymentEntries += @{ Destination = $runtimeFlag.Path; Content = $runtimeValue + [Environment]::NewLine }
}

# Diagnostic flags are never production state. Make a normal deployment an
# authoritative clean boundary so a profiler, trace, or A/B probe left enabled
# by an interrupted run cannot silently alter the next headset session.
$disabledDiagnosticFlags = @(
    'darktidevr_body_ik_trace.flag',
    'darktidevr_coincident_eyes.flag',
    'darktidevr_full_second_eye.flag',
    'darktidevr_inherit_viewport_metadata.flag',
    'darktidevr_offline_dual_view.flag',
    'darktidevr_performance_pass_trace.flag',
    'darktidevr_performance_profile.flag',
    'darktidevr_reverse_eye_order.flag',
    'darktidevr_weapon_pose_trace.flag',
    'darktidevr_weapon_presentation.flag'
)
foreach ($diagnosticFlagName in $disabledDiagnosticFlags) {
    $diagnosticFlagPath = Join-Path $modRoot $diagnosticFlagName
    $deploymentEntries += @{ Destination = $diagnosticFlagPath; Content = 'disabled' + [Environment]::NewLine }
}

if ($InitializeInstall) {
    . (Join-Path $PSScriptRoot 'get-vr-mod-load-order.ps1')
    $orderPath = Join-Path $gameRootPath 'mods\mod_load_order.txt'
    $order = Get-DarktideVrModLoadOrder -Bytes ([IO.File]::ReadAllBytes($orderPath))
    if ($order.Changed) { $deploymentEntries += @{ Destination = $orderPath; Bytes = $order.Bytes } }
}

# Files and runtime flags form one update. Stage and back up everything before
# the first installed write; a failed copy must not leave mixed build versions.
. (Join-Path $PSScriptRoot 'invoke-deployment-transaction.ps1')
$deployment = Invoke-DarktideDeploymentTransaction -Root $gameRootPath `
    -Entries $deploymentEntries -BackupRoot (Join-Path $repoRoot 'artifacts\deployment-backups') `
    -CreateDirectories:$InitializeInstall
Write-Output "Development deployment=$($deployment.Status) files=$($deployment.FileCount) backup=$($deployment.BackupDirectory)"
