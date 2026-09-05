$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/stereo/darktide-process-result.ps1')

foreach ($expectedCode in @(0, 17)) {
    $child = [Diagnostics.Process]::new()
    $child.StartInfo.FileName = (Get-Process -Id $PID).Path
    $child.StartInfo.Arguments = "-NoProfile -Command [Console]::ReadLine() | Out-Null; exit $expectedCode"
    $child.StartInfo.UseShellExecute = $false
    $child.StartInfo.CreateNoWindow = $true
    $child.StartInfo.RedirectStandardInput = $true
    try {
        $null = $child.Start()
        # Observe through Get-Process, as the launcher does, rather than relying
        # on the process object returned by Start to keep a handle automatically.
        $observed = Get-Process -Id $child.Id
        try {
            $null = $observed.Handle
            $running = Get-DarktideProcessResult -Process $observed
            if ($running.Status -ne 'running' -or $null -ne $running.ExitCode) {
                throw 'A live game must not be reported as a completed pass.'
            }
            $child.StandardInput.WriteLine('exit')
            $child.StandardInput.Flush()
            if (-not $child.WaitForExit(10000)) { throw 'Exit fixture timed out.' }
            $result = Get-DarktideProcessResult -Process $observed
            $expectedStatus = if ($expectedCode -eq 0) { 'exited' } else { 'failed' }
            if ($result.ExitCode -ne $expectedCode -or $result.Status -ne $expectedStatus) {
                throw "Lost the original process exit result: $($result | ConvertTo-Json -Compress)"
            }
        }
        finally { $observed.Dispose() }
    }
    finally {
        if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
        $child.Dispose()
    }
}
Write-Output 'game_exit_result=pass running_and_normal_and_abnormal'
