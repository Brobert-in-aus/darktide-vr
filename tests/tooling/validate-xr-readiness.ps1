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

# Request flags that outlived the run that set them. Every flag the runner
# writes is restored in its `finally`, which does not run when the PC
# bugchecks mid-load -- which is how 18 September ended, with
# `darktidevr_foveation.flag` still in the installed mod. That flag installs a
# hook on every indexed draw, so a later worn session would have carried it
# silently and any timing taken there would have measured a different
# renderer.
$persistent = @('darktidevr_crosshair_scale.flag')

# Nothing but the persistent flag: fine.
Assert-NoStaleFlags -Present @('darktidevr_crosshair_scale.flag') -Allowed $persistent -Expected @()
Assert-NoStaleFlags -Present @() -Allowed $persistent -Expected @()

# The actual state the 18 September crash left behind.
$afterTheCrash = @('darktidevr_crosshair_scale.flag', 'darktidevr_foveation.flag',
                   'darktidevr_enter_psykhanium.flag', 'darktidevr_start_character.flag')
$caught = $false
try { Assert-NoStaleFlags -Present $afterTheCrash -Allowed $persistent -Expected @() }
catch {
    $caught = $true
    foreach ($name in @('darktidevr_foveation.flag', 'darktidevr_enter_psykhanium.flag',
                        'darktidevr_start_character.flag')) {
        if ($_.Exception.Message -notlike "*$name*") {
            throw "The stale-flag message must name $name so it can be deleted: $($_.Exception.Message)"
        }
    }
    if ($_.Exception.Message -like '*crosshair_scale*') {
        throw 'The persistent flag must not be reported as stale.'
    }
}
if (-not $caught) { throw 'The flags the crash left behind were accepted.' }

# A run that deliberately sets a flag is not refused for it.
Assert-NoStaleFlags -Present @('darktidevr_crosshair_scale.flag', 'darktidevr_foveation.flag') `
    -Allowed $persistent -Expected @('darktidevr_foveation.flag')

# But naming one does not excuse the others.
$caught = $false
try {
    Assert-NoStaleFlags -Present @('darktidevr_foveation.flag', 'darktidevr_ads_test.flag') `
        -Allowed $persistent -Expected @('darktidevr_foveation.flag')
} catch { $caught = $true }
if (-not $caught) { throw 'Naming one expected flag excused an unexpected one.' }

# Case and whitespace are the filesystem's business, not a licence to slip a
# flag past the gate.
$caught = $false
try { Assert-NoStaleFlags -Present @('DarktideVR_Foveation.FLAG') -Allowed $persistent -Expected @() }
catch { $caught = $true }
if (-not $caught) { throw 'A differently-cased stale flag was accepted.' }
Assert-NoStaleFlags -Present @('DARKTIDEVR_CROSSHAIR_SCALE.FLAG') -Allowed $persistent -Expected @()

# The deployment's own flags come from the deployment's own manifest. A
# hard-coded list would have refused every run the moment `sync-darktide-vr-dev`
# changed an option -- and it did: the first cut allowed one flag while the dev
# deployment places fourteen.
$manifest = [pscustomobject]@{ entries = @(
    [pscustomobject]@{ Destination = 'D:\game\mods\darktidevr\darktidevr_hud_panel.flag' },
    [pscustomobject]@{ Destination = 'D:\game\mods\darktidevr\darktidevr_full_second_eye.flag' },
    [pscustomobject]@{ Destination = 'D:\game\mods\darktidevr\scripts\mods\darktidevr\darktidevr.lua' },
    [pscustomobject]@{ Destination = 'D:\gameinaries\d3d12.dll' }
) }
$deployed = Get-DeployedFlagNames -Manifest $manifest
if ($deployed.Count -ne 2) { throw "Only the .flag entries are flags, got $($deployed.Count)" }
if ($deployed -notcontains 'darktidevr_hud_panel.flag') { throw 'leaf names, not full paths' }

# A manifest given as a bare array works too, and nothing at all is no flags
# rather than an error.
if ((Get-DeployedFlagNames -Manifest $manifest.entries).Count -ne 2) { throw 'bare array' }
if ((Get-DeployedFlagNames -Manifest $null).Count -ne 0) { throw 'no manifest, no flags' }

# Together: the deployment's flags and the runtime one pass, a run request does not.
$allowed = @($persistent) + @($deployed)
Assert-NoStaleFlags -Present @('darktidevr_hud_panel.flag', 'darktidevr_full_second_eye.flag',
                               'darktidevr_crosshair_scale.flag') -Allowed $allowed -Expected @()
$caught = $false
try {
    Assert-NoStaleFlags -Present @('darktidevr_hud_panel.flag', 'darktidevr_foveation.flag') `
        -Allowed $allowed -Expected @()
} catch { $caught = $true }
if (-not $caught) { throw 'A run request was excused by the deployment manifest.' }


# ---------------------------------------------------------------------------
# The Quest controller radio. Every fixture below is a real line from the
# headset's log on 18 September 2026, because a check built against invented
# lines is a check against the shape they were imagined to have.
# ---------------------------------------------------------------------------

# The healthy period: hundreds of thousands of packets, 1-2% lost.
$healthyLog = @(
  '09-18 18:49:56.842 I/SyncBossFW(  934): 47568112 [info   ] {WIHO}: Disconnected device stats: RSSI=-39, rx=250004, missed=1308',
  '09-18 18:56:40.858 I/SyncBossFW(  934): 47972112 [info   ] {WIHO}: Disconnected device stats: RSSI=-38, rx=89447, missed=300'
)
$healthy = Get-ControllerLinkHealth -LogLines $healthyLog
if ($healthy.State -ne 'healthy') { throw "a healthy link read as $($healthy.State)" }
if ($healthy.DisconnectSamples -ne 2) { throw 'both samples counted' }
if ($healthy.WorstLossPercent -ge 5) { throw "1-2% loss read as $($healthy.WorstLossPercent)%" }

# The failure, as it actually appeared.
$badLog = @(
  '09-18 19:16:25.904 I/SyncBossFW(  934): 49157112 [info   ] {WIHO}: Disconnected device stats: RSSI=-24, rx=14107, missed=6953'
)
$bad = Get-ControllerLinkHealth -LogLines $badLog
if ($bad.State -ne 'bad') { throw "33% loss at -24 dBm read as $($bad.State)" }
if ($bad.WorstLossPercent -ne 33) { throw "loss computed as $($bad.WorstLossPercent), expected 33" }

# THE POINT OF THE WHOLE CHECK: the register failures came eighteen minutes
# before the session became unplayable, with no packet loss recorded yet. If
# this reads as anything but bad, the warning arrives at the same time as the
# symptom and is worth nothing.
$earlyLog = @(
  '09-18 18:56:40.860 E/SyncBossFW(  934): 47972230 [error  ] {WIHO}: Register read failed (-128)',
  '09-18 18:56:40.861 E/SyncBossFW(  934): 47972231 [error  ] {WIHO}: Failed to get or set pulsar value for reg 36 with error -128'
)
$early = Get-ControllerLinkHealth -LogLines $earlyLog
if ($early.State -ne 'bad') { throw "the early warning read as $($early.State)" }
if ($early.RegisterFailures -ne 2) { throw 'both register failures counted' }
if ($early.WorstLossPercent -ne 0) { throw 'no loss had happened yet' }
if ($early.Reasons[0] -notmatch 'register') {
  throw 'the reason that cannot be anything else is named first'
}

# A state machine that has lost track of itself.
$lost = Get-ControllerLinkHealth -LogLines @(
  '09-18 18:56:41.716 W/SyncBossFW(  934): 47972973 [warning] {WIHO}: Got a TX timeout event when no requests were outstanding')
if ($lost.State -ne 'bad') { throw "a phantom timeout read as $($lost.State)" }

# A slow enumeration alone is the weakest of the three -- it is a symptom of
# load as well as of a wedge -- so it must not reach 'bad' on its own.
$slow = Get-ControllerLinkHealth -LogLines @(
  '09-18 19:15:10.000 E/SyncBossHAL(  967): [error  ] pulsar_input_cache.c(912): Excessive enumeration duration (7661ms)')
if ($slow.State -ne 'degrading') { throw "a slow enumeration read as $($slow.State)" }

# The WORST reading, not the last one. A session produces many disconnects and
# the bad ones are not conveniently last: on 18 September the 66% reading came
# first and a 24% one came four minutes later. Keeping the last would have
# reported the mildest sample of a collapsing link.
$manyLog = @(
  '09-18 19:14:43.899 I/SyncBossFW(  934): 49055112 [info   ] {WIHO}: Disconnected device stats: RSSI=-34, rx=133, missed=253',
  '09-18 19:17:51.907 I/SyncBossFW(  934): 49243112 [info   ] {WIHO}: Disconnected device stats: RSSI=-24, rx=2930, missed=911'
)
$many = Get-ControllerLinkHealth -LogLines $manyLog
if ($many.WorstLossPercent -ne 66) {
  throw "the worst of the two readings is 66%, got $($many.WorstLossPercent)"
}
if ($many.WorstLossRssi -ne -34) { throw 'and its signal strength travels with it' }
if ($many.DisconnectSamples -ne 2) { throw 'both samples counted' }

# The wolf-crying case, and the reason the RSSI test exists at all. A
# controller put down on a desk loses packets legitimately, and that must not
# look like a fault or the check will fire every time the headset comes off.
$distant = Get-ControllerLinkHealth -LogLines @(
  '09-18 19:00:00.000 I/SyncBossFW(  934): 1 [info   ] {WIHO}: Disconnected device stats: RSSI=-88, rx=100, missed=900')
if ($distant.State -ne 'healthy') { throw "a distant controller read as $($distant.State)" }
if ($distant.DisconnectSamples -ne 1) { throw 'the sample is still counted, just not judged' }

# Loss between the two thresholds is worth saying and not worth refusing over.
$middling = Get-ControllerLinkHealth -LogLines @(
  '09-18 19:00:00.000 I/SyncBossFW(  934): 1 [info   ] {WIHO}: Disconnected device stats: RSSI=-30, rx=900, missed=100')
if ($middling.State -ne 'degrading') { throw "10% loss read as $($middling.State)" }
# ...but a few per cent from controllers idling on a desk is not. The first
# live run of this reported 6% at -48 dBm with nothing wrong, and a check that
# speaks up about nothing is a check that stops being read.
$quiet = Get-ControllerLinkHealth -LogLines @(
  '09-18 19:46:00.000 I/SyncBossFW(  934): 1 [info   ] {WIHO}: Disconnected device stats: RSSI=-48, rx=940, missed=60')
if ($quiet.State -ne 'healthy') { throw "6% loss at rest read as $($quiet.State)" }
# The advice is graded: only a bad radio is worth rebooting over.
if ((Assert-ControllerLinkHealth -Health $middling -Mode 'Ready') -match 'reboot it') {
  throw 'a degrading reading told somebody to reboot'
}

# Nothing to read is not a fault. An idle headset logs none of these lines, and
# a check that calls silence a failure would refuse every run.
if ((Get-ControllerLinkHealth -LogLines @()).State -ne 'healthy') { throw 'silence is not a fault' }
if ((Get-ControllerLinkHealth -LogLines $null).State -ne 'healthy') { throw 'no log is not a fault' }
# A malformed counter line must not divide by zero or count as loss.
$emptySample = Get-ControllerLinkHealth -LogLines @(
  'Disconnected device stats: RSSI=-24, rx=0, missed=0')
if ($emptySample.State -ne 'healthy') { throw 'an empty sample is not a fault' }
# And is not counted either: the sample count is reported to whoever reads the
# verdict, and a line carrying no packets is not evidence of anything.
if ($emptySample.DisconnectSamples -ne 0) { throw 'an empty sample is not a sample' }

# The decision. A worn session on a wedged radio is a wasted session, so Ready
# refuses; a desk measurement is not invalidated by it, so nothing else does.
$threw = $false
try { Assert-ControllerLinkHealth -Health $bad -Mode 'Ready' } catch { $threw = $true }
if (-not $threw) { throw 'Ready did not refuse a bad radio' }
$message = Assert-ControllerLinkHealth -Health $bad -Mode 'Probe'
if (-not $message) { throw 'a bad radio is reported outside Ready' }
if ($message -notmatch 'reboot') { throw 'the message says what to do about it' }
if ($message -notmatch 'not the controllers') {
  throw 'and says what it is not, because that is where three days went'
}
# Degrading warns even in Ready: it is an early warning, not a verdict.
if (-not (Assert-ControllerLinkHealth -Health $slow -Mode 'Ready')) {
  throw 'a degrading radio is reported'
}
if (Assert-ControllerLinkHealth -Health $healthy -Mode 'Ready') {
  throw 'a healthy radio says nothing'
}
# The override, for when the headset is known to be fine and the run matters.
if (-not (Assert-ControllerLinkHealth -Health $bad -Mode 'Ready' -AllowDegradedLink)) {
  throw 'the override still reports what it allowed'
}

Write-Output 'xr_readiness=pass cases=34 controller_link=19'
