$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tools/unattended/xr-readiness.ps1')
$shellPath = (Get-Process -Id $PID).Path
function Invoke-Fixture([string] $Code, [int] $Timeout = 10) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
    Invoke-BoundedXrSmoke -FilePath $shellPath -Arguments `
        "-NoProfile -NonInteractive -EncodedCommand $encoded" -TimeoutSeconds $Timeout
}
# More than pipe capacity on both streams must drain while the process runs.
$success = Invoke-Fixture @'
[Console]::Out.WriteLine(('x' * 100000))
[Console]::Error.WriteLine(('y' * 100000))
[Console]::Out.WriteLine('result=pass')
exit 0
'@
if ($success.timed_out -or -not $success.output_complete -or $success.exit_code -ne 0 -or
        $success.output.Count -ne 3 -or $success.output[0].Length -ne 100000 -or
        $success.output[2].Length -ne 100000 -or $success.output[1] -ne 'result=pass') {
    throw 'Concurrent stdout/stderr capture failed'
}
$failure = Invoke-Fixture "[Console]::Out.WriteLine('result=pass'); [Console]::Error.WriteLine('runtime failure'); exit 7"
if ($failure.timed_out -or $failure.exit_code -ne 7 -or
        $failure.output -notcontains 'runtime failure') { throw 'Runtime failure was lost' }
$watch = [Diagnostics.Stopwatch]::StartNew()
$stalled = Invoke-Fixture "[Console]::Out.WriteLine('child=' + `$PID); [Console]::Out.WriteLine('result=pass'); Start-Sleep -Seconds 30" 2
$watch.Stop()
if (-not $stalled.timed_out -or -not $stalled.output_complete -or $watch.Elapsed.TotalSeconds -gt 10 -or
        $stalled.output -notcontains 'result=pass') { throw 'Stalled runtime was not bounded' }
$childLine = $stalled.output | Where-Object { $_ -match '^child=\d+$' } | Select-Object -First 1
if (-not $childLine) { throw 'Child did not reach the simulated runtime wait' }
$childId = [int]$childLine.Substring(6)
if (Get-Process -Id $childId -ErrorAction SilentlyContinue) { throw 'Timed-out child is still running' }
if (-not (Get-Process -Id $PID -ErrorAction SilentlyContinue)) { throw 'Parent was terminated' }

# Exercise the preflight's actual result classification, including a premature
# pass marker followed by a stuck runtime. No Quest or XR process is started.
$preflight = Get-Content (Join-Path $PSScriptRoot '../../tools/unattended/invoke-unattended-preflight.ps1') -Raw
$start = $preflight.IndexOf('    $resultLine =')
$end = $preflight.IndexOf("`n}`n`n`$report =", $start)
if ($end -lt 0) { $end = $preflight.IndexOf("`r`n}`r`n`r`n`$report =", $start) }
if ($start -lt 0 -or $end -lt 0) { throw 'Preflight classification boundary missing' }
$classification = [scriptblock]::Create($preflight.Substring($start, $end - $start))
$outputFullPath = 'fixture-report.json'
foreach ($case in @($success, $failure, $stalled)) {
    $smokeProcess = $case
    $smokeOutput = @($case.output)
    $smokeExitCode = $case.exit_code
    $smokeFailure = $null
    . $classification
    $shouldFail = $case -ne $success
    if ([bool]$smokeFailure -ne $shouldFail -or $xrSmoke.timed_out -ne $case.timed_out) {
        throw 'Preflight accepted failed or timed-out output'
    }
}
Write-Output 'xr_smoke_timeout=pass dual_pipes=drained failure=preserved timeout=terminated premature_pass=rejected'
