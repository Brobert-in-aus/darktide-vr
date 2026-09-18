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

# The one flag that legitimately persists: the mod writes it as a live setting
# rather than a run request.
$script:PersistentModFlags = @('darktidevr_crosshair_scale.flag')
