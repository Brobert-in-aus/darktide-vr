[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $OutputPath,
    [Parameter(Mandatory)][string] $QueuePath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$output = & (Join-Path $PSScriptRoot 'read-ngx-output-probe.ps1') -Path $OutputPath
$identities = @{}
foreach ($observation in $output.Observations) { $identities[[uint64]$observation.Call] = $observation }
$seen = @{}
$matchedSubmissions = @()
$resetCalls = @()
$otherCalls = 0
foreach ($line in Get-Content -LiteralPath $QueuePath) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line.Split(' ')
    if ($parts[0] -cnotin @('NGX_SUBMIT','NGX_RESET')) { throw 'Unknown NGX queue event.' }
    $fields = @{}
    foreach ($part in $parts | Select-Object -Skip 1) {
        $pair = $part.Split('=',2)
        if ($pair.Count -ne 2 -or $fields.ContainsKey($pair[0])) { throw 'Malformed NGX queue field.' }
        $fields[$pair[0]] = $pair[1]
    }
    if ($fields.call -notmatch '^\d+$') { throw 'Invalid NGX call identity.' }
    $call = [uint64]::Parse($fields.call)
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
[pscustomobject]@{
    CompleteEvaluationCount=$output.CompleteObservations
    MatchedSubmissionCount=$matchedSubmissions.Count; Matches=$matchedSubmissions; ResetCalls=$resetCalls
    OtherEvaluationSubmissions=$otherCalls
    GpuCompletionVerified=$false; GeneratedPublicationVerified=$false
}
