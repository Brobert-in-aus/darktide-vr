$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$artifactRoot=[IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts/unattended'))
$fixtureRoot=Join-Path $artifactRoot ('proximity-result-fixture-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
$fakeAdb=Join-Path $fixtureRoot 'fake-adb.ps1'
$proximityScript=Join-Path $repoRoot 'tools/quest/set-proximity-override.ps1'
try {
    @'
$global:LASTEXITCODE=0
if ($args -contains 'getprop') { 'Quest Fixture'; return }
if ($args -contains 'broadcast') {
    [void]$global:proximityFixtureCalls.Add($args[-1])
    switch ($global:proximityFixtureMode) {
        'exit_failure' { 'Broadcast completed: result=0';$global:LASTEXITCODE=1 }
        'result_failure' { 'Broadcast completed: result=1' }
        'leading_zero_failure' { 'Broadcast completed: result=01' }
        'missing_result' { 'Broadcasting: Intent { fixture }' }
        default { 'Broadcast completed: result=0' }
    }
    return
}
if ($args -contains 'dumpsys') {
    [void]$global:proximityFixtureCalls.Add('power')
    'mWakefulness=Awake'
    if ($global:proximityFixtureMode -eq 'exit_failure') { $global:LASTEXITCODE=1 }
    return
}
throw 'Unexpected fake ADB command'
'@ | Set-Content -LiteralPath $fakeAdb -Encoding UTF8
    $caseCount=0
    foreach ($action in @('Disable','Enable')) {
        foreach ($mode in @('pass','exit_failure','result_failure','leading_zero_failure','missing_result')) {
            $global:proximityFixtureMode=$mode
            $global:proximityFixtureCalls=[Collections.Generic.List[string]]::new()
            $rejected=$false
            try { $output=@(& $proximityScript -Action $action -Device 'fixture' -AdbPath $fakeAdb) }
            catch { $rejected=$true }
            if ($rejected -ne ($mode -ne 'pass')) { throw "Incorrect $action result for $mode" }
            if ($global:proximityFixtureCalls.Count -ne 1) { throw 'Broadcast was repeated or skipped' }
            $expected=if ($action -eq 'Disable') { 'com.oculus.vrpowermanager.prox_close' } else { 'com.oculus.vrpowermanager.automation_disable' }
            if ($global:proximityFixtureCalls[0] -ne $expected) { throw 'Wrong proximity action' }
            if (-not $rejected -and ($output -join "`n") -notmatch 'Broadcast completed: result=0') { throw 'Successful receipt was lost' }
            $caseCount++
        }
    }
    foreach ($mode in @('pass','exit_failure')) {
        $global:proximityFixtureMode=$mode
        $global:proximityFixtureCalls=[Collections.Generic.List[string]]::new()
        $rejected=$false
        try { & $proximityScript -Action Status -Device 'fixture' -AdbPath $fakeAdb | Out-Null }
        catch { $rejected=$true }
        if ($rejected -ne ($mode -ne 'pass')) { throw 'Incorrect power query result' }
        if ($global:proximityFixtureCalls.Count -ne 1 -or $global:proximityFixtureCalls[0] -ne 'power') { throw 'Status attempted a mutation' }
        $caseCount++
    }
    Write-Output "quest_proximity_results=pass cases=$caseCount broadcast_receipts power_exit no_real_adb"
} finally {
    $resolvedFixture=[IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolvedFixture.StartsWith($artifactRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    Remove-Variable proximityFixtureCalls,proximityFixtureMode -Scope Global -ErrorAction SilentlyContinue
}
