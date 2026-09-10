[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('On','Off')] [string] $FrameGeneration,
    [ValidateSet('Preserve','Unlimited','30','40','60','72','90','120')] [string] $FrameRateLimit = 'Preserve',
    [ValidateSet(90,120)] [int] $SimulatorRefreshRate = 90,
    [switch] $ClusterLightTrace,
    [switch] $ObserveDlssSrInputs,
    [string] $RenderWorldCensusSourcePath,
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
    [ValidateRange(512,4096)] [int] $EyeWidth = 2112,
    [ValidateRange(512,4096)] [int] $EyeHeight = 2304
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'resolve-darktide-game-root.ps1')
. (Join-Path $PSScriptRoot 'synthetic-framegen-settings.ps1')
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
$luaTrialFiles = @{}
if($RenderWorldCensusWarmupFrames -ne 120 -and -not $RenderWorldCensusSourcePath) {
    throw 'A custom census warm-up requires the focused census Lua source.'
}
if($RenderWorldCensusSourcePath -or $ExpectedInstalledLuaSha256) {
    if(-not $RenderWorldCensusSourcePath -or $ExpectedInstalledLuaSha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'A census Lua trial requires a source path and the installed main Lua hash.'
    }
    $RenderWorldCensusSourcePath = (Resolve-Path -LiteralPath $RenderWorldCensusSourcePath).Path
    & (Join-Path $PSScriptRoot 'test-darktide-lua-source.ps1') -SourcePath $RenderWorldCensusSourcePath
    foreach($name in @('darktidevr_stereo_probe.lua','darktidevr_render_world_census.lua')) {
        $luaTrialFiles[(Join-Path $luaDirectory $name)] = [IO.File]::ReadAllBytes(
            (Join-Path (Split-Path $RenderWorldCensusSourcePath) $name))
    }
}
$simulatorSettings = Join-Path $env:LOCALAPPDATA 'OpenXR-Simulator/settings.json'
$mutex = [Threading.Mutex]::new($false,'Local\DarktideVR-synthetic-framegen-benchmark')
$ownsMutex = $false
$saved = @{}
$consumer = $null
$failure = $null
$priorRuntime = $env:XR_RUNTIME_JSON
$priorPairWait = $env:DTVR_XR_PRECISE_PAIR_WAIT
$priorSimulatorRefresh = $env:DTVR_SIMULATOR_REFRESH_HZ
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
    if($RenderWorldCensusSourcePath) {
        if((Get-FileHash (Join-Path $luaDirectory 'darktidevr_stereo_probe.lua')).Hash -ne $ExpectedInstalledLuaSha256) {
            throw 'Installed Lua baseline changed.'
        }
        foreach($path in $luaTrialFiles.Keys) { Save-BenchmarkFile $path }
        Save-BenchmarkFile $censusFlag
    }
    # The launcher temporarily owns these flags too. The outer byte backups
    # preserve even a pre-existing malformed/legacy file exactly after the run.
    $flagNames = @('probe','input_snapshot_probe','target_token_probe','eye_target_probe',
        'stereo_swapchain_probe','stereo_stage_probe','stereo_submit_probe') |
        ForEach-Object { "darktidevr_streamline_$_.flag" }
    $flagNames += 'darktidevr_ngx_output_probe.flag'
    foreach ($name in $flagNames) { Save-BenchmarkFile (Join-Path $modPath $name) }
    $clusterTraceFlag = Join-Path $modPath 'bin/darktidevr_cluster_trace.flag'
    if($ClusterLightTrace) { Save-BenchmarkFile $clusterTraceFlag }
    $nativeTargets = @((Join-Path $GameRoot 'binaries/darktidevr_native_capture.dll'),
        (Join-Path $modPath 'bin/darktidevr_native_capture.dll'))
    if ($NativeDllPath) {
        foreach ($path in $nativeTargets) {
            if ((Get-FileHash $path -Algorithm SHA256).Hash -ne $ExpectedInstalledNativeSha256) { throw 'Installed native baseline changed.' }
            Save-BenchmarkFile $path
        }
    }
    $settings = [IO.File]::ReadAllText($SettingsPath)
    $enabled = $FrameGeneration -eq 'On'
    $settings = ConvertTo-SyntheticFramegenSettings -Settings $settings -Enabled $enabled -FrameRateLimit $FrameRateLimit
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
    if ($NativeDllPath) {
        foreach ($path in $nativeTargets) { [IO.File]::WriteAllBytes($path,[IO.File]::ReadAllBytes($NativeDllPath)) }
    }
    if($RenderWorldCensusSourcePath) {
        foreach($path in $luaTrialFiles.Keys) { [IO.File]::WriteAllBytes($path,$luaTrialFiles[$path]) }
        [IO.File]::WriteAllText($censusFlag,"enabled`r`nwarmup=$RenderWorldCensusWarmupFrames`r`n")
        & (Join-Path $PSScriptRoot 'test-darktide-lua-source.ps1') -SourcePath (Join-Path $luaDirectory 'darktidevr_stereo_probe.lua')
    }
    [IO.File]::WriteAllText($SettingsPath,$settings,[Text.UTF8Encoding]::new($false))
    if($ClusterLightTrace) { [IO.File]::WriteAllText($clusterTraceFlag,"enabled=1`r`n") }
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
    $simSettings['preview_fps']=0
    $simSettings | ConvertTo-Json | Set-Content -LiteralPath $simulatorSettings -Encoding utf8
    $env:XR_RUNTIME_JSON = $RuntimeJson
    $env:DTVR_XR_PRECISE_PAIR_WAIT = '1'
    $env:DTVR_SIMULATOR_REFRESH_HZ = [string]$SimulatorRefreshRate
    $receipt = [ordered]@{
        frame_generation=$FrameGeneration; frames_to_generate=1
        frame_rate_limit=$FrameRateLimit
        simulator_refresh_hz=$SimulatorRefreshRate
        eye_width=$EyeWidth; eye_height=$EyeHeight; ssw='not_applicable_simulator'
        runtime_json=$RuntimeJson; runtime_sha256=$RuntimeSha256
        harness_sha256=(Get-FileHash $HarnessPath -Algorithm SHA256).Hash
        native_sha256=(Get-FileHash (Join-Path $GameRoot 'binaries/darktidevr_native_capture.dll') -Algorithm SHA256).Hash
        duration_seconds=$DurationSeconds; preview_fps=0; physical_xr_ready=$false
        cluster_trace=(Test-Path -LiteralPath $clusterTraceFlag)
        observe_dlss_sr_inputs=$ObserveDlssSrInputs.IsPresent
        render_world_census=(Test-Path -LiteralPath $censusFlag)
        render_world_census_warmup=$RenderWorldCensusWarmupFrames
        lua_sha256=(Get-FileHash (Join-Path $luaDirectory 'darktidevr_stereo_probe.lua')).Hash
    }
    $receipt | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'configuration.json') -Encoding utf8
    # This consumer is also the sole synthetic head publisher. Do not launch
    # SyntheticRuntimeFrusta beside it: two writers would race on pose metadata.
    $consumer = Start-Process -FilePath $HarnessPath -WindowStyle Hidden -PassThru `
        -ArgumentList @('--flush-log','--shared-eyes','--require-rendering','--enable-gameplay-reticle',
            '--xr-seconds',($StartupTimeoutSeconds+$DurationSeconds+60), '--stop-file',('"'+$stopFile+'"')) `
        -RedirectStandardOutput (Join-Path $OutputDirectory 'consumer.log') `
        -RedirectStandardError (Join-Path $OutputDirectory 'consumer-error.log')
    $consumerReadyDeadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 100
        $consumer.Refresh()
        if ($consumer.HasExited) { throw 'Simulator consumer failed before launch; inspect consumer-error.log.' }
        $initialLog = Get-Content (Join-Path $OutputDirectory 'consumer.log') -Raw
        $consumerReady = $initialLog -match 'openxr.runtime_name=OpenXR Simulator Runtime' -and
            $initialLog -match 'openxr.render_projection=recentered-symmetric'
    } while (-not $consumerReady -and (Get-Date) -lt $consumerReadyDeadline)
    if (-not $consumerReady) { throw 'Expected simulator session did not become active.' }
    & (Join-Path $PSScriptRoot 'start-darktide-vr.ps1') -GameRoot $GameRoot `
        -OfflineDualViewBenchmark -SkipDeploymentSync -DlssGeneratedStereo:$enabled `
        -ObserveDlssSrInputs:$ObserveDlssSrInputs `
        -DurationSeconds $DurationSeconds -GameStartTimeoutSeconds $StartupTimeoutSeconds `
        *> (Join-Path $OutputDirectory 'launch.log')
} catch { $failure = $_ }
finally {
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
    $gamePidMatch = [regex]::Match($launchText,'Authenticated Darktide process started: PID (\d+)\.')
    if ($gamePidMatch.Success) {
        $gamePidText = $gamePidMatch.Groups[1].Value
        foreach ($name in @("darktidevr-generated-stereo-$gamePidText.log",
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
