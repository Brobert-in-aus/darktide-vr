[CmdletBinding()]
param([string] $Path = (Join-Path $env:TEMP 'darktidevr-streamline-probe.tsv'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$records = @(Get-Content -LiteralPath $Path | Where-Object { $_.StartsWith("STEREO_CONTINUOUS`t") } | ForEach-Object {
    $record = @{}
    foreach ($field in ($_ -split "`t" | Select-Object -Skip 1)) {
        $parts = $field -split '=', 2
        if ($parts.Count -ne 2 -or $record.ContainsKey($parts[0])) { throw 'Malformed continuous record.' }
        $record[$parts[0]] = $parts[1]
    }
    $record
})
if (-not $records.Count) { throw 'No continuous submission records.' }
if (@($records | Where-Object phase -EQ 'failed').Count) { throw 'Continuous submission reported a failure.' }
$ready = @($records | Where-Object phase -EQ 'ready')
$stop = @($records | Where-Object phase -EQ 'stopped')
$presents = @($records | Where-Object phase -EQ 'present')
$tickets = @($records | Where-Object phase -EQ 'ticket')
$states = @($records | Where-Object phase -EQ 'state')
if ($ready.Count -ne 1 -or $stop.Count -ne 1) { throw 'Incomplete or duplicate continuous lifecycle.' }
if ($ready[0].ContainsKey('frame_trace') -and $ready[0].frame_trace -ne 'complete') {
    throw 'Sampled continuous-play logs cannot certify a consecutive bounded probe.'
}
$count = [uint32]$ready[0].frames
if ($count -lt 2 -or $count -gt 8 -or [uint32]$ready[0].eye_width -eq 0 -or
    [uint32]$ready[0].eye_height -eq 0 -or $presents.Count -ne $count -or
    $tickets.Count -ne 2 * $count -or [uint32]$stop[0].frames -ne $count -or
    $stop[0].tags_cleared -ne '1' -or $stop[0].owners_retained -ne '1') {
    throw 'Continuous frame count, extent, cleanup or ownership evidence is incomplete.'
}
$reportedGeneratedEyes = 0
if ($states.Count -ne 0 -and $states.Count -ne 2 * $count) {
    throw 'Incomplete DLSS state status evidence.'
}
for ($index = 0; $index -lt $count; ++$index) {
    $present = $presents[$index]
    if ([uint32]$present.frame -ne $index + 1 -or [uint64]$present.pose -eq 0 -or
        [uint64]$present.present_frame -eq 0 -or $present.publication -ne '0') {
        throw 'Invalid continuous Present identity.'
    }
    if ($index -gt 0 -and [uint64]$present.present_frame -ne [uint64]$presents[$index - 1].present_frame + 1) {
        throw 'Continuous submission contains a Present gap.'
    }
    for ($eye = 0; $eye -lt 2; ++$eye) {
        if ($states.Count) {
            $state = @($states | Where-Object { [uint32]$_.frame -eq $index + 1 -and [uint32]$_.eye -eq $eye })
            if ($state.Count -ne 1 -or $state[0].result -ne '0' -or
                $state[0].status -ne '0' -or [uint32]$state[0].version -lt 3) {
                throw 'Missing, duplicate or unsuccessful DLSS state.'
            }
        }
        $ticket = @($tickets | Where-Object { [uint32]$_.frame -eq $index + 1 -and [uint32]$_.eye -eq $eye })
        if ($ticket.Count -ne 1 -or [uint64]$ticket[0].value -eq [uint64]::MaxValue) {
            throw 'Missing, duplicate or poisoned input completion ticket.'
        }
        if ([uint32]$ticket[0].frames_presented -gt 1) { ++$reportedGeneratedEyes }
    }
}
[pscustomobject]@{
    ConsecutiveSubmissionVerified = $true
    FrameCount = $count
    EyeWidth = [uint32]$ready[0].eye_width
    EyeHeight = [uint32]$ready[0].eye_height
    GeneratedEyePresentsReported = $reportedGeneratedEyes
    OwnersRetained = $true
    StateStatusVerified = $states.Count -eq 2 * $count
    OutputOwnershipVerified = $false
    GeneratedXrPublicationVerified = $false
    VisualAcceptance = 'unverified'
}
