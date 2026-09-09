Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot '../../tools/stereo/get-focused-trial-status.ps1'
$root=Join-Path ([IO.Path]::GetTempPath()) ('darktidevr-trial-status-'+[guid]::NewGuid().ToString('N'))
$game=Join-Path $root 'game'
$stage=Join-Path $root 'stage'
[IO.Directory]::CreateDirectory($game)|Out-Null
[IO.Directory]::CreateDirectory($stage)|Out-Null
[IO.File]::WriteAllText("$game/target.lua",'accepted')
[IO.File]::WriteAllText("$game/sentinel",'preserve')
[IO.File]::WriteAllText("$stage/source.lua",'candidate')
$sourceHash=(Get-FileHash "$stage/source.lua").Hash
$baselineHash=(Get-FileHash "$game/target.lua").Hash
$entry=@{Source='source.lua';Destination='target.lua';ExpectedSourceHash=$sourceHash;ExpectedDestinationHash=$baselineHash}
$plan=@{schema_version=1;kind='selective_trial_plan';status='staged_not_deployed';reviewed_revision='fixture';entries=@($entry)}
function Save-Plan { $plan|ConvertTo-Json -Depth 5|Set-Content "$stage/plan.json" }
function Check([bool]$Value) { if(-not $Value){throw 'Trial status assertion failed'} }
function Reject {
    $failed=$false
    try { & $script -PlanPaths "$stage/plan.json" -GameRoot $game|Out-Null } catch { $failed=$true }
    Check $failed
}
Save-Plan
$report=& $script -PlanPaths "$stage/plan.json" -GameRoot $game
Check ($report.all_hashes_match -and -not $report.readiness_verified)
Check ($report.overlapping_destinations.Count -eq 0)
$entry.ExpectedSourceHash='0'*64;Save-Plan
Check (-not (& $script -PlanPaths "$stage/plan.json" -GameRoot $game).all_hashes_match)
$entry.ExpectedSourceHash=$sourceHash;$entry.ExpectedDestinationHash='0'*64;Save-Plan
Check (-not (& $script -PlanPaths "$stage/plan.json" -GameRoot $game).all_hashes_match)
$entry.ExpectedDestinationHash=$null;Save-Plan
Check (-not (& $script -PlanPaths "$stage/plan.json" -GameRoot $game).all_hashes_match)
$entry.Destination='absent.lua';Save-Plan
Check ((& $script -PlanPaths "$stage/plan.json" -GameRoot $game).all_hashes_match)
$entry.Source='missing.lua';Save-Plan
Check (-not (& $script -PlanPaths "$stage/plan.json" -GameRoot $game).all_hashes_match)
$entry.Source='../outside.lua';Save-Plan;Reject
$entry.Source='source.lua';$entry.Destination='../outside.lua';Save-Plan;Reject
$entry.Destination="$game/target.lua";Save-Plan;Reject
$entry.Destination='target.lua';$entry.ExpectedDestinationHash=$baselineHash
$plan.entries=@($entry,$entry);Save-Plan;Reject
$plan.entries=@($entry);Save-Plan
Copy-Item "$stage/plan.json" "$stage/other.json"
$report=& $script -PlanPaths @("$stage/plan.json","$stage/other.json") -GameRoot $game
Check ($report.all_hashes_match -and $report.overlapping_destinations.Count -eq 1)
Check ($report.overlapping_destinations[0].plans.Count -eq 2)
Check ((Get-FileHash "$game/target.lua").Hash -eq $baselineHash)
Check ((Get-FileHash "$stage/source.lua").Hash -eq $sourceHash)
Check ([IO.File]::ReadAllText("$game/sentinel") -ceq 'preserve')
Check (@(Get-ChildItem -LiteralPath $game -File).Count -eq 2)
Write-Output 'focused_trial_status=pass hashes absence containment duplicates overlaps read_only'
