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

function Assert-XrReadiness {
    param([int] $StreamerCount, [string] $Runtime, [string[]] $PowerLines,
          [int] $PowerExitCode)
    if ($StreamerCount -lt 1) { throw 'Virtual Desktop Streamer is not running.' }
    if (-not $Runtime -or (Split-Path $Runtime -Leaf) -ine 'virtualdesktop-openxr.json' -or
        -not (Test-Path -LiteralPath $Runtime -PathType Leaf)) {
        throw 'Select the installed Virtual Desktop OpenXR runtime (VDXR).'
    }
    if ($PowerExitCode -ne 0) { throw 'ADB could not read Quest power state.' }
    $power = $PowerLines -join "`n"
    if ($power -notmatch 'mWakefulness=Awake\b' -or
        $power -notmatch 'mHoldingDisplaySuspendBlocker=true\b') {
        throw 'Quest is not awake with its display held on; reapply the proximity override.'
    }
}
