function Get-DarktideProcessResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [Diagnostics.Process] $Process)

    # The caller must retain Process.Handle before the game exits. Looking the
    # PID up afterwards can lose the exit code or observe a reused PID.
    try {
        $Process.Refresh()
        if (-not $Process.HasExited) {
            return [pscustomobject]@{ Status = 'running'; ExitCode = $null }
        }
        $exitCode = $Process.ExitCode
        return [pscustomobject]@{
            Status = $(if ($exitCode -eq 0) { 'exited' } else { 'failed' })
            ExitCode = $exitCode
        }
    }
    catch {
        # An unreadable result is not evidence of a successful game session.
        return [pscustomobject]@{ Status = 'unavailable'; ExitCode = $null }
    }
}
