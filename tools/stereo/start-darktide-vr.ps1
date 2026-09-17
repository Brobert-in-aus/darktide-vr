[CmdletBinding()]
param(
    [ValidateRange(5, 43200)]
    [int] $DurationSeconds = 28800,

    [ValidateRange(5, 1800)]
    [int] $GameStartTimeoutSeconds = 600,

    [string] $GameRoot,

    [switch] $FreshPsoCache,

    [switch] $TuneWorkerThreads,

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

    [switch] $StreamlineEyeTargetProbe,

    [switch] $StreamlineStereoStageProbe,

    [switch] $NgxOutputProbe,

    [switch] $ObserveDlssSrInputs,

    [switch] $NgxOutputProbeAtStereoSubmit,

    [switch] $NgxOutputCopyProbe,

    [switch] $DlssGeneratedStereo,

    [switch] $StreamlineStereoSubmitProbe,
    [switch] $StreamlineContinuousSubmitProbe,
    [ValidateRange(1, 8)] [int] $StreamlineStereoSubmitFrames = 1,

    [switch] $ClusterLightTrace,

    [bool] $ClusterLightVisibilityFix = $true,

    [switch] $EnableMenuInput,

    [switch] $XrDebugLayer,
    [switch] $PreserveDiagnosticFlags,

    [switch] $EnableMenuTestControls,

    [switch] $SyntheticControllerPath,

    [switch] $MenuAimStabilization,

    [switch] $SyntheticGameplayInput,

    [switch] $SyntheticWeaponAimMatrix,

    [switch] $SyntheticMovementReferencePath,

    [switch] $EnableGameplayReticle = $true,

    [switch] $TrackedCuffOverlay,

    [switch] $EnableHudPanel,

    [switch] $EnablePerformanceProfile,

    [switch] $EnablePerformancePassTrace,

    [switch] $OfflineDualViewBenchmark,
    [ValidateSet('','cm_archives')] [string] $OfflineSoloMission = '',

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

    [switch] $ManualCharacterSelect,

    [switch] $ManualStartup,

    [ValidateRange(-2.0, 2.0)]
    [double] $ProjectionTranslationScale = 1.0,

    [switch] $SkipDeploymentSync,

    [switch] $UsePrebuiltProductionShader,

    [switch] $DoNotOpenLauncher,

    [switch] $ManualLauncherPlay,

    # The viewer's measured 11 September timing defaults: high-resolution pair
    # polling and direct native original copies (the latter applies only when
    # frame generation is not published). This switch restores the earlier
    # viewer behaviour for a comparison run.
    [switch] $LegacyViewerTiming,
    # Draws the gameplay reticle into the eye images instead of handing the
    # runtime a quad layer, which Virtual Desktop draws with a projection that
    # does not match a cropped display. Off until it has been worn.
    [switch] $ReticleInEyes,

    # Native stereo launches (no -DlssGeneratedStereo) publish originals through
    # the three-slot native ring by default since the 11 September bundle. This
    # switch keeps the legacy single-slot handoff for a comparison run.
    [switch] $NoNativeOriginalRing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-DarktideOfflineWorkloadReady {
    param([string] $ConsoleText, [string] $SoloMission = '')
    if ($ConsoleText -notmatch 'DARKTIDEVR_STEREO active mode=synchronized_sequential') {
        return $false
    }
    if ($SoloMission) {
        $missionPattern = [regex]::Escape($SoloMission)
        return $ConsoleText -match "DARKTIDEVR_SOLO_BENCHMARK ready mission=$missionPattern difficulty=[1-5] host=singleplay"
    }
    return $ConsoleText -match 'StateGameplay:on_enter\(\): hub_ship'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'resolve-darktide-game-root.ps1')
$GameRoot = Resolve-DarktideGameRoot -GameRoot $GameRoot
. (Join-Path $PSScriptRoot 'psykhanium-launch-request.ps1')

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
    # left/right gameplay viewports. This launcher omits its own OpenXR consumer;
    # the simulator wrapper can supply one in a separate process.
    # Keep this baseline uninstrumented unless profiling was explicitly
    # requested: the native GPU profiler injects additional command lists and
    # submissions, so enabling it here changes the workload being measured.
    $AutoEnterHub = -not [bool]$OfflineSoloMission
    if ($OfflineSoloMission) { $AutoAdvanceSplash = $true }
}
if ($OfflineSoloMission -and -not $OfflineDualViewBenchmark) {
    throw '-OfflineSoloMission requires the isolated dual-view benchmark.'
}
if ($DlssGeneratedStereo) {
    $NgxOutputProbeAtStereoSubmit = $true
    $StreamlineContinuousSubmitProbe = $true
    $StreamlineStereoSubmitFrames = 8
}
if ($ObserveDlssSrInputs) {
    $NgxOutputProbeAtStereoSubmit = $true
}
if ($NgxOutputCopyProbe) {
    $NgxOutputProbeAtStereoSubmit = $true
    $StreamlineContinuousSubmitProbe = $true
}
if ($StreamlineContinuousSubmitProbe) {
    if ($StreamlineStereoSubmitFrames -lt 2) { throw 'Continuous submission requires 2 to 8 frames.' }
    $StreamlineStereoSubmitProbe = $true
}
if ($NgxOutputProbeAtStereoSubmit) {
    $NgxOutputProbe = $true
    $StreamlineStereoSubmitProbe = $true
}
if ($StreamlineStereoSubmitProbe) {
    $StreamlineStereoStageProbe = $true
}
if ($StreamlineStereoStageProbe) {
    $StreamlineTargetTokenProbe = $true
    $StreamlineStereoSwapchainProbe = $true
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
# Flag files are restored byte-exact from their captured contents; tests
# override this function to observe restores without touching the disk.
function Restore-FlagOriginal([string] $LiteralPath, $Original) {
    [IO.File]::WriteAllBytes($LiteralPath, [byte[]]$Original)
}
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
if ($StreamlineStereoSwapchainProbe) { $StreamlineEyeTargetProbe = $true }
# The native original ring publishes only identified eye finals, so a native
# stereo launch that uses it also isolates the gameplay eye targets.
$nativeOriginalRingDefault = -not $DlssGeneratedStereo -and -not $NoNativeOriginalRing
if ($nativeOriginalRingDefault) { $StreamlineEyeTargetProbe = $true }
$nativeOriginalRingFlags = @()
$streamlineEyeTargetProbeFlagPath = $null
$streamlineEyeTargetProbeFlagOriginal = $null
$streamlineEyeTargetProbeFlagExisted = $false
$streamlineStereoSwapchainProbeFlagPath = $null
$streamlineStereoSwapchainProbeFlagOriginal = $null
$streamlineStereoSwapchainProbeFlagExisted = $false
$streamlineStereoStageProbeFlagPath = $null
$streamlineStereoStageProbeFlagOriginal = $null
$streamlineStereoStageProbeFlagExisted = $false
$streamlineStereoSubmitProbeFlagPath = $null
$streamlineStereoSubmitProbeFlagOriginal = $null
$streamlineStereoSubmitProbeFlagExisted = $false
$ngxOutputProbeFlagPath = $null
$ngxOutputProbeFlagOriginal = $null

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
            -UsePrebuiltProductionShader:$UsePrebuiltProductionShader `
            -DiagnosticRenderHooks:$DiagnosticRenderHooks `
            -ClusterLightTrace:$ClusterLightTrace `
            -ClusterLightVisibilityFix:$ClusterLightVisibilityFix
    }
}

# The selected installation may differ from this checkout, especially during a
# focused trial with sync skipped. Compile what the game will actually load,
# including its descriptor and extra companions, before launch preparation.
& $luaSourceCheck -SourcePath (Join-Path $GameRoot `
    'mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua')

if ($TuneWorkerThreads -and -not (Get-Process Darktide -ErrorAction SilentlyContinue)) {
    & (Join-Path $PSScriptRoot 'set-vr-worker-threads.ps1') -Action Apply
}

$psykhaniumRequest = $null

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
$launchFailure = $null
$cleanLaunchSaved = @{}
. (Join-Path $PSScriptRoot 'clean-launch-diagnostics.ps1')
$advanceProcess = $null
$characterStartFlag = Join-Path $GameRoot 'mods\darktidevr\darktidevr_start_character.flag'
try {
$gameAlreadyRunning = [bool](Get-Process Darktide -ErrorAction SilentlyContinue)
if (-not $gameAlreadyRunning -and -not $PreserveDiagnosticFlags) {
    Set-CleanLaunchDiagnostics -ModRoot (Join-Path $GameRoot 'mods/darktidevr') `
        -Saved $cleanLaunchSaved -CopyProbe $StreamlineCopyProbe.IsPresent `
        -TransportProbe $StreamlineTransportProbe.IsPresent `
        -PerformanceProfile $EnablePerformanceProfile.IsPresent `
        -PerformancePassTrace $EnablePerformancePassTrace.IsPresent
    Write-Output "launch.optional_diagnostics=clean suppressed_files=$($cleanLaunchSaved.Count)"
}
if ($EnterPsykhanium -and $gameAlreadyRunning) {
    throw 'Psykhanium entry must be armed before Darktide starts; close the game and retry.'
}
if (-not $gameAlreadyRunning) {
    $rangeAction = if ($EnterPsykhanium) { 'enter' } else { 'disabled' }
    $psykhaniumRequest = Set-PsykhaniumLaunchRequest -GameRoot $GameRoot -Action $rangeAction
    Write-Output "Psykhanium one-shot request: $rangeAction (owned by this launch)."
}
if ($EnterPsykhanium) {

    # The in-game one-shot state machine deliberately waits for an
    # authenticated hub before opening the training-ground view.  Therefore
    # Psykhanium entry also owns the guarded splash/operative advance; without
    # it an unattended run can remain at character select until its timeout.
    $AutoEnterHub = $true
}

# One-shot mod callback: use the actual ready Start action without depending on
# desktop focus or synthetic confirmation timing. Keyboard input stays enabled.
$characterStartRequest = if ($AutoEnterHub -and -not $ManualStartup -and -not $ManualCharacterSelect) { 'start' } else { 'disabled' }
Set-Content -LiteralPath $characterStartFlag -Value $characterStartRequest -Encoding ascii

if ($StreamlineProbe -or $StreamlineCopyProbe -or
        $StreamlineTransportProbe -or $StreamlineInputSnapshotProbe -or
        $StreamlineTargetTokenProbe -or $StreamlineEyeTargetProbe -or $StreamlineStereoSwapchainProbe -or
        $StreamlineStereoStageProbe) {
    $streamlineProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_streamline_probe.flag'
    $streamlineProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineProbeFlagPath -PathType Leaf
    if ($streamlineProbeFlagExisted) {
        $streamlineProbeFlagOriginal = [IO.File]::ReadAllBytes($streamlineProbeFlagPath)
    }
    Set-Content -LiteralPath $streamlineProbeFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output `
        'Observe-only Streamline/Present probe enabled for this run.'
}
if ($StreamlineCopyProbe) {
    $streamlineCopyProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_streamline_copy_probe.flag'
    $streamlineCopyProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineCopyProbeFlagPath -PathType Leaf
    if ($streamlineCopyProbeFlagExisted) {
        $streamlineCopyProbeFlagOriginal = [IO.File]::ReadAllBytes($streamlineCopyProbeFlagPath)
    }
    Set-Content -LiteralPath $streamlineCopyProbeFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output `
        'One-shot Streamline generated-backbuffer copy probe enabled.'
}
if ($StreamlineTransportProbe) {
    $streamlineTransportProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_streamline_transport_probe.flag'
    $streamlineTransportProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineTransportProbeFlagPath -PathType Leaf
    if ($streamlineTransportProbeFlagExisted) {
        $streamlineTransportProbeFlagOriginal = [IO.File]::ReadAllBytes($streamlineTransportProbeFlagPath)
    }
    Set-Content -LiteralPath $streamlineTransportProbeFlagPath `
        -Value 'enabled' -Encoding ascii
    Write-Output 'Bounded Streamline generated-output transport probe enabled.'
}
if ($StreamlineInputSnapshotProbe -or $StreamlineTargetTokenProbe) {
    $streamlineInputSnapshotProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_streamline_input_snapshot_probe.flag'
    $streamlineInputSnapshotProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineInputSnapshotProbeFlagPath -PathType Leaf
    if ($streamlineInputSnapshotProbeFlagExisted) {
        $streamlineInputSnapshotProbeFlagOriginal = [IO.File]::ReadAllBytes($streamlineInputSnapshotProbeFlagPath)
    }
    Set-Content -LiteralPath $streamlineInputSnapshotProbeFlagPath `
        -Value 'enabled' -Encoding ascii
    Write-Output 'One-pair Streamline input snapshot probe enabled.'
}
if ($StreamlineTargetTokenProbe) {
    $streamlineTargetTokenProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_streamline_target_token_probe.flag'
    $streamlineTargetTokenProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineTargetTokenProbeFlagPath -PathType Leaf
    if ($streamlineTargetTokenProbeFlagExisted) {
        $streamlineTargetTokenProbeFlagOriginal = [IO.File]::ReadAllBytes($streamlineTargetTokenProbeFlagPath)
    }
    Set-Content -LiteralPath $streamlineTargetTokenProbeFlagPath `
        -Value 'enabled' -Encoding ascii
    Write-Output 'One-shot Streamline stereo target-token probe enabled.'
}
if ($StreamlineEyeTargetProbe) {
    $streamlineEyeTargetProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_streamline_eye_target_probe.flag'
    $streamlineEyeTargetProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineEyeTargetProbeFlagPath -PathType Leaf
    if ($streamlineEyeTargetProbeFlagExisted) {
        $streamlineEyeTargetProbeFlagOriginal = [IO.File]::ReadAllBytes($streamlineEyeTargetProbeFlagPath)
    }
    Set-Content -LiteralPath $streamlineEyeTargetProbeFlagPath `
        -Value 'enabled' -Encoding ascii
    Write-Output 'Isolated gameplay eye targets enabled for this diagnostic.'
}
if ($nativeOriginalRingDefault) {
    # The native module reads the flag beside the DLL it was loaded from; both
    # installed copies get one. Persistent FG launches publish originals through
    # the continuous submission and never construct this ring.
    foreach ($ringDirectory in @('mods\darktidevr\bin', 'binaries')) {
        $ringFlagPath = Join-Path $GameRoot (Join-Path $ringDirectory 'darktidevr_native_original_ring.flag')
        $ringFlagExisted = Test-Path -LiteralPath $ringFlagPath -PathType Leaf
        $nativeOriginalRingFlags += [pscustomobject]@{
            Path = $ringFlagPath
            Existed = $ringFlagExisted
            Original = if ($ringFlagExisted) { [IO.File]::ReadAllBytes($ringFlagPath) } else { $null }
        }
        Set-Content -LiteralPath $ringFlagPath -Value "[probe]`r`nenabled=1" -Encoding ascii
    }
    Write-Output 'Native original ring enabled for this native stereo run.'
}
if ($StreamlineStereoSwapchainProbe) {
    $streamlineStereoSwapchainProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_streamline_stereo_swapchain_probe.flag'
    $streamlineStereoSwapchainProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineStereoSwapchainProbeFlagPath -PathType Leaf
    if ($streamlineStereoSwapchainProbeFlagExisted) {
        $streamlineStereoSwapchainProbeFlagOriginal = [IO.File]::ReadAllBytes($streamlineStereoSwapchainProbeFlagPath)
    }
    Set-Content -LiteralPath $streamlineStereoSwapchainProbeFlagPath `
        -Value 'enabled' -Encoding ascii
    Write-Output 'Wide stereo Streamline swapchain probe enabled.'
}
if ($StreamlineStereoStageProbe) {
    $streamlineStereoStageProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_streamline_stereo_stage_probe.flag'
    $streamlineStereoStageProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineStereoStageProbeFlagPath -PathType Leaf
    if ($streamlineStereoStageProbeFlagExisted) {
        $streamlineStereoStageProbeFlagOriginal = [IO.File]::ReadAllBytes($streamlineStereoStageProbeFlagPath)
    }
    Set-Content -LiteralPath $streamlineStereoStageProbeFlagPath `
        -Value 'enabled' -Encoding ascii
    Write-Output 'One-shot stereo Present staging probe enabled.'
}
if ($NgxOutputProbe) {
    $ngxOutputProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_ngx_output_probe.flag'
    if (Test-Path -LiteralPath $ngxOutputProbeFlagPath -PathType Leaf) {
        $ngxOutputProbeFlagOriginal = [IO.File]::ReadAllBytes($ngxOutputProbeFlagPath)
    }
    $ngxWaitForStereo = if ($NgxOutputProbeAtStereoSubmit) { 1 } else { 0 }
    $ngxCopyOutput = if ($NgxOutputCopyProbe) { 1 } else { 0 }
    Set-Content -LiteralPath $ngxOutputProbeFlagPath `
        -Value "[probe]`nwait_for_stereo=$ngxWaitForStereo`ncopy_output=$ngxCopyOutput`ngenerated_stereo=$([int]$DlssGeneratedStereo.IsPresent)`nobserve_sr_inputs=$([int]$ObserveDlssSrInputs.IsPresent)" -Encoding ascii
    if ($ObserveDlssSrInputs) { Write-Output 'Bounded DLSS SR input observation enabled.' }
    if ($DlssGeneratedStereo) { Write-Output 'Experimental sustained generated stereo publication enabled.' }
    else { Write-Output 'Bounded NGX output identity observation enabled; no generated XR publication.' }
    if ($NgxOutputCopyProbe) { Write-Output 'One private generated stereo output copy/readback armed.' }
}
if ($StreamlineStereoSubmitProbe) {
    $streamlineStereoSubmitProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_streamline_stereo_submit_probe.flag'
    $streamlineStereoSubmitProbeFlagExisted = Test-Path -LiteralPath `
        $streamlineStereoSubmitProbeFlagPath -PathType Leaf
    if ($streamlineStereoSubmitProbeFlagExisted) {
        $streamlineStereoSubmitProbeFlagOriginal = [IO.File]::ReadAllBytes($streamlineStereoSubmitProbeFlagPath)
    }
    Set-Content -LiteralPath $streamlineStereoSubmitProbeFlagPath `
        -Value "[probe]`nframes=$StreamlineStereoSubmitFrames`ncontinuous=$([int]$StreamlineContinuousSubmitProbe.IsPresent)`npersistent=$([int]$DlssGeneratedStereo.IsPresent)" -Encoding ascii
    if ($DlssGeneratedStereo) { Write-Output 'Sustained stereo tags enabled with eight reusable input owners.' }
    else { Write-Output "Stereo tag submission enabled for $StreamlineStereoSubmitFrames batches; generated XR publication remains disabled." }
}
# The native module and the Lua mod default to the accepted play configuration
# when one of these flags is absent. A development launch that did not request
# a probe must therefore say so explicitly, and the file goes away afterwards.
$playDefaultOffFlags = @()
foreach ($playDefault in @(
        @{ Requested = [bool] $streamlineProbeFlagPath; Name = 'darktidevr_streamline_probe.flag'; Value = 'disabled' },
        @{ Requested = [bool] $streamlineInputSnapshotProbeFlagPath; Name = 'darktidevr_streamline_input_snapshot_probe.flag'; Value = 'disabled' },
        @{ Requested = [bool] $streamlineTargetTokenProbeFlagPath; Name = 'darktidevr_streamline_target_token_probe.flag'; Value = 'disabled' },
        @{ Requested = [bool] $streamlineEyeTargetProbeFlagPath; Name = 'darktidevr_streamline_eye_target_probe.flag'; Value = 'disabled' },
        @{ Requested = [bool] $streamlineStereoSwapchainProbeFlagPath; Name = 'darktidevr_streamline_stereo_swapchain_probe.flag'; Value = 'disabled' },
        @{ Requested = [bool] $streamlineStereoStageProbeFlagPath; Name = 'darktidevr_streamline_stereo_stage_probe.flag'; Value = 'disabled' },
        @{ Requested = [bool] $ngxOutputProbeFlagPath; Name = 'darktidevr_ngx_output_probe.flag'; Value = "[probe]`nwait_for_stereo=0`ncopy_output=0`ngenerated_stereo=0`nobserve_sr_inputs=0" },
        @{ Requested = [bool] $streamlineStereoSubmitProbeFlagPath; Name = 'darktidevr_streamline_stereo_submit_probe.flag'; Value = "[probe]`nframes=1`ncontinuous=0`npersistent=0" })) {
    if ($playDefault.Requested) { continue }
    $playDefaultPath = Join-Path $GameRoot (Join-Path 'mods\darktidevr' $playDefault.Name)
    $playDefaultExisted = Test-Path -LiteralPath $playDefaultPath -PathType Leaf
    $playDefaultOffFlags += [pscustomobject]@{
        Path = $playDefaultPath
        Existed = $playDefaultExisted
        Original = if ($playDefaultExisted) { [IO.File]::ReadAllBytes($playDefaultPath) } else { $null }
    }
    Set-Content -LiteralPath $playDefaultPath -Value $playDefault.Value -Encoding ascii
}
if ($playDefaultOffFlags.Count -gt 0) {
    Write-Output "Play defaults explicitly off for this run: $($playDefaultOffFlags.Count) flag(s)."
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
        "mods\darktidevr\bin\billboard_shaders\ps-$BillboardPixelShaderProbeHash.dxil"
    $billboardPixelProbeDestinationExisted = Test-Path -LiteralPath `
        $billboardPixelProbeDestinationPath -PathType Leaf
    if ($billboardPixelProbeDestinationExisted) {
        $billboardPixelProbeDestinationOriginal =
            [IO.File]::ReadAllBytes($billboardPixelProbeDestinationPath)
    }
    Copy-Item -LiteralPath $probeSource `
        -Destination $billboardPixelProbeDestinationPath -Force
    $billboardPixelProbeFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_billboard_pixel_shader_probe.flag'
    $billboardPixelProbeFlagExisted = Test-Path -LiteralPath `
        $billboardPixelProbeFlagPath -PathType Leaf
    if ($billboardPixelProbeFlagExisted) {
        $billboardPixelProbeFlagOriginal = [IO.File]::ReadAllBytes($billboardPixelProbeFlagPath)
    }
    Set-Content -LiteralPath $billboardPixelProbeFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output `
        "Exact billboard pixel probe enabled for hash=$BillboardPixelShaderProbeHash"
}
if ($EnableGameplayReticle -and -not $offlineNoHeadset) {
    $candidateControllerAimFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_controller_aim_test.flag'
    if (-not (Test-Path -LiteralPath $candidateControllerAimFlagPath -PathType Leaf)) {
        throw "Controller-aim test flag not found: $candidateControllerAimFlagPath"
    }
    $controllerAimFlagOriginal = [IO.File]::ReadAllBytes($candidateControllerAimFlagPath)
    $controllerAimFlagPath = $candidateControllerAimFlagPath
    Set-Content -LiteralPath $controllerAimFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output 'Controller aim enabled for this reticle run.'
}
if ($EnableHudPanel) {
    $candidateHudPanelFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_hud_panel.flag'
    # The panel is on by default; an absent flag is restored to 'disabled',
    # which the panel ignores, so the run's 'enable' command stays one-shot.
    $hudPanelFlagOriginal = if (Test-Path -LiteralPath $candidateHudPanelFlagPath -PathType Leaf) {
        [IO.File]::ReadAllBytes($candidateHudPanelFlagPath)
    } else {
        [Text.Encoding]::ASCII.GetBytes("disabled`r`n")
    }
    $hudPanelFlagPath = $candidateHudPanelFlagPath
    Set-Content -LiteralPath $hudPanelFlagPath -Value 'enable' `
        -Encoding ascii
    Write-Output 'Fixed HUD panel enabled for this XR run.'
}
if ($EnablePerformanceProfile) {
    $candidatePerformanceProfileFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_performance_profile.flag'
    if (-not (Test-Path -LiteralPath `
            $candidatePerformanceProfileFlagPath -PathType Leaf)) {
        throw "Performance-profile flag not found: $candidatePerformanceProfileFlagPath"
    }
    $performanceProfileFlagOriginal = [IO.File]::ReadAllBytes($candidatePerformanceProfileFlagPath)
    $performanceProfileFlagPath = $candidatePerformanceProfileFlagPath
    Set-Content -LiteralPath $performanceProfileFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output 'Performance profiling enabled for this XR run.'
}
if ($EnablePerformancePassTrace) {
    $candidatePerformancePassTraceFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_performance_pass_trace.flag'
    if (-not (Test-Path -LiteralPath `
            $candidatePerformancePassTraceFlagPath -PathType Leaf)) {
        throw "Performance-pass trace flag not found: $candidatePerformancePassTraceFlagPath"
    }
    $performancePassTraceFlagOriginal = [IO.File]::ReadAllBytes($candidatePerformancePassTraceFlagPath)
    $performancePassTraceFlagPath = $candidatePerformancePassTraceFlagPath
    Set-Content -LiteralPath $performancePassTraceFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output 'Performance pass tracing enabled for this XR run.'
}
if ($offlineNoHeadset) {
    $candidateOfflineDualViewFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_offline_dual_view.flag'
    $offlineDualViewFlagExisted = Test-Path -LiteralPath `
        $candidateOfflineDualViewFlagPath -PathType Leaf
    if ($offlineDualViewFlagExisted) {
        $offlineDualViewFlagOriginal = [IO.File]::ReadAllBytes($candidateOfflineDualViewFlagPath)
    }
    $offlineDualViewFlagPath = $candidateOfflineDualViewFlagPath
    Set-Content -LiteralPath $offlineDualViewFlagPath -Value 'enabled' `
        -Encoding ascii
    if ($OfflineDualViewBenchmark) {
        Write-Output "Offline dual-view benchmark enabled; solo_mission=$OfflineSoloMission (empty means hub spin)."
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
                -not $_.HasExited -and $_.Path -eq $expectedLauncherPath
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
    & (Join-Path $PSScriptRoot 'set-darktide-windowed.ps1')
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

if (-not $ManualStartup -and ($AutoEnterHub -or $AutoAdvanceSplash)) {
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
    if ($ManualCharacterSelect -or ($AutoAdvanceSplash -and -not $AutoEnterHub)) {
        $advanceArguments += '-StopAtCharacterSelect'
    }
    $advanceGames = @(Get-Process Darktide -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -ieq $expectedGamePath })
    if ($advanceGames.Count -gt 1) { throw 'Startup advance requires one Darktide process.' }
    if ($advanceGames.Count -eq 1) { $advanceArguments += @('-GameProcessId', $advanceGames[0].Id) }
    $advanceLogRoot = Join-Path $repoRoot 'artifacts\unattended'
    New-Item -ItemType Directory -Path $advanceLogRoot -Force | Out-Null
    $advanceLogStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
    $advanceProcess = Start-Process -FilePath $powershell -WindowStyle Hidden `
        -ArgumentList $advanceArguments -PassThru `
        -RedirectStandardOutput (Join-Path $advanceLogRoot "character-select-$advanceLogStamp.log") `
        -RedirectStandardError (Join-Path $advanceLogRoot "character-select-$advanceLogStamp.err.log")
    if ($AutoEnterHub -and -not $ManualCharacterSelect) {
        Write-Output 'Armed title Space and one-shot stock Start callback through character select.'
    }
    else {
        Write-Output 'Armed state-gated Space automation to character select.'
    }
}

if ($offlineNoHeadset) {
    Write-Output 'Waiting for the offline Darktide workload to become ready.'
}
else {
    Write-Output 'Waiting for the Darktide splash window; XR will start as soon as it exists.'
}
if ($ReticleInEyes) {
    # Inherited by the viewer started below (src/xr/main.cpp).
    $env:DTVR_XR_RETICLE_IN_EYES = '1'
    Write-Output 'Gameplay reticle: drawn into the eye images, not as a quad layer.'
}
if (-not $LegacyViewerTiming) {
    # Inherited by the viewer started below. Both were part of the 11 September
    # performance bundle; see docs/PERFORMANCE-BUNDLE-2026-09-11.md.
    $env:DTVR_XR_PRECISE_PAIR_WAIT = '1'
    $env:DTVR_XR_NATIVE_ORIGINAL_DIRECT = '1'
    Write-Output 'Viewer timing defaults: precise pair wait and direct native originals.'
}
$runnerArguments = @{
    DurationSeconds = $DurationSeconds
    WaitForGameSeconds = $GameStartTimeoutSeconds
    ProjectionTranslationScale = $ProjectionTranslationScale
    GameExe = Join-Path $GameRoot 'binaries\Darktide.exe'
    RequireSharedStereo = [bool]($AutoEnterHub -or $EnterPsykhanium)
    DebugLayer = $XrDebugLayer.IsPresent
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
if ($MenuAimStabilization) {
    $runnerArguments.MenuAimStabilization = $true
}
if ($SyntheticGameplayInput) {
    $candidateGameplayInputFlagPath = Join-Path $GameRoot `
        'mods\darktidevr\darktidevr_gameplay_input_test.flag'
    if (-not (Test-Path -LiteralPath $candidateGameplayInputFlagPath -PathType Leaf)) {
        throw "Gameplay-input test flag not found: $candidateGameplayInputFlagPath"
    }
    $gameplayInputFlagOriginal = [IO.File]::ReadAllBytes($candidateGameplayInputFlagPath)
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
    $observedBenchmarkGameId = $null
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
        if ($game) {
            if ($null -ne $observedBenchmarkGameId -and $game.Id -ne $observedBenchmarkGameId) {
                throw 'The benchmark game process changed before readiness.'
            }
            $observedBenchmarkGameId = $game.Id
        }
        elseif ($null -ne $observedBenchmarkGameId) {
            throw 'The benchmark game exited before workload readiness.'
        }
        $benchmarkLog = Get-ChildItem -LiteralPath $consoleLogRoot `
                -Filter '*.log' -ErrorAction SilentlyContinue |
            Where-Object LastWriteTime -ge $launchStarted |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($game -and $benchmarkLog) {
            $benchmarkText = Get-Content -LiteralPath $benchmarkLog.FullName `
                -Raw -ErrorAction SilentlyContinue
            if ($benchmarkText -match '\[MOD\]\[darktidevr\]\[ERROR\].*mod_script.*initialization') {
                throw 'The stereo mod failed initialization; inspect the launch console log.'
            }
            $ready = if ($OfflineDualViewBenchmark) {
                Test-DarktideOfflineWorkloadReady -ConsoleText $benchmarkText -SoloMission $OfflineSoloMission
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
            throw 'Timed out waiting for the selected offline dual-view workload.'
        }
        if ($OfflineCharacterSelectCapture) {
            throw 'Timed out waiting for the offline character-select identity capture.'
        }
        throw 'Timed out waiting for the offline title identity capture.'
    }
    if ($OfflineDualViewBenchmark) {
        Write-Output "Offline dual-view benchmark started; log=$($benchmarkLog.FullName)"
        Write-Output "offline_benchmark.started_utc=$([DateTime]::UtcNow.ToString('o'))"
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
catch { $launchFailure = $_; throw }
finally {
    # Attempt every independent owner even if an earlier restoration fails.
    $cleanupSteps = @(
    {
        Restore-CleanLaunchDiagnostics -Saved $cleanLaunchSaved
    }
    {
        if (Test-Path -LiteralPath variable:playDefaultOffFlags) {
            foreach ($playDefaultFlag in $playDefaultOffFlags) {
                if ($playDefaultFlag.Existed) {
                    Restore-FlagOriginal -LiteralPath $playDefaultFlag.Path -Original $playDefaultFlag.Original
                }
                elseif (Test-Path -LiteralPath $playDefaultFlag.Path -PathType Leaf) {
                    Remove-Item -LiteralPath $playDefaultFlag.Path -Force
                }
            }
        }
    }
    {
        if (Test-Path -LiteralPath $characterStartFlag -PathType Leaf) {
            Remove-Item -LiteralPath $characterStartFlag -Force
        }
    }
    {
        if ($advanceProcess) {
            try {
                $advanceProcess.Refresh()
                if (-not $advanceProcess.HasExited) { $advanceProcess.Kill() }
            } finally {
                $advanceProcess.Dispose()
            }
        }
    }
    {
        if ($ngxOutputProbeFlagPath) {
            if ($null -ne $ngxOutputProbeFlagOriginal) {
                Restore-FlagOriginal -LiteralPath $ngxOutputProbeFlagPath -Original $ngxOutputProbeFlagOriginal
            }
            elseif (Test-Path -LiteralPath $ngxOutputProbeFlagPath -PathType Leaf) {
                Remove-Item -LiteralPath $ngxOutputProbeFlagPath -Force
            }
        }
    }
    {
        if ($streamlineStereoSubmitProbeFlagPath) {
            if ($streamlineStereoSubmitProbeFlagExisted) {
                Restore-FlagOriginal -LiteralPath $streamlineStereoSubmitProbeFlagPath -Original $streamlineStereoSubmitProbeFlagOriginal
            }
            elseif (Test-Path -LiteralPath $streamlineStereoSubmitProbeFlagPath -PathType Leaf) {
                Remove-Item -LiteralPath $streamlineStereoSubmitProbeFlagPath -Force
            }
        }
    }
    {
        if ($streamlineProbeFlagPath) {
            if ($streamlineProbeFlagExisted) {
                Restore-FlagOriginal -LiteralPath $streamlineProbeFlagPath -Original $streamlineProbeFlagOriginal
            }
            elseif (Test-Path -LiteralPath $streamlineProbeFlagPath `
                    -PathType Leaf) {
                Remove-Item -LiteralPath $streamlineProbeFlagPath -Force
            }
            Write-Output 'Restored the prior Streamline probe flag.'
        }
    }
    {
        if ($streamlineCopyProbeFlagPath) {
            if ($streamlineCopyProbeFlagExisted) {
                Restore-FlagOriginal -LiteralPath $streamlineCopyProbeFlagPath -Original $streamlineCopyProbeFlagOriginal
            }
            elseif (Test-Path -LiteralPath $streamlineCopyProbeFlagPath `
                    -PathType Leaf) {
                Remove-Item -LiteralPath $streamlineCopyProbeFlagPath -Force
            }
            Write-Output 'Restored the prior Streamline copy-probe flag.'
        }
    }
    {
        if ($streamlineTransportProbeFlagPath) {
            if ($streamlineTransportProbeFlagExisted) {
                Restore-FlagOriginal -LiteralPath $streamlineTransportProbeFlagPath -Original $streamlineTransportProbeFlagOriginal
            }
            elseif (Test-Path -LiteralPath $streamlineTransportProbeFlagPath `
                    -PathType Leaf) {
                Remove-Item -LiteralPath $streamlineTransportProbeFlagPath -Force
            }
            Write-Output 'Restored the prior Streamline transport-probe flag.'
        }
    }
    {
        if ($streamlineInputSnapshotProbeFlagPath) {
            if ($streamlineInputSnapshotProbeFlagExisted) {
                Restore-FlagOriginal -LiteralPath $streamlineInputSnapshotProbeFlagPath -Original $streamlineInputSnapshotProbeFlagOriginal
            }
            elseif (Test-Path -LiteralPath $streamlineInputSnapshotProbeFlagPath `
                    -PathType Leaf) {
                Remove-Item -LiteralPath $streamlineInputSnapshotProbeFlagPath `
                    -Force
            }
            Write-Output 'Restored the prior Streamline input-snapshot flag.'
        }
    }
    {
        if ($streamlineTargetTokenProbeFlagPath) {
            if ($streamlineTargetTokenProbeFlagExisted) {
                Restore-FlagOriginal -LiteralPath $streamlineTargetTokenProbeFlagPath -Original $streamlineTargetTokenProbeFlagOriginal
            }
            elseif (Test-Path -LiteralPath $streamlineTargetTokenProbeFlagPath `
                    -PathType Leaf) {
                Remove-Item -LiteralPath $streamlineTargetTokenProbeFlagPath `
                    -Force
            }
            Write-Output 'Restored the prior Streamline target-token flag.'
        }
    }
    {
        if ($streamlineEyeTargetProbeFlagPath) {
            if ($streamlineEyeTargetProbeFlagExisted) {
                Restore-FlagOriginal -LiteralPath $streamlineEyeTargetProbeFlagPath -Original $streamlineEyeTargetProbeFlagOriginal
            }
            elseif (Test-Path -LiteralPath $streamlineEyeTargetProbeFlagPath `
                    -PathType Leaf) {
                Remove-Item -LiteralPath $streamlineEyeTargetProbeFlagPath `
                    -Force
            }
            Write-Output 'Restored the prior Streamline eye-target flag.'
        }
    }
    {
        # The cleanup continuation can run before the ring flags were touched.
        $ringFlags = @()
        if (Test-Path -LiteralPath variable:nativeOriginalRingFlags) { $ringFlags = @($nativeOriginalRingFlags) }
        foreach ($ringFlag in $ringFlags) {
            if ($ringFlag.Existed) {
                Restore-FlagOriginal -LiteralPath $ringFlag.Path -Original $ringFlag.Original
            }
            elseif (Test-Path -LiteralPath $ringFlag.Path -PathType Leaf) {
                Remove-Item -LiteralPath $ringFlag.Path -Force
            }
        }
        if ($ringFlags.Count -gt 0) {
            Write-Output 'Restored the prior native original ring flags.'
        }
    }
    {
        if ($streamlineStereoSwapchainProbeFlagPath) {
            if ($streamlineStereoSwapchainProbeFlagExisted) {
                Restore-FlagOriginal -LiteralPath $streamlineStereoSwapchainProbeFlagPath -Original $streamlineStereoSwapchainProbeFlagOriginal
            }
            elseif (Test-Path -LiteralPath $streamlineStereoSwapchainProbeFlagPath `
                    -PathType Leaf) {
                Remove-Item -LiteralPath $streamlineStereoSwapchainProbeFlagPath `
                    -Force
            }
            Write-Output 'Restored the prior Streamline stereo-swapchain flag.'
        }
    }
    {
        if ($streamlineStereoStageProbeFlagPath) {
            if ($streamlineStereoStageProbeFlagExisted) {
                Restore-FlagOriginal -LiteralPath $streamlineStereoStageProbeFlagPath -Original $streamlineStereoStageProbeFlagOriginal
            }
            elseif (Test-Path -LiteralPath $streamlineStereoStageProbeFlagPath `
                    -PathType Leaf) {
                Remove-Item -LiteralPath $streamlineStereoStageProbeFlagPath `
                    -Force
            }
            Write-Output 'Restored the prior Streamline stereo-stage flag.'
        }
    }
    {
        if ($syntheticHeadPublisher) {
            if (-not $syntheticHeadPublisher.HasExited) {
                $syntheticHeadPublisher | Stop-Process -Force
            }
            Write-Output 'Stopped the run-owned synthetic head publisher.'
        }
    }
    {
        if ($billboardPixelProbeFlagPath) {
            if ($billboardPixelProbeFlagExisted) {
                Restore-FlagOriginal -LiteralPath $billboardPixelProbeFlagPath -Original $billboardPixelProbeFlagOriginal
            }
            elseif (Test-Path -LiteralPath $billboardPixelProbeFlagPath -PathType Leaf) {
                Remove-Item -LiteralPath $billboardPixelProbeFlagPath -Force
            }
        }
    }
    {
        if ($billboardPixelProbeFlagPath) {
            if ($billboardPixelProbeDestinationExisted) {
                [IO.File]::WriteAllBytes(
                    $billboardPixelProbeDestinationPath,
                    $billboardPixelProbeDestinationOriginal)
            }
            elseif (Test-Path -LiteralPath $billboardPixelProbeDestinationPath `
                    -PathType Leaf) {
                Remove-Item -LiteralPath $billboardPixelProbeDestinationPath -Force
            }
        }
    }
    {
        if ($offlineDualViewFlagPath) {
            if ($offlineDualViewFlagExisted) {
                Restore-FlagOriginal -LiteralPath $offlineDualViewFlagPath -Original $offlineDualViewFlagOriginal
            }
            elseif (Test-Path -LiteralPath $offlineDualViewFlagPath -PathType Leaf) {
                Remove-Item -LiteralPath $offlineDualViewFlagPath -Force
            }
            Write-Output 'Restored the prior offline dual-view benchmark flag.'
        }
    }
    {
        if ($performancePassTraceFlagPath) {
            Restore-FlagOriginal -LiteralPath $performancePassTraceFlagPath -Original $performancePassTraceFlagOriginal
            Write-Output 'Restored the prior performance-pass trace flag.'
        }
    }
    {
        if ($performanceProfileFlagPath) {
            Restore-FlagOriginal -LiteralPath $performanceProfileFlagPath -Original $performanceProfileFlagOriginal
            Write-Output 'Restored the prior performance-profile flag.'
        }
    }
    {
        if ($controllerAimFlagPath) {
            Restore-FlagOriginal -LiteralPath $controllerAimFlagPath -Original $controllerAimFlagOriginal
            Write-Output 'Restored the prior controller-aim test flag.'
        }
    }
    {
        if ($hudPanelFlagPath) {
            Restore-FlagOriginal -LiteralPath $hudPanelFlagPath -Original $hudPanelFlagOriginal
            Write-Output 'Restored the prior HUD-panel test flag.'
        }
    }
    {
        if ($gameplayInputFlagPath) {
            Restore-FlagOriginal -LiteralPath $gameplayInputFlagPath -Original $gameplayInputFlagOriginal
            Write-Output 'Restored the prior gameplay-input test flag.'
        }
    }
    {
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
    }
    {
        if ($psykhaniumRequest) {
            Clear-PsykhaniumLaunchRequest -Request $psykhaniumRequest
            Write-Output 'Retired this launch''s Psykhanium request without restoring old commands.'
        }
    }
    {
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
    )
    $cleanupFailures = [Collections.Generic.List[string]]::new()
    foreach ($cleanupStep in $cleanupSteps) {
        try { & $cleanupStep }
        catch { $cleanupFailures.Add($_.Exception.Message) }
    }
    if ($cleanupFailures.Count -gt 0) {
        $cleanupMessage = 'Launch cleanup failed: ' + ($cleanupFailures -join '; ')
        if ($launchFailure) {
            # Keep the original launch exception after reporting cleanup damage.
            Write-Warning -Message $cleanupMessage -WarningAction Continue
        } else {
            throw $cleanupMessage
        }
    }
}
