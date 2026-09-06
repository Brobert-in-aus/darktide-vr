[CmdletBinding()]
param([Parameter(Mandatory)] [string] $Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$lines = @(Get-Content -LiteralPath $Path)
$expectedHeader = 'ngx_output_probe=armed schema=1 runtime=32.0.16.1088 resource_get_slot=9 call_limit=32768 sample_limit=256 publication=0'
if ($lines.Count -eq 0 -or $lines[0] -cne $expectedHeader) {
    throw 'Missing or unsupported NGX observation header.'
}
$seen = @{}
$observed = @()
$rejected = @()
$records = 0
foreach ($line in $lines | Select-Object -Skip 1) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if (-not $line.StartsWith('NGX_EVAL ')) { throw 'Unexpected NGX record.' }
    $fields = @{}
    foreach ($part in $line.Substring(9).Split(' ')) {
        $pair = $part.Split('=', 2)
        if ($pair.Count -ne 2 -or $fields.ContainsKey($pair[0])) {
            throw 'Malformed or duplicate NGX field.'
        }
        $fields[$pair[0]] = $pair[1]
    }
    foreach ($required in @('call','tick_ms','thread','commands','feature','parameters',
            'result','captured','abi_verified','output','backbuffer','depth','motion',
            'hudless','get_results','output_complete','publication')) {
        if (-not $fields.ContainsKey($required)) { throw "Missing NGX field: $required" }
    }
    foreach ($numeric in @('call','tick_ms','thread')) {
        if ($fields[$numeric] -notmatch '^\d+$') { throw "Invalid NGX integer: $numeric" }
        $fields[$numeric] = [uint64]::Parse($fields[$numeric])
    }
    if ($fields.call -eq 0 -or $fields.call -gt 32768 -or $seen.ContainsKey($fields.call)) {
        throw 'Out-of-range or repeated NGX call identity.'
    }
    $seen[$fields.call] = $true
    foreach ($boolean in @('captured','abi_verified','output_complete','publication')) {
        if ($fields[$boolean] -notmatch '^[01]$') { throw "Invalid NGX boolean: $boolean" }
    }
    if ($fields.output_complete -ne '0' -or $fields.publication -ne '0') {
        throw 'Identity-only observation cannot certify output completion or publication.'
    }
    foreach ($pointer in @('commands','feature','parameters','output','backbuffer','depth','motion','hudless')) {
        if ($fields[$pointer] -notmatch '^(?:0x)?[0-9a-fA-F]{1,16}$') {
            throw "Invalid NGX pointer: $pointer"
        }
        $fields[$pointer] = [Convert]::ToUInt64(($fields[$pointer] -replace '^0x',''),16)
    }
    if ($fields.result -notmatch '^0x[0-9a-fA-F]{8}$' -or
            $fields.get_results -notmatch '^[0-9a-fA-F]+(?:,[0-9a-fA-F]+){4}$') {
        throw 'Malformed NGX result codes.'
    }
    $results = @($fields.get_results.Split(',') | ForEach-Object { [Convert]::ToUInt32($_,16) })
    $records++
    if ($fields.captured -eq '0') { continue }
    $reasons = @()
    if ($fields.abi_verified -ne '1') { $reasons += 'parameter_abi_unverified' }
    if ([Convert]::ToUInt32($fields.result.Substring(2),16) -ne 1) { $reasons += 'evaluation_failed' }
    if (@($results | Where-Object { $_ -ne 1 }).Count) { $reasons += 'incomplete_resource_queries' }
    foreach ($pointer in @('commands','feature','parameters','output','backbuffer','depth','motion','hudless')) {
        if ($fields[$pointer] -eq 0) { $reasons += "missing_$pointer" }
    }
    if ($fields.output -in @($fields.backbuffer,$fields.depth,$fields.motion,$fields.hudless)) {
        $reasons += 'output_input_alias'
    }
    if ($reasons.Count) {
        $rejected += [pscustomobject]@{Call=$fields.call; Reasons=$reasons}
    }
    else {
        $observed += [pscustomobject]@{
            Call=$fields.call; Thread=$fields.thread; TickMs=$fields.tick_ms
            Commands=('{0:X16}' -f $fields.commands); Feature=('{0:X16}' -f $fields.feature)
            Output=('{0:X16}' -f $fields.output); Backbuffer=('{0:X16}' -f $fields.backbuffer)
            Depth=('{0:X16}' -f $fields.depth); Motion=('{0:X16}' -f $fields.motion)
            Hudless=('{0:X16}' -f $fields.hudless)
        }
    }
}
if (($observed.Count + $rejected.Count) -gt 256) { throw 'NGX capture budget exceeded.' }
[pscustomobject]@{
    SchemaVersion=1; Records=$records; CompleteObservations=$observed.Count
    Observations=@($observed | Sort-Object Call); Rejected=$rejected
    ObservationAvailable=($observed.Count -gt 0)
    StereoAssociationVerified=$false; GpuCompletionVerified=$false
    GeneratedPublicationVerified=$false
    NextStep=if ($observed.Count) { 'associate_exact_stereo_inputs_and_queue_completion' } else { 'inspect_missing_or_failed_runtime_observation' }
}
