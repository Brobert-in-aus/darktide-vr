[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $OutputPath,
    [Parameter(Mandatory)][string] $StatePath,
    [Parameter(Mandatory)][string] $QueuePath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$output = & (Join-Path $PSScriptRoot 'read-ngx-output-probe.ps1') -Path $OutputPath
$queue = & (Join-Path $PSScriptRoot 'read-ngx-queue-probe.ps1') -OutputPath $OutputPath -QueuePath $QueuePath
$calls = @{}
foreach ($observation in $output.Observations) { $calls[[uint64]$observation.Call] = $observation }
$states = @{}; $pairs = @(); $seen = @{}; $barrierCounts = @{}
foreach ($line in Get-Content -LiteralPath $StatePath) {
    $parts = $line -split ' '
    if ($parts[0] -notin @('NGX_STATE','NGX_BARRIER','NGX_PAIR')) { throw 'Unknown output-state record.' }
    $fields = @{}
    foreach ($part in $parts[1..($parts.Count-1)]) {
        $field = $part -split '=',2
        if ($field.Count -ne 2 -or $fields.ContainsKey($field[0])) { throw 'Malformed output-state field.' }
        $fields[$field[0]] = $field[1]
    }
    if ($fields.call -notmatch '^[1-9]\d*$') { throw 'Invalid output-state call.' }
    $call = [uint64]$fields.call
    if ($parts[0] -eq 'NGX_STATE') {
        if ($states.ContainsKey($call) -or $states.Count -ge 256 -or
            $fields.truncated -notmatch '^[01]$' -or $fields.barriers -notmatch '^\d+$' -or
            [uint32]$fields.barriers -gt 32) { throw 'Invalid or duplicate state scope.' }
        $states[$call] = $fields
        $barrierCounts[$call] = 0
    } elseif ($parts[0] -eq 'NGX_BARRIER') {
        if (-not $states.ContainsKey($call) -or $fields.index -notmatch '^\d+$' -or
            [uint32]$fields.index -ne $barrierCounts[$call] -or $fields.type -notmatch '^[01]$') {
            throw 'Barrier trace has a missing scope, index gap or unsupported type.'
        }
        ++$barrierCounts[$call]
    } elseif ($parts[0] -eq 'NGX_PAIR') {
        if ($seen.ContainsKey($call)) { throw 'Duplicate output pair.' }
        $seen[$call] = $true
        $pairs += $fields
    }
}
$verified = @()
foreach ($pair in $pairs) {
    foreach ($field in @('call','left_call','known','state','ambiguous','transitions')) {
        if ($pair[$field] -notmatch '^\d+$') { throw 'Invalid pair numeric field.' }
    }
    $leftCall = [uint64]$pair.left_call; $rightCall = [uint64]$pair.call
    if ($rightCall -ne $leftCall + 1 -or $pair.known -ne '1' -or $pair.ambiguous -ne '0' -or
        $pair.publication -ne '0' -or [uint32]$pair.transitions -eq 0 -or
        -not $calls.ContainsKey($leftCall) -or -not $calls.ContainsKey($rightCall)) {
        throw 'Pair lacks adjacent successful, complete evaluations and a known state.'
    }
    $left = $calls[$leftCall]; $right = $calls[$rightCall]
    foreach ($call in @($leftCall,$rightCall)) {
        if (-not $states.ContainsKey($call) -or $states[$call].truncated -ne '0' -or
            [uint32]$states[$call].barriers -ne $barrierCounts[$call] -or
            $states[$call].single_subresource -ne '1' -or $call -notin $queue.CompletedCalls) {
            throw 'Pair lacks complete state trace or GPU completion.'
        }
        $scope = $states[$call]; $observation = $calls[$call]
        if ($scope.output -cne $observation.Output -or $scope.commands -cne $observation.Commands) {
            throw 'State scope does not match evaluation.'
        }
    }
    if (-not $left.OutputStateKnown -or $left.FeatureLifetime -eq $right.FeatureLifetime -or
        $left.Thread -ne $right.Thread -or $left.Commands -cne $right.Commands -or
        $left.Output -cne $right.Output -or $pair.commands -cne $left.Commands -or
        $pair.output -cne $left.Output -or $left.OutputWidth -ne $right.OutputWidth -or
        $left.OutputHeight -ne $right.OutputHeight -or -not $left.LegacyRegionAvailable -or
        -not $right.LegacyRegionAvailable) { throw 'Stereo evaluation identity mismatch.' }
    $width = [uint64]$left.LegacyRegion[2]; $height = [uint64]$left.LegacyRegion[3]
    if ($width -eq 0 -or $left.OutputWidth -ne 2*$width -or $left.OutputHeight -ne $height -or
        ($left.LegacyRegion -join ',') -ne "0,0,$width,$height" -or
        ($right.LegacyRegion -join ',') -ne "$width,0,$width,$height") {
        throw 'Pair does not cover the exact packed stereo output.'
    }
    $submissions = @($queue.Matches | Where-Object { $_.Call -in @($leftCall,$rightCall) })
    if ($submissions.Count -ne 2 -or $submissions[0].Queue -cne $submissions[1].Queue -or
        $submissions[0].QueueType -ne $submissions[1].QueueType) { throw 'Pair queue mismatch.' }
    $verified += [pscustomobject]@{LeftCall=$leftCall;RightCall=$rightCall;Output=$left.Output;
        Width=2*$width;Height=$height;EndState=[uint32]$pair.state;Queue=$submissions[0].Queue}
}
if (-not $verified.Count) { throw 'No fully verified output-state pair.' }
[pscustomobject]@{
    PairEndStateVerified=$true; PairCount=$verified.Count; Pairs=$verified
    EvaluationCommandsCompleted=$true
    OutputOwnershipVerified=$false; GeneratedXrPublicationVerified=$false
}
