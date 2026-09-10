[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BenchmarkDirectory,
    [Parameter(Mandatory)] [string] $GameExe,
    [Parameter(Mandatory)] [ValidatePattern('^[a-fA-F0-9]{64}$')] [string] $ExpectedGameSha256,
    [ValidateRange(10,2000)] [int] $Samples = 1000,
    [ValidateRange(5,50)] [int] $IntervalMilliseconds = 11,
    [switch] $ObserveDispatchLayout,
    [ValidateRange(0,2147483647)] [int] $ThreadId = 0,
    [ValidateRange(0,2147483647)] [int] $PeerThreadId = 0,
    [string] $SamplerPath = (Join-Path $PSScriptRoot '../../build/xr-frame-stage-timing/tests/native_capture/Release/darktidevr-thread-residency.exe')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Samples * $IntervalMilliseconds -gt 30000) { throw 'Residency capture is limited to 30 seconds.' }
$BenchmarkDirectory = (Resolve-Path -LiteralPath $BenchmarkDirectory).Path
$GameExe = (Resolve-Path -LiteralPath $GameExe).Path
$SamplerPath = (Resolve-Path -LiteralPath $SamplerPath).Path
if ((Get-FileHash -LiteralPath $GameExe).Hash -ne $ExpectedGameSha256) { throw 'Game hash mismatch.' }
$launch = Get-Content -LiteralPath (Join-Path $BenchmarkDirectory 'launch.log') -Raw
if ($launch -notmatch 'offline_benchmark.started_utc=' -or $launch -match 'Offline dual-view benchmark completed') {
    throw 'Requires an active, ready, isolated benchmark workload.'
}
$pidMatch = [regex]::Match($launch,'Authenticated Darktide process started: PID (\d+)\.')
if (-not $pidMatch.Success) { throw 'No run-owned game PID.' }
$gameId = [int]$pidMatch.Groups[1].Value
$gameProcess = Get-Process -Id $gameId
if ($gameProcess.Path -ne $GameExe) { throw 'Running game path mismatch.' }
$started = $gameProcess.StartTime.ToUniversalTime()
$profilePath = Join-Path $env:TEMP "darktidevr-present-cpu-$gameId.log"
if ((Get-Item -LiteralPath $profilePath).LastWriteTimeUtc -lt $started) { throw 'Stale Present profile.' }
$profile = Get-Content -LiteralPath $profilePath -Raw
if ($profile -notmatch "(?m)^PRESENT_CPU_BEGIN pid=$gameId ") { throw 'Present profile PID mismatch.' }
$threadIds = @([regex]::Matches($profile,'(?m)^PRESENT_CPU sample=\d+ thread=(\d+) ') |
    ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique)
if ($threadIds.Count -ne 1) { throw 'Requires one observed Present thread.' }
$presentThreadId = $threadIds[0]
if ($ThreadId -eq 0) { $ThreadId = $presentThreadId }
if ($PeerThreadId -eq $ThreadId) { throw 'Peer must be a different thread.' }
if ($ObserveDispatchLayout -and $ThreadId -ne $presentThreadId) { throw 'Dispatcher layout requires the observed Present thread.' }
$outputName = if ($ThreadId -eq $presentThreadId) { 'thread-residency' } else { "thread-residency-$ThreadId" }
if ($PeerThreadId) { $outputName += "-peer-$PeerThreadId" }
$output = Join-Path $BenchmarkDirectory $outputName
if (Test-Path -LiteralPath $output) { throw 'Use a fresh residency output directory.' }
$modules = @($gameProcess.Modules | ForEach-Object {
    [pscustomobject]@{name=$_.ModuleName;path=$_.FileName;base_address=$_.BaseAddress.ToInt64();size=$_.ModuleMemorySize}
})
$engineBase = 0
if ($ObserveDispatchLayout) {
    if ($ExpectedGameSha256 -ne '6fce8db87a77a412b22ef9f33f74fa16ef85126cc0fbb24187d78b85fc7a19d3') { throw 'Dispatch layout requires the verified engine build.' }
    $engineModules = @($modules | Where-Object path -eq $GameExe)
    if ($engineModules.Count -ne 1) { throw 'Expected one exact engine module.' }
    $engineBase = $engineModules[0].base_address
}
$threadBefore = $gameProcess.Threads | Where-Object Id -eq $threadId
if (-not $threadBefore) { throw 'Present thread exited.' }
if ($PeerThreadId -and -not ($gameProcess.Threads | Where-Object Id -eq $PeerThreadId)) { throw 'Peer thread exited.' }
$cpuBefore = $threadBefore.TotalProcessorTime.TotalMilliseconds
[IO.Directory]::CreateDirectory($output) | Out-Null
$modules | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'modules.json')
$begin = [DateTime]::UtcNow
& $SamplerPath $gameId $threadId $Samples $IntervalMilliseconds $GameExe $started.ToFileTimeUtc() $engineBase $PeerThreadId |
    Set-Content -LiteralPath (Join-Path $output 'samples.csv')
$result = $LASTEXITCODE
$end = [DateTime]::UtcNow
$gameProcess.Refresh()
$threadAfter = $gameProcess.Threads | Where-Object Id -eq $threadId
@{
    pid=$gameId; thread=$threadId; present_thread=$presentThreadId; process_started_utc=$started.ToString('o')
    start_utc=$begin.ToString('o'); end_utc=$end.ToString('o'); exit_code=$result
    game_sha256=$ExpectedGameSha256; sampler_sha256=(Get-FileHash $SamplerPath).Hash
    observe_dispatch_layout=$ObserveDispatchLayout.IsPresent
    peer_thread=$PeerThreadId
    thread_cpu_delta_ms=if($threadAfter){$threadAfter.TotalProcessorTime.TotalMilliseconds-$cpuBefore}else{$null}
    scope='instruction-pointer residency including waits; debugger pauses perturb execution'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'receipt.json')
if ($result -ne 0) { throw 'Residency capture failed; no permission or policy changes were attempted.' }
"thread_residency=complete output=$output"
