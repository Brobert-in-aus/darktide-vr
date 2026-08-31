[CmdletBinding()]
param(
    [ValidateRange(5, 43200)]
    [int] $DurationSeconds = 300,

    [string] $GameExe =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\binaries\Darktide.exe',

    [string] $Harness =
        'build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe',

    [switch] $EnableMenuInput,

    [switch] $EnableMenuTestControls,

    [switch] $SyntheticControllerPath,

    [switch] $SyntheticGameplayInput,

    [switch] $SyntheticWeaponAimMatrix,

    [switch] $EnableGameplayReticle,

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
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop

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
            $_.Responding -and
            $_.MainWindowTitle -eq 'Warhammer 40,000: Darktide'
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

$harnessPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $Harness)
if (-not (Test-Path -LiteralPath $harnessPath -PathType Leaf)) {
    throw "Release XR harness not found: $harnessPath"
}

$arguments = @(
    '--frames', '30',
    '--debug-layer',
    '--require-rendering',
    '--xr-seconds', $DurationSeconds,
    '--shared-eyes',
    '--capture-window-title', 'Warhammer 40,000: Darktide'
)
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
if ($EnableGameplayReticle) {
    $arguments += '--enable-gameplay-reticle'
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
try {
    # The Khronos loader can write a diagnostic to stderr when the harness's
    # first API-version attempt is rejected, then succeed on its built-in
    # compatibility retry. Windows PowerShell converts native stderr into
    # ErrorRecord objects; with the launcher's Stop policy those records used
    # to abort the shortcut before the successful retry. Stream both native
    # channels back as ordinary text and use only the process exit code as the
    # success/failure contract.
    $ErrorActionPreference = 'Continue'
    & $harnessPath @arguments 2>&1 | ForEach-Object {
        Write-Output ([string] $_)
    }
    $harnessExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $priorErrorActionPreference
}
if ($harnessExitCode -ne 0) {
    throw "Darktide stereo harness failed with exit code $harnessExitCode"
}
}
finally {
    if ($singleWriterAcquired) {
        $singleWriterMutex.ReleaseMutex()
    }
    $singleWriterMutex.Dispose()
}
