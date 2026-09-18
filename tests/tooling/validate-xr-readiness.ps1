$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tools/unattended/xr-readiness.ps1')
# Both manifests exist for the fixtures; nothing else does.
function Test-Path {
    param($LiteralPath, $PathType)
    return $LiteralPath -in @('C:\fixture\virtualdesktop-openxr.json',
                              'C:\fixture\steamxr_win64.json')
}

# Which runtime the machine is pointed at is decided by the manifest's name,
# because that is what the OpenXR loader is registered against.
if ((Get-XrRuntimeProfile -Runtime 'C:\fixture\virtualdesktop-openxr.json') -ne 'VDXR') {
    throw 'VDXR manifest not recognised'
}
if ((Get-XrRuntimeProfile -Runtime 'C:\x\steamxr_win64.json') -ne 'SteamVR') {
    throw 'SteamVR manifest not recognised'
}
if ((Get-XrRuntimeProfile -Runtime 'C:\x\STEAMXR_WIN64.JSON') -ne 'SteamVR') {
    throw 'the manifest name is compared case-insensitively by the loader'
}
if ((Get-XrRuntimeProfile -Runtime '') -ne 'none') { throw 'empty runtime' }
if ((Get-XrRuntimeProfile -Runtime 'C:\x\oculus_openxr_64.json') -ne 'unsupported') {
    throw 'a runtime nobody has brought up here must not read as supported'
}

# Virtual Desktop: unchanged. A Quest behind a Streamer, awake, with the
# display blocker held by the proximity override.
$vdxr = @{
    StreamerCount = 1; Runtime = 'C:\fixture\virtualdesktop-openxr.json'
    PowerLines = @('mWakefulness=Awake', 'mHoldingDisplaySuspendBlocker=true')
    PowerExitCode = 0
    SteamVrServerCount = 0
}
Assert-XrReadiness @vdxr
foreach ($change in @(
    @{ StreamerCount = 0 }, @{ Runtime = 'C:\fixture\other.json' },
    @{ Runtime = '' }, @{ PowerExitCode = 1 },
    @{ PowerLines = @('mWakefulness=Asleep', 'mHoldingDisplaySuspendBlocker=false') },
    @{ PowerLines = @() },
    # The manifest may name VDXR and still not be installed.
    @{ Runtime = 'C:\fixture\missing\virtualdesktop-openxr.json' }
)) {
    $candidate = $vdxr.Clone()
    foreach ($key in $change.Keys) { $candidate[$key] = $change[$key] }
    $rejected = $false
    try { Assert-XrReadiness @candidate } catch { $rejected = $true }
    if (-not $rejected) { throw "Readiness accepted an invalid VDXR fixture: $($change.Keys)" }
}

# SteamVR, for the Steam Frame. There is no Streamer, no ADB and no proximity
# override on that path, and requiring any of them would fail every Frame run
# before it started. What is required instead is the Steam manifest and a live
# vrserver; that a headset is really there and rendering is proved by the
# bounded XR smoke the caller runs next.
$steam = @{
    StreamerCount = 0; Runtime = 'C:\fixture\steamxr_win64.json'
    PowerLines = @(); PowerExitCode = 1
    SteamVrServerCount = 1
}
Assert-XrReadiness @steam
foreach ($change in @(
    @{ SteamVrServerCount = 0 },
    @{ Runtime = 'C:\fixture\missing\steamxr_win64.json' }
)) {
    $candidate = $steam.Clone()
    foreach ($key in $change.Keys) { $candidate[$key] = $change[$key] }
    $rejected = $false
    try { Assert-XrReadiness @candidate } catch { $rejected = $true }
    if (-not $rejected) { throw "Readiness accepted an invalid SteamVR fixture: $($change.Keys)" }
}

# And the split must not leak in either direction. A SteamVR session is not
# excused the Steam checks by a Quest being plugged in, and a VDXR session is
# not excused the Quest checks by SteamVR happening to be running.
$steamWithQuestAttached = $steam.Clone()
$steamWithQuestAttached.SteamVrServerCount = 0
$steamWithQuestAttached.StreamerCount = 1
$steamWithQuestAttached.PowerExitCode = 0
$steamWithQuestAttached.PowerLines = @('mWakefulness=Awake',
                                       'mHoldingDisplaySuspendBlocker=true')
$leaked = $false
try { Assert-XrReadiness @steamWithQuestAttached } catch { $leaked = $true }
if (-not $leaked) {
    throw 'a SteamVR session passed with vrserver down because a Quest was ready'
}
$vdxrWithSteamRunning = $vdxr.Clone()
$vdxrWithSteamRunning.StreamerCount = 0
$vdxrWithSteamRunning.SteamVrServerCount = 1
$leaked = $false
try { Assert-XrReadiness @vdxrWithSteamRunning } catch { $leaked = $true }
if (-not $leaked) {
    throw 'a VDXR session passed with no Streamer because SteamVR was running'
}

Write-Output 'xr_readiness=pass cases=19'
