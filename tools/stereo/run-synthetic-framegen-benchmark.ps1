[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('On','Off')] [string] $FrameGeneration,
    [ValidateSet('Preserve','Unlimited','30','40','60','72','90','120')] [string] $FrameRateLimit = 'Preserve',
    [ValidateSet(90,120,144)] [int] $SimulatorRefreshRate = 90,
    [ValidateSet('Legacy','Fixed')] [string] $SimulatorDisplayClock = 'Legacy',
    [ValidateRange(0,16)] [int] $WorkerThreads = 0,
    [ValidateSet('Preserve','Quality','Performance')] [string] $DlssQuality = 'Preserve',
    [ValidateSet('Preserve','On','Off')] [string] $Reflex = 'Preserve',
    [ValidateSet('Preserve','Disabled')] [string] $MeshStreaming = 'Preserve',
    [ValidateSet('','cm_archives')] [string] $SoloMission = '',
    [ValidateRange(1,5)] [int] $SoloDifficulty = 3,
    [string] $ExpectedInstalledSoloSha256,
    [switch] $ClusterLightTrace,
    [switch] $PresentCpuProfile,
    [switch] $DebugLayer,
    [switch] $PreserveDiagnosticFlags,
    [bool] $EnableHudPanel = $true,
    [bool] $EnableMenuInput = $true,
    [ValidateSet(0,30,60,90,120)] [int] $SimulatorPreviewFps = 0,
    [switch] $GpuProfile,
    [switch] $RenderApiCpuProfile,
    [switch] $ObserveDlssSrInputs,
    [switch] $ObserveGpuEngineActivity,
    [switch] $DisableGameplayMirror,
    [switch] $GameplayMirrorMetrics,
    [string] $RenderWorldCensusSourcePath,
    [string] $CpuRenderTimingSourcePath,
    [ValidateRange(0,600)] [int] $RenderWorldCensusWarmupFrames = 120,
    [string] $ExpectedInstalledLuaSha256,
    [Parameter(Mandatory)] [string] $RuntimeJson,
    [Parameter(Mandatory)] [ValidatePattern('^[a-fA-F0-9]{64}$')] [string] $RuntimeSha256,
    [Parameter(Mandatory)] [string] $OutputDirectory,
    [string] $GameRoot,
    [string] $SettingsPath = (Join-Path $env:APPDATA 'Fatshark/Darktide/user_settings.config'),
    [string] $HarnessPath = (Join-Path $PSScriptRoot '../../build/xr-frame-stage-timing/tests/xr_harness/Release/darktidevr-xr-harness.exe'),
    [string] $NativeDllPath,
    [string] $NativeSha256,
    [string] $ExpectedInstalledNativeSha256,
    [ValidateRange(30,600)] [int] $DurationSeconds = 120,
    [ValidateRange(60,600)] [int] $StartupTimeoutSeconds = 300,
    [string] $VdxrReadinessPath,
    [ValidateRange(0,4096)] [int] $EyeWidth = 0,
    [ValidateRange(0,4096)] [int] $EyeHeight = 0
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($RenderApiCpuProfile) { $PresentCpuProfile = [switch]$true }
if ($GpuProfile -and $CpuRenderTimingSourcePath) { throw 'GPU profiling cannot be combined with the CPU-only timing control.' }
. (Join-Path $PSScriptRoot 'resolve-darktide-game-root.ps1')
. (Join-Path $PSScriptRoot 'synthetic-framegen-settings.ps1')
. (Join-Path $PSScriptRoot 'resolve-synthetic-eye-size.ps1')
$eyeSize = Resolve-SyntheticEyeSize -VdxrReadinessPath $VdxrReadinessPath -EyeWidth $EyeWidth -EyeHeight $EyeHeight
$EyeWidth = $eyeSize.width
$EyeHeight = $eyeSize.height
$GameRoot = Resolve-DarktideGameRoot -GameRoot $GameRoot
if (Get-Process Darktide,darktidevr-xr-harness,darktidevr-synthetic-head-publisher -ErrorAction SilentlyContinue) {
    throw 'Close the game and other XR/synthetic consumers before this isolated benchmark.'
}
$RuntimeJson = (Resolve-Path -LiteralPath $RuntimeJson).Path
$runtime = Get-Content -LiteralPath $RuntimeJson -Raw | ConvertFrom-Json
$libraryPath = [IO.Path]::GetFullPath([IO.Path]::Combine((Split-Path $RuntimeJson), $runtime.runtime.library_path))
if ((Get-FileHash -LiteralPath $libraryPath -Algorithm SHA256).Hash -ne $RuntimeSha256) {
    throw 'Simulator DLL hash mismatch.'
}
$HarnessPath = (Resolve-Path -LiteralPath $HarnessPath).Path
if ($NativeDllPath -or $NativeSha256 -or $ExpectedInstalledNativeSha256) {
    if (-not $NativeDllPath -or $NativeSha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        $ExpectedInstalledNativeSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'A native trial requires candidate and installed hashes.' }
    $NativeDllPath = (Resolve-Path -LiteralPath $NativeDllPath).Path
    if ((Get-FileHash $NativeDllPath -Algorithm SHA256).Hash -ne $NativeSha256) { throw 'Native trial hash mismatch.' }
}
$SettingsPath = (Resolve-Path -LiteralPath $SettingsPath).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Use a new output directory for each run.' }
$modPath = Join-Path $GameRoot 'mods/darktidevr_stereo_probe'
$luaDirectory = Join-Path $modPath 'scripts/mods/darktidevr_stereo_probe'
$censusFlag = Join-Path $modPath 'darktidevr_render_world_census.flag'
$cpuTimingFlag = Join-Path $modPath 'darktidevr_cpu_render_timing.flag'
$luaTrialFiles = @{}
$soloSource = Join-Path $GameRoot 'mods/SoloPlay/scripts/mods/SoloPlay/SoloPlay.lua'
$soloModule = Join-Path (Split-Path $soloSource) 'dtvr_mission_benchmark.lua'
if ($SoloMission) {
    if ($ExpectedInstalledSoloSha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        (Get-FileHash -LiteralPath $soloSource).Hash -ne $ExpectedInstalledSoloSha256) {
        throw 'Solo mission benchmark requires the exact installed SoloPlay source hash.'
    }
    & (Join-Path $PSScriptRoot '../lua/test-lua-syntax.ps1') -SourcePaths (Join-Path $PSScriptRoot 'solo-mission-benchmark.lua')
}
if($RenderWorldCensusWarmupFrames -ne 120 -and -not $RenderWorldCensusSourcePath) {
    throw 'A custom census warm-up requires the focused census Lua source.'
}
if ($RenderWorldCensusSourcePath -and $CpuRenderTimingSourcePath) { throw 'Choose one diagnostic Lua trial per run.' }
$diagnosticLuaSource = if($CpuRenderTimingSourcePath){$CpuRenderTimingSourcePath}else{$RenderWorldCensusSourcePath}
if($diagnosticLuaSource -or $ExpectedInstalledLuaSha256) {
    if(-not $diagnosticLuaSource -or $ExpectedInstalledLuaSha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'A diagnostic Lua trial requires a source path and the installed main Lua hash.'
    }
    $diagnosticLuaSource = (Resolve-Path -LiteralPath $diagnosticLuaSource).Path
    & (Join-Path $PSScriptRoot 'test-darktide-lua-source.ps1') -SourcePath $diagnosticLuaSource
    foreach($name in @('darktidevr_stereo_probe.lua','darktidevr_render_world_census.lua')) {
        $luaTrialFiles[(Join-Path $luaDirectory $name)] = [IO.File]::ReadAllBytes(
            (Join-Path (Split-Path $diagnosticLuaSource) $name))
    }
}
$simulatorSettings = Join-Path $env:LOCALAPPDATA 'OpenXR-Simulator/settings.json'
$mutex = [Threading.Mutex]::new($false,'Local\DarktideVR-synthetic-framegen-benchmark')
$ownsMutex = $false
$saved = @{}
$consumer = $null
$gpuActivityJob = $null
$gpuActivityStop = Join-Path $OutputDirectory 'gpu-engine-activity.stop'
$failure = $null
$priorRuntime = $env:XR_RUNTIME_JSON
$priorPairWait = $env:DTVR_XR_PRECISE_PAIR_WAIT
$priorSimulatorRefresh = $env:DTVR_SIMULATOR_REFRESH_HZ
$priorSimulatorClock = $env:DTVR_SIMULATOR_FIXED_DISPLAY_CLOCK
$systemRuntime = Get-ItemPropertyValue 'HKLM:/SOFTWARE/Khronos/OpenXR/1' -Name ActiveRuntime
$stopFile = Join-Path $OutputDirectory 'consumer.stop'
function Save-BenchmarkFile([string] $Path) {
    if (-not $saved.ContainsKey($Path)) {
        $saved[$Path] = if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::ReadAllBytes($Path) } else { $null }
    }
}
try {
    $ownsMutex = $mutex.WaitOne(0)
    if (-not $ownsMutex) { throw 'Another synthetic benchmark owns the settings.' }
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    Save-BenchmarkFile $SettingsPath
    Save-BenchmarkFile $simulatorSettings
    if ($SoloMission) {
        Save-BenchmarkFile $soloSource
        Save-BenchmarkFile $soloModule
    }
    if($diagnosticLuaSource) {
        if((Get-FileHash (Join-Path $luaDirectory 'darktidevr_stereo_probe.lua')).Hash -ne $ExpectedInstalledLuaSha256) {
            throw 'Installed Lua baseline changed.'
        }
        foreach($path in $luaTrialFiles.Keys) { Save-BenchmarkFile $path }
        Save-BenchmarkFile $censusFlag
        Save-BenchmarkFile $cpuTimingFlag
    }
    # The launcher temporarily owns these flags too. The outer byte backups
    # preserve even a pre-existing malformed/legacy file exactly after the run.
    $flagNames = @('probe','input_snapshot_probe','target_token_probe','eye_target_probe',
        'stereo_swapchain_probe','stereo_stage_probe','stereo_submit_probe') |
        ForEach-Object { "darktidevr_streamline_$_.flag" }
    $flagNames += 'darktidevr_ngx_output_probe.flag'
    $flagNames += 'darktidevr_hud_panel.flag'
    if ($GpuProfile) { $flagNames += 'darktidevr_performance_profile.flag' }
    foreach ($name in $flagNames) { Save-BenchmarkFile (Join-Path $modPath $name) }
    $clusterTraceFlag = Join-Path $modPath 'bin/darktidevr_cluster_trace.flag'
    $presentCpuFlag = Join-Path $modPath 'bin/darktidevr_present_cpu_profile.flag'
    if ($PresentCpuProfile) { Save-BenchmarkFile $presentCpuFlag }
    if($ClusterLightTrace) { Save-BenchmarkFile $clusterTraceFlag }
    $nativeTargets = @((Join-Path $GameRoot 'binaries/darktidevr_native_capture.dll'),
        (Join-Path $modPath 'bin/darktidevr_native_capture.dll'))
    $mirrorFlags = @($nativeTargets | ForEach-Object {
        Join-Path (Split-Path $_) 'darktidevr_gameplay_mirror.flag'
    })
    foreach ($path in $mirrorFlags) { Save-BenchmarkFile $path }
    if ($NativeDllPath) {
        foreach ($path in $nativeTargets) {
            if ((Get-FileHash $path -Algorithm SHA256).Hash -ne $ExpectedInstalledNativeSha256) { throw 'Installed native baseline changed.' }
            Save-BenchmarkFile $path
        }
    }
    $settings = [IO.File]::ReadAllText($SettingsPath)
    $enabled = $FrameGeneration -eq 'On'
    $settings = ConvertTo-SyntheticFramegenSettings -Settings $settings -Enabled $enabled -FrameRateLimit $FrameRateLimit -WorkerThreads $WorkerThreads -DlssQuality $DlssQuality -Reflex $Reflex -MeshStreaming $MeshStreaming
    $recovery = Join-Path $OutputDirectory 'recovery'
    New-Item -ItemType Directory -Path $recovery | Out-Null
    $recoveryIndex = 0
    $recoveryManifest = foreach ($path in $saved.Keys) {
        $backup = Join-Path $recovery ("$recoveryIndex-"+[IO.Path]::GetFileName($path)+'.backup')
        ++$recoveryIndex
        if ($null -ne $saved[$path]) { [IO.File]::WriteAllBytes($backup,$saved[$path]) }
        [pscustomobject]@{path=$path;existed=($null -ne $saved[$path]);backup=$backup}
    }
    $recoveryManifest | ConvertTo-Json | Set-Content (Join-Path $recovery 'manifest.json') -Encoding utf8
    foreach ($path in $mirrorFlags) {
        [IO.File]::WriteAllText($path,
            "[probe]`r`ndisabled=$([int]$DisableGameplayMirror.IsPresent)`r`nmetrics=$([int]$GameplayMirrorMetrics.IsPresent)`r`n")
    }
    if ($SoloMission) {
        [IO.File]::WriteAllBytes($soloModule, [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'solo-mission-benchmark.lua')))
        $soloText = [Text.Encoding]::UTF8.GetString($saved[$soloSource])
        $soloText += "`r`nmod:io_dofile('SoloPlay/scripts/mods/SoloPlay/dtvr_mission_benchmark')(mod, '$SoloMission', $SoloDifficulty)`r`n"
        [IO.File]::WriteAllText($soloSource, $soloText, [Text.UTF8Encoding]::new($false))
        & (Join-Path $PSScriptRoot '../lua/test-lua-syntax.ps1') -SourcePaths @($soloSource,$soloModule)
    }
    if ($NativeDllPath) {
        foreach ($path in $nativeTargets) { [IO.File]::WriteAllBytes($path,[IO.File]::ReadAllBytes($NativeDllPath)) }
    }
    if($diagnosticLuaSource) {
        foreach($path in $luaTrialFiles.Keys) { [IO.File]::WriteAllBytes($path,$luaTrialFiles[$path]) }
        if ($CpuRenderTimingSourcePath) {
            [IO.File]::WriteAllText($cpuTimingFlag,"enabled`r`n")
            [IO.File]::WriteAllText($censusFlag,"disabled`r`n")
        } else {
            [IO.File]::WriteAllText($cpuTimingFlag,"disabled`r`n")
            [IO.File]::WriteAllText($censusFlag,"enabled`r`nwarmup=$RenderWorldCensusWarmupFrames`r`n")
        }
        & (Join-Path $PSScriptRoot 'test-darktide-lua-source.ps1') -SourcePath (Join-Path $luaDirectory 'darktidevr_stereo_probe.lua')
    }
    [IO.File]::WriteAllText($SettingsPath,$settings,[Text.UTF8Encoding]::new($false))
    # Make both control states explicit; a false switch must not inherit a
    # previously enabled HUD from the installed flag. Restore exact bytes later.
    [IO.File]::WriteAllText((Join-Path $modPath 'darktidevr_hud_panel.flag'),
        $(if ($EnableHudPanel) { "enable`r`n" } else { "disable`r`n" }))
    if ($GpuProfile) { [IO.File]::WriteAllText((Join-Path $modPath 'darktidevr_performance_profile.flag'),"enabled`r`n") }
    if($ClusterLightTrace) { [IO.File]::WriteAllText($clusterTraceFlag,"enabled=1`r`n") }
    if($PresentCpuProfile) { [IO.File]::WriteAllText($presentCpuFlag,"[probe]`r`nenabled=1`r`n") }
    if (-not $enabled) {
        foreach ($name in @('darktidevr_streamline_stereo_submit_probe.flag',
            'darktidevr_streamline_stereo_stage_probe.flag','darktidevr_ngx_output_probe.flag')) {
            $path = Join-Path $modPath $name
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
        }
    }
    New-Item -ItemType Directory -Path (Split-Path $simulatorSettings) -Force | Out-Null
    $simSettings = @{}
    if ($null -ne $saved[$simulatorSettings]) {
        $priorSimSettings = [Text.Encoding]::UTF8.GetString($saved[$simulatorSettings]) | ConvertFrom-Json
        foreach ($property in $priorSimSettings.PSObject.Properties) { $simSettings[$property.Name] = $property.Value }
    }
    $simSettings['headset_profile']='quest3'
    $simSettings['asymmetric_fov']=$true
    $simSettings['ipd_mm']=64
    $simSettings['render_width']=$EyeWidth
    $simSettings['render_height']=$EyeHeight
    $simSettings['preview_fps']=$SimulatorPreviewFps
    $simSettings['view_mode']='both'
    $simSettings['layout']='side_by_side'
    $simSettings | ConvertTo-Json | Set-Content -LiteralPath $simulatorSettings -Encoding utf8
    $env:XR_RUNTIME_JSON = $RuntimeJson
    $env:DTVR_XR_PRECISE_PAIR_WAIT = '1'
    $env:DTVR_SIMULATOR_REFRESH_HZ = [string]$SimulatorRefreshRate
    $env:DTVR_SIMULATOR_FIXED_DISPLAY_CLOCK = if ($SimulatorDisplayClock -eq 'Fixed') { '1' } else { '0' }
    $receipt = [ordered]@{
        frame_generation=$FrameGeneration; frames_to_generate=1
        frame_rate_limit=$FrameRateLimit
        simulator_refresh_hz=$SimulatorRefreshRate
        worker_threads_override=$WorkerThreads
        dlss_quality_override=$DlssQuality
        reflex_override=$Reflex
        mesh_streaming_override=$MeshStreaming
        reflex_mode_setting=[regex]::Match($settings,'(?m)^\tnv_low_latency_mode[ \t]*=[ \t]*(true|false)').Groups[1].Value
        dlss_quality_setting=[regex]::Match($settings,'(?m)^\tupscaling_quality[ \t]*=[ \t]*"([^"]+)"').Groups[1].Value
        worker_threads_setting=[regex]::Match($settings,'(?m)^max_worker_threads[ \t]*=[ \t]*([0-9]+)').Groups[1].Value
        workload=$(if($SoloMission){'mission_start_stationary'}else{'hub_spin'})
        solo_mission=$SoloMission; solo_difficulty=$(if($SoloMission){$SoloDifficulty}else{$null})
        solo_baseline_sha256=$ExpectedInstalledSoloSha256
        solo_trial_sha256=$(if($SoloMission){(Get-FileHash -LiteralPath $soloSource).Hash}else{$null})
        solo_module_sha256=$(if($SoloMission){(Get-FileHash -LiteralPath $soloModule).Hash}else{$null})
        eye_width=$EyeWidth; eye_height=$EyeHeight; ssw='not_applicable_simulator'
        eye_size_source=$eyeSize.source; eye_size_receipt_sha256=$eyeSize.receipt_sha256
        eye_size_captured_utc=$eyeSize.captured_utc
        runtime_json=$RuntimeJson; runtime_sha256=$RuntimeSha256
        harness_sha256=(Get-FileHash $HarnessPath -Algorithm SHA256).Hash
        simulator_display_clock=$SimulatorDisplayClock
        native_sha256=(Get-FileHash (Join-Path $GameRoot 'binaries/darktidevr_native_capture.dll') -Algorithm SHA256).Hash
        duration_seconds=$DurationSeconds; preview_fps=$SimulatorPreviewFps; physical_xr_ready=$false
        hud_panel_enabled=$EnableHudPanel; preview_mode='both'; preview_layout='side_by_side'
        menu_input_enabled=$EnableMenuInput; desktop_window_capture=$false
        gameplay_mirror_copy_suppression=$DisableGameplayMirror.IsPresent
        gameplay_mirror_metrics=$GameplayMirrorMetrics.IsPresent
        optional_diagnostics_clean=(-not $PreserveDiagnosticFlags.IsPresent)
        cluster_trace=(Test-Path -LiteralPath $clusterTraceFlag)
        observe_dlss_sr_inputs=$ObserveDlssSrInputs.IsPresent
        render_world_census=[bool]$RenderWorldCensusSourcePath
        cpu_render_timing=[bool]$CpuRenderTimingSourcePath
        present_cpu_profile=$PresentCpuProfile.IsPresent
        debug_layer=$DebugLayer.IsPresent
        gpu_profile=$GpuProfile.IsPresent
        render_api_cpu_profile=$RenderApiCpuProfile.IsPresent
        render_world_census_warmup=$RenderWorldCensusWarmupFrames
        lua_sha256=(Get-FileHash (Join-Path $luaDirectory 'darktidevr_stereo_probe.lua')).Hash
    }
    $receipt['gpu_engine_activity_observed'] = [bool]$ObserveGpuEngineActivity
    $receipt | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'configuration.json') -Encoding utf8
    if ($ObserveGpuEngineActivity) {
        $gpuActivityJob = Start-Job -FilePath (Join-Path $PSScriptRoot 'capture-gpu-engine-activity.ps1') `
            -ArgumentList (Join-Path $OutputDirectory 'gpu-engine-activity.jsonl'),$gpuActivityStop,($StartupTimeoutSeconds+$DurationSeconds+60),5
    }
    # This consumer is also the sole synthetic head publisher. Do not launch
    # SyntheticRuntimeFrusta beside it: two writers would race on pose metadata.
    $consumerArguments = @('--flush-log','--shared-eyes','--require-rendering','--enable-gameplay-reticle',
        '--xr-seconds',($StartupTimeoutSeconds+$DurationSeconds+60), '--stop-file',('"'+$stopFile+'"'))
    if ($EnableMenuInput) { $consumerArguments += '--enable-menu-input' }
    if ($DebugLayer) { $consumerArguments += '--debug-layer' }
    $consumer = Start-Process -FilePath $HarnessPath -WindowStyle Hidden -PassThru `
        -ArgumentList $consumerArguments `
        -RedirectStandardOutput (Join-Path $OutputDirectory 'consumer.log') `
        -RedirectStandardError (Join-Path $OutputDirectory 'consumer-error.log')
    # Retain the process handle before Refresh/HasExited polling. Windows
    # PowerShell 5.1 otherwise can lose ExitCode after the process exits, even
    # when WaitForExit succeeds. Null is not evidence of a successful exit.
    $null = $consumer.Handle
    $consumerReadyDeadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 100
        $consumer.Refresh()
        if ($consumer.HasExited) { throw 'Simulator consumer failed before launch; inspect consumer-error.log.' }
        $initialLog = [string](Get-Content (Join-Path $OutputDirectory 'consumer.log') -Raw)
        $displayPeriod = [regex]::Match($initialLog,'last_display_period_ms=([0-9.]+)')
        $consumerReady = $initialLog -match 'openxr.runtime_name=OpenXR Simulator Runtime' -and
            $initialLog -match 'openxr.render_projection=recentered-symmetric' -and $displayPeriod.Success
    } while (-not $consumerReady -and (Get-Date) -lt $consumerReadyDeadline)
    if (-not $consumerReady) { throw 'Expected simulator session did not become active.' }
    if ($SimulatorDisplayClock -eq 'Fixed' -and $initialLog -notmatch 'openxr.simulator_display_clock=fixed_refresh') {
        throw 'Simulator did not confirm the requested fixed display clock.'
    }
    $observedPeriod = [double]::Parse($displayPeriod.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
    if ([math]::Abs($observedPeriod - 1000.0/$SimulatorRefreshRate) -gt 0.02) {
        throw 'Simulator display period does not match the requested refresh rate; use the patched runtime.'
    }
    & (Join-Path $PSScriptRoot 'start-darktide-vr.ps1') -GameRoot $GameRoot `
        -OfflineDualViewBenchmark -SkipDeploymentSync -DlssGeneratedStereo:$enabled `
        -EnablePerformanceProfile:$GpuProfile `
        -EnableHudPanel:$EnableHudPanel `
        -PreserveDiagnosticFlags:$PreserveDiagnosticFlags `
        -OfflineSoloMission $SoloMission `
        -ObserveDlssSrInputs:$ObserveDlssSrInputs `
        -DurationSeconds $DurationSeconds -GameStartTimeoutSeconds $StartupTimeoutSeconds `
        *> (Join-Path $OutputDirectory 'launch.log')
} catch { $failure = $_ }
finally {
    if ($gpuActivityJob) {
        try {
            Set-Content -LiteralPath $gpuActivityStop -Value 'stop' -Encoding ascii
            $null = Wait-Job -Job $gpuActivityJob -Timeout 7
            if ($gpuActivityJob.State -eq 'Running') { Stop-Job -Job $gpuActivityJob }
            Receive-Job -Job $gpuActivityJob -ErrorAction Continue *> (Join-Path $OutputDirectory 'gpu-engine-activity-job.log')
        } catch {
            $_ | Out-String | Set-Content (Join-Path $OutputDirectory 'gpu-engine-activity-job.log')
        } finally { Remove-Job -Job $gpuActivityJob -Force -ErrorAction SilentlyContinue }
    }
    $consumerStopped = $true
    if ($consumer) {
        $consumerStopped = $false
        try {
            Set-Content -LiteralPath $stopFile -Value 'stop' -Encoding ascii
            $consumerStopped = $consumer.WaitForExit(15000)
            if (-not $consumerStopped) {
                $consumer.Kill(); $consumerStopped = $consumer.WaitForExit(5000)
                if (-not $failure) { $failure = 'Consumer did not stop cleanly.' }
            }
            if ($consumerStopped -and $consumer.ExitCode -ne 0 -and -not $failure) { $failure = "Consumer failed: $($consumer.ExitCode)" }
        } catch {
            if (-not $failure) { $failure = $_ }
            try {
                $consumer.Refresh()
                if (-not $consumer.HasExited) { $consumer.Kill() }
                $consumerStopped = $consumer.WaitForExit(5000)
            } catch { $consumerStopped = $false }
        } finally { $consumer.Dispose() }
    }
    # Launcher cleanup must have closed its owned game before settings restore.
    # Stop-Process can return while Windows is still completing teardown.
    $gameExitDeadline = (Get-Date).AddSeconds(15)
    while ($ownsMutex -and (Get-Process Darktide -ErrorAction SilentlyContinue) -and
        (Get-Date) -lt $gameExitDeadline) { Start-Sleep -Milliseconds 100 }
    if (-not $consumerStopped -or ($ownsMutex -and (Get-Process Darktide -ErrorAction SilentlyContinue))) {
        $failure = 'An owned process has not stopped: preserved recovery backups; settings were not overwritten.'
    } else {
        foreach ($path in $saved.Keys) {
            try {
                if ($null -ne $saved[$path]) { [IO.File]::WriteAllBytes($path,$saved[$path]) }
                elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
            } catch { if (-not $failure) { $failure = $_ } }
        }
    }
    $env:XR_RUNTIME_JSON = $priorRuntime
    $env:DTVR_XR_PRECISE_PAIR_WAIT = $priorPairWait
    $env:DTVR_SIMULATOR_REFRESH_HZ = $priorSimulatorRefresh
    $env:DTVR_SIMULATOR_FIXED_DISPLAY_CLOCK = $priorSimulatorClock
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
if ((Get-ItemPropertyValue 'HKLM:/SOFTWARE/Khronos/OpenXR/1' -Name ActiveRuntime) -ne $systemRuntime) {
    throw 'System runtime changed during the run; this benchmark did not modify it.'
}
# Preserve evidence before evaluating success, including failed FG attempts.
$launchPath = Join-Path $OutputDirectory 'launch.log'
if (Test-Path -LiteralPath $launchPath) {
    $launchText = [IO.File]::ReadAllText($launchPath)
    $hudConsole = [regex]::Match($launchText,'(?m)^Offline dual-view benchmark started; log=([^\r\n]+)')
    if ($hudConsole.Success -and (Test-Path -LiteralPath $hudConsole.Groups[1].Value)) {
        $hudText = [IO.File]::ReadAllText($hudConsole.Groups[1].Value)
        @($hudText -split "`n" | Where-Object { $_ -match 'DARKTIDEVR_HUD' }) |
            Set-Content (Join-Path $OutputDirectory 'hud-panel.log') -Encoding utf8
        $expectedHudState = $EnableHudPanel.ToString().ToLowerInvariant()
        if (($hudText -notmatch "DARKTIDEVR_HUD enabled=$expectedHudState source=flag" -or
             ($EnableHudPanel -and $hudText -notmatch "DARKTIDEVR_HUD target_created width=$EyeWidth ")) -and -not $failure) {
            $failure = 'World-space HUD did not confirm its requested state or expected-width target.'
        }
    } elseif (-not $failure) { $failure = 'HUD validation has no launch-selected console log.' }
    if ($GpuProfile) {
        $gpuConsole = [regex]::Match($launchText,'(?m)^Offline dual-view benchmark started; log=([^\r\n]+)')
        if ($gpuConsole.Success -and (Test-Path -LiteralPath $gpuConsole.Groups[1].Value)) {
            $gpuText = [IO.File]::ReadAllText($gpuConsole.Groups[1].Value)
            @($gpuText -split "`n" | Where-Object { $_ -match 'DARKTIDEVR_(PERF|GPU_PERF|GPU_STAGE)' }) |
                Set-Content (Join-Path $OutputDirectory 'gpu-profile.log') -Encoding utf8
            if ($gpuText -notmatch 'DARKTIDEVR_GPU_PERF target=' -and -not $failure) {
                $failure = 'Requested GPU profiling produced no eye timing evidence.'
            }
        } elseif (-not $failure) { $failure = 'GPU profiling has no launch-selected console log.' }
    }
    if ($CpuRenderTimingSourcePath) {
        $timingConsole = [regex]::Match($launchText,'(?m)^Offline dual-view benchmark started; log=([^\r\n]+)')
        if ($timingConsole.Success -and (Test-Path -LiteralPath $timingConsole.Groups[1].Value)) {
            $timingText = [IO.File]::ReadAllText($timingConsole.Groups[1].Value)
            @($timingText -split "`n" | Where-Object { $_ -match 'DARKTIDEVR_(PERF|GPU_PERF|GPU_STAGE)' }) |
                Set-Content (Join-Path $OutputDirectory 'cpu-render-timing.log') -Encoding utf8
            if (($timingText -notmatch 'cpu_render_timing=true gpu_profile=false' -or
                 $timingText -notmatch 'DARKTIDEVR_PERF target=.+ samples=240 ' -or
                 $timingText -match 'DARKTIDEVR_GPU_PERF target=') -and -not $failure) {
                $failure = 'CPU-only render timing evidence is missing or GPU profiling was enabled.'
            }
        } elseif (-not $failure) { $failure = 'CPU render timing has no launch-selected console log.' }
    }
    if ($SoloMission) {
        $missionConsole = [regex]::Match($launchText,'(?m)^Offline dual-view benchmark started; log=([^\r\n]+)')
        if ($missionConsole.Success -and (Test-Path -LiteralPath $missionConsole.Groups[1].Value)) {
            $missionText = [IO.File]::ReadAllText($missionConsole.Groups[1].Value)
            @($missionText -split "`n" | Where-Object { $_ -match 'DARKTIDEVR_SOLO_BENCHMARK' }) |
                Set-Content (Join-Path $OutputDirectory 'solo-mission.log') -Encoding utf8
            if ($missionText -notmatch "DARKTIDEVR_SOLO_BENCHMARK ready mission=$SoloMission difficulty=$SoloDifficulty host=singleplay" -and -not $failure) {
                $failure = 'Solo mission identity or difficulty evidence is missing.'
            }
        } elseif (-not $failure) { $failure = 'Solo mission has no launch-selected console log.' }
    }
    if($RenderWorldCensusSourcePath) {
        $consoleMatch = [regex]::Match($launchText,'(?m)^Offline dual-view benchmark started; log=([^\r\n]+)')
        if($consoleMatch.Success -and (Test-Path -LiteralPath $consoleMatch.Groups[1].Value)) {
            $consoleText = [IO.File]::ReadAllText($consoleMatch.Groups[1].Value)
            $censusLines = @($consoleText -split "`n" | Where-Object { $_ -match 'DARKTIDEVR_WORLD_CENSUS' })
            $censusLines | Set-Content (Join-Path $OutputDirectory 'render-world-census.log') -Encoding utf8
            if(($consoleText -notmatch 'DARKTIDEVR_WORLD_CENSUS complete records=64' -or
                $consoleText -match 'DARKTIDEVR_WORLD_CENSUS failed') -and -not $failure) {
                $failure = 'World census did not complete successfully.'
            }
        } elseif(-not $failure) { $failure = 'World census has no launch-selected console log.' }
    }
    $gamePidMatch = [regex]::Match($launchText,'Authenticated Darktide process started(?: during (?:launcher transition|Play activation|Play retry))?: PID (\d+)\.')
    if ($gamePidMatch.Success) {
        $gamePidText = $gamePidMatch.Groups[1].Value
        foreach ($name in @("darktidevr-generated-stereo-$gamePidText.log",
            "darktidevr-present-cpu-$gamePidText.log",
            "darktidevr-render-api-cpu-$gamePidText.log",
            "darktidevr-ngx-sr-$gamePidText.log",
            "darktidevr-ngx-output-$gamePidText.log", "darktidevr-ngx-timing-$gamePidText.log",
            "darktidevr-ngx-gpu-timing-$gamePidText.log",'darktidevr-streamline-probe.tsv',
            'darktidevr-cluster-trace.log')) {
            $path = Join-Path $env:TEMP $name
            if (Test-Path -LiteralPath $path) {
                $logText = [IO.File]::ReadAllText($path)
                if($name -eq 'darktidevr-cluster-trace.log' -and
                    $logText -notmatch "(?m)^CLUSTER_TRACE_BEGIN`tpid=$gamePidText`r?$") { continue }
                [IO.File]::WriteAllText((Join-Path $OutputDirectory $name),$logText)
            }
        }
    }
}
if($ClusterLightTrace -and -not (Test-Path (Join-Path $OutputDirectory 'darktidevr-cluster-trace.log')) -and -not $failure) {
    $failure = 'No cluster trace belongs to this game process; stale logs were rejected.'
}
if ($PresentCpuProfile -and -not $failure) {
    $cpuLogs = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter 'darktidevr-present-cpu-*.log' -File)
    if ($cpuLogs.Count -ne 1 -or [regex]::Matches([IO.File]::ReadAllText($cpuLogs[0].FullName),'(?m)^PRESENT_CPU sample=').Count -ne 240) {
        $failure = 'Presentation CPU profile lacks its complete bounded sample window.'
    }
}
if ($RenderApiCpuProfile -and -not $failure) {
    $apiLogs = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter 'darktidevr-render-api-cpu-*.log' -File)
    if ($apiLogs.Count -ne 1 -or [regex]::Matches([IO.File]::ReadAllText($apiLogs[0].FullName),'(?m)^RENDER_API_CPU sample=').Count -ne 1440) {
        $failure = 'Render API CPU profile lacks its complete 240-frame, six-category window.'
    }
}
if($ObserveDlssSrInputs -and -not $failure) {
    $srLogs = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter 'darktidevr-ngx-sr-*.log' -File)
    if($srLogs.Count -ne 1 -or [regex]::Matches(
        [IO.File]::ReadAllText($srLogs[0].FullName),'(?m)^NGX_SR_EVAL call=\d+ result=1 ').Count -ne 64) {
        $failure = 'The requested SR capture lacks 64 successful evaluations; inspect it with read-ngx-sr-probe.py.'
    }
}
if (Test-Path -LiteralPath (Join-Path $OutputDirectory 'recovery/manifest.json')) {
    $restoration = foreach ($entry in (Get-Content (Join-Path $OutputDirectory 'recovery/manifest.json') -Raw | ConvertFrom-Json)) {
        $restored = if ($entry.existed) {
            (Test-Path -LiteralPath $entry.path -PathType Leaf) -and
            ((Get-FileHash -LiteralPath $entry.path).Hash -eq (Get-FileHash -LiteralPath $entry.backup).Hash)
        } else { -not (Test-Path -LiteralPath $entry.path) }
        [pscustomobject]@{name=[IO.Path]::GetFileName($entry.path);restored=$restored}
    }
    $restoration | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'restoration.json') -Encoding utf8
    if (@($restoration | Where-Object { -not $_.restored }).Count -gt 0 -and -not $failure) {
        $failure = 'A benchmark-owned file was not restored.'
    }
}
if ($failure) { throw $failure }
$consumerText = Get-Content (Join-Path $OutputDirectory 'consumer.log') -Raw
if ($consumerText -notmatch 'openxr.lifecycle=stopped' -or $consumerText -notmatch 'result=pass') {
    throw 'Consumer completion evidence is missing.'
}
$fresh = [regex]::Match($consumerText,'openxr.fresh_shared_pairs=(\d+)')
if (-not $fresh.Success -or [uint64]$fresh.Groups[1].Value -lt 30) { throw 'Insufficient fresh stereo pairs for this benchmark.' }
$generatedFinal = [regex]::Match($consumerText,'openxr.generated_submitted_frames=(\d+)')
$generated = @([regex]::Matches($consumerText,'openxr.generated_stereo=submitted count=(\d+)'))
$generatedCount = if ($generatedFinal.Success) { [uint64]$generatedFinal.Groups[1].Value }
    elseif ($generated.Count) { [uint64]$generated[-1].Groups[1].Value } else { 0 }
if ($FrameGeneration -eq 'On' -and $generatedCount -lt 30) { throw 'Frame generation was requested but sustained generated stereo submission was not established.' }
if ($FrameGeneration -eq 'Off' -and $generatedCount -gt 0) { throw 'Generated stereo frames appeared in the Off control.' }
Write-Output "synthetic_benchmark.completed frame_generation=$FrameGeneration output=$OutputDirectory"
