[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BenchmarkDirectory,
    [Parameter(Mandatory)] [string] $GameExe,
    [Parameter(Mandatory)] [ValidatePattern('^[a-fA-F0-9]{64}$')] [string] $ExpectedGameSha256
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$BenchmarkDirectory = (Resolve-Path -LiteralPath $BenchmarkDirectory).Path
$GameExe = (Resolve-Path -LiteralPath $GameExe).Path
if ((Get-FileHash -LiteralPath $GameExe).Hash -ne $ExpectedGameSha256) { throw 'Game hash mismatch.' }
$launch = Get-Content -LiteralPath (Join-Path $BenchmarkDirectory 'launch.log') -Raw
if ($launch -notmatch 'offline_benchmark.started_utc=' -or $launch -match 'Offline dual-view benchmark completed') { throw 'Requires an active ready benchmark.' }
$match = [regex]::Match($launch,'Authenticated Darktide process started(?: during (?:launcher transition|Play activation|Play retry))?: PID (\d+)\.')
if (-not $match.Success) { throw 'No run-owned PID.' }
$gameId = [int]$match.Groups[1].Value
$game = Get-Process -Id $gameId
if ($game.Path -ne $GameExe) { throw 'Running game path mismatch.' }
$created = $game.StartTime.ToUniversalTime()
if (-not ('DarktideThreadNames' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DarktideThreadNames {
    [DllImport("kernel32.dll")] static extern IntPtr OpenThread(uint access, bool inherit, uint tid);
    [DllImport("kernel32.dll")] static extern uint GetProcessIdOfThread(IntPtr thread);
    [DllImport("kernel32.dll")] static extern int GetThreadDescription(IntPtr thread, out IntPtr text);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    public static string Read(uint tid, uint pid) {
        var h = OpenThread(0x800, false, tid);
        if (h == IntPtr.Zero) return null;
        IntPtr text = IntPtr.Zero;
        try {
            if (GetProcessIdOfThread(h) != pid || GetThreadDescription(h, out text) < 0) return null;
            return Marshal.PtrToStringUni(text);
        } finally { if (text != IntPtr.Zero) LocalFree(text); CloseHandle(h); }
    }
}
'@
}
$before = @{}
foreach ($thread in $game.Threads) {
    try { $before[$thread.Id] = $thread.TotalProcessorTime.TotalMilliseconds } catch { }
}
$begin = [DateTime]::UtcNow
Start-Sleep -Milliseconds 1000
$game.Refresh()
if ($game.HasExited -or $game.StartTime.ToUniversalTime() -ne $created) { throw 'Run-owned process exited or changed.' }
$elapsed = ([DateTime]::UtcNow - $begin).TotalMilliseconds
$rows = @(foreach ($thread in $game.Threads) {
    try {
        if ($before.ContainsKey($thread.Id)) {
            $delta = $thread.TotalProcessorTime.TotalMilliseconds - $before[$thread.Id]
            if ($delta -ge 0) {
                [pscustomobject]@{thread=$thread.Id; name=[DarktideThreadNames]::Read($thread.Id,$gameId); cpu_ms=$delta}
            }
        }
    } catch { }
})
$result = [pscustomobject]@{pid=$gameId; process_started_utc=$created.ToString('o'); elapsed_ms=$elapsed;
    scope='CPU deltas include active waits; names are observations, not verified roles';
    threads=@($rows | Sort-Object cpu_ms -Descending)}
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $BenchmarkDirectory 'thread-inventory.json')
$result.threads | Select-Object -First 20
