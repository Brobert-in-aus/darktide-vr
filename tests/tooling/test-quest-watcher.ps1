Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('dtvr-quest-watcher-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$watcher = Join-Path $fixtureRoot 'watch-quest-online.ps1'
$proximity = Join-Path $fixtureRoot 'set-proximity-override.ps1'
$fakeAdb = Join-Path $fixtureRoot 'fake-adb.ps1'
$log = Join-Path $fixtureRoot 'watcher.log'
$oldLocalAppData = $env:LOCALAPPDATA
$oldAppData = $env:APPDATA
try {
    # Run the actual scripts together. Only this fixture client can be found;
    # neither device discovery, real ADB, wall-clock waits nor XR is exercised.
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../tools/quest/watch-quest-online.ps1') -Destination $watcher
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../tools/quest/set-proximity-override.ps1') -Destination $proximity
    $env:LOCALAPPDATA = $fixtureRoot
    $env:APPDATA = $fixtureRoot
    Set-Content -LiteralPath $fakeAdb -Encoding ascii -Value @'
$global:LASTEXITCODE = 0
if ($args[0] -eq 'devices') {
    $global:questFixture.polls++
    'List of devices attached'
    if (-not $global:questFixture.disconnected -or $global:questFixture.polls -eq 1) {
        foreach ($device in $global:questFixture.devices) { "$device`tdevice" }
    }
    return
}
if ($args[0] -ne '-s' -or $args[1] -notin $global:questFixture.devices) { throw 'Unexpected fixture target' }
if ($args -contains 'getprop') { 'Quest Fixture'; return }
if ($args -contains 'broadcast') {
    $action = if ($args -contains 'com.oculus.vrpowermanager.prox_close') { 'Disable' } else { 'Enable' }
    $global:questFixture.calls.Add("${action}:$($args[1])")
    if (($action -eq 'Enable' -and $args[1] -eq $global:questFixture.failRestore) -or
        ($action -eq 'Disable' -and $global:questFixture.failApply)) { $global:LASTEXITCODE = 1 }
    if ($action -eq 'Enable' -and $global:questFixture.badRestoreResult) {
        'Broadcast completed: result=1'
    } else { 'Broadcast completed: result=0' }
    return
}
throw 'Unexpected fixture ADB command'
'@
    function Get-Command { param([string] $Name)
        if ($Name -ne 'adb') { throw 'Unexpected command lookup' }
        [pscustomobject]@{Source=$fakeAdb}
    }
    function Get-CimInstance {
        [CmdletBinding()] param([string] $ClassName, [string] $Filter)
        [pscustomobject]@{CommandLine='fork-server server';ExecutablePath=$fakeAdb}
    }
    function Get-Date { param([string] $Format)
        $date = [datetime]'2000-01-01T00:00:00'
        if ($Format) { return $date.ToString($Format) }
        if ($global:questFixture.polls -ge 2) { return $date.AddSeconds(2) }
        return $date
    }
    function Start-Sleep { param([int] $Seconds)
        if ($global:questFixture.loopFault) { throw 'fixture loop fault' }
    }
    foreach ($case in @('normal','disconnected','restore_failure','restore_result_failure','apply_failure','loop_failure')) {
        $global:questFixture = @{
            polls=0; devices=@('Quest-A'); disconnected=($case -eq 'disconnected')
            failRestore=''; failApply=($case -eq 'apply_failure')
            badRestoreResult=($case -eq 'restore_result_failure')
            loopFault=($case -eq 'loop_failure')
            calls=(New-Object 'System.Collections.Generic.List[string]')
        }
        if ($case -eq 'restore_failure') {
            $global:questFixture.devices=@('Quest-A','Quest-B')
            $global:questFixture.failRestore='Quest-B'
        }
        $failed=$false; $failureMessage=''
        try { & $watcher -Until ([datetime]'2000-01-01T00:00:01') -PollSeconds 2 -LogPath $log }
        catch { $failed=$true; $failureMessage=$_.Exception.Message }
        if ($failed -ne ($case -in @('restore_failure','restore_result_failure','loop_failure'))) { throw "Unexpected watcher result: $case $failureMessage" }
        if ($case -eq 'loop_failure' -and $failureMessage -ne 'fixture loop fault') { throw 'Cleanup replaced the original loop fault' }
        foreach ($device in $global:questFixture.devices) {
            if (@($global:questFixture.calls | Where-Object { $_ -eq "Enable:$device" }).Count -ne 1) {
                throw "Cleanup lost or repeated a device: $case $device"
            }
        }
        $contents = Get-Content -LiteralPath $log -Raw
        if ($case -eq 'restore_failure' -and ($contents -notmatch 'listener=restore_failed device=Quest-B' -or
                $contents -notmatch 'listener=restored device=Quest-A')) { throw 'Failed cleanup hid another device outcome' }
        if ($case -eq 'restore_result_failure' -and $contents -notmatch 'listener=restore_failed device=Quest-A') { throw 'Failed broadcast result was reported as restored' }
        if ($case -eq 'disconnected' -and $contents -notmatch 'listener=disconnected') { throw 'Disconnect case did not run' }
        if ($case -eq 'apply_failure' -and $contents -notmatch 'listener=apply_failed') { throw 'Apply failure case did not run' }
        if ($contents -notmatch 'listener=stopped') { throw 'Watcher did not finish cleanup' }
        Remove-Item -LiteralPath $log
    }
    'quest_watcher=pass normal disconnected ambiguous_apply loop_fault failed_restore broadcast_result isolated_adb'
}
finally {
    $env:LOCALAPPDATA=$oldLocalAppData
    $env:APPDATA=$oldAppData
    Remove-Variable -Name questFixture -Scope Global -ErrorAction SilentlyContinue
    foreach ($path in @($watcher,$proximity,$fakeAdb,$log)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    Remove-Item -LiteralPath $fixtureRoot
}
