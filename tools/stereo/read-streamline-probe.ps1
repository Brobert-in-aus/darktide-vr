[CmdletBinding()]
param(
    [string] $Path = (Join-Path $env:TEMP 'darktidevr-streamline-probe.tsv')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Streamline probe log not found: $Path"
}

function ConvertFrom-ProbeLine {
    param([Parameter(Mandatory)][string] $Line)

    $fields = $Line -split "`t"
    $record = [ordered]@{ event = $fields[0] }
    foreach ($field in $fields[1..($fields.Count - 1)]) {
        $separator = $field.IndexOf('=')
        if ($separator -gt 0) {
            $record[$field.Substring(0, $separator)] =
                $field.Substring($separator + 1)
        }
    }
    [pscustomobject]$record
}

$records = @(Get-Content -LiteralPath $Path |
    Where-Object { $_.Length -gt 0 } |
    ForEach-Object { ConvertFrom-ProbeLine $_ })
$probe = @($records | Where-Object event -eq 'PROBE')
$target = @($records | Where-Object event -eq 'PRESENT_TARGET')
$nativeTarget = @($records | Where-Object event -eq 'NATIVE_PRESENT_TARGET')
$modules = @($records | Where-Object event -eq 'MODULE')
$begins = @($records | Where-Object event -eq 'PRESENT_BEGIN')
$ends = @($records | Where-Object event -eq 'PRESENT_END')
$nativeBegins = @($records | Where-Object event -eq 'NATIVE_PRESENT_BEGIN')
$nativeEnds = @($records | Where-Object event -eq 'NATIVE_PRESENT_END')
$stateCalls = @($records | Where-Object event -eq 'DLSSG_STATE')
$optionCalls = @($records | Where-Object event -eq 'DLSSG_OPTIONS')
$copySchedules = @($records | Where-Object event -eq 'GENERATED_COPY_SCHEDULE')
$copyCompletions = @($records | Where-Object event -eq 'GENERATED_COPY_COMPLETE')
$transportSubmits = @($records |
    Where-Object event -eq 'GENERATED_TRANSPORT_SUBMIT')
$transportCompletions = @($records |
    Where-Object event -eq 'GENERATED_TRANSPORT_COMPLETE')
$transportDrops = @($records |
    Where-Object event -eq 'GENERATED_TRANSPORT_DROP')
$fatalTransportDrops = @($transportDrops |
    Where-Object reason -ne 'ring_full')
$executePrecursors = @($records | Where-Object event -eq 'EXECUTE_PRECURSOR')
$frameTokens = @($records | Where-Object event -eq 'FRAME_TOKEN')
$setConstants = @($records | Where-Object event -eq 'SET_CONSTANTS')

if ($probe.Count -ne 1 -or $target.Count -ne 1 -or
        $nativeTarget.Count -ne 1 -or $begins.Count -eq 0 -or
        $nativeBegins.Count -eq 0) {
    throw 'Streamline probe log is incomplete.'
}

$threads = @($begins.thread | Sort-Object -Unique)
$swapchains = @($begins.swapchain | Sort-Object -Unique)
$identities = @($begins.identity | Sort-Object -Unique)
$presentDurations = @()
$nativePresentDurations = @()
$endByFrame = @{}
foreach ($record in $ends) {
    $endByFrame[$record.frame] = $record
}
foreach ($begin in $begins) {
    if ($endByFrame.ContainsKey($begin.frame)) {
        $presentDurations +=
            ([double]$endByFrame[$begin.frame].qpc - [double]$begin.qpc) *
            1000.0 / [Diagnostics.Stopwatch]::Frequency
    }
}
$nativeEndByCall = @{}
foreach ($record in $nativeEnds) {
    $nativeEndByCall[$record.call] = $record
}
foreach ($begin in $nativeBegins) {
    if ($nativeEndByCall.ContainsKey($begin.call)) {
        $nativePresentDurations +=
            ([double]$nativeEndByCall[$begin.call].qpc - [double]$begin.qpc) *
            1000.0 / [Diagnostics.Stopwatch]::Frequency
    }
}
$readySamples = @($begins | Where-Object {
        $_.ready_fence -ne '0000000000000000'
    })
$readyLagMax = if ($readySamples.Count -gt 0) {
    ($readySamples | ForEach-Object {
            [long]$_.ready_value - [long]$_.ready_completed
        } | Measure-Object -Maximum).Maximum
}
else {
    0
}

Write-Output "probe.mode=$($probe[0].mode)"
Write-Output "probe.dlssg_state_query=$($probe[0].dlssg_state_query)"
$copyProbe = if ($probe[0].PSObject.Properties['copy_probe']) {
    $probe[0].copy_probe
}
else {
    '0'
}
Write-Output "probe.copy_probe=$copyProbe"
$transportProbe = if ($probe[0].PSObject.Properties['transport_probe']) {
    $probe[0].transport_probe
}
else {
    '0'
}
Write-Output "probe.transport_probe=$transportProbe"
Write-Output "present.target_path=$($target[0].path)"
Write-Output "present.target_version=$($target[0].version)"
Write-Output "native_present.target_path=$($nativeTarget[0].path)"
Write-Output "native_present.target_version=$($nativeTarget[0].version)"
foreach ($module in $modules | Where-Object loaded -eq '1') {
    Write-Output "module.$($module.name).version=$($module.version)"
    Write-Output "module.$($module.name).path=$($module.path)"
}
Write-Output "present.samples=$($begins.Count)"
Write-Output "present.thread_count=$($threads.Count)"
Write-Output "present.swapchain_count=$($swapchains.Count)"
Write-Output "present.identity_count=$($identities.Count)"
Write-Output "present.ready_samples=$($readySamples.Count)"
Write-Output "present.ready_lag_max=$readyLagMax"
Write-Output "native_present.samples=$($nativeBegins.Count)"
Write-Output "native_present.thread_count=$(@($nativeBegins.thread | Sort-Object -Unique).Count)"
Write-Output "native_present.swapchain_count=$(@($nativeBegins.swapchain | Sort-Object -Unique).Count)"
Write-Output "native_present.back_buffer_count=$(@($nativeBegins.back_buffer | Where-Object { $_ -ne '0000000000000000' } | Sort-Object -Unique).Count)"
$asynchronousNativeSamples = @($nativeBegins | Where-Object {
        if ($_.PSObject.Properties['class']) {
            $_.class -eq 'asynchronous'
        }
        else {
            $_.thread -ne $threads[0]
        }
    })
Write-Output "native_present.asynchronous_samples=$($asynchronousNativeSamples.Count)"
if ($asynchronousNativeSamples.Count -gt 0) {
    Write-Output "native_present.first_asynchronous_call=$($asynchronousNativeSamples[0].call)"
    Write-Output "native_present.first_asynchronous_outer_frame=$($asynchronousNativeSamples[0].outer_frame)"
    if ($asynchronousNativeSamples[0].PSObject.Properties['class']) {
        $burstEndCall = [uint64]$asynchronousNativeSamples[0].call + 239
        $burstSamples = @($nativeBegins | Where-Object {
                [uint64]$_.call -ge [uint64]$asynchronousNativeSamples[0].call -and
                [uint64]$_.call -le $burstEndCall
            })
        $burstAsync = @($burstSamples |
            Where-Object class -eq 'asynchronous')
        $burstOuter = @($burstSamples |
            Where-Object class -eq 'outer_thread')
        $burstGenerated = @($burstSamples | Where-Object {
                if ($_.PSObject.Properties['generated_candidate']) {
                    $_.generated_candidate -eq '1'
                }
                else {
                    $_.thread -eq $_.last_execute_thread -and
                    [uint32]$_.last_execute_queue_type -eq 0 -and
                    [uint32]$_.last_execute_list_count -eq 1 -and
                    [long]$_.last_execute_delta_us -ge 0 -and
                    [long]$_.last_execute_delta_us -le 500
                }
            })
        $burstSource = @($burstSamples | Where-Object {
                $_ -notin $burstGenerated
            })
        $activeAsync = @($burstAsync | Where-Object {
                [uint64]$_.active_outer_frame -ne 0
            })
        $pairedFrames = @($burstSamples | Group-Object outer_frame |
            Where-Object {
                @($_.Group |
                    Where-Object class -eq 'asynchronous').Count -eq 1 -and
                @($_.Group |
                    Where-Object class -eq 'outer_thread').Count -eq 1
            })
        Write-Output "native_present.burst_samples=$($burstSamples.Count)"
        Write-Output "native_present.burst_asynchronous_samples=$($burstAsync.Count)"
        Write-Output "native_present.burst_outer_thread_samples=$($burstOuter.Count)"
        Write-Output "native_present.burst_generated_candidates=$($burstGenerated.Count)"
        Write-Output "native_present.burst_source_candidates=$($burstSource.Count)"
        if ($burstGenerated.Count -gt 0) {
            $generatedDelta = @($burstGenerated | ForEach-Object {
                    if ($_.PSObject.Properties['generator_execute_delta_us']) {
                        [double]$_.generator_execute_delta_us
                    }
                    else {
                        [double]$_.last_execute_delta_us
                    }
                }) | Measure-Object -Average -Minimum -Maximum
            $generatedQueues = @(if ($burstGenerated[0].PSObject.Properties[
                        'generator_queue']) {
                    $burstGenerated.generator_queue | Sort-Object -Unique
                }
                else {
                    $burstGenerated.last_execute_queue | Sort-Object -Unique
                })
            Write-Output "native_present.burst_generated_queue_count=$($generatedQueues.Count)"
            Write-Output ('native_present.burst_generated_delta_us_average={0:F2}' -f $generatedDelta.Average)
            Write-Output ('native_present.burst_generated_delta_us_min={0:F2}' -f $generatedDelta.Minimum)
            Write-Output ('native_present.burst_generated_delta_us_max={0:F2}' -f $generatedDelta.Maximum)
        }
        Write-Output "native_present.burst_async_active_outer_samples=$($activeAsync.Count)"
        Write-Output "native_present.burst_one_to_one_outer_frames=$($pairedFrames.Count)"
    }
    $sameThreadExecuteSamples = @($asynchronousNativeSamples | Where-Object {
            $_.last_execute_thread -eq $_.thread
        })
    Write-Output "native_present.asynchronous_last_execute_same_thread=$($sameThreadExecuteSamples.Count)"
    if ($sameThreadExecuteSamples.Count -gt 0) {
        Write-Output "native_present.same_thread_execute_queue_count=$(@($sameThreadExecuteSamples.last_execute_queue | Sort-Object -Unique).Count)"
        Write-Output "native_present.same_thread_execute_queue_types=$(($sameThreadExecuteSamples.last_execute_queue_type | Sort-Object -Unique) -join ',')"
        $executeDeltas = @($sameThreadExecuteSamples | ForEach-Object {
                [double]$_.last_execute_delta_us
            })
        $executeDelta = $executeDeltas | Measure-Object -Average -Maximum
        Write-Output ('native_present.same_thread_execute_delta_us_average={0:F2}' -f $executeDelta.Average)
        Write-Output ('native_present.same_thread_execute_delta_us_max={0:F2}' -f $executeDelta.Maximum)
    }
}
$lastOuterSample = $ends | Select-Object -Last 1
if ($null -ne $lastOuterSample.native_present_count) {
    Write-Output "native_present.count_at_last_outer_sample=$($lastOuterSample.native_present_count)"
    Write-Output "native_present.last_outer_frame=$($lastOuterSample.frame)"
    Write-Output ('native_present.per_outer_at_last_sample={0:F4}' -f
        ([double]$lastOuterSample.native_present_count /
            [double]$lastOuterSample.frame))
    Write-Output "native_present.surplus_at_last_outer_sample=$([long]$lastOuterSample.native_present_count - [long]$lastOuterSample.frame)"
}
Write-Output "dlssg.state_samples=$($stateCalls.Count)"
Write-Output "frame_token.samples=$($frameTokens.Count)"
if ($frameTokens.Count -gt 0) {
    Write-Output "frame_token.result_values=$(($frameTokens.result | Sort-Object -Unique) -join ',')"
    Write-Output "frame_token.pointer_count=$(@($frameTokens.token | Sort-Object -Unique).Count)"
    Write-Output "frame_token.requested_index_values=$(@($frameTokens.requested_index | Sort-Object -Unique).Count)"
}
Write-Output "set_constants.samples=$($setConstants.Count)"
if ($setConstants.Count -gt 0) {
    Write-Output "set_constants.result_values=$(($setConstants.result | Sort-Object -Unique) -join ',')"
    Write-Output "set_constants.token_count=$(@($setConstants.token | Sort-Object -Unique).Count)"
    Write-Output "set_constants.viewport_count=$(@($setConstants.viewport | Sort-Object -Unique).Count)"
}
if ($stateCalls.Count -gt 0) {
    Write-Output "dlssg.state_thread_count=$(@($stateCalls.thread | Sort-Object -Unique).Count)"
    Write-Output "dlssg.state_result_count=$(@($stateCalls.result | Sort-Object -Unique).Count)"
    Write-Output "dlssg.state_version_count=$(@($stateCalls.state_version | Sort-Object -Unique).Count)"
    Write-Output "dlssg.frames_presented_values=$(($stateCalls.frames_presented | Sort-Object -Unique) -join ',')"
    Write-Output "dlssg.frames_to_generate_max_values=$(($stateCalls.frames_to_generate_max | Sort-Object -Unique) -join ',')"
    Write-Output "dlssg.status_values=$(($stateCalls.status | Sort-Object -Unique) -join ',')"
}
Write-Output "dlssg.options_samples=$($optionCalls.Count)"
if ($optionCalls.Count -gt 0) {
    Write-Output "dlssg.option_thread_count=$(@($optionCalls.thread | Sort-Object -Unique).Count)"
    Write-Output "dlssg.option_modes=$(($optionCalls.mode | Sort-Object -Unique) -join ',')"
    Write-Output "dlssg.option_generation_counts=$(($optionCalls.frames_to_generate | Sort-Object -Unique) -join ',')"
    Write-Output "dlssg.option_results=$(($optionCalls.result | Sort-Object -Unique) -join ',')"
    Write-Output "dlssg.option_viewports=$(($optionCalls.viewport | Sort-Object -Unique) -join ',')"
    foreach ($mode in @($optionCalls.mode | Sort-Object -Unique)) {
        $modeCalls = @($optionCalls | Where-Object mode -eq $mode)
        $firstModeCall = $modeCalls | Select-Object -First 1
        $lastModeCall = $modeCalls | Select-Object -Last 1
        Write-Output "dlssg.mode_${mode}.first_call=$($firstModeCall.call)"
        Write-Output "dlssg.mode_${mode}.first_present=$($firstModeCall.present_frame)"
        Write-Output "dlssg.mode_${mode}.last_call=$($lastModeCall.call)"
        Write-Output "dlssg.mode_${mode}.last_present=$($lastModeCall.present_frame)"
    }
}
if ($presentDurations.Count -gt 0) {
    $duration = $presentDurations | Measure-Object -Average -Maximum
    Write-Output ('present.duration_ms_average={0:F4}' -f $duration.Average)
    Write-Output ('present.duration_ms_max={0:F4}' -f $duration.Maximum)
}
if ($nativePresentDurations.Count -gt 0) {
    $nativeDuration = $nativePresentDurations | Measure-Object -Average -Maximum
    Write-Output ('native_present.duration_ms_average={0:F4}' -f $nativeDuration.Average)
    Write-Output ('native_present.duration_ms_max={0:F4}' -f $nativeDuration.Maximum)
}
Write-Output "generated_copy.schedule_samples=$($copySchedules.Count)"
Write-Output "generated_copy.completion_samples=$($copyCompletions.Count)"
Write-Output "generated_transport.submit_samples=$($transportSubmits.Count)"
Write-Output "generated_transport.completion_samples=$($transportCompletions.Count)"
Write-Output "generated_transport.drop_samples=$($transportDrops.Count)"
Write-Output "generated_transport.fatal_drop_samples=$($fatalTransportDrops.Count)"
if ($transportSubmits.Count -gt 0) {
    Write-Output "generated_transport.slot_count=$(@($transportSubmits.slot | Sort-Object -Unique).Count)"
    Write-Output "generated_transport.sequence_count=$(@($transportSubmits.sequence | Sort-Object -Unique).Count)"
    Write-Output "generated_transport.frame_index_count=$(@($transportSubmits.frame_index | Sort-Object -Unique).Count)"
    Write-Output "generated_transport.extents=$(($transportSubmits | ForEach-Object { "$($_.width)x$($_.height)" } | Sort-Object -Unique) -join ',')"
    Write-Output "generated_transport.formats=$(($transportSubmits.format | Sort-Object -Unique) -join ',')"
}
Write-Output "execute_precursor.samples=$($executePrecursors.Count)"
if ($executePrecursors.Count -gt 0) {
    Write-Output "execute_precursor.native_call_count=$(@($executePrecursors.native_call | Sort-Object -Unique).Count)"
    Write-Output "execute_precursor.queue_count=$(@($executePrecursors.queue | Sort-Object -Unique).Count)"
    Write-Output "execute_precursor.queue_types=$(($executePrecursors.queue_type | Sort-Object -Unique) -join ',')"
    $presentTransitionPrecursors = @($executePrecursors | Where-Object {
            $_.present_transition -eq '1'
        })
    Write-Output "execute_precursor.present_transition_samples=$($presentTransitionPrecursors.Count)"
    if ($presentTransitionPrecursors.Count -gt 0) {
        Write-Output "execute_precursor.present_transition_native_call_count=$(@($presentTransitionPrecursors.native_call | Sort-Object -Unique).Count)"
        Write-Output "execute_precursor.present_transition_queue_count=$(@($presentTransitionPrecursors.queue | Sort-Object -Unique).Count)"
    }
}
if ($copyCompletions.Count -gt 0) {
    $copy = $copyCompletions | Select-Object -Last 1
    Write-Output "generated_copy.result=$($copy.result)"
    if ($copy.result -eq 'success') {
        Write-Output "generated_copy.native_call=$($copy.native_call)"
        Write-Output "generated_copy.outer_frame=$($copy.outer_frame)"
        Write-Output "generated_copy.hash=$($copy.hash)"
        Write-Output "generated_copy.nonzero_bytes=$($copy.nonzero_bytes)"
        Write-Output "generated_copy.byte_range=$($copy.min_byte),$($copy.max_byte)"
    }
}
if ($copyProbe -eq '1' -and
        ($copyCompletions.Count -ne 1 -or
            $copyCompletions[0].result -ne 'success')) {
    throw 'The requested generated-backbuffer copy did not complete successfully.'
}
if ($transportProbe -eq '1' -and
        ($transportSubmits.Count -ne 120 -or
            $transportCompletions.Count -ne $transportSubmits.Count -or
            $fatalTransportDrops.Count -ne 0 -or
            @($transportSubmits.sequence | Sort-Object -Unique).Count -ne
                $transportSubmits.Count -or
            [uint64]$transportSubmits[0].sequence -ne 1 -or
            [uint64]$transportSubmits[-1].sequence -ne
                [uint64]$transportSubmits.Count -or
            @($transportSubmits.slot | Sort-Object -Unique).Count -gt 3)) {
    throw 'The bounded generated-output transport did not complete cleanly.'
}
Write-Output 'result=pass'
