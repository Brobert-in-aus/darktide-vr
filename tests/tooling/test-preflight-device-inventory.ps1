$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
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
        $script:modelQueries++
        if ($script:failModel) { $global:LASTEXITCODE=1; return }
        $script:fixtureModel
    } elseif ($args -contains 'broadcast') {
        $script:broadcasts++
        'Broadcast completed: result=0'
    } elseif ($args -contains 'dumpsys') {
        $script:powerQueries++
        'mWakefulness=Awake'
    } else { throw 'Unexpected fixture ADB command.' }
}
foreach ($case in @(
    @{count=0;mode='Inventory';status='missing';queries=0},
    @{count=2;mode='Inventory';status='ambiguous';queries=0},
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
    @{count=2;mode='Inventory';smoke=$true;reject=$true}
)) {
    $script:fixtureCount=$case.count
    $script:fixtureModel=if ($case.ContainsKey('model')) { $case.model } else { 'Quest Fixture' }
    $script:failModel=$case.ContainsKey('fail')
    $script:failDeviceQuery=$case.ContainsKey('device_fail')
    $script:broadcasts=0; $script:modelQueries=0; $script:powerQueries=0
    $Mode=$case.mode; $RunXrSmoke=$case.ContainsKey('smoke'); $SkipProximityApply=$false
    $rejected=$false
    try { . $selection } catch { $rejected=$true }
    if ($rejected -ne $case.ContainsKey('reject')) { throw "Unexpected selection result: $($case | ConvertTo-Json -Compress)" }
    if ($rejected) {
        if ($script:broadcasts -or $script:powerQueries) { throw 'Rejected target reached device mutation/power query.' }
    } else {
        if ($deviceSelection -ne $case.status -or $script:powerQueries -ne $case.queries) { throw 'Incorrect inventory status.' }
        if ($case.mode -eq 'Inventory' -and ($script:broadcasts -or $proximityApplied)) { throw 'Inventory mutated proximity.' }
        if ($case.mode -eq 'Ready' -and $script:broadcasts -ne 1) { throw 'Ready skipped proximity application.' }
    }
    if (($case.count -ne 1 -or $script:failDeviceQuery) -and $script:modelQueries) { throw 'Unproven selection queried a device.' }
}
Write-Output 'preflight_device_inventory=pass cases=13 no_ambiguous_selection no_inventory_mutation strict_ready'
