[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $OutputPath,
    [Parameter(Mandatory)][string] $QueuePath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$output = & (Join-Path $PSScriptRoot 'read-ngx-output-probe.ps1') -Path $OutputPath
$identities = @{}
foreach ($observation in $output.Observations) {
    if ($observation.FeatureKind -eq 11 -and $observation.FeatureLifetime -gt 0) {
        $identities[[uint64]$observation.Call] = $observation
    }
}
$seen = @{}
$matchedSubmissions = @()
$resetCalls = @()
$otherCalls = 0
$fenceRecords = @{}
$completionRecords = @{}
foreach ($line in Get-Content -LiteralPath $QueuePath) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line.Split(' ')
    if ($parts[0] -cnotin @('NGX_SUBMIT','NGX_RESET','NGX_FENCE','NGX_COMPLETE')) { throw 'Unknown NGX queue event.' }
    $fields = @{}
    foreach ($part in $parts | Select-Object -Skip 1) {
        $pair = $part.Split('=',2)
        if ($pair.Count -ne 2 -or $fields.ContainsKey($pair[0])) { throw 'Malformed NGX queue field.' }
        $fields[$pair[0]] = $pair[1]
    }
    if ($fields.call -notmatch '^\d+$') { throw 'Invalid NGX call identity.' }
    $call = [uint64]::Parse($fields.call)
    if ($parts[0] -cin @('NGX_FENCE','NGX_COMPLETE')) {
        if (-not $call -or $fields.ticket -notmatch '^[1-9]\d*$' -or
            [uint64]$fields.ticket -gt 256 -or $fields.fence -notmatch '^[0-9a-fA-F]{1,16}$') { throw 'Invalid completion identity.' }
        if ($parts[0] -ceq 'NGX_FENCE') {
            if ($fenceRecords.ContainsKey($call) -or $fields.result -notmatch '^0x[0-9a-fA-F]{8}$' -or
                $fields.queue -notmatch '^[0-9a-fA-F]{1,16}$' -or $fields.value -cne '1' -or
                $fields.gpu_complete -cne '0') { throw 'Invalid fence signal record.' }
            $fenceRecords[$call]=$fields
        } else {
            if ($completionRecords.ContainsKey($call) -or $fields.completed -notmatch '^\d+$' -or
                $fields.gpu_complete -notmatch '^[01]$' -or $fields.publication -cne '0') { throw 'Invalid fence completion record.' }
            $completionRecords[$call]=$fields
        }
        continue
    }
    if (-not $call -or $seen.ContainsKey($call)) { throw 'Duplicate or zero NGX queue identity.' }
    $seen[$call] = $true
    if ($seen.Count -gt 256) { throw 'NGX queue budget exceeded.' }
    if ($fields.commands -notmatch '^[0-9A-Fa-f]{1,16}$') { throw 'Invalid command-list identity.' }
    $commands = '{0:X16}' -f [Convert]::ToUInt64($fields.commands,16)
    if ($commands -eq '0000000000000000') { throw 'Null command-list identity.' }
    if ($parts[0] -ceq 'NGX_RESET') {
        if ($fields.submitted -cne '0') { throw 'Reset claimed submission.' }
        $resetCalls += $call
        continue
    }
    if ($fields.gpu_complete -cne '0' -or $fields.queue_type -notmatch '^\d+$' -or
        $fields.tick_ms -notmatch '^\d+$' -or $fields.thread -notmatch '^\d+$' -or
        $fields.queue -notmatch '^[0-9A-Fa-f]{1,16}$') { throw 'Invalid queue submission evidence.' }
    $queue = '{0:X16}' -f [Convert]::ToUInt64($fields.queue,16)
    if ($queue -eq '0000000000000000') { throw 'Null queue identity.' }
    if (-not $identities.ContainsKey($call)) { $otherCalls++; continue }
    $observation = $identities[$call]
    if ($observation.Commands -cne $commands) { throw 'Queue command list does not match its evaluation.' }
    $matchedSubmissions += [pscustomobject]@{
        Call=$call; Commands=$commands; Queue=$queue; QueueType=[uint32]$fields.queue_type
        FeatureLifetime=$observation.FeatureLifetime; Output=$observation.Output
        Region=$observation.LegacyRegion; RegionAvailable=$observation.LegacyRegionAvailable
    }
}
$completedCalls = @()
foreach ($call in $completionRecords.Keys) {
    if (-not $fenceRecords.ContainsKey($call) -or -not $seen.ContainsKey($call)) { throw 'Completion lacks an observed signal/submission.' }
    $completion=$completionRecords[$call]
    $signal=$fenceRecords[$call]
    if ($signal.ticket -cne $completion.ticket -or $signal.fence -cne $completion.fence) { throw 'Fence completion identity mismatch.' }
    $matched=@($matchedSubmissions | Where-Object Call -eq $call)
    if ($matched.Count -eq 0) { continue }
    if ($matched[0].Queue -cne $signal.queue.ToUpperInvariant()) { throw 'Signal queue differs from submission queue.' }
    $completedValue=[uint64]::Parse($completion.completed)
    if ($signal.result -ceq '0x00000000' -and [Convert]::ToUInt64($signal.fence,16) -ne 0 -and
        $completedValue -ge 1 -and $completedValue -ne [uint64]::MaxValue -and $completion.gpu_complete -ceq '1') {
        $completedCalls += $call
    }
}
[pscustomobject]@{
    CompleteEvaluationCount=$output.CompleteObservations
    MatchedSubmissionCount=$matchedSubmissions.Count; Matches=$matchedSubmissions; ResetCalls=$resetCalls
    OtherEvaluationSubmissions=$otherCalls
    CompletedEvaluationCount=$completedCalls.Count; CompletedCalls=$completedCalls
    EvaluationCommandsCompleted=($output.CompleteObservations -gt 0 -and $completedCalls.Count -eq $output.CompleteObservations)
    GpuCompletionVerified=$false; GeneratedPublicationVerified=$false
}
