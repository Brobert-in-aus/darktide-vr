[CmdletBinding()]
param(
    [ValidateRange(5, 43200)]
    [int] $DurationSeconds = 300,

    [string] $GameExe =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\binaries\Darktide.exe',

    [string] $Harness =
        (Join-Path $PSScriptRoot '..\..\build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe'),

    [switch] $EnableMenuInput,

    [switch] $DebugLayer,

    [switch] $RequireSharedStereo,

    [switch] $EnableMenuTestControls,

    [switch] $SyntheticControllerPath,

    [switch] $MenuAimStabilization,

    [switch] $SyntheticGameplayInput,

    [switch] $SyntheticWeaponAimMatrix,

    [switch] $SyntheticMovementReferencePath,

    [switch] $EnableGameplayReticle = $true,

    [switch] $TrackedCuffOverlay,

    [switch] $SyntheticBodyPath,

    [switch] $SyntheticHeadSweep,

    [switch] $SyntheticBodyInspection,

    [switch] $SyntheticNeckPivotPath,

    [switch] $SyntheticRoomscalePath,

    [switch] $SyntheticCrouchPath,

    [ValidateRange(0, 1800)]
    [int] $WaitForGameSeconds = 0,

    [ValidateRange(-2.0, 2.0)]
    [double] $ProjectionTranslationScale = 1.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
. (Join-Path $PSScriptRoot 'darktide-process-result.ps1')
. (Join-Path $PSScriptRoot 'shared-stereo-evidence.ps1')
$observedGameProcess = $null

# The shared mapping has one producer sequence and no multi-writer arbitration.
# Two harnesses therefore make pose/frame sequence numbers run backwards and
# the Lua consumer repeatedly resets its capture tags. Hold a named mutex for
# the complete native session, and also reject an older harness that predates
# this guard but is still alive.
$singleWriterMutex = [Threading.Mutex]::new(
    $false,
    'Local\DarktideVR_XR_Harness_SingleWriter')
$singleWriterAcquired = $false
try {
    $singleWriterAcquired = $singleWriterMutex.WaitOne(0)
    if (-not $singleWriterAcquired) {
        throw 'Another Darktide VR XR runner owns the shared-eye mapping.'
    }
    $existingHarnesses = @(Get-Process -Name 'darktidevr-xr-harness' `
        -ErrorAction SilentlyContinue)
    if ($existingHarnesses.Count -gt 0) {
        $existingPids = ($existingHarnesses.Id | Sort-Object) -join ','
        throw "A pre-guard XR harness is already running (PID $existingPids). Stop it before launching another writer."
    }

$knownPatchedSha256 =
    '6fce8db87a77a412b22ef9f33f74fa16ef85126cc0fbb24187d78b85fc7a19d3'

if (-not (Test-Path -LiteralPath $GameExe -PathType Leaf)) {
    throw "Darktide executable not found: $GameExe"
}
$resolvedGameExe = (Resolve-Path -LiteralPath $GameExe).Path
$actualHash = (Get-FileHash -LiteralPath $GameExe -Algorithm SHA256).
    Hash.ToLowerInvariant()
if ($actualHash -ne $knownPatchedSha256) {
    throw "Shared-eye stereo requires the exact guarded skinner patch; found $actualHash"
}

$eac = Get-Service EasyAntiCheat_EOS -ErrorAction SilentlyContinue
if ($eac -and $eac.Status -ne 'Stopped') {
    throw "Darktide stereo mode refuses to run while EAC is $($eac.Status)"
}

$waitDeadline = [DateTime]::UtcNow.AddSeconds($WaitForGameSeconds)
do {
    $game = @(Get-Process Darktide -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.Responding -and
                    $_.MainWindowTitle -eq 'Warhammer 40,000: Darktide' -and
                    $_.Path -ieq $resolvedGameExe
            }
            catch {
                $false
            }
        })
    if ($game.Count -eq 1 -or $WaitForGameSeconds -eq 0) {
        break
    }
    Start-Sleep -Milliseconds 250
} while ([DateTime]::UtcNow -lt $waitDeadline)

if ($game.Count -ne 1 -or -not $game[0].Responding) {
    throw "Expected exactly one responsive Darktide window; found $($game.Count)"
}
if ($game[0].MainWindowTitle -ne 'Warhammer 40,000: Darktide') {
    throw 'The running Darktide process does not expose the expected capture window'
}
$observedGameProcess = $game[0]
# Hold the exact process handle while it is alive so its exit code survives
# termination. The viewer's result=pass describes only the XR session.
$null = $observedGameProcess.Handle

$harnessPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $Harness)
if (-not (Test-Path -LiteralPath $harnessPath -PathType Leaf)) {
    throw "Release XR harness not found: $harnessPath"
}

$arguments = @(
    '--frames', '30',
    '--require-rendering',
    '--xr-seconds', $DurationSeconds,
    '--shared-eyes',
    '--capture-window-title', 'Warhammer 40,000: Darktide'
)
if ($DebugLayer) { $arguments += '--debug-layer' }
Write-Output "xr.debug_layer=$($DebugLayer.IsPresent.ToString().ToLowerInvariant())"
if ($EnableMenuInput) {
    $arguments += '--enable-menu-input'
}
if ($EnableMenuTestControls) {
    $arguments += '--enable-menu-test-controls'
}
if ($SyntheticControllerPath) {
    $arguments += '--synthetic-controller-path'
}
if ($SyntheticGameplayInput) {
    if (-not $SyntheticControllerPath) {
        throw '-SyntheticGameplayInput requires -SyntheticControllerPath'
    }
    $arguments += '--synthetic-gameplay-input'
}
if ($SyntheticWeaponAimMatrix) {
    if (-not $SyntheticGameplayInput) {
        throw '-SyntheticWeaponAimMatrix requires -SyntheticGameplayInput'
    }
    $arguments += '--synthetic-weapon-aim-matrix'
}
if ($SyntheticMovementReferencePath) {
    if (-not $SyntheticGameplayInput) {
        throw '-SyntheticMovementReferencePath requires -SyntheticGameplayInput'
    }
    $arguments += '--synthetic-movement-reference-path'
}
if ($EnableGameplayReticle) {
    $arguments += '--enable-gameplay-reticle'
}
if ($MenuAimStabilization) {
    $arguments += '--menu-aim-stabilization'
}
if ($TrackedCuffOverlay) {
    $arguments += '--tracked-cuff-overlay'
}
if ($SyntheticBodyPath) {
    if (-not $SyntheticControllerPath) {
        throw '-SyntheticBodyPath requires -SyntheticControllerPath'
    }
    $arguments += '--synthetic-body-path'
}
if ($SyntheticHeadSweep) {
    $arguments += '--synthetic-head-sweep'
}
if ($SyntheticBodyInspection) {
    $arguments += '--synthetic-body-inspection'
}
if ($SyntheticNeckPivotPath) {
    $arguments += '--synthetic-neck-pivot-path'
}
if ($SyntheticRoomscalePath) {
    $arguments += '--synthetic-roomscale-path'
}
if ($SyntheticCrouchPath) {
    $arguments += '--synthetic-crouch-path'
}
$arguments += '--projection-translation-scale'
$arguments += $ProjectionTranslationScale.ToString(
    [System.Globalization.CultureInfo]::InvariantCulture)

$priorErrorActionPreference = $ErrorActionPreference
$sharedStereoEvidence = @{}
$priorReticleScaleFile = $env:DTVR_RETICLE_SCALE_FILE
try {
    $env:DTVR_RETICLE_SCALE_FILE = Join-Path (Split-Path (Split-Path $resolvedGameExe -Parent) -Parent) 'mods\darktidevr_stereo_probe\darktidevr_crosshair_scale.flag'
    # The Khronos loader can write a diagnostic to stderr when the harness's
    # first API-version attempt is rejected, then succeed on its built-in
    # compatibility retry. Windows PowerShell converts native stderr into
    # ErrorRecord objects; with the launcher's Stop policy those records used
    # to abort the shortcut before the successful retry. Stream both native
    # channels back as ordinary text. Process failure remains authoritative;
    # automatic gameplay runs also require actual shared stereo delivery.
    $ErrorActionPreference = 'Continue'
    & $harnessPath @arguments 2>&1 | ForEach-Object {
        $line = [string] $_
        if ($RequireSharedStereo) {
            Add-SharedStereoEvidence -Evidence $sharedStereoEvidence -Line $line
        }
        Write-Output $line
    }
    $harnessExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $priorErrorActionPreference
    $env:DTVR_RETICLE_SCALE_FILE = $priorReticleScaleFile
}
$gameResult = Get-DarktideProcessResult -Process $observedGameProcess
Write-Output "game.result=$($gameResult.Status) exit_code=$($gameResult.ExitCode)"
if ($harnessExitCode -ne 0) {
    throw "Darktide stereo harness failed with exit code $harnessExitCode"
}
if ($gameResult.Status -eq 'failed') {
    throw "Darktide exited abnormally with code $($gameResult.ExitCode); XR viewer shutdown is not game stability."
}
if ($RequireSharedStereo) {
    Assert-SharedStereoEvidence -Evidence $sharedStereoEvidence
}
}
finally {
    if ($observedGameProcess) {
        $observedGameProcess.Dispose()
    }
    if ($singleWriterAcquired) {
        $singleWriterMutex.ReleaseMutex()
    }
    $singleWriterMutex.Dispose()
}
