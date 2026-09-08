$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$path = Join-Path $PSScriptRoot '../../tools/unattended/invoke-unattended-preflight.ps1'
$source = Get-Content -LiteralPath $path -Raw
$first = $source.IndexOf('$adb = Get-AdbPath')
$last = $source.IndexOf('$vdProcesses =', $first)
if ($first -lt 0 -or $last -lt $first) { throw 'Preflight device section not found.' }
$selection = [scriptblock]::Create($source.Substring($first, $last - $first))
function Get-AdbPath { 'Invoke-FixtureAdb' }
function Invoke-FixtureAdb {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'devices') {
        'List of devices attached'
        for ($i=0; $i -lt $script:fixtureCount; $i++) { "fixture-$i`tdevice" }
        if ($script:failDeviceQuery) { $global:LASTEXITCODE=1 }
    } elseif ($args -contains 'getprop') {
        if ($args -contains 'ro.serialno') {
            $script:identityQueries++
            if ($script:identityFailure) { $global:LASTEXITCODE=1; return }
            if ($script:emptyIdentity) { return }
            if ($script:sameIdentity) { 'fixture-0' } else { $args[1] }
            return
        }
        $script:modelQueries++
        if ($script:failModel) { $global:LASTEXITCODE=1; return }
        $script:fixtureModel
    } elseif ($args -contains 'broadcast') {
        $script:broadcasts++
        if ($script:badBroadcast) { 'Broadcast completed: result=01';return }
        'Broadcast completed: result=0'
    } elseif ($args -contains 'dumpsys') {
        $script:powerQueries++
        'mWakefulness=Awake'
    } else { throw 'Unexpected fixture ADB command.' }
}
foreach ($case in @(
    @{count=0;mode='Inventory';status='missing';queries=0},
    @{count=2;mode='Inventory';status='ambiguous';queries=0},
    @{count=2;mode='Inventory';status='selected';queries=1;same=$true},
    @{count=2;mode='Ready';status='selected';queries=1;same=$true},
    @{count=2;mode='Inventory';status='identity_query_failed';queries=0;identity_fail=$true},
    @{count=2;mode='Ready';reject=$true;identity_fail=$true},
    @{count=2;mode='Inventory';status='identity_query_failed';queries=0;empty_identity=$true},
    @{count=2;mode='Ready';reject=$true;empty_identity=$true},
    @{count=1;mode='Inventory';status='selected';queries=1},
    @{count=1;mode='Inventory';status='not_quest';queries=0;model='Phone'},
    @{count=1;mode='Inventory';status='model_query_failed';queries=0;fail=$true},
    @{count=1;mode='Inventory';status='device_query_failed';queries=0;device_fail=$true},
    @{count=0;mode='Ready';reject=$true},
    @{count=2;mode='Ready';reject=$true},
    @{count=1;mode='Ready';reject=$true;model='Phone'},
    @{count=1;mode='Ready';reject=$true;fail=$true},
    @{count=1;mode='Ready';reject=$true;device_fail=$true},
    @{count=1;mode='Ready';status='selected';queries=1},
    @{count=1;mode='Ready';reject=$true;broadcast_bad=$true},
    @{count=2;mode='Ready';reject=$true;broadcast_bad=$true;same=$true},
    @{count=2;mode='Inventory';smoke=$true;reject=$true}
)) {
    $script:fixtureCount=$case.count
    $script:fixtureModel=if ($case.ContainsKey('model')) { $case.model } else { 'Quest Fixture' }
    $script:failModel=$case.ContainsKey('fail')
    $script:failDeviceQuery=$case.ContainsKey('device_fail')
    $script:sameIdentity=$case.ContainsKey('same')
    $script:identityFailure=$case.ContainsKey('identity_fail')
    $script:emptyIdentity=$case.ContainsKey('empty_identity')
    $script:badBroadcast=$case.ContainsKey('broadcast_bad')
    $script:broadcasts=0; $script:modelQueries=0; $script:powerQueries=0; $script:identityQueries=0
    $Mode=$case.mode; $RunXrSmoke=$case.ContainsKey('smoke'); $SkipProximityApply=$false
    $rejected=$false
    try { . $selection } catch { $rejected=$true }
    if ($rejected -ne $case.ContainsKey('reject')) { throw "Unexpected selection result: $($case | ConvertTo-Json -Compress)" }
    if ($rejected) {
        $expectedBroadcasts=if ($script:badBroadcast) { 1 } else { 0 }
        if ($script:broadcasts -ne $expectedBroadcasts -or $script:powerQueries) { throw 'Rejected target reached unexpected mutation/power query.' }
    } else {
        if ($deviceSelection -ne $case.status -or $script:powerQueries -ne $case.queries) { throw 'Incorrect inventory status.' }
        if ($case.mode -eq 'Inventory' -and ($script:broadcasts -or $proximityApplied)) { throw 'Inventory mutated proximity.' }
        if ($case.mode -eq 'Ready' -and $script:broadcasts -ne 1) { throw 'Ready skipped proximity application.' }
    }
    if (($case.count -eq 0 -or $script:failDeviceQuery) -and $script:modelQueries) { throw 'Missing/failed inventory queried a device.' }
    if ($script:sameIdentity -and ($device -ne 'fixture-0' -or $physicalQuestCount -ne 1 -or -not $duplicateTransports)) {
        throw 'Same Quest aliases did not prefer its direct transport.'
    }
}
function Invoke-IdentityFixtureAdb {
    $global:LASTEXITCODE=0
    $index=if ($args[1] -eq 'network-a') { 0 } else { 1 }
    if ($args -contains 'ro.product.model') {
        if ($script:identityCase -eq 'model_failure' -and $index -eq 1) { $global:LASTEXITCODE=1;return }
        if ($script:identityCase -eq 'phone' -and $index -eq 1) { 'Phone';return }
        if ($script:identityCase -eq 'model_conflict' -and $index -eq 1) { 'Quest 3S';return }
        'Quest 3';return
    }
    if ($args -contains 'ro.serialno') {
        if ($script:identityCase -eq 'serial_failure' -and $index -eq 1) { $global:LASTEXITCODE=1;return }
        if ($script:identityCase -eq 'unknown') { 'unknown';return }
        if ($script:identityCase -eq 'zero') { '000000';return }
        if ($script:identityCase -eq 'case_distinct' -and $index -eq 1) { 'physical-a';return }
        'PHYSICAL-A';return
    }
    throw 'Identity resolver attempted a non-read-only command.'
}
foreach ($identitySpec in @(
    @{name='network_aliases';status='selected'},
    @{name='model_failure';status='model_query_failed'},
    @{name='phone';status='not_quest'},
    @{name='model_conflict';status='identity_conflict'},
    @{name='serial_failure';status='identity_query_failed'},
    @{name='unknown';status='identity_query_failed'},
    @{name='zero';status='identity_query_failed'},
    @{name='case_distinct';status='ambiguous'}
)) {
    $script:identityCase=$identitySpec.name
    $resolved=Resolve-QuestTransport -Adb 'Invoke-IdentityFixtureAdb' -AuthorizedTransports @('network-b','network-a')
    if ($resolved.Status -ne $identitySpec.status) { throw "Unexpected identity status for $($identitySpec.name)" }
    if ($resolved.Status -eq 'selected') {
        if ($resolved.Device -ne 'network-a' -or -not $resolved.DuplicateTransports) { throw 'Equivalent network aliases were not deterministic.' }
    } elseif ($resolved.Device -or $resolved.Model -or $resolved.DuplicateTransports) {
        throw 'Rejected identity leaked a selected device.'
    }
}
Write-Output 'preflight_device_inventory=pass cases=29 proven_aliases no_ambiguous_selection no_inventory_mutation strict_ready'
