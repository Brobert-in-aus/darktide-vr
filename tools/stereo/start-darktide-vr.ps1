[CmdletBinding()]
param(
    [ValidateRange(5, 43200)]
    [int] $DurationSeconds = 28800,

    [ValidateRange(5, 1800)]
    [int] $GameStartTimeoutSeconds = 600,

    [string] $GameRoot =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE',

    [switch] $FreshPsoCache,

    [switch] $CaptureBillboardPsoIdentities,

    [ValidatePattern('^[0-9a-fA-F]{16}$')]
    [string] $BillboardPixelShaderProbeHash,

    [switch] $DiagnosticRenderHooks,

    [switch] $StreamlineProbe,

    [switch] $StreamlineCopyProbe,

    [switch] $StreamlineTransportProbe,

    [switch] $StreamlineInputSnapshotProbe,

    [switch] $StreamlineTargetTokenProbe,

    [switch] $StreamlineStereoSwapchainProbe,

    [switch] $ClusterLightTrace,

    [bool] $ClusterLightVisibilityFix = $true,

    [switch] $EnableMenuInput,

    [switch] $EnableMenuTestControls,

    [switch] $SyntheticControllerPath,

    [switch] $SyntheticGameplayInput,

    [switch] $SyntheticWeaponAimMatrix,

    [switch] $SyntheticMovementReferencePath,

    [switch] $EnableGameplayReticle = $true,

    [switch] $TrackedCuffOverlay,

    [switch] $EnableHudPanel,

    [switch] $EnablePerformanceProfile,

    [switch] $EnablePerformancePassTrace,

    [switch] $OfflineDualViewBenchmark,

    [switch] $SyntheticRuntimeFrusta,

    [switch] $OfflineCharacterSelectCapture,

    [switch] $OfflineTitleCapture,

    [switch] $SyntheticBodyPath,

    [switch] $SyntheticHeadSweep,

    [switch] $SyntheticBodyInspection,

    [switch] $SyntheticNeckPivotPath,

    [switch] $SyntheticCrouchPath,

    [switch] $EnterPsykhanium,

    [switch] $AutoEnterHub,

    [switch] $AutoAdvanceSplash,

    [ValidateRange(-2.0, 2.0)]
    [double] $ProjectionTranslationScale = 1.0,

    [switch] $SkipDeploymentSync,

    [switch] $DoNotOpenLauncher,

    [switch] $ManualLauncherPlay
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runner = Join-Path $PSScriptRoot 'run-darktide-shared-eyes.ps1'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw "XR runner not found: $runner"
}
$luaSourceCheck = Join-Path $PSScriptRoot 'test-darktide-lua-source.ps1'
if (-not (Test-Path -LiteralPath $luaSourceCheck -PathType Leaf)) {
    throw "Lua source check not found: $luaSourceCheck"
}
& $luaSourceCheck

if ($SyntheticWeaponAimMatrix) {
    # The matrix is a self-contained private-range gate: deterministic tracked
    # controls, Lua gameplay adapter, controller-authored aim and depth reticle.
    $SyntheticControllerPath = $true
    $SyntheticGameplayInput = $true
    $EnableGameplayReticle = $true
    $EnterPsykhanium = $true
}
if ($SyntheticMovementReferencePath) {
    $SyntheticControllerPath = $true
    $SyntheticGameplayInput = $true
}
if ($EnablePerformancePassTrace) {
    $EnablePerformanceProfile = $true
}
if ($OfflineDualViewBenchmark) {
    # The game still creates and sequentially renders the exact production
    # left/right gameplay viewports. Only the OpenXR consumer is omitted.
    # Keep this baseline uninstrumented unless profiling was explicitly
    # requested: the native GPU profiler injects additional command lists and
    # submissions, so enabling it here changes the workload being measured.
    $AutoEnterHub = $true
}
if ($SyntheticRuntimeFrusta -and -not $OfflineDualViewBenchmark) {
    throw '-SyntheticRuntimeFrusta requires -OfflineDualViewBenchmark.'
}
if ($OfflineCharacterSelectCapture) {
    if (-not $CaptureBillboardPsoIdentities) {
        throw '-OfflineCharacterSelectCapture requires -CaptureBillboardPsoIdentities.'
    }
    $AutoAdvanceSplash = $true
}
if ($OfflineTitleCapture -and -not $CaptureBillboardPsoIdentities) {
    throw '-OfflineTitleCapture requires -CaptureBillboardPsoIdentities.'
}
if ($BillboardPixelShaderProbeHash) {
    # Shader replacement must see PSO construction rather than an old pipeline
    # library entry. Preserve the cache through the launcher's existing backup
    # path before applying this exact, interface-validated colour probe.
    $FreshPsoCache = $true
    $BillboardPixelShaderProbeHash =
        $BillboardPixelShaderProbeHash.ToLowerInvariant()
}
if ($CaptureBillboardPsoIdentities) {
    # The native producer keeps the broad first-bind PSO census behind the
    # diagnostic hook mode so normal substitution has no per-bind mutex or
    # file-I/O tax. Identity-capture runs explicitly opt into that cost.
    $DiagnosticRenderHooks = $true
}
# ClusterLightTrace installs only its compute marker/root/dispatch subset in
# the native producer. Do not imply DiagnosticRenderHooks: that broad mode also
# runs the unrelated graphics-PSO census and can stall renderer startup.
$offlineNoHeadset = $OfflineDualViewBenchmark -or
    $OfflineCharacterSelectCapture -or $OfflineTitleCapture
$streamlineProbeFlagPath = $null
$streamlineProbeFlagOriginal = $null
$streamlineProbeFlagExisted = $false
$streamlineCopyProbeFlagPath = $null
$streamlineCopyProbeFlagOriginal = $null
$streamlineCopyProbeFlagExisted = $false
$streamlineTransportProbeFlagPath = $null
$streamlineTransportProbeFlagOriginal = $null
$streamlineTransportProbeFlagExisted = $false
$streamlineInputSnapshotProbeFlagPath = $null
$streamlineInputSnapshotProbeFlagOriginal = $null
$streamlineInputSnapshotProbeFlagExisted = $false
$streamlineTargetTokenProbeFlagPath = $null
$streamlineTargetTokenProbeFlagOriginal = $null
$streamlineTargetTokenProbeFlagExisted = $false
$streamlineStereoSwapchainProbeFlagPath = $null
$streamlineStereoSwapchainProbeFlagOriginal = $null
$streamlineStereoSwapchainProbeFlagExisted = $false

if (-not $SkipDeploymentSync) {
    $sync = Join-Path $PSScriptRoot 'sync-darktide-vr-dev.ps1'
    if (-not (Test-Path -LiteralPath $sync -PathType Leaf)) {
        throw "Development sync script not found: $sync"
    }
    if (Get-Process Darktide -ErrorAction SilentlyContinue) {
        Write-Warning 'Darktide is already running; deployment sync cannot update loaded files.'
    }
    else {
        & $sync -GameRoot $GameRoot -Configuration Release `
            -DiagnosticRenderHooks:$DiagnosticRenderHooks `
            -ClusterLightTrace:$ClusterLightTrace `
            -ClusterLightVisibilityFix:$ClusterLightVisibilityFix
    }
}

$psykhaniumFlag = $null
$psykhaniumFlagOriginal = $null
if ($EnterPsykhanium) {
    if (Get-Process Darktide -ErrorAction SilentlyContinue) {
        throw 'Psykhanium entry must be armed before Darktide starts; close the game and retry.'
    }
    $psykhaniumFlag = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_enter_psykhanium.flag'
    if (-not (Test-Path -LiteralPath $psykhaniumFlag -PathType Leaf)) {
        throw "Psykhanium one-shot flag not found: $psykhaniumFlag"
    }
    $psykhaniumFlagOriginal = Get-Content -LiteralPath $psykhaniumFlag -Raw
    Set-Content -LiteralPath $psykhaniumFlag -Value 'enter' -Encoding ascii
    Write-Output 'Psykhanium entry armed before launcher startup.'

    # The in-game one-shot state machine deliberately waits for an
    # authenticated hub before opening the training-ground view.  Therefore
    # Psykhanium entry also owns the guarded splash/operative advance; without
    # it an unattended run can remain at character select until its timeout.
    $AutoEnterHub = $true
}

if ($FreshPsoCache) {
    if (Get-Process -Name Darktide -ErrorAction SilentlyContinue) {
        throw 'Darktide must be fully closed before preserving its PSO cache.'
    }
    $cacheRoot = Join-Path $env:APPDATA 'Fatshark\Darktide'
    if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) {
        throw "Darktide cache directory not found: $cacheRoot"
    }
    $resolvedCacheRoot = (Resolve-Path -LiteralPath $cacheRoot).Path
    if ($resolvedCacheRoot -ne $cacheRoot) {
        throw "Unexpected Darktide cache directory: $resolvedCacheRoot"
    }
    $cacheFiles = @(@(
        Join-Path $cacheRoot 'shader_library.pso_lib'
        Join-Path $cacheRoot 'state_stream_library.pso_lib'
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($cacheFiles.Count -gt 0) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = Join-Path $cacheRoot "pso-cache-backup-$stamp"
        New-Item -ItemType Directory -Path $backup | Out-Null
        foreach ($cacheFile in $cacheFiles) {
            Move-Item -LiteralPath $cacheFile -Destination $backup
        }
        Write-Output "Preserved the prior PSO cache in $backup"
    }
}

$xrLaunchOwnsGame = $false
$xrRunnerStarted = $false
$syntheticHeadPublisher = $null
$expectedGamePath = [IO.Path]::GetFullPath(
    (Join-Path $GameRoot 'binaries\Darktide.exe'))
$preLaunchGameProcessIds = [Collections.Generic.HashSet[int]]::new()
foreach ($existingGame in @(Get-Process -Name Darktide `
        -ErrorAction SilentlyContinue)) {
    [void] $preLaunchGameProcessIds.Add($existingGame.Id)
}
$gameplayInputFlagPath = $null
$gameplayInputFlagOriginal = $null
$hudPanelFlagPath = $null
$hudPanelFlagOriginal = $null
$controllerAimFlagPath = $null
$controllerAimFlagOriginal = $null
$performanceProfileFlagPath = $null
$performanceProfileFlagOriginal = $null
$performancePassTraceFlagPath = $null
$performancePassTraceFlagOriginal = $null
$offlineDualViewFlagPath = $null
$offlineDualViewFlagOriginal = $null
$offlineDualViewFlagExisted = $false
$billboardIdentityLogPath = $null
$billboardIdentityStartOffset = 0L
$billboardIdentityCapturePath = $null
$billboardPixelProbeFlagPath = $null
$billboardPixelProbeFlagOriginal = $null
$billboardPixelProbeFlagExisted = $false
$billboardPixelProbeDestinationPath = $null
$billboardPixelProbeDestinationOriginal = $null
$billboardPixelProbeDestinationExisted = $false
if ($CaptureBillboardPsoIdentities) {
    $billboardIdentityLogPath = Join-Path $env:TEMP `
        'darktidevr-billboard-pso-identity.tsv'
    if (Test-Path -LiteralPath $billboardIdentityLogPath -PathType Leaf) {
        $billboardIdentityStartOffset =
            (Get-Item -LiteralPath $billboardIdentityLogPath).Length
    }
    $sceneLabel = if ($OfflineTitleCapture) {
        'title'
    }
    elseif ($EnterPsykhanium) {
        'psykhanium'
    }
    elseif ($AutoEnterHub -or $OfflineDualViewBenchmark) {
        'hub'
    }
    elseif ($AutoAdvanceSplash) {
        'character-select'
    }
    else {
        'manual'
    }
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $captureDirectory = Join-Path $repositoryRoot `
        'artifacts\unattended\billboard-scene-identities'
    $captureStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $billboardIdentityCapturePath = Join-Path $captureDirectory `
        "$sceneLabel-$captureStamp.tsv"
    Write-Output `
        "Billboard PSO identity slice armed; scene=$sceneLabel offset=$billboardIdentityStartOffset"
}
$launchStarted = Get-Date
try {
if ($StreamlineProbe -or $StreamlineCopyProbe -or
        $StreamlineTransportProbe -or $StreamlineInputSnapshotProbe -or
        $StreamlineTargetTokenProbe -or $StreamlineStereoSwapchainProbe) {
    $streamlineProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_streamline_probe.flag'
    $streamlineProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineProbeFlagPath -PathType Leaf
    if ($streamlineProbeFlagExisted) {
        $streamlineProbeFlagOriginal = Get-Content -LiteralPath `
            $streamlineProbeFlagPath -Raw
    }
    Set-Content -LiteralPath $streamlineProbeFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output `
        'Observe-only Streamline/Present probe enabled for this run.'
}
if ($StreamlineCopyProbe) {
    $streamlineCopyProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_streamline_copy_probe.flag'
    $streamlineCopyProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineCopyProbeFlagPath -PathType Leaf
    if ($streamlineCopyProbeFlagExisted) {
        $streamlineCopyProbeFlagOriginal = Get-Content -LiteralPath `
            $streamlineCopyProbeFlagPath -Raw
    }
    Set-Content -LiteralPath $streamlineCopyProbeFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output `
        'One-shot Streamline generated-backbuffer copy probe enabled.'
}
if ($StreamlineTransportProbe) {
    $streamlineTransportProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_streamline_transport_probe.flag'
    $streamlineTransportProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineTransportProbeFlagPath -PathType Leaf
    if ($streamlineTransportProbeFlagExisted) {
        $streamlineTransportProbeFlagOriginal = Get-Content -LiteralPath `
            $streamlineTransportProbeFlagPath -Raw
    }
    Set-Content -LiteralPath $streamlineTransportProbeFlagPath `
        -Value 'enabled' -Encoding ascii
    Write-Output 'Bounded Streamline generated-output transport probe enabled.'
}
if ($StreamlineInputSnapshotProbe -or $StreamlineTargetTokenProbe) {
    $streamlineInputSnapshotProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_streamline_input_snapshot_probe.flag'
    $streamlineInputSnapshotProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineInputSnapshotProbeFlagPath -PathType Leaf
    if ($streamlineInputSnapshotProbeFlagExisted) {
        $streamlineInputSnapshotProbeFlagOriginal = Get-Content -LiteralPath `
            $streamlineInputSnapshotProbeFlagPath -Raw
    }
    Set-Content -LiteralPath $streamlineInputSnapshotProbeFlagPath `
        -Value 'enabled' -Encoding ascii
    Write-Output 'One-pair Streamline input snapshot probe enabled.'
}
if ($StreamlineTargetTokenProbe) {
    $streamlineTargetTokenProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_streamline_target_token_probe.flag'
    $streamlineTargetTokenProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineTargetTokenProbeFlagPath -PathType Leaf
    if ($streamlineTargetTokenProbeFlagExisted) {
        $streamlineTargetTokenProbeFlagOriginal = Get-Content -LiteralPath `
            $streamlineTargetTokenProbeFlagPath -Raw
    }
    Set-Content -LiteralPath $streamlineTargetTokenProbeFlagPath `
        -Value 'enabled' -Encoding ascii
    Write-Output 'One-shot Streamline stereo target-token probe enabled.'
}
if ($StreamlineStereoSwapchainProbe) {
    $streamlineStereoSwapchainProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_streamline_stereo_swapchain_probe.flag'
    $streamlineStereoSwapchainProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineStereoSwapchainProbeFlagPath -PathType Leaf
    if ($streamlineStereoSwapchainProbeFlagExisted) {
        $streamlineStereoSwapchainProbeFlagOriginal = Get-Content -LiteralPath `
            $streamlineStereoSwapchainProbeFlagPath -Raw
    }
    Set-Content -LiteralPath $streamlineStereoSwapchainProbeFlagPath `
        -Value 'enabled' -Encoding ascii
    Write-Output 'Wide stereo Streamline swapchain probe enabled.'
}
if ($SyntheticRuntimeFrusta) {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $syntheticHeadPublisherPath = Join-Path $repositoryRoot `
        'build\windows-vs2022\tests\xr_harness\Release\darktidevr-synthetic-head-publisher.exe'
    if (-not (Test-Path -LiteralPath $syntheticHeadPublisherPath -PathType Leaf)) {
        throw "Synthetic head publisher not found: $syntheticHeadPublisherPath"
    }
    $publisherSeconds = $GameStartTimeoutSeconds + $DurationSeconds + 60
    $syntheticHeadPublisher = Start-Process `
        -FilePath $syntheticHeadPublisherPath -WindowStyle Hidden -PassThru `
        -ArgumentList @('--seconds', $publisherSeconds)
    Start-Sleep -Milliseconds 100
    if ($syntheticHeadPublisher.HasExited) {
        throw "Synthetic head publisher exited with code $($syntheticHeadPublisher.ExitCode)."
    }
    Write-Output `
        "Synthetic VirtualDesktopXR runtime frusta enabled; publisher_pid=$($syntheticHeadPublisher.Id)"
}
if ($BillboardPixelShaderProbeHash) {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $probeSource = Join-Path $repositoryRoot `
        "build\generated\blended_pixel_shaders\ps-$BillboardPixelShaderProbeHash.dxil"
    if (-not (Test-Path -LiteralPath $probeSource -PathType Leaf)) {
        throw "Interface-matched pixel probe not found: $probeSource"
    }
    $billboardPixelProbeDestinationPath = Join-Path $GameRoot `
        "mods\darktidevr_stereo_probe\bin\billboard_shaders\ps-$BillboardPixelShaderProbeHash.dxil"
    $billboardPixelProbeDestinationExisted = Test-Path -LiteralPath `
        $billboardPixelProbeDestinationPath -PathType Leaf
    if ($billboardPixelProbeDestinationExisted) {
        $billboardPixelProbeDestinationOriginal =
            [IO.File]::ReadAllBytes($billboardPixelProbeDestinationPath)
    }
    Copy-Item -LiteralPath $probeSource `
        -Destination $billboardPixelProbeDestinationPath -Force
    $billboardPixelProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_billboard_pixel_shader_probe.flag'
    $billboardPixelProbeFlagExisted = Test-Path -LiteralPath `
        $billboardPixelProbeFlagPath -PathType Leaf
    if ($billboardPixelProbeFlagExisted) {
        $billboardPixelProbeFlagOriginal = Get-Content -LiteralPath `
            $billboardPixelProbeFlagPath -Raw
    }
    Set-Content -LiteralPath $billboardPixelProbeFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output `
        "Exact billboard pixel probe enabled for hash=$BillboardPixelShaderProbeHash"
}
if ($EnableGameplayReticle -and -not $offlineNoHeadset) {
    $candidateControllerAimFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_controller_aim_test.flag'
    if (-not (Test-Path -LiteralPath $candidateControllerAimFlagPath -PathType Leaf)) {
        throw "Controller-aim test flag not found: $candidateControllerAimFlagPath"
    }
    $controllerAimFlagOriginal = Get-Content -LiteralPath `
        $candidateControllerAimFlagPath -Raw
    $controllerAimFlagPath = $candidateControllerAimFlagPath
    Set-Content -LiteralPath $controllerAimFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output 'Controller aim enabled for this reticle run.'
}
if ($EnableHudPanel) {
    $candidateHudPanelFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_hud_panel.flag'
    if (-not (Test-Path -LiteralPath $candidateHudPanelFlagPath -PathType Leaf)) {
        throw "HUD-panel test flag not found: $candidateHudPanelFlagPath"
    }
    $hudPanelFlagOriginal = Get-Content -LiteralPath `
        $candidateHudPanelFlagPath -Raw
    $hudPanelFlagPath = $candidateHudPanelFlagPath
    Set-Content -LiteralPath $hudPanelFlagPath -Value 'enable' `
        -Encoding ascii
    Write-Output 'Fixed HUD panel enabled for this XR run.'
}
if ($EnablePerformanceProfile) {
    $candidatePerformanceProfileFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_performance_profile.flag'
    if (-not (Test-Path -LiteralPath `
            $candidatePerformanceProfileFlagPath -PathType Leaf)) {
        throw "Performance-profile flag not found: $candidatePerformanceProfileFlagPath"
    }
    $performanceProfileFlagOriginal = Get-Content -LiteralPath `
        $candidatePerformanceProfileFlagPath -Raw
    $performanceProfileFlagPath = $candidatePerformanceProfileFlagPath
    Set-Content -LiteralPath $performanceProfileFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output 'Performance profiling enabled for this XR run.'
}
if ($EnablePerformancePassTrace) {
    $candidatePerformancePassTraceFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_performance_pass_trace.flag'
    if (-not (Test-Path -LiteralPath `
            $candidatePerformancePassTraceFlagPath -PathType Leaf)) {
        throw "Performance-pass trace flag not found: $candidatePerformancePassTraceFlagPath"
    }
    $performancePassTraceFlagOriginal = Get-Content -LiteralPath `
        $candidatePerformancePassTraceFlagPath -Raw
    $performancePassTraceFlagPath = $candidatePerformancePassTraceFlagPath
    Set-Content -LiteralPath $performancePassTraceFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output 'Performance pass tracing enabled for this XR run.'
}
if ($offlineNoHeadset) {
    $candidateOfflineDualViewFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_offline_dual_view.flag'
    $offlineDualViewFlagExisted = Test-Path -LiteralPath `
        $candidateOfflineDualViewFlagPath -PathType Leaf
    if ($offlineDualViewFlagExisted) {
        $offlineDualViewFlagOriginal = Get-Content -LiteralPath `
            $candidateOfflineDualViewFlagPath -Raw
    }
    $offlineDualViewFlagPath = $candidateOfflineDualViewFlagPath
    Set-Content -LiteralPath $offlineDualViewFlagPath -Value 'enabled' `
        -Encoding ascii
    if ($OfflineDualViewBenchmark) {
        Write-Output 'Offline dual-view hub-spin benchmark enabled for this run.'
    }
    elseif ($OfflineCharacterSelectCapture) {
        Write-Output 'Offline character-select identity capture enabled for this run.'
    }
    else {
        Write-Output 'Offline title identity capture enabled for this run.'
    }
}
if (-not $DoNotOpenLauncher) {
    $expectedLauncherPath = Join-Path $GameRoot 'launcher\Launcher.exe'
    if (-not (Test-Path -LiteralPath $expectedLauncherPath -PathType Leaf)) {
        throw "Fatshark launcher not found: $expectedLauncherPath"
    }
    $expectedLauncherPath =
        (Resolve-Path -LiteralPath $expectedLauncherPath).Path
    $runningDarktideLaunchers = @(Get-Process Launcher `
            -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.Path -eq $expectedLauncherPath
            }
            catch {
                $false
            }
        })
    if ($runningDarktideLaunchers.Count -ne 0) {
        throw 'A launcher process is already running; close it before a clean authenticated launch.'
    }
    # Preserve the supported Steam -> Fatshark launcher path. The launcher has
    # no autoplay command-line switch, so the guarded helper invokes its normal
    # Play control after verifying process identity and window geometry.
    $xrLaunchOwnsGame = $true
    Start-Process 'steam://rungameid/1361210'
    if (-not $ManualLauncherPlay) {
        $launcherPlayHelper = Join-Path $PSScriptRoot `
            'invoke-darktide-launcher-play.ps1'
        if (-not (Test-Path -LiteralPath $launcherPlayHelper -PathType Leaf)) {
            throw "Launcher Play helper not found: $launcherPlayHelper"
        }
        & $launcherPlayHelper `
            -TimeoutSeconds $GameStartTimeoutSeconds `
            -GameRoot $GameRoot
    }
}
else {
    $xrLaunchOwnsGame = $true
}

if ($AutoEnterHub -or $AutoAdvanceSplash) {
    $advanceHelper = Join-Path $PSScriptRoot 'advance-darktide-to-hub.ps1'
    if (-not (Test-Path -LiteralPath $advanceHelper -PathType Leaf)) {
        throw "Darktide hub advance helper not found: $advanceHelper"
    }
    $powershell = (Get-Process -Id $PID).Path
    $advanceArguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        "`"$advanceHelper`"",
        '-TimeoutSeconds',
        $GameStartTimeoutSeconds,
        '-GameExe',
        ('"' + $expectedGamePath + '"')
    )
    if ($AutoAdvanceSplash -and -not $AutoEnterHub) {
        $advanceArguments += '-StopAtCharacterSelect'
    }
    Start-Process -FilePath $powershell -WindowStyle Hidden `
        -ArgumentList $advanceArguments
    if ($AutoEnterHub) {
        Write-Output 'Armed state-gated Space/Enter automation through character select.'
    }
    else {
        Write-Output 'Armed state-gated Space automation to character select.'
    }
}

Write-Output 'Waiting for the Darktide splash window; XR will start as soon as it exists.'
$runnerArguments = @{
    DurationSeconds = $DurationSeconds
    WaitForGameSeconds = $GameStartTimeoutSeconds
    ProjectionTranslationScale = $ProjectionTranslationScale
    GameExe = Join-Path $GameRoot 'binaries\Darktide.exe'
}
if ($EnableMenuInput) {
    $runnerArguments.EnableMenuInput = $true
}
if ($EnableMenuTestControls) {
    $runnerArguments.EnableMenuTestControls = $true
}
if ($SyntheticControllerPath) {
    $runnerArguments.SyntheticControllerPath = $true
}
if ($SyntheticGameplayInput) {
    $candidateGameplayInputFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_gameplay_input_test.flag'
    if (-not (Test-Path -LiteralPath $candidateGameplayInputFlagPath -PathType Leaf)) {
        throw "Gameplay-input test flag not found: $candidateGameplayInputFlagPath"
    }
    $gameplayInputFlagOriginal = Get-Content -LiteralPath `
        $candidateGameplayInputFlagPath -Raw
    $gameplayInputFlagPath = $candidateGameplayInputFlagPath
    Set-Content -LiteralPath $gameplayInputFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output 'Synthetic gameplay adapter enabled for this XR run.'
    $runnerArguments.SyntheticGameplayInput = $true
}
if ($SyntheticWeaponAimMatrix) {
    $runnerArguments.SyntheticWeaponAimMatrix = $true
}
if ($SyntheticMovementReferencePath) {
    $runnerArguments.SyntheticMovementReferencePath = $true
}
if ($EnableGameplayReticle -and -not $offlineNoHeadset) {
    $runnerArguments.EnableGameplayReticle = $true
}
if ($TrackedCuffOverlay -and -not $offlineNoHeadset) {
    $runnerArguments.TrackedCuffOverlay = $true
}
if ($SyntheticBodyPath) {
    $runnerArguments.SyntheticBodyPath = $true
}
if ($SyntheticHeadSweep) {
    $runnerArguments.SyntheticHeadSweep = $true
}
if ($SyntheticBodyInspection) {
    $runnerArguments.SyntheticBodyInspection = $true
}
if ($SyntheticNeckPivotPath) {
    $runnerArguments.SyntheticNeckPivotPath = $true
}
if ($SyntheticCrouchPath) {
    $runnerArguments.SyntheticCrouchPath = $true
}
if ($offlineNoHeadset) {
    $xrRunnerStarted = $true
    $readyDeadline = (Get-Date).AddSeconds($GameStartTimeoutSeconds)
    $consoleLogRoot = Join-Path $env:APPDATA 'Fatshark\Darktide\console_logs'
    $benchmarkLog = $null
    $benchmarkText = ''
    $game = $null
    $ready = $false
    do {
        $game = Get-Process Darktide -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    $pathMatches = $_.Path -ieq $expectedGamePath
                    $launchMatches = $DoNotOpenLauncher -or
                        -not $preLaunchGameProcessIds.Contains($_.Id)
                    $pathMatches -and $launchMatches
                }
                catch {
                    $false
                }
            } |
            Select-Object -First 1
        $benchmarkLog = Get-ChildItem -LiteralPath $consoleLogRoot `
                -Filter '*.log' -ErrorAction SilentlyContinue |
            Where-Object LastWriteTime -ge $launchStarted |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($game -and $benchmarkLog) {
            $benchmarkText = Get-Content -LiteralPath $benchmarkLog.FullName `
                -Raw -ErrorAction SilentlyContinue
            $ready = if ($OfflineDualViewBenchmark) {
                $benchmarkText -match 'StateGameplay:on_enter\(\): hub_ship' -and
                    $benchmarkText -match
                        'DARKTIDEVR_STEREO active mode=synchronized_sequential'
            }
            elseif ($OfflineCharacterSelectCapture) {
                $benchmarkText -match 'Entering Game State StateMainMenu' -and
                    $benchmarkText -match
                        'UIProfileSpawner.*cb_on_unit_3p_streaming_complete'
            }
            else {
                $benchmarkText -match 'Entering Game State StateTitle'
            }
            if ($ready) {
                break
            }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $readyDeadline)
    if (-not $game -or -not $benchmarkLog -or -not $ready) {
        if ($OfflineDualViewBenchmark) {
            throw 'Timed out waiting for the offline dual-view hub benchmark.'
        }
        if ($OfflineCharacterSelectCapture) {
            throw 'Timed out waiting for the offline character-select identity capture.'
        }
        throw 'Timed out waiting for the offline title identity capture.'
    }
    if ($OfflineDualViewBenchmark) {
        Write-Output "Offline dual-view benchmark started; log=$($benchmarkLog.FullName)"
    }
    elseif ($OfflineCharacterSelectCapture) {
        Write-Output "Offline character-select capture started; log=$($benchmarkLog.FullName)"
    }
    else {
        Write-Output "Offline title capture started; log=$($benchmarkLog.FullName)"
    }
    $benchmarkEnd = (Get-Date).AddSeconds($DurationSeconds)
    while ((Get-Date) -lt $benchmarkEnd) {
        if (-not (Get-Process -Id $game.Id -ErrorAction SilentlyContinue)) {
            throw 'Darktide exited during the offline dual-view benchmark.'
        }
        Start-Sleep -Seconds 1
    }
    if ($OfflineDualViewBenchmark) {
        Write-Output "Offline dual-view benchmark completed; log=$($benchmarkLog.FullName)"
    }
    elseif ($OfflineCharacterSelectCapture) {
        Write-Output "Offline character-select capture completed; log=$($benchmarkLog.FullName)"
    }
    else {
        Write-Output "Offline title capture completed; log=$($benchmarkLog.FullName)"
    }
}
else {
    $xrRunnerStarted = $true
    & $runner @runnerArguments
}
}
finally {
    if ($streamlineProbeFlagPath) {
        if ($streamlineProbeFlagExisted) {
            Set-Content -LiteralPath $streamlineProbeFlagPath `
                -Value $streamlineProbeFlagOriginal.Trim() -Encoding ascii
        }
        elseif (Test-Path -LiteralPath $streamlineProbeFlagPath `
                -PathType Leaf) {
            Remove-Item -LiteralPath $streamlineProbeFlagPath -Force
        }
        Write-Output 'Restored the prior Streamline probe flag.'
    }
    if ($streamlineCopyProbeFlagPath) {
        if ($streamlineCopyProbeFlagExisted) {
            Set-Content -LiteralPath $streamlineCopyProbeFlagPath `
                -Value $streamlineCopyProbeFlagOriginal.Trim() -Encoding ascii
        }
        elseif (Test-Path -LiteralPath $streamlineCopyProbeFlagPath `
                -PathType Leaf) {
            Remove-Item -LiteralPath $streamlineCopyProbeFlagPath -Force
        }
        Write-Output 'Restored the prior Streamline copy-probe flag.'
    }
    if ($streamlineTransportProbeFlagPath) {
        if ($streamlineTransportProbeFlagExisted) {
            Set-Content -LiteralPath $streamlineTransportProbeFlagPath `
                -Value $streamlineTransportProbeFlagOriginal.Trim() `
                -Encoding ascii
        }
        elseif (Test-Path -LiteralPath $streamlineTransportProbeFlagPath `
                -PathType Leaf) {
            Remove-Item -LiteralPath $streamlineTransportProbeFlagPath -Force
        }
        Write-Output 'Restored the prior Streamline transport-probe flag.'
    }
    if ($streamlineInputSnapshotProbeFlagPath) {
        if ($streamlineInputSnapshotProbeFlagExisted) {
            Set-Content -LiteralPath $streamlineInputSnapshotProbeFlagPath `
                -Value $streamlineInputSnapshotProbeFlagOriginal.Trim() `
                -Encoding ascii
        }
        elseif (Test-Path -LiteralPath $streamlineInputSnapshotProbeFlagPath `
                -PathType Leaf) {
            Remove-Item -LiteralPath $streamlineInputSnapshotProbeFlagPath `
                -Force
        }
        Write-Output 'Restored the prior Streamline input-snapshot flag.'
    }
    if ($streamlineTargetTokenProbeFlagPath) {
        if ($streamlineTargetTokenProbeFlagExisted) {
            Set-Content -LiteralPath $streamlineTargetTokenProbeFlagPath `
                -Value $streamlineTargetTokenProbeFlagOriginal.Trim() `
                -Encoding ascii
        }
        elseif (Test-Path -LiteralPath $streamlineTargetTokenProbeFlagPath `
                -PathType Leaf) {
            Remove-Item -LiteralPath $streamlineTargetTokenProbeFlagPath `
                -Force
        }
        Write-Output 'Restored the prior Streamline target-token flag.'
    }
    if ($streamlineStereoSwapchainProbeFlagPath) {
        if ($streamlineStereoSwapchainProbeFlagExisted) {
            Set-Content -LiteralPath $streamlineStereoSwapchainProbeFlagPath `
                -Value $streamlineStereoSwapchainProbeFlagOriginal.Trim() `
                -Encoding ascii
        }
        elseif (Test-Path -LiteralPath $streamlineStereoSwapchainProbeFlagPath `
                -PathType Leaf) {
            Remove-Item -LiteralPath $streamlineStereoSwapchainProbeFlagPath `
                -Force
        }
        Write-Output 'Restored the prior Streamline stereo-swapchain flag.'
    }
    if ($syntheticHeadPublisher) {
        if (-not $syntheticHeadPublisher.HasExited) {
            $syntheticHeadPublisher | Stop-Process -Force
        }
        Write-Output 'Stopped the run-owned synthetic head publisher.'
    }
    if ($billboardPixelProbeFlagPath) {
        if ($billboardPixelProbeFlagExisted) {
            Set-Content -LiteralPath $billboardPixelProbeFlagPath `
                -Value $billboardPixelProbeFlagOriginal.Trim() -Encoding ascii
        }
        elseif (Test-Path -LiteralPath $billboardPixelProbeFlagPath -PathType Leaf) {
            Remove-Item -LiteralPath $billboardPixelProbeFlagPath -Force
        }
        if ($billboardPixelProbeDestinationExisted) {
            [IO.File]::WriteAllBytes(
                $billboardPixelProbeDestinationPath,
                $billboardPixelProbeDestinationOriginal)
        }
        elseif (Test-Path -LiteralPath $billboardPixelProbeDestinationPath `
                -PathType Leaf) {
            Remove-Item -LiteralPath $billboardPixelProbeDestinationPath -Force
        }
        Write-Output 'Restored the prior exact billboard pixel-probe state.'
    }
    if ($offlineDualViewFlagPath) {
        if ($offlineDualViewFlagExisted) {
            Set-Content -LiteralPath $offlineDualViewFlagPath `
                -Value $offlineDualViewFlagOriginal.Trim() -Encoding ascii
        }
        elseif (Test-Path -LiteralPath $offlineDualViewFlagPath -PathType Leaf) {
            Remove-Item -LiteralPath $offlineDualViewFlagPath -Force
        }
        Write-Output 'Restored the prior offline dual-view benchmark flag.'
    }
    if ($performancePassTraceFlagPath) {
        Set-Content -LiteralPath $performancePassTraceFlagPath `
            -Value $performancePassTraceFlagOriginal.Trim() -Encoding ascii
        Write-Output 'Restored the prior performance-pass trace flag.'
    }
    if ($performanceProfileFlagPath) {
        Set-Content -LiteralPath $performanceProfileFlagPath `
            -Value $performanceProfileFlagOriginal.Trim() -Encoding ascii
        Write-Output 'Restored the prior performance-profile flag.'
    }
    if ($controllerAimFlagPath) {
        Set-Content -LiteralPath $controllerAimFlagPath `
            -Value $controllerAimFlagOriginal.Trim() -Encoding ascii
        Write-Output 'Restored the prior controller-aim test flag.'
    }
    if ($hudPanelFlagPath) {
        Set-Content -LiteralPath $hudPanelFlagPath `
            -Value $hudPanelFlagOriginal.Trim() -Encoding ascii
        Write-Output 'Restored the prior HUD-panel test flag.'
    }
    if ($gameplayInputFlagPath) {
        Set-Content -LiteralPath $gameplayInputFlagPath `
            -Value $gameplayInputFlagOriginal.Trim() -Encoding ascii
        Write-Output 'Restored the prior gameplay-input test flag.'
    }
    if ($xrLaunchOwnsGame) {
        # A supported launch must never leave its authenticated flat Darktide
        # process behind after its XR owner exits. Preserve every PID that
        # existed before this invocation and require the exact configured
        # executable so cleanup cannot terminate an unrelated same-name game.
        # Launcher Play can complete just after its UI helper reports failure,
        # so cover that late-process race before returning the original error.
        $cleanupDeadline = if ($xrRunnerStarted) {
            Get-Date
        }
        else {
            (Get-Date).AddSeconds(30)
        }
        do {
            $orphanedGames = @(Get-Process -Name Darktide `
                    -ErrorAction SilentlyContinue |
                Where-Object {
                    if ($preLaunchGameProcessIds.Contains($_.Id)) {
                        return $false
                    }
                    try {
                        $_.Path -ieq $expectedGamePath
                    }
                    catch {
                        $false
                    }
                })
            if ($orphanedGames.Count -gt 0) {
                $orphanedGames | Stop-Process -Force
                if ($offlineNoHeadset) {
                    Write-Output `
                        'Offline run completed; terminated the run-owned Darktide process.'
                }
                elseif ($xrRunnerStarted) {
                    Write-Warning `
                        'XR owner exited; terminated the orphaned flat Darktide process.'
                }
                else {
                    Write-Warning `
                        'Launch failed; terminated the late run-owned Darktide process.'
                }
                break
            }
            if ((Get-Date) -ge $cleanupDeadline) {
                break
            }
            Start-Sleep -Milliseconds 500
        } while ($true)
    }
    if ($psykhaniumFlag) {
        Set-Content -LiteralPath $psykhaniumFlag `
            -Value $psykhaniumFlagOriginal.Trim() -Encoding ascii
        Write-Output 'Restored the prior Psykhanium one-shot flag.'
    }
    if ($billboardIdentityCapturePath -and $billboardIdentityLogPath -and
            (Test-Path -LiteralPath $billboardIdentityLogPath -PathType Leaf)) {
        $identityLength =
            (Get-Item -LiteralPath $billboardIdentityLogPath).Length
        if ($identityLength -gt $billboardIdentityStartOffset) {
            $captureDirectory = Split-Path -Parent $billboardIdentityCapturePath
            New-Item -ItemType Directory -Path $captureDirectory -Force |
                Out-Null
            $sourceStream = [System.IO.File]::Open(
                $billboardIdentityLogPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite)
            $destinationStream = $null
            try {
                [void]$sourceStream.Seek(
                    $billboardIdentityStartOffset,
                    [System.IO.SeekOrigin]::Begin)
                $destinationStream = [System.IO.File]::Create(
                    $billboardIdentityCapturePath)
                $sourceStream.CopyTo($destinationStream)
            }
            finally {
                if ($destinationStream) {
                    $destinationStream.Dispose()
                }
                $sourceStream.Dispose()
            }
            Write-Output `
                "Captured run-scoped billboard PSO identities: $billboardIdentityCapturePath"
        }
        elseif ($identityLength -lt $billboardIdentityStartOffset) {
            Write-Warning `
                'Billboard PSO identity log was replaced during the run; no unsafe cross-run slice was emitted.'
        }
        else {
            Write-Warning 'No billboard PSO identities were appended during this run.'
        }
    }
}
