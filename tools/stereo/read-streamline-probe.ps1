[CmdletBinding()]
param(
    [string] $Path = (Join-Path $env:TEMP 'darktidevr-streamline-probe.tsv')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'get-streamline-stereo-input-readiness.ps1')

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

function ConvertFrom-ProbeVector3 {
    param([Parameter(Mandatory)][string] $Value)

    $parts = @($Value -split ',')
    if ($parts.Count -ne 3) {
        throw "Expected a three-component probe vector, got: $Value"
    }
    @([double]$parts[0], [double]$parts[1], [double]$parts[2])
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
$setConstantMatrices = @($records |
    Where-Object event -eq 'SET_CONSTANTS_MATRIX')
$resourceTags = @($records | Where-Object event -eq 'RESOURCE_TAG')
$resourceTagCalls = @($records | Where-Object event -eq 'RESOURCE_TAG_CALL')
$eyeOutputBoundaries = @($records |
    Where-Object event -eq 'EYE_OUTPUT_BOUNDARY')
$inputSnapshots = @($records | Where-Object event -eq 'INPUT_SNAPSHOT')
$inputSnapshotResources = @($records |
    Where-Object event -eq 'INPUT_SNAPSHOT_RESOURCE')
$inputSnapshotBindings = @($records |
    Where-Object event -eq 'INPUT_SNAPSHOT_BINDING')
$inputSnapshotReadbacks = @($records |
    Where-Object event -eq 'INPUT_SNAPSHOT_READBACK')
$inputSnapshotSamples = @($records |
    Where-Object event -eq 'INPUT_SNAPSHOT_SAMPLE')
$stereoBackbuffers = @($records | Where-Object event -eq 'STEREO_BACKBUFFER')
$stereoTransportReservations = @($records |
    Where-Object event -eq 'STEREO_TRANSPORT_RESERVATION')
$stereoTargetTokens = @($records | Where-Object event -eq 'STEREO_TARGET_TOKEN')
$stereoPresentTargets = @($records |
    Where-Object event -eq 'STEREO_PRESENT_TARGET')
$stereoPresentStages = @($records |
    Where-Object event -eq 'STEREO_PRESENT_STAGE')
$generatedBackbufferExtents = @()
$generatedBackbufferFormats = @()

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
$inputSnapshotProbe = if (
        $probe[0].PSObject.Properties['input_snapshot_probe']) {
    $probe[0].input_snapshot_probe
}
else {
    '0'
}
Write-Output "probe.input_snapshot_probe=$inputSnapshotProbe"
$targetTokenProbe = if ($probe[0].PSObject.Properties['target_token_probe']) {
    $probe[0].target_token_probe
}
else {
    '0'
}
Write-Output "probe.target_token_probe=$targetTokenProbe"
$stereoSwapchainProbe = if (
        $probe[0].PSObject.Properties['stereo_swapchain_probe']) {
    $probe[0].stereo_swapchain_probe
}
else {
    '0'
}
Write-Output "probe.stereo_swapchain_probe=$stereoSwapchainProbe"
$stereoStageProbe = if (
        $probe[0].PSObject.Properties['stereo_stage_probe']) {
    $probe[0].stereo_stage_probe
}
else {
    '0'
}
Write-Output "probe.stereo_stage_probe=$stereoStageProbe"
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
            $generatedBackbufferExtents = @($burstGenerated | ForEach-Object {
                    "$($_.width)x$($_.height)"
                } | Sort-Object -Unique)
            $generatedBackbufferFormats = @($burstGenerated.format |
                Sort-Object -Unique)
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
            Write-Output "native_present.burst_generated_extents=$($generatedBackbufferExtents -join ',')"
            Write-Output "native_present.burst_generated_formats=$($generatedBackbufferFormats -join ',')"
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
Write-Output "set_constants.matrix_samples=$($setConstantMatrices.Count)"
if ($setConstants.Count -gt 0) {
    Write-Output "set_constants.result_values=$(($setConstants.result | Sort-Object -Unique) -join ',')"
    Write-Output "set_constants.token_count=$(@($setConstants.token | Sort-Object -Unique).Count)"
    Write-Output "set_constants.viewport_count=$(@($setConstants.viewport | Sort-Object -Unique).Count)"
    $eyeConstants = @($setConstants | Where-Object {
            $_.PSObject.Properties['armed_eye'] -and
            $_.armed_eye -in @('0', '1')
        })
    Write-Output "set_constants.eye_labeled_samples=$($eyeConstants.Count)"
    foreach ($eye in 0..1) {
        $samples = @($eyeConstants | Where-Object armed_eye -eq "$eye")
        Write-Output "set_constants.eye${eye}.samples=$($samples.Count)"
        if ($samples.Count -gt 0) {
            Write-Output "set_constants.eye${eye}.viewports=$(($samples.viewport | Sort-Object -Unique) -join ',')"
            Write-Output "set_constants.eye${eye}.token_count=$(@($samples.token | Sort-Object -Unique).Count)"
            Write-Output "set_constants.eye${eye}.versions=$(($samples.version | Sort-Object -Unique) -join ',')"
            Write-Output "set_constants.eye${eye}.mvec_scales=$(($samples.mvec_scale | Sort-Object -Unique) -join ';')"
            Write-Output "set_constants.eye${eye}.depth_inverted=$(($samples.depth_inverted | Sort-Object -Unique) -join ',')"
            Write-Output "set_constants.eye${eye}.camera_motion_included=$(($samples.camera_motion_included | Sort-Object -Unique) -join ',')"
            Write-Output "set_constants.eye${eye}.mvec_3d=$(($samples.mvec_3d | Sort-Object -Unique) -join ',')"
            Write-Output "set_constants.eye${eye}.mvec_dilated=$(($samples.mvec_dilated | Sort-Object -Unique) -join ',')"
            Write-Output "set_constants.eye${eye}.mvec_jittered=$(($samples.mvec_jittered | Sort-Object -Unique) -join ',')"
            Write-Output "set_constants.eye${eye}.fov_values=$(($samples.fov | Sort-Object -Unique) -join ',')"
            Write-Output "set_constants.eye${eye}.aspect_values=$(($samples.aspect | Sort-Object -Unique) -join ',')"
        }
    }
    $pairedConstantFrames = @($eyeConstants | Where-Object {
            $_.PSObject.Properties['frame_index'] -and
            $_.frame_index -ne '4294967295'
        } | Group-Object frame_index |
        Where-Object {
            @($_.Group | Where-Object armed_eye -eq '0').Count -gt 0 -and
            @($_.Group | Where-Object armed_eye -eq '1').Count -gt 0
        })
    $sameTokenPairs = 0
    $sameJitterPairs = 0
    $eyeSeparations = @()
    foreach ($pair in $pairedConstantFrames) {
        $eye0 = $pair.Group | Where-Object armed_eye -eq '0' |
            Select-Object -Last 1
        $eye1 = $pair.Group | Where-Object armed_eye -eq '1' |
            Select-Object -Last 1
        if ($eye0.token -eq $eye1.token) {
            ++$sameTokenPairs
        }
        if ($eye0.jitter -eq $eye1.jitter) {
            ++$sameJitterPairs
        }
        $eye0Position = ConvertFrom-ProbeVector3 $eye0.camera_pos
        $eye1Position = ConvertFrom-ProbeVector3 $eye1.camera_pos
        $deltaX = $eye0Position[0] - $eye1Position[0]
        $deltaY = $eye0Position[1] - $eye1Position[1]
        $deltaZ = $eye0Position[2] - $eye1Position[2]
        $eyeSeparations += [Math]::Sqrt(
            $deltaX * $deltaX + $deltaY * $deltaY + $deltaZ * $deltaZ)
    }
    Write-Output "set_constants.paired_frame_count=$($pairedConstantFrames.Count)"
    Write-Output "set_constants.paired_same_token_count=$sameTokenPairs"
    Write-Output "set_constants.paired_same_jitter_count=$sameJitterPairs"
    if ($eyeSeparations.Count -gt 0) {
        $separation = $eyeSeparations | Measure-Object -Average -Minimum -Maximum
        Write-Output ('set_constants.eye_separation_average={0:F8}' -f $separation.Average)
        Write-Output ('set_constants.eye_separation_min={0:F8}' -f $separation.Minimum)
        Write-Output ('set_constants.eye_separation_max={0:F8}' -f $separation.Maximum)
    }
}
if ($setConstantMatrices.Count -gt 0) {
    Write-Output "set_constants.matrix_names=$(($setConstantMatrices.name | Sort-Object -Unique) -join ',')"
    foreach ($eye in 0..1) {
        $eyeMatrices = @($setConstantMatrices |
            Where-Object armed_eye -eq "$eye")
        Write-Output "set_constants.eye${eye}.matrix_samples=$($eyeMatrices.Count)"
        foreach ($name in @($eyeMatrices | ForEach-Object { $_.name } |
                Sort-Object -Unique)) {
            $namedMatrices = @($eyeMatrices | Where-Object name -eq $name)
            Write-Output "set_constants.eye${eye}.${name}.distinct_values=$(@($namedMatrices.values | Sort-Object -Unique).Count)"
        }
    }
}
Write-Output "resource_tag.samples=$($resourceTags.Count)"
Write-Output "resource_tag.empty_calls=$($resourceTagCalls.Count)"
$eye0Tags = @()
$eye1Tags = @()
if ($resourceTags.Count -gt 0) {
    Write-Output "resource_tag.apis=$(($resourceTags.api | Sort-Object -Unique) -join ',')"
    Write-Output "resource_tag.viewports=$(($resourceTags.viewport | Sort-Object -Unique) -join ',')"
    Write-Output "resource_tag.armed_eyes=$(($resourceTags.armed_eye | Sort-Object -Unique) -join ',')"
    foreach ($viewport in @($resourceTags.viewport | Sort-Object -Unique)) {
        $viewportTags = @($resourceTags | Where-Object viewport -eq $viewport)
        Write-Output "resource_tag.viewport_${viewport}.samples=$($viewportTags.Count)"
        Write-Output "resource_tag.viewport_${viewport}.armed_eyes=$(($viewportTags.armed_eye | Sort-Object -Unique) -join ',')"
        Write-Output "resource_tag.viewport_${viewport}.types=$(($viewportTags.type_name | Sort-Object -Unique) -join ',')"
    }
    $eye0Tags = @($resourceTags | Where-Object armed_eye -eq '0')
    $eye1Tags = @($resourceTags | Where-Object armed_eye -eq '1')
    foreach ($typeName in @(($eye0Tags + $eye1Tags) |
            ForEach-Object { $_.type_name } | Sort-Object -Unique)) {
        $eye0Native = @($eye0Tags | Where-Object type_name -eq $typeName |
            Select-Object -ExpandProperty native -Unique)
        $eye1Native = @($eye1Tags | Where-Object type_name -eq $typeName |
            Select-Object -ExpandProperty native -Unique)
        $sharedNative = @($eye0Native | Where-Object { $eye1Native -contains $_ })
        Write-Output "resource_tag.${typeName}.eye0_native_count=$($eye0Native.Count)"
        Write-Output "resource_tag.${typeName}.eye1_native_count=$($eye1Native.Count)"
        Write-Output "resource_tag.${typeName}.shared_native_count=$($sharedNative.Count)"
    }
    foreach ($group in @($resourceTags | Group-Object type_name | Sort-Object Name)) {
        $prefix = "resource_tag.$($group.Name)"
        Write-Output "$prefix.samples=$($group.Count)"
        Write-Output "$prefix.native_count=$(@($group.Group.native | Sort-Object -Unique).Count)"
        Write-Output "$prefix.extents=$(($group.Group.extent | Sort-Object -Unique) -join ';')"
        Write-Output "$prefix.formats=$(($group.Group.d3d12_format | Sort-Object -Unique) -join ',')"
        Write-Output "$prefix.lifecycle=$(($group.Group.lifecycle | Sort-Object -Unique) -join ',')"
        Write-Output "$prefix.frame_count=$(@($group.Group.frame | Sort-Object -Unique).Count)"
    }
}
$stereoReadiness = Get-StreamlineStereoInputReadiness -ResourceTags $resourceTags
Write-Output "resource_tag.stereo_required_types=$($stereoReadiness.RequiredTypes -join ',')"
Write-Output "resource_tag.stereo_missing_eye0_types=$($stereoReadiness.MissingEye0Types -join ',')"
Write-Output "resource_tag.stereo_missing_eye1_types=$($stereoReadiness.MissingEye1Types -join ',')"
Write-Output "resource_tag.stereo_aliased_types=$($stereoReadiness.AliasedTypes -join ',')"
Write-Output "resource_tag.stereo_input_ready=$([int]$stereoReadiness.Ready)"
Write-Output "resource_tag.stereo_input_blockers=$($stereoReadiness.Blockers -join ',')"
$nativeFrameLabeledResourceTags = @($resourceTags | Where-Object {
        $_.PSObject.Properties['frame_index'] -and
        $_.frame_index -ne '4294967295' -and
        $_.armed_eye -in @('0', '1')
    })
Write-Output "resource_tag.native_frame_labeled_samples=$($nativeFrameLabeledResourceTags.Count)"
$constantsByEyeViewportPose = @{}
foreach ($constant in @($setConstants | Where-Object {
            $_.PSObject.Properties['frame_index'] -and
            $_.frame_index -ne '4294967295' -and
            $_.armed_eye -in @('0', '1')
        })) {
    $key = "$($constant.armed_eye)|$($constant.viewport)|$($constant.armed_pose)"
    if (-not $constantsByEyeViewportPose.ContainsKey($key)) {
        $constantsByEyeViewportPose[$key] = @()
    }
    $constantsByEyeViewportPose[$key] += $constant
}
$resolvedResourceTags = @()
$nativeOfflineComparable = 0
$nativeOfflineAgreement = 0
foreach ($tag in @($resourceTags | Where-Object {
            $_.armed_eye -in @('0', '1')
        })) {
    $resolvedFrame = $null
    $resolvedConstantsCall = $null
    $resolutionSource = $null
    $resolutionDeltaUs = $null
    $key = "$($tag.armed_eye)|$($tag.viewport)|$($tag.armed_pose)"
    if ($constantsByEyeViewportPose.ContainsKey($key)) {
        $nearest = $constantsByEyeViewportPose[$key] | Sort-Object @{
            Expression = { [Math]::Abs([double]$_.qpc - [double]$tag.qpc) }
        } | Select-Object -First 1
        $resolvedFrame = $nearest.frame_index
        $resolvedConstantsCall = $nearest.call
        $resolutionSource = 'offline_nearest'
        $resolutionDeltaUs = [Math]::Abs(
            ([double]$nearest.qpc - [double]$tag.qpc) * 1000000.0 /
                [Diagnostics.Stopwatch]::Frequency)
        if ($tag.PSObject.Properties['frame_index'] -and
                $tag.frame_index -ne '4294967295') {
            ++$nativeOfflineComparable
            if ($tag.frame_index -eq $nearest.frame_index) {
                ++$nativeOfflineAgreement
            }
        }
    }
    elseif ($tag.PSObject.Properties['frame_index'] -and
            $tag.frame_index -ne '4294967295') {
        $resolvedFrame = $tag.frame_index
        $resolvedConstantsCall = $tag.constants_call
        $resolutionSource = 'native_forward_fallback'
        $resolutionDeltaUs = 0.0
    }
    if ($null -ne $resolvedFrame) {
        $resolvedResourceTags += $tag | Select-Object *,
            @{ Name = 'resolved_frame_index'; Expression = { $resolvedFrame } },
            @{ Name = 'resolved_constants_call'; Expression = { $resolvedConstantsCall } },
            @{ Name = 'resolution_source'; Expression = { $resolutionSource } },
            @{ Name = 'resolution_delta_us'; Expression = { $resolutionDeltaUs } }
    }
}
Write-Output "resource_tag.resolved_frame_labeled_samples=$($resolvedResourceTags.Count)"
Write-Output "resource_tag.offline_resolved_samples=$(@($resolvedResourceTags | Where-Object resolution_source -eq 'offline_nearest').Count)"
Write-Output "resource_tag.native_offline_comparable_samples=$nativeOfflineComparable"
Write-Output "resource_tag.native_offline_agreement_samples=$nativeOfflineAgreement"
if ($resolvedResourceTags.Count -gt 0) {
    Write-Output "resource_tag.frame_constants_call_count=$(@($resolvedResourceTags.resolved_constants_call | Sort-Object -Unique).Count)"
    $offlineResolutionDeltas = @($resolvedResourceTags |
        Where-Object resolution_source -eq 'offline_nearest' |
        Select-Object -ExpandProperty resolution_delta_us)
    if ($offlineResolutionDeltas.Count -gt 0) {
        $resolutionDelta = $offlineResolutionDeltas |
            Measure-Object -Average -Maximum
        Write-Output ('resource_tag.offline_resolution_delta_us_average={0:F2}' -f $resolutionDelta.Average)
        Write-Output ('resource_tag.offline_resolution_delta_us_max={0:F2}' -f $resolutionDelta.Maximum)
    }
    foreach ($typeName in $stereoReadiness.RequiredTypes) {
        $typeFrames = @($resolvedResourceTags |
            Where-Object type_name -eq $typeName |
            Group-Object resolved_frame_index)
        $pairedFrames = @($typeFrames | Where-Object {
                @($_.Group | Where-Object armed_eye -eq '0').Count -gt 0 -and
                @($_.Group | Where-Object armed_eye -eq '1').Count -gt 0
            })
        $aliasedFrames = @($pairedFrames | Where-Object {
                $eye0Native = @($_.Group |
                    Where-Object armed_eye -eq '0' |
                    Select-Object -ExpandProperty native -Unique)
                $eye1Native = @($_.Group |
                    Where-Object armed_eye -eq '1' |
                    Select-Object -ExpandProperty native -Unique)
                @($eye0Native | Where-Object { $eye1Native -contains $_ }).Count -gt 0
            })
        Write-Output "resource_tag.${typeName}.paired_frame_count=$($pairedFrames.Count)"
        Write-Output "resource_tag.${typeName}.aliased_frame_count=$($aliasedFrames.Count)"
    }
}
Write-Output "resource_tag.ui_color_alpha.samples=$(@($resourceTags |
        Where-Object type_name -eq 'ui_color_alpha').Count)"
Write-Output "eye_output_boundary.samples=$($eyeOutputBoundaries.Count)"
if ($eyeOutputBoundaries.Count -gt 0) {
    foreach ($phase in @($eyeOutputBoundaries.phase | Sort-Object -Unique)) {
        Write-Output "eye_output_boundary.${phase}.samples=$(@($eyeOutputBoundaries | Where-Object phase -eq $phase).Count)"
    }
    $executeBegins = @($eyeOutputBoundaries |
        Where-Object phase -eq 'execute_begin')
    foreach ($typeName in $stereoReadiness.RequiredTypes) {
        $deltas = @()
        foreach ($tag in @($resourceTags | Where-Object {
                    $_.armed_eye -in @('0', '1') -and
                    $_.type_name -eq $typeName
                })) {
            $candidates = @($executeBegins | Where-Object {
                    $_.eye -eq $tag.armed_eye -and
                    $_.pose -eq $tag.armed_pose -and
                    $_.present_frame -eq $tag.present_frame
                })
            if ($candidates.Count -eq 0) {
                continue
            }
            $nearest = $candidates | Sort-Object @{
                Expression = { [Math]::Abs([double]$_.qpc - [double]$tag.qpc) }
            } | Select-Object -First 1
            $deltas += ([double]$tag.qpc - [double]$nearest.qpc) *
                1000000.0 / [Diagnostics.Stopwatch]::Frequency
        }
        Write-Output "eye_output_boundary.${typeName}.matched_samples=$($deltas.Count)"
        if ($deltas.Count -gt 0) {
            $delta = $deltas | Measure-Object -Average -Minimum -Maximum
            Write-Output ('eye_output_boundary.{0}.tag_delta_us_average={1:F2}' -f $typeName, $delta.Average)
            Write-Output ('eye_output_boundary.{0}.tag_delta_us_min={1:F2}' -f $typeName, $delta.Minimum)
            Write-Output ('eye_output_boundary.{0}.tag_delta_us_max={1:F2}' -f $typeName, $delta.Maximum)
        }
    }
}
Write-Output "input_snapshot.samples=$($inputSnapshots.Count)"
Write-Output "input_snapshot.resource_samples=$($inputSnapshotResources.Count)"
if ($inputSnapshots.Count -gt 0) {
    foreach ($phase in @($inputSnapshots.phase | Sort-Object -Unique)) {
        Write-Output "input_snapshot.${phase}.samples=$(@($inputSnapshots |
                Where-Object phase -eq $phase).Count)"
    }
    $inputSnapshotComplete = @($inputSnapshots |
        Where-Object phase -eq 'complete' | Select-Object -Last 1)
    if ($inputSnapshotComplete.Count -eq 1) {
        Write-Output "input_snapshot.source_alias_mask=$($inputSnapshotComplete[0].source_alias_mask)"
        Write-Output "input_snapshot.snapshot_alias_mask=$($inputSnapshotComplete[0].snapshot_alias_mask)"
        Write-Output "input_snapshot.snapshot_unique_count=$($inputSnapshotComplete[0].snapshot_unique_count)"
        Write-Output "input_snapshot.policy_status=$($inputSnapshotComplete[0].policy_status)"
        Write-Output "input_snapshot.policy_aliased_mask=$($inputSnapshotComplete[0].policy_aliased_mask)"
        Write-Output "input_snapshot.ready=$($inputSnapshotComplete[0].snapshot_ready)"
        Write-Output "input_snapshot.fence_value=$($inputSnapshotComplete[0].fence_value)"
    }
}
Write-Output "input_snapshot.readback_samples=$($inputSnapshotReadbacks.Count)"
Write-Output "input_snapshot.content_samples=$($inputSnapshotSamples.Count)"
Write-Output "input_snapshot.binding_samples=$($inputSnapshotBindings.Count)"
Write-Output "input_snapshot.stereo_backbuffer_samples=$($stereoBackbuffers.Count)"
Write-Output "input_snapshot.transport_reservation_samples=$($stereoTransportReservations.Count)"
Write-Output "input_snapshot.target_token_samples=$($stereoTargetTokens.Count)"
if ($stereoTransportReservations.Count -eq 1) {
    Write-Output "input_snapshot.transport_slot=$($stereoTransportReservations[0].slot)"
    Write-Output "input_snapshot.transport_metadata_published=$($stereoTransportReservations[0].metadata_published)"
    Write-Output "input_snapshot.transport_ready_signaled=$($stereoTransportReservations[0].ready_signaled)"
}
if ($stereoTargetTokens.Count -eq 1) {
    $targetGenerationPresentSubmitted = if (
            $stereoTargetTokens[0].PSObject.Properties[
                'generation_present_submitted']) {
        $stereoTargetTokens[0].generation_present_submitted
    }
    else {
        $stereoTargetTokens[0].evaluation_called
    }
    Write-Output "input_snapshot.target_token_phase=$($stereoTargetTokens[0].phase)"
    Write-Output "input_snapshot.target_frame_index=$($stereoTargetTokens[0].target_frame_index)"
    Write-Output "input_snapshot.target_policy_status=$($stereoTargetTokens[0].policy_status)"
    Write-Output "input_snapshot.target_generation_present_submitted=$targetGenerationPresentSubmitted"
    Write-Output "input_snapshot.target_metadata_published=$($stereoTargetTokens[0].metadata_published)"
    Write-Output "input_snapshot.target_ready_signaled=$($stereoTargetTokens[0].ready_signaled)"
}
if ($stereoBackbuffers.Count -gt 0) {
    foreach ($phase in @($stereoBackbuffers.phase | Sort-Object -Unique)) {
        Write-Output "input_snapshot.stereo_backbuffer_${phase}.samples=$(@($stereoBackbuffers |
                Where-Object phase -eq $phase).Count)"
    }
    $stereoBackbufferComplete = @($stereoBackbuffers |
        Where-Object phase -eq 'complete' | Select-Object -Last 1)
    if ($stereoBackbufferComplete.Count -eq 1) {
        $stereoPresentCompatible =
            $generatedBackbufferExtents -contains
                "$($stereoBackbufferComplete[0].width)x$($stereoBackbufferComplete[0].height)" -and
            $generatedBackbufferFormats -contains
                $stereoBackbufferComplete[0].format
        Write-Output "input_snapshot.stereo_backbuffer_extent=$($stereoBackbufferComplete[0].width)x$($stereoBackbufferComplete[0].height)"
        Write-Output "input_snapshot.stereo_backbuffer_eye_width=$($stereoBackbufferComplete[0].eye_width)"
        Write-Output "input_snapshot.stereo_backbuffer_state=$($stereoBackbufferComplete[0].state)"
        Write-Output "input_snapshot.stereo_present_compatible=$([int]$stereoPresentCompatible)"
    }
}
Write-Output "input_snapshot.present_target_samples=$($stereoPresentTargets.Count)"
if ($stereoPresentTargets.Count -gt 0) {
    Write-Output "input_snapshot.present_target_compatible=$($stereoPresentTargets[-1].compatible)"
    Write-Output "input_snapshot.present_target_extent=$($stereoPresentTargets[-1].present_extent)"
    Write-Output "input_snapshot.present_target_format=$($stereoPresentTargets[-1].present_format)"
    Write-Output "input_snapshot.present_target_copy_staged=$($stereoPresentTargets[-1].copy_staged)"
    Write-Output "input_snapshot.present_target_tags_staged=$($stereoPresentTargets[-1].tags_staged)"
}
Write-Output "input_snapshot.present_stage_samples=$($stereoPresentStages.Count)"
if ($stereoPresentStages.Count -gt 0) {
    foreach ($phase in @($stereoPresentStages |
            ForEach-Object { $_.phase } | Sort-Object -Unique)) {
        Write-Output "input_snapshot.present_stage_${phase}_samples=$(@(
                $stereoPresentStages | Where-Object phase -eq $phase).Count)"
    }
}
if ($inputSnapshotBindings.Count -eq 2) {
    Write-Output "input_snapshot.frame_tokens=$(($inputSnapshotBindings.frame_token) -join ',')"
    Write-Output "input_snapshot.frame_token_calls=$(($inputSnapshotBindings.frame_token_call) -join ',')"
    Write-Output "input_snapshot.frame_indices=$(($inputSnapshotBindings.frame_index) -join ',')"
    Write-Output "input_snapshot.viewports=$(($inputSnapshotBindings.viewport) -join ',')"
    Write-Output "input_snapshot.constants_calls=$(($inputSnapshotBindings.constants_call) -join ',')"
    Write-Output "input_snapshot.constants_versions=$(($inputSnapshotBindings.constants_version) -join ',')"
}
if ($inputSnapshotReadbacks.Count -gt 0) {
    foreach ($phase in @($inputSnapshotReadbacks.phase | Sort-Object -Unique)) {
        Write-Output "input_snapshot.readback_${phase}.samples=$(@($inputSnapshotReadbacks |
                Where-Object phase -eq $phase).Count)"
    }
    $readbackComplete = @($inputSnapshotReadbacks |
        Where-Object phase -eq 'complete' | Select-Object -Last 1)
    if ($readbackComplete.Count -eq 1) {
        Write-Output "input_snapshot.content_divergent_mask=$($readbackComplete[0].divergent_mask)"
    }
}
if ($inputSnapshotSamples.Count -gt 0) {
    foreach ($typeName in @($inputSnapshotSamples |
            ForEach-Object { $_.type_name } | Sort-Object -Unique)) {
        $typeSamples = @($inputSnapshotSamples |
            Where-Object type_name -eq $typeName)
        Write-Output "input_snapshot.${typeName}.content_hashes=$(($typeSamples.hash) -join ',')"
        Write-Output "input_snapshot.${typeName}.nonzero_bytes=$(($typeSamples.nonzero_bytes) -join ',')"
    }
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
$inputSnapshotCompleteRecord = @($inputSnapshots |
    Where-Object phase -eq 'complete')
$inputSnapshotReadbackComplete = @($inputSnapshotReadbacks |
    Where-Object phase -eq 'complete')
$stereoBackbufferComplete = @($stereoBackbuffers |
    Where-Object phase -eq 'complete')
$inputSnapshotPopulatedTypes = @()
$inputSnapshotSourceIdentityCoherent = $false
if ($inputSnapshotSamples.Count -gt 0) {
    $inputSnapshotPopulatedTypes = @($inputSnapshotSamples |
        Group-Object type_name | Where-Object {
            $_.Count -eq 2 -and
            @($_.Group | Where-Object {
                    [uint64]$_.nonzero_bytes -gt 0
                }).Count -eq 2
        })
}
if ($inputSnapshotBindings.Count -eq 2) {
    $frameIndexDelta = [math]::Abs(
        [int64]$inputSnapshotBindings[0].frame_index -
        [int64]$inputSnapshotBindings[1].frame_index)
    $tokenCallDelta = [math]::Abs(
        [int64]$inputSnapshotBindings[0].frame_token_call -
        [int64]$inputSnapshotBindings[1].frame_token_call)
    $inputSnapshotSourceIdentityCoherent =
        $frameIndexDelta -le 1 -and $tokenCallDelta -le 1
}
if ($inputSnapshotProbe -eq '1' -and
        (@($inputSnapshots | Where-Object phase -eq 'scheduled').Count -ne 2 -or
            $inputSnapshotCompleteRecord.Count -ne 1 -or
            @($inputSnapshots | Where-Object phase -eq 'failed').Count -ne 0 -or
            $inputSnapshotResources.Count -ne 10 -or
            $inputSnapshotBindings.Count -ne 2 -or
            -not $inputSnapshotSourceIdentityCoherent -or
            @($inputSnapshotBindings.viewport | Sort-Object -Unique).Count -ne 2 -or
            @($inputSnapshotBindings.constants_call | Sort-Object -Unique).Count -ne 2 -or
            @($inputSnapshotBindings.constants_version | Where-Object { $_ -ne '2' }).Count -ne 0 -or
            @($inputSnapshotReadbacks | Where-Object phase -eq 'scheduled').Count -ne 1 -or
            $inputSnapshotReadbackComplete.Count -ne 1 -or
            @($inputSnapshotReadbacks | Where-Object phase -eq 'failed').Count -ne 0 -or
            $inputSnapshotSamples.Count -ne 10 -or
            $inputSnapshotPopulatedTypes.Count -ne 5 -or
            $inputSnapshotReadbackComplete[0].divergent_mask -ne '31' -or
            @($stereoBackbuffers | Where-Object phase -eq 'scheduled').Count -ne 1 -or
            $stereoBackbufferComplete.Count -ne 1 -or
            @($stereoBackbuffers | Where-Object phase -eq 'failed').Count -ne 0 -or
            @($stereoTransportReservations | Where-Object phase -eq 'reserved').Count -ne 1 -or
            @($stereoTransportReservations | Where-Object phase -eq 'failed').Count -ne 0 -or
            @($stereoTransportReservations | Where-Object {
                    $_.metadata_published -ne '0' -or $_.ready_signaled -ne '0'
                }).Count -ne 0 -or
            [uint64]$stereoBackbufferComplete[0].width -ne
                2 * [uint64]$stereoBackbufferComplete[0].eye_width -or
            $stereoBackbufferComplete[0].format -ne '28' -or
            $stereoBackbufferComplete[0].state -ne '0' -or
            $inputSnapshotCompleteRecord[0].snapshot_alias_mask -ne '0' -or
            $inputSnapshotCompleteRecord[0].snapshot_unique_count -ne '10' -or
            $inputSnapshotCompleteRecord[0].snapshot_ready -ne '1')) {
    throw 'The one-pair input snapshot/readback did not prove ten populated, distinct per-eye inputs.'
}
if ($targetTokenProbe -eq '1') {
    $allocatedTargetTokens = @($stereoTargetTokens |
        Where-Object phase -eq 'allocated')
    if ($allocatedTargetTokens.Count -ne 1 -or
            @($stereoTargetTokens | Where-Object phase -eq 'failed').Count -ne 0 -or
            [uint64]$allocatedTargetTokens[0].target_frame_index -le
                [uint64]$inputSnapshotBindings[0].frame_index -or
            [uint64]$allocatedTargetTokens[0].target_frame_index -le
                [uint64]$inputSnapshotBindings[1].frame_index -or
            $allocatedTargetTokens[0].result -ne '0' -or
            $allocatedTargetTokens[0].policy_status -ne '6' -or
            $targetGenerationPresentSubmitted -ne '0' -or
            $allocatedTargetTokens[0].metadata_published -ne '0' -or
            $allocatedTargetTokens[0].ready_signaled -ne '0') {
        throw 'The requested stereo target token was not allocated safely.'
    }
}
if ($stereoSwapchainProbe -eq '1' -and
        ($generatedBackbufferExtents.Count -ne 1 -or
            $generatedBackbufferExtents[0] -ne '4992x2688' -or
            $generatedBackbufferFormats.Count -ne 1 -or
            $generatedBackbufferFormats[0] -ne '28')) {
    throw 'The wide stereo swapchain did not reach the Streamline present path.'
}
if ($targetTokenProbe -eq '1' -and $stereoSwapchainProbe -eq '1' -and
        ($stereoPresentTargets.Count -ne 1 -or
            $stereoPresentTargets[0].phase -ne 'observed' -or
            $stereoPresentTargets[0].compatible -ne '1' -or
            $stereoPresentTargets[0].copy_staged -ne '0' -or
            $stereoPresentTargets[0].tags_staged -ne '0' -or
            $stereoPresentTargets[0].generation_present_submitted -ne '0' -or
            $stereoPresentTargets[0].metadata_published -ne '0' -or
            $stereoPresentTargets[0].ready_signaled -ne '0')) {
    throw 'The packed stereo resource was not safely bound to one Present target.'
}
if ($stereoStageProbe -eq '1') {
    $scheduledStages = @($stereoPresentStages |
        Where-Object phase -eq 'scheduled')
    $completedStages = @($stereoPresentStages |
        Where-Object phase -eq 'complete')
    if ($scheduledStages.Count -ne 1 -or $completedStages.Count -ne 1 -or
            @($stereoPresentStages | Where-Object phase -eq 'failed').Count -ne 0 -or
            $scheduledStages[0].copy_staged -ne '1' -or
            $scheduledStages[0].tags_staged -ne '0' -or
            $scheduledStages[0].additional_present_submitted -ne '0' -or
            $scheduledStages[0].metadata_published -ne '0' -or
            $scheduledStages[0].ready_signaled -ne '0' -or
            $completedStages[0].copy_staged -ne '1' -or
            $completedStages[0].tags_staged -ne '0' -or
            $completedStages[0].additional_present_submitted -ne '0' -or
            $completedStages[0].metadata_published -ne '0' -or
            $completedStages[0].ready_signaled -ne '0') {
        throw 'The one-shot Present staging copy did not complete safely.'
    }
}
Write-Output 'result=pass'
