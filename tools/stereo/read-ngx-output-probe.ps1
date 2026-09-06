[CmdletBinding()]
param([Parameter(Mandatory)] [string] $Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$lines = @(Get-Content -LiteralPath $Path)
$expectedHeader = 'ngx_output_probe=armed schema=1 runtime=32.0.16.1088 resource_get_slot=9 call_limit=32768 sample_limit=256 publication=0'
$windowHeader = $expectedHeader.Replace('schema=1','schema=2').Replace(' publication=0',' wait_for_stereo=0 publication=0')
$gatedHeader = $windowHeader.Replace('wait_for_stereo=0','wait_for_stereo=1')
$featureHeader = $windowHeader.Replace('schema=2','schema=3')
$featureGatedHeader = $gatedHeader.Replace('schema=2','schema=3')
$regionHeader = $featureHeader.Replace('schema=3','schema=4')
$regionGatedHeader = $featureGatedHeader.Replace('schema=3','schema=4')
if ($lines.Count -eq 0 -or $lines[0] -cnotin @($expectedHeader,$windowHeader,$gatedHeader,$featureHeader,$featureGatedHeader,$regionHeader,$regionGatedHeader)) {
    throw 'Missing or unsupported NGX observation header.'
}
$windowSchema = $lines[0] -cne $expectedHeader
$regionSchema = $lines[0] -cin @($regionHeader,$regionGatedHeader)
$featureSchema = $regionSchema -or $lines[0] -cin @($featureHeader,$featureGatedHeader)
$gated = $lines[0] -cin @($gatedHeader,$featureGatedHeader,$regionGatedHeader)
$captureWindow = $null
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
    if ($fields.call -eq 0 -or (-not $windowSchema -and $fields.call -gt 32768) -or $seen.ContainsKey($fields.call)) {
        throw 'Out-of-range or repeated NGX call identity.'
    }
    $seen[$fields.call] = $true
    if ($featureSchema) {
        foreach ($field in @('feature_kind','feature_lifetime')) {
            if (-not $fields.ContainsKey($field) -or $fields[$field] -notmatch '^\d+$') {
                throw "Missing or invalid NGX feature identity: $field"
            }
            $fields[$field] = [uint64]::Parse($fields[$field])
        }
    }
    if ($windowSchema) {
        foreach ($field in @('window_batch','window_present','window_first_call')) {
            if (-not $fields.ContainsKey($field) -or $fields[$field] -notmatch '^\d+$') {
                throw "Missing or invalid NGX window field: $field"
            }
            $fields[$field] = [uint64]::Parse($fields[$field])
        }
    }
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
    $regionAvailable = $false
    if ($regionSchema) {
        foreach ($field in @('output_width','output_height','output_format','region_x','region_y','region_width','region_height')) {
            if (-not $fields.ContainsKey($field) -or $fields[$field] -notmatch '^\d+$') {
                throw "Missing or invalid output-region field: $field"
            }
            $fields[$field] = [uint64]::Parse($fields[$field])
            if ($fields[$field] -gt [uint32]::MaxValue) { throw 'Output-region value exceeds texture/parameter limits.' }
        }
        if ($fields.region_results -notmatch '^[0-9a-fA-F]+(?:,[0-9a-fA-F]+){3}$') { throw 'Malformed output-region query results.' }
        $regionResults = @($fields.region_results.Split(',') | ForEach-Object { [Convert]::ToUInt32($_,16) })
        $regionAvailable = @($regionResults | Where-Object { $_ -ne 1 }).Count -eq 0 -and
            $fields.region_width -gt 0 -and $fields.region_height -gt 0 -and
            $fields.region_x + $fields.region_width -le $fields.output_width -and
            $fields.region_y + $fields.region_height -le $fields.output_height
    }
    $records++
    if ($fields.captured -eq '0') { continue }
    if ($windowSchema) {
        if ($fields.call -le $fields.window_first_call -or
                ($fields.call-$fields.window_first_call) -gt 32768) {
            throw 'NGX capture lies outside its bounded observation window.'
        }
        if ($gated -and ($fields.window_batch -eq 0 -or $fields.window_present -eq 0)) {
            throw 'Submission-gated capture has no window context.'
        }
        if (-not $gated -and ($fields.window_batch -ne 0 -or $fields.window_present -ne 0 -or $fields.window_first_call -ne 0)) {
            throw 'Startup observation unexpectedly acquired a submission window.'
        }
        $key = '{0}/{1}/{2}' -f $fields.window_batch,$fields.window_present,$fields.window_first_call
        if ($null -ne $captureWindow -and $captureWindow -cne $key) {
            throw 'NGX records changed capture window or replenished their budget.'
        }
        $captureWindow = $key
    }
    $reasons = @()
    if ($featureSchema -and ($fields.feature_kind -ne 11 -or $fields.feature_lifetime -eq 0)) {
        $reasons += 'frame_generation_feature_unverified'
    }
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
            FeatureKind=if ($featureSchema) { $fields.feature_kind } else { $null }
            FeatureLifetime=if ($featureSchema) { $fields.feature_lifetime } else { $null }
            OutputWidth=if ($regionSchema) { $fields.output_width } else { $null }
            OutputHeight=if ($regionSchema) { $fields.output_height } else { $null }
            RegionAvailable=$regionAvailable
            Region=if ($regionSchema) { @($fields.region_x,$fields.region_y,$fields.region_width,$fields.region_height) } else { $null }
            RegionResults=if ($regionSchema) { $regionResults } else { $null }
        }
    }
}
if (($observed.Count + $rejected.Count) -gt 256) { throw 'NGX capture budget exceeded.' }
[pscustomobject]@{
    SchemaVersion=if ($regionSchema) { 4 } elseif ($featureSchema) { 3 } elseif ($windowSchema) { 2 } else { 1 }
    WaitForStereoSubmission=$gated; CaptureWindow=$captureWindow
    Records=$records; CompleteObservations=$observed.Count
    Observations=@($observed | Sort-Object Call); Rejected=$rejected
    ObservationAvailable=($observed.Count -gt 0)
    FeatureQualifiedObservations=if ($featureSchema) { $observed.Count } else { 0 }
    StereoAssociationVerified=$false; GpuCompletionVerified=$false
    GeneratedPublicationVerified=$false
    NextStep=if ($observed.Count) { 'associate_exact_stereo_inputs_and_queue_completion' } else { 'inspect_missing_or_failed_runtime_observation' }
}
