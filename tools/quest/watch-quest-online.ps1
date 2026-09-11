[CmdletBinding()]
param(
    [ValidateRange(2, 300)]
    [int] $PollSeconds = 10,

    [datetime] $Until = (Get-Date).Date.AddDays(1),

    [string] $LogPath = (Join-Path ([IO.Path]::GetTempPath()) `
        'darktidevr-quest-online.log')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$adbFallbacks = @(
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
    (Join-Path $env:APPDATA 'SideQuest\platform-tools\adb.exe')
)
$adbFallbacks = @($adbFallbacks | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($adbCommand -and $adbFallbacks -notcontains $adbCommand.Source) {
    $adbFallbacks += $adbCommand.Source
}
if ($adbFallbacks.Count -eq 0) {
    throw 'adb.exe was not found in the Android SDK, SideQuest, or PATH'
}

$proximityScript = Join-Path $PSScriptRoot 'set-proximity-override.ps1'
$applied = @{}
# Keep cleanup responsibility even when a device disappears from a poll.
$restoreDevices = @{}
$lastAdb = $null
$watcherFailure = $null

# Under a fail-closed preference, Windows PowerShell turns every native stderr
# line behind 2>&1 into a terminating error. Merge the streams with the
# preference relaxed and return the text with the exit code.
function Invoke-NativeMerged([scriptblock] $Command) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $Command 2>&1 | ForEach-Object { "$_" })
        [pscustomobject]@{ Output = $lines; ExitCode = $LASTEXITCODE }
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Get-AdbCandidates {
    $candidates = @()
    try {
        $candidates += @(Get-CimInstance Win32_Process `
                -Filter "Name='adb.exe'" -ErrorAction Stop |
            Where-Object {
                $_.CommandLine -match 'fork-server\s+server' -and
                $_.ExecutablePath
            } |
            ForEach-Object ExecutablePath)
    }
    catch {
        # Process discovery is an optimization. Static clients below retain
        # the listener if CIM is temporarily unavailable.
    }
    $candidates += $adbFallbacks
    return @($candidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -Unique)
}

function Write-WatcherLog {
    param([string] $Message)

    $timestamp = Get-Date -Format o
    Add-Content -LiteralPath $LogPath -Value "$timestamp $Message"
}

Write-WatcherLog "listener=started pid=$PID poll_seconds=$PollSeconds until=$($Until.ToString('o'))"

try {
    while ((Get-Date) -lt $Until) {
        try {
            $rows = $null
            $activeAdb = $null
            $failures = @()
            foreach ($candidate in @(Get-AdbCandidates)) {
                # ADB writes daemon startup diagnostics to stderr even when it
                # succeeds. Capture that stream without letting the script's
                # fail-closed preference turn a successful poll into a fault.
                $previousErrorActionPreference = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                try {
                    $candidateRows = @(& $candidate devices 2>&1)
                    $candidateExitCode = $LASTEXITCODE
                }
                finally {
                    $ErrorActionPreference = $previousErrorActionPreference
                }
                if ($candidateExitCode -eq 0) {
                    $rows = $candidateRows
                    $activeAdb = $candidate
                    break
                }
                $failures +=
                    "client=$candidate exit=$($candidateExitCode) output=$($candidateRows -join ' ')"
            }
            if (-not $activeAdb) {
                throw "all adb clients failed: $($failures -join ' | ')"
            }
            if ($activeAdb -ne $lastAdb) {
                Write-WatcherLog "listener=adb_selected path=$activeAdb"
                $lastAdb = $activeAdb
            }
        }
        catch {
            Write-WatcherLog `
                "listener=adb_failed error=$($_.Exception.Message)"
            Start-Sleep -Seconds $PollSeconds
            continue
        }
        $online = @{}

        foreach ($row in $rows) {
            if ($row -match '^([^\s]+)\s+device(?:\s|$)') {
                $device = $Matches[1]
                $online[$device] = $true

                if (-not $applied.ContainsKey($device)) {
                    try {
                        $modelQuery = Invoke-NativeMerged {
                            & $activeAdb -s $device shell getprop ro.product.model
                        }
                        $model = ($modelQuery.Output -join "`n").Trim()
                        if ($modelQuery.ExitCode -eq 0 -and $model -match '^Quest') {
                            $restoreDevices[$device] = $activeAdb
                            $applyResult = Invoke-NativeMerged {
                                & $proximityScript -Action Disable -Device $device `
                                    -AdbPath $activeAdb
                            }
                            $result = $applyResult.Output
                            if ($applyResult.ExitCode -ne 0) {
                                throw ($result -join ' ')
                            }
                            $applied[$device] = $true
                            Write-WatcherLog `
                                "listener=applied device=$device model=$model result=$($result -join ' ')"
                        }
                    }
                    catch {
                        Write-WatcherLog `
                            "listener=apply_failed device=$device error=$($_.Exception.Message)"
                    }
                }
            }
        }

        foreach ($device in @($applied.Keys)) {
            if (-not $online.ContainsKey($device)) {
                $applied.Remove($device)
                Write-WatcherLog "listener=disconnected device=$device"
            }
        }

        Start-Sleep -Seconds $PollSeconds
    }
}
catch {
    $watcherFailure = $_.Exception
    Write-WatcherLog "listener=fault error=$($_.Exception.Message)"
    throw
}
finally {
    $restoreFailures = 0
    foreach ($device in @($restoreDevices.Keys)) {
        try {
            $restoreResult = Invoke-NativeMerged {
                & $proximityScript -Action Enable -Device $device `
                    -AdbPath $restoreDevices[$device]
            }
            $result = $restoreResult.Output
            if ($restoreResult.ExitCode -ne 0) { throw ($result -join ' ') }
            Write-WatcherLog "listener=restored device=$device result=$($result -join ' ')"
        }
        catch {
            $restoreFailures++
            Write-WatcherLog "listener=restore_failed device=$device error=$($_.Exception.Message)"
        }
    }
    Write-WatcherLog "listener=stopped pid=$PID"
    if ($restoreFailures) {
        $restoreMessage = "Could not restore proximity automation on $restoreFailures Quest device(s); see $LogPath"
        if ($watcherFailure) {
            # A cleanup failure must not erase the reason the watcher stopped.
            throw [AggregateException]::new("Quest watcher failed: $($watcherFailure.Message); additionally, $restoreMessage",
                [Exception[]]@($watcherFailure,[InvalidOperationException]::new($restoreMessage)))
        }
        throw $restoreMessage
    }
}
