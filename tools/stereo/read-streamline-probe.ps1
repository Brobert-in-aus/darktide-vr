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
$executePrecursors = @($records | Where-Object event -eq 'EXECUTE_PRECURSOR')

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
        $_.thread -ne $threads[0]
    })
Write-Output "native_present.asynchronous_samples=$($asynchronousNativeSamples.Count)"
if ($asynchronousNativeSamples.Count -gt 0) {
    Write-Output "native_present.first_asynchronous_call=$($asynchronousNativeSamples[0].call)"
    Write-Output "native_present.first_asynchronous_outer_frame=$($asynchronousNativeSamples[0].outer_frame)"
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
Write-Output 'result=pass'
