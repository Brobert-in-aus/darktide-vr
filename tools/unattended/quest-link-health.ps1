<#
.SYNOPSIS
Watch the Quest's controller radio and say so before a session is lost to it.

.DESCRIPTION
On 18 September 2026 a worn session was lost to controllers dropping every few
seconds. Three wrong answers were given -- a lost controller, a flat battery,
interference -- before a headset reboot fixed it outright. What the headset's
own log had been saying all along was that ITS radio coprocessor was failing
its own register reads, and the first of those came eighteen minutes before the
session became unplayable.

Eighteen minutes is the entire value of this script. The fault announces itself
long before it is felt, and the fix is a forty second reboot.

    # One look, right now.
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\unattended\quest-link-health.ps1

    # The heartbeat: check every two minutes and print only when it changes.
    ... -File tools\unattended\quest-link-health.ps1 -Watch

    # Reboot the headset by itself when it goes bad, and keep watching.
    ... -File tools\unattended\quest-link-health.ps1 -Watch -RebootOnBad

Exit codes: 0 healthy, 1 degrading, 2 bad, 3 the headset could not be read.
So it can gate something else:

    ... -File tools\unattended\quest-link-health.ps1; if ($LASTEXITCODE -ge 2) { ... }

.NOTES
The decision lives in xr-readiness.ps1 (Get-ControllerLinkHealth) so it is
tested against fixtures rather than against a headset.
#>
[CmdletBinding()]
param(
    # Keep checking rather than looking once.
    [switch] $Watch,

    [ValidateRange(15, 3600)]
    [int] $IntervalSeconds = 120,

    # How far back through the headset's log to read each time. The buffer
    # holds a few tens of minutes; this bounds the work, not the history.
    [ValidateRange(1, 120)]
    [int] $WindowMinutes = 10,

    # Reboot the headset when the radio goes bad. Off by default: this is a
    # diagnostic, and rebooting a headset somebody is wearing is rude.
    [switch] $RebootOnBad,

    # Which device, when more than one is attached (USB and network both show).
    [string] $Serial,

    # Print every check, not only the ones where the verdict changed.
    # Not named -Verbose: CmdletBinding already defines that one.
    [switch] $EveryCheck
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'xr-readiness.ps1')

function Get-Adb {
    $sdkAdb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (Test-Path -LiteralPath $sdkAdb -PathType Leaf) { return $sdkAdb }
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $command) { throw 'adb.exe was not found in the Android SDK or PATH' }
    return $command.Source
}

function Get-TargetSerial {
    param([string] $Adb, [string] $Requested)
    if ($Requested) { return $Requested }
    $devices = @(& $Adb devices |
        Where-Object { $_ -match '^(\S+)\s+device\s*$' } |
        ForEach-Object { ($_ -split '\s+')[0] })
    if ($devices.Count -eq 0) { throw 'No Quest is attached to adb.' }
    # A network target is preferred when both are present: the USB one comes
    # and goes with the cable, and this script is meant to keep running.
    $network = @($devices | Where-Object { $_ -match ':\d+$' })
    if ($network.Count -ge 1) { return $network[0] }
    return $devices[0]
}

# The headset's log, bounded. -t takes a count of lines rather than a duration
# on every build that matters here, so the window is a line budget sized to the
# interval: the radio is quiet when it is well, so this is nearly always short.
function Get-HeadsetLog {
    param([string] $Adb, [string] $Serial, [int] $Minutes)
    $lines = @(& $Adb -s $Serial logcat -d -t ([string] ($Minutes * 2000)) `
        SyncBossFW:* SyncBossHAL:* '*:S' 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "adb could not read the headset log (exit $LASTEXITCODE): $($lines -join ' ')"
    }
    return $lines
}

$stateExit = @{ 'healthy' = 0; 'degrading' = 1; 'bad' = 2 }
$adb = Get-Adb
$target = Get-TargetSerial -Adb $adb -Requested $Serial
Write-Output "Watching the controller radio on $target."

$previousState = $null
$lastExit = 3
while ($true) {
    $stamp = (Get-Date).ToString('HH:mm:ss')
    try {
        $log = Get-HeadsetLog -Adb $adb -Serial $target -Minutes $WindowMinutes
        $health = Get-ControllerLinkHealth -LogLines $log
        $lastExit = $stateExit[$health.State]
        $changed = $health.State -ne $previousState
        if ($changed -or $EveryCheck) {
            if ($health.State -eq 'healthy') {
                Write-Output "$stamp  healthy  (no radio faults in the last $WindowMinutes min)"
            } else {
                Write-Output "$stamp  $($health.State.ToUpperInvariant())  $($health.Reasons -join '; ')"
                if ($changed) {
                    Write-Output ('           This is the headset, not the controllers and not ' +
                        'their batteries. Reboot it: adb -s ' + $target + ' reboot')
                }
            }
        }
        if ($health.State -eq 'bad' -and $RebootOnBad) {
            Write-Output "$stamp  rebooting the headset."
            & $adb -s $target reboot | Out-Null
            # The device goes away and comes back; nothing useful can be read
            # until it does, and a network target has to be reconnected.
            Start-Sleep -Seconds 60
            & $adb connect $target | Out-Null
            $previousState = $null
            continue
        }
        $previousState = $health.State
    } catch {
        $lastExit = 3
        Write-Output "$stamp  unreadable  $($_.Exception.Message)"
        $previousState = $null
    }
    if (-not $Watch) { break }
    Start-Sleep -Seconds $IntervalSeconds
}
exit $lastExit
