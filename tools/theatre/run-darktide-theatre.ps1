[CmdletBinding()]
param(
    [ValidateRange(5, 3600)]
    [int] $DurationSeconds = 300,

    [string] $GameExe =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\binaries\Darktide.exe',

    [string] $Harness =
        'build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$knownGameSha256 =
    'e0f581d2c63b692c7d9f328e3edeb39c0f484956905569d38ba27bbb3fcc0aae'

if (-not (Test-Path -LiteralPath $GameExe -PathType Leaf)) {
    throw "Darktide executable not found: $GameExe"
}
if ((Get-FileHash -LiteralPath $GameExe -Algorithm SHA256).Hash.ToLowerInvariant() -ne
    $knownGameSha256) {
    throw 'Darktide theatre mode rejects this unknown executable build'
}

$eac = Get-Service EasyAntiCheat_EOS -ErrorAction SilentlyContinue
if ($eac -and $eac.Status -ne 'Stopped') {
    throw "Darktide theatre mode refuses to run while EAC is $($eac.Status)"
}

$game = @(Get-Process Darktide -ErrorAction SilentlyContinue)
if ($game.Count -ne 1 -or -not $game[0].Responding) {
    throw "Expected exactly one responsive Darktide process; found $($game.Count)"
}
if ($game[0].MainWindowTitle -ne 'Warhammer 40,000: Darktide') {
    throw 'The running Darktide process does not expose the expected capture window'
}

$harnessPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $Harness)
if (-not (Test-Path -LiteralPath $harnessPath -PathType Leaf)) {
    throw "Release XR harness not found: $harnessPath"
}

# VirtualDesktopXR is currently configured for 120 Hz. The harness exits after
# this bounded frame count even if the source window stops updating.
$xrFrames = $DurationSeconds * 120
& $harnessPath `
    --frames 30 `
    --debug-layer `
    --require-rendering `
    --xr-frames $xrFrames `
    --theatre `
    --capture-window-title 'Warhammer 40,000: Darktide'
if ($LASTEXITCODE -ne 0) {
    throw "Darktide theatre harness failed with exit code $LASTEXITCODE"
}
