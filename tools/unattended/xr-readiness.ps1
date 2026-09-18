function Invoke-BoundedXrSmoke {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string] $Arguments,
        [ValidateRange(1, 300)][int] $TimeoutSeconds = 90
    )
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = $FilePath
    $process.StartInfo.Arguments = $Arguments
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw 'Could not start the XR rendering test.' }
        # Drain both streams while the child runs; a full pipe must not stall
        # the runtime or prevent the timeout from being observed.
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            # This handle belongs to the child we started, never an existing
            # viewer, the game, Streamer or another process with the same name.
            try { $process.Kill() }
            catch [InvalidOperationException] {
                if (-not $process.HasExited) { throw }
            }
            if (-not $process.WaitForExit(5000)) {
                throw 'Timed-out XR rendering test did not terminate.'
            }
        }
        $readbacks = [Threading.Tasks.Task[]] @($stdout, $stderr)
        $outputComplete = [Threading.Tasks.Task]::WaitAll($readbacks, 5000)
        $lines = @(
            foreach ($readback in @($stdout, $stderr)) {
                if ($readback.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion) {
                    $readback.Result -split '\r?\n' | Where-Object { $_ -ne '' }
                }
            }
        )
        [pscustomobject]@{
            exit_code = $process.ExitCode
            timed_out = $timedOut
            timeout_seconds = $TimeoutSeconds
            output_complete = $outputComplete
            output = $lines
        }
    }
    finally {
        if ($started -and -not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}

# Which runtime the machine is pointed at, decided by the manifest the OpenXR
# loader is registered against rather than by what is installed. The readiness
# gate asks different questions of each: a Steam Frame session has no
# VirtualDesktop.Streamer, no VDXR manifest and no ADB, so requiring those
# would fail every Frame run before it started.
function Get-XrRuntimeProfile {
    param([string] $Runtime)
    if (-not $Runtime) { return 'none' }
    switch ((Split-Path $Runtime -Leaf).ToLowerInvariant()) {
        'virtualdesktop-openxr.json' { return 'VDXR' }
        'steamxr_win64.json' { return 'SteamVR' }
        default { return 'unsupported' }
    }
}

# Facts in, a decision out: every query lives in the caller so this can be
# tested against fixtures.
#   VDXR     -- Streamer running, its manifest present, and the Quest awake
#               with the display blocker held (the proximity override).
#   SteamVR  -- the Steam manifest present and vrserver alive. There is no
#               ADB and no proximity override on a Frame; the proof that a
#               headset is really there and rendering is the bounded XR smoke
#               that the caller runs next, not a power dump.
function Assert-XrReadiness {
    param([int] $StreamerCount, [string] $Runtime, [string[]] $PowerLines,
          [int] $PowerExitCode, [int] $SteamVrServerCount)
    # Not named $profile: that is a PowerShell automatic variable.
    $runtimeProfile = Get-XrRuntimeProfile -Runtime $Runtime
    if ($runtimeProfile -eq 'none' -or $runtimeProfile -eq 'unsupported') {
        throw ("The active OpenXR runtime is '$Runtime'. Select Virtual " +
               'Desktop (VDXR) or SteamVR; no other runtime has been brought up here.')
    }
    if (-not (Test-Path -LiteralPath $Runtime -PathType Leaf)) {
        throw "The active OpenXR runtime manifest does not exist: $Runtime"
    }
    if ($runtimeProfile -eq 'SteamVR') {
        if ($SteamVrServerCount -lt 1) {
            throw ('SteamVR is the active OpenXR runtime but vrserver is not ' +
                   'running. Start SteamVR with the headset connected.')
        }
        return
    }
    if ($StreamerCount -lt 1) { throw 'Virtual Desktop Streamer is not running.' }
    if ($PowerExitCode -ne 0) { throw 'ADB could not read Quest power state.' }
    $power = $PowerLines -join "`n"
    if ($power -notmatch 'mWakefulness=Awake\b' -or
        $power -notmatch 'mHoldingDisplaySuspendBlocker=true\b') {
        throw 'Quest is not awake with its display held on; reapply the proximity override.'
    }
}

# The Quest's controller radio, read from the headset's own log.
#
# On 18 September 2026 a worn session was lost to controllers that dropped
# every few seconds, and three wrong answers were given before a headset reboot
# fixed it. What the log had been saying the whole time was that the HEADSET's
# radio coprocessor -- `SyncBossFW`, an nRF reached over SPI, not the
# controllers -- was failing its own register reads. The first of those came
# EIGHTEEN MINUTES before the session became unplayable.
#
# That gap is the whole point of this check. The fault announces itself long
# before it is felt, and the fix is a forty second reboot, so noticing early
# costs nothing and noticing late costs a session.
#
# Facts in, a decision out: the caller pulls the log, this reads it.
#
# The three signatures, in the order they matter:
#
#   Register read failed / Failed to get or set pulsar value
#       The headset cannot talk to its own radio. No controller is involved in
#       that operation, so it cannot be a battery, a range problem or
#       interference. This is the early warning.
#   Got a TX timeout event when no requests were outstanding
#       The radio reporting a timeout for a request that does not exist: a
#       state machine that has lost track of itself.
#   Excessive enumeration duration
#       Enumerating a controller is a millisecond job. It was taking 7.6
#       seconds. On its own this is a symptom of load as well as of a wedge,
#       so it is the weakest of the three and only ever reads as `degrading`.
#
# And the quantitative one, from each disconnect's own counters:
#
#   Disconnected device stats: RSSI=-24, rx=14107, missed=6953
#       Heavy loss at STRONG signal is a degraded link. Weak signal with loss
#       is only range, and a controller put down on a desk reads that way, so
#       the RSSI test is what keeps this from crying wolf every time the
#       headset is taken off. Healthy readings on this rig were 0-2% loss over
#       hundreds of thousands of packets; the bad ones were 24-66%.
$script:ControllerLinkStrongRssiDbm = -50
$script:ControllerLinkBadLossPercent = 20
# Raised from 5 after the first live run reported 6% at -48 dBm from two
# controllers idling on a desk. A check that speaks up about nothing is a check
# that gets ignored, and the loss figure was never the early warning anyway --
# the register failures are, and they carry no threshold at all.
$script:ControllerLinkDegradingLossPercent = 10
function Get-ControllerLinkHealth {
    param([string[]] $LogLines)
    $lines = @($LogLines)
    $registerFailures = @($lines | Where-Object {
        $_ -match 'Register read failed' -or $_ -match 'Failed to get or set pulsar value' }).Count
    $lostRequests = @($lines | Where-Object {
        $_ -match 'TX timeout event when no requests were outstanding' }).Count
    $slowEnumerations = @($lines | Where-Object { $_ -match 'Excessive enumeration duration' }).Count
    # Every disconnect logs what the link actually managed.
    $worstLoss = 0
    $worstRssi = $null
    $samples = 0
    foreach ($line in $lines) {
        if ($line -notmatch 'Disconnected device stats: RSSI=(-?\d+), rx=(\d+), missed=(\d+)') { continue }
        $rssi = [int] $Matches[1]
        $received = [double] $Matches[2]
        $missed = [double] $Matches[3]
        $total = $received + $missed
        if ($total -le 0) { continue }
        $samples++
        # Only a strong signal says anything about the link's health. A
        # controller lying on a desk out of range loses packets legitimately.
        if ($rssi -lt $script:ControllerLinkStrongRssiDbm) { continue }
        $loss = [math]::Round(100.0 * $missed / $total)
        if ($loss -gt $worstLoss) { $worstLoss = $loss; $worstRssi = $rssi }
    }
    $state = 'healthy'
    $reasons = @()
    if ($slowEnumerations -gt 0) {
        $state = 'degrading'
        $reasons += "$slowEnumerations slow controller enumeration(s)"
    }
    if ($worstLoss -ge $script:ControllerLinkDegradingLossPercent -and
        $worstLoss -lt $script:ControllerLinkBadLossPercent) {
        $state = 'degrading'
        $reasons += "$worstLoss% packet loss at $worstRssi dBm"
    }
    if ($worstLoss -ge $script:ControllerLinkBadLossPercent) {
        $state = 'bad'
        $reasons += "$worstLoss% packet loss at $worstRssi dBm (strong signal)"
    }
    if ($lostRequests -gt 0) {
        $state = 'bad'
        $reasons += "$lostRequests radio timeout(s) with no request outstanding"
    }
    # Last, so it is the reason that ends up first in the message: it is the
    # one that cannot be anything else.
    if ($registerFailures -gt 0) {
        $state = 'bad'
        $reasons = @("$registerFailures failed radio register access(es) on the headset") + $reasons
    }
    return [pscustomobject]@{
        State = $state
        RegisterFailures = $registerFailures
        LostRequests = $lostRequests
        SlowEnumerations = $slowEnumerations
        WorstLossPercent = $worstLoss
        WorstLossRssi = $worstRssi
        DisconnectSamples = $samples
        Reasons = $reasons
    }
}

# What to do about it. A worn session on a wedged radio is a wasted session, so
# Ready refuses; anything else says so and carries on, because a degraded
# controller link does not invalidate a desk measurement.
function Assert-ControllerLinkHealth {
    param($Health, [string] $Mode, [switch] $AllowDegradedLink)
    if (-not $Health) { return $null }
    if ($Health.State -eq 'healthy') { return $null }
    $detail = ($Health.Reasons -join '; ')
    # Only 'bad' earns "reboot it". Telling somebody to reboot over a reading
    # that may be nothing is how a check stops being read.
    $advice = if ($Health.State -eq 'bad') {
        'This is the headset, not the controllers and not their batteries: ' +
        'reboot it (adb reboot, about forty seconds) before a worn session.'
    } else {
        'Not worth acting on by itself; it is the headset rather than the ' +
        'controllers, and worth another look before a worn session.'
    }
    $message = "Quest controller radio: $($Health.State) -- $detail. $advice"
    if ($Health.State -eq 'bad' -and $Mode -eq 'Ready' -and -not $AllowDegradedLink) {
        throw $message
    }
    return $message
}

# Request flags that outlived the run that set them.
#
# Every flag the runner writes is restored in its `finally`, which does not run
# when the run is interrupted -- or when the PC bugchecks mid-load, which has
# now happened five times. The flags left behind on 18 September included
# `darktidevr_foveation.flag`, which installs a hook on EVERY indexed draw: a
# later worn session would have carried it silently, and any timing taken in
# that session would have been of a different renderer than the one being
# measured.
#
# Checking by hand was already the rule and was already missed, so the gate
# does it. Facts in, a decision out.
function Assert-NoStaleFlags {
    param(
        # Flag file names present in the installed mod root.
        [string[]] $Present,
        # Names that legitimately persist between runs.
        [string[]] $Allowed,
        # Names this run is deliberately setting.
        [string[]] $Expected
    )
    $permitted = @($Allowed) + @($Expected) |
        Where-Object { $_ } |
        ForEach-Object { $_.Trim().ToLowerInvariant() }
    $stale = @(
        @($Present) |
            Where-Object { $_ } |
            Where-Object { $permitted -notcontains $_.Trim().ToLowerInvariant() })
    if ($stale.Count -gt 0) {
        throw ("Request flags left over from an earlier run are still in the installed mod: " +
               ($stale -join ', ') +
               ". They change what the game does and what a measurement means. Delete them, " +
               "or name them with -AllowFlags if this run wants them.")
    }
}

# Flags the mod itself writes as live settings rather than run requests. The
# DEPLOYMENT's own flags are not listed here: `sync-darktide-vr-dev.ps1` places
# fourteen of them and which fourteen depends on its options, so a hard-coded
# list would have refused every run the moment an option changed. They are read
# from the deployment manifest instead, which is written by the deployment and
# therefore cannot drift from it.
$script:PersistentModFlags = @('darktidevr_crosshair_scale.flag')

# The flag names a deployment placed, from its own manifest. Takes the parsed
# manifest rather than a path so it can be tested without one.
function Get-DeployedFlagNames {
    param($Manifest)
    if (-not $Manifest) { return @() }
    $entries = if ($Manifest.PSObject.Properties.Name -contains 'entries') {
        $Manifest.entries
    } else { $Manifest }
    return @(
        @($entries) |
            ForEach-Object { $_.Destination } |
            Where-Object { $_ -and ([string]$_).ToLowerInvariant().EndsWith('.flag') } |
            ForEach-Object { Split-Path $_ -Leaf })
}
