[CmdletBinding()]
param(
    [ValidateRange(5, 3600)]
    [int] $DurationSeconds = 300,

    [string] $GameExe =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\binaries\Darktide.exe',

    [string] $Harness =
        'build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe',

    [switch] $EnableMenuInput,

    [switch] $SyntheticControllerPath,

    [switch] $SyntheticGameplayInput,

    [switch] $SyntheticBodyPath,

    [switch] $SyntheticHeadSweep,

    [ValidateRange(0, 1800)]
    [int] $WaitForGameSeconds = 0,

    [ValidateRange(-2.0, 2.0)]
    [double] $ProjectionTranslationScale = 1.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
if ($SyntheticControllerPath) {
    $arguments += '--synthetic-controller-path'
}
if ($SyntheticGameplayInput) {
    if (-not $SyntheticControllerPath) {
        throw '-SyntheticGameplayInput requires -SyntheticControllerPath'
    }
    $arguments += '--synthetic-gameplay-input'
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
$arguments += '--projection-translation-scale'
$arguments += $ProjectionTranslationScale.ToString(
    [System.Globalization.CultureInfo]::InvariantCulture)

& $harnessPath @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Darktide stereo harness failed with exit code $LASTEXITCODE"
}
