[CmdletBinding()]
param(
    [string] $GameRoot,

    [string] $OutputPath,

    [switch] $SkipProximityApply,

    # Request flags this run is deliberately setting, so the stale-flag
    # gate does not refuse them.
    [string[]] $AllowFlags = @(),

    [switch] $RunXrSmoke,

    # Start a Ready run even though the Quest's controller radio is in a bad
    # state. The refusal exists because a worn session on a wedged radio is a
    # wasted one, but a run that is not about input should not be blocked by it.
    [switch] $AllowDegradedLink,

    [switch] $RuntimeD3D11Diagnostics,

    [switch] $ProbeSharedImportAdapters,

    [ValidateSet('Ready', 'Inventory')]
    [string] $Mode = 'Ready',

    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Release',

    [ValidateRange(120, 2400)]
    [int] $XrFrames = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'tools\stereo\resolve-darktide-game-root.ps1')
$gameRootPath = Resolve-DarktideGameRoot -GameRoot $GameRoot
$gameExe = Join-Path $gameRootPath 'binaries\Darktide.exe'
$modRoot = Join-Path $gameRootPath 'mods\darktidevr'
$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$luaSourceCheck = Join-Path $repoRoot `
    'tools\stereo\test-darktide-lua-source.ps1'
if (-not (Test-Path -LiteralPath $luaSourceCheck -PathType Leaf)) {
    throw "Lua source check not found: $luaSourceCheck"
}
& $luaSourceCheck
if ($Mode -eq 'Ready') {
    # Inventory remains observation-only; Ready must validate the package that
    # the selected game installation will load, not only development source.
    & $luaSourceCheck -SourcePath (Join-Path $modRoot `
        'scripts/mods/darktidevr/darktidevr.lua')
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot "artifacts\unattended\preflight-$timestamp.json"
}
$outputFullPath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($OutputPath)

function Get-AdbPath {
    $sdkAdb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (Test-Path -LiteralPath $sdkAdb -PathType Leaf) {
        return $sdkAdb
    }

    $command = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'adb.exe was not found in the Android SDK or PATH'
    }

    return $command.Source
}

function Get-FileIdentity([string] $Label, [string] $Path) {
    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    $item = if ($exists) { Get-Item -LiteralPath $Path } else { $null }

    [ordered]@{
        label = $Label
        exists = $exists
        relative_or_leaf = if ($Path.StartsWith($repoRoot,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            $Path.Substring($repoRoot.Length).TrimStart('\', '/')
        } else {
            Split-Path -Leaf $Path
        }
        size = if ($item) { $item.Length } else { $null }
        sha256 = if ($item) {
            (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        } else {
            $null
        }
    }
}

if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf)) {
    throw "Darktide executable not found: $gameExe"
}

. (Join-Path $PSScriptRoot 'xr-readiness.ps1')
$runtimeProperty = Get-ItemProperty `
    -Path 'HKLM:\SOFTWARE\Khronos\OpenXR\1' `
    -Name ActiveRuntime `
    -ErrorAction SilentlyContinue
$activeRuntime = if ($runtimeProperty) { $runtimeProperty.ActiveRuntime } else { '' }
$runtimeProfile = Get-XrRuntimeProfile -Runtime $activeRuntime
# Only the Virtual Desktop path has a Quest behind it. Under SteamVR the
# headset is on its own link and there is nothing for ADB to talk to, so the
# transport, the proximity override and the power dump are all skipped rather
# than failed.
$questExpected = $runtimeProfile -ne 'SteamVR'

# Flags from an earlier run change what the next one measures, and an
# interrupted or bugchecked run leaves them behind. Checked before the
# readiness gate so a stale flag stops the session rather than silently
# joining it.
$presentFlags = @(
    Get-ChildItem -LiteralPath $modRoot -Filter '*.flag' -File -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Name })
# The deployment's own flags come from the deployment's own manifest, so the
# gate cannot drift from what `sync-darktide-vr-dev.ps1` actually places.
$deployedFlags = @()
$deploymentManifest = Get-ChildItem `
    -LiteralPath (Join-Path $repoRoot 'artifacts\deployment-backups') `
    -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    ForEach-Object { Join-Path $_.FullName 'manifest.json' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if ($deploymentManifest) {
    try {
        $deployedFlags = Get-DeployedFlagNames `
            -Manifest (Get-Content -LiteralPath $deploymentManifest -Raw | ConvertFrom-Json)
    } catch {
        # A manifest that cannot be read is not a reason to refuse the run; it
        # is a reason to fall back to the stricter list and say so if that
        # then trips.
        $deployedFlags = @()
    }
}
if ($Mode -eq 'Ready') {
    Assert-NoStaleFlags -Present $presentFlags `
        -Allowed (@($PersistentModFlags) + @($deployedFlags)) -Expected $AllowFlags
}

$adb = Get-AdbPath
. (Join-Path $repoRoot 'tools/quest/resolve-quest-transport.ps1')
if ($RunXrSmoke) { $Mode = 'Ready' }
$authorizedDevices = @(
    & $adb devices |
        ForEach-Object {
            if ($_ -match '^([^\s]+)\s+device(?:\s|$)') { $Matches[1] }
        }
)
$deviceQueryExitCode = $LASTEXITCODE
if ($deviceQueryExitCode -ne 0 -and $Mode -eq 'Ready' -and $questExpected) {
    throw 'Failed to query authorized ADB devices'
}
$device = $null
$questModel = $null
$physicalQuestCount = $null
$duplicateTransports = $false
$deviceSelection = 'device_query_failed'
if ($deviceQueryExitCode -eq 0) {
    $questTransportSelection = Resolve-QuestTransport -Adb $adb -AuthorizedTransports $authorizedDevices
    $deviceSelection = $questTransportSelection.Status
    $device = $questTransportSelection.Device
    $questModel = $questTransportSelection.Model
    $physicalQuestCount = $questTransportSelection.PhysicalQuestCount
    $duplicateTransports = $questTransportSelection.DuplicateTransports
}
if ($Mode -eq 'Ready' -and $questExpected -and $deviceSelection -ne 'selected') {
    throw "Expected exactly one proven authorized Quest; selection status: $deviceSelection"
}
$proximityApplied = $false
$powerLines = @()
$powerExitCode = $null
if ($questExpected -and $deviceSelection -eq 'selected') {
    if ($Mode -eq 'Ready' -and -not $SkipProximityApply) {
        $broadcast = @(& $adb -s $device shell am broadcast `
            -a com.oculus.vrpowermanager.prox_close)
        if ($LASTEXITCODE -ne 0 -or
            ($broadcast -join "`n") -notmatch 'Broadcast completed: result=0(?:\s|$)') {
            throw 'Failed to apply the Quest proximity override'
        }
        $proximityApplied = $true
    }
    $powerLines = @(
        & $adb -s $device shell dumpsys power |
            Select-String -Pattern `
                'mWakefulness=|mProximityPositive=|mHoldingDisplaySuspendBlocker=' `
                -CaseSensitive:$false |
            ForEach-Object { $_.Line.Trim() }
    )
    $powerExitCode = $LASTEXITCODE
}

$vdProcesses = @(Get-Process 'VirtualDesktop.Streamer' -ErrorAction SilentlyContinue)
$steamVrProcesses = @(Get-Process vrserver -ErrorAction SilentlyContinue)
if ($Mode -eq 'Ready') {
    Assert-XrReadiness -StreamerCount $vdProcesses.Count -Runtime $activeRuntime `
        -PowerLines $powerLines -PowerExitCode $powerExitCode `
        -SteamVrServerCount $steamVrProcesses.Count
}

# The Quest's controller radio, read from its own log. On 18 September 2026 a
# worn session was lost to controllers dropping every few seconds, and the
# headset had been reporting failed reads of its own radio registers for
# eighteen minutes before that became noticeable. A run that starts on a wedged
# radio is a run whose input is unreliable, and nothing downstream can tell.
#
# Only where there is an ADB to ask: a Frame has none, and the readiness gate
# above already splits on that.
$linkHealth = $null
if ($adb -and (Get-XrRuntimeProfile -Runtime $activeRuntime) -eq 'VDXR') {
    try {
        $linkLog = @(& $adb logcat -d -t 20000 SyncBossFW:* SyncBossHAL:* '*:S' 2>&1)
        if ($LASTEXITCODE -eq 0) {
            $linkHealth = Get-ControllerLinkHealth -LogLines $linkLog
        }
    } catch {
        # A headset that cannot be read is already the readiness gate's
        # business; this check does not get its own opinion about it.
        $linkHealth = $null
    }
}
$linkMessage = Assert-ControllerLinkHealth -Health $linkHealth -Mode $Mode `
    -AllowDegradedLink:$AllowDegradedLink
if ($linkMessage) { Write-Warning $linkMessage }

$gameProcesses = @(Get-Process Darktide -ErrorAction SilentlyContinue)
$launcherProcesses = @(Get-Process Launcher -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($gameRootPath,
        [System.StringComparison]::OrdinalIgnoreCase) })
$crashProcesses = @(
    Get-Process CrashReporter, CrashifyUploader -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($gameRootPath,
            [System.StringComparison]::OrdinalIgnoreCase) }
)
$eac = Get-Service EasyAntiCheat_EOS -ErrorAction SilentlyContinue

$filePaths = @(
    @('game_executable', $gameExe),
    @('installed_mod_descriptor', (Join-Path $modRoot 'darktidevr.mod')),
    @('installed_mod_lua', (Join-Path $modRoot 'scripts\mods\darktidevr\darktidevr.lua')),
    @('installed_native_capture', (Join-Path $modRoot 'bin\darktidevr_native_capture.dll')),
    @('installed_d3d12_bootstrap', (Join-Path $gameRootPath 'binaries\d3d12.dll')),
    @('source_mod_lua', (Join-Path $repoRoot 'mods\darktidevr\scripts\mods\darktidevr\darktidevr.lua')),
    @('source_native_capture', (Join-Path $repoRoot "build\windows-vs2022\src\producer\$Configuration\darktidevr_native_capture.dll")),
    @('source_d3d12_bootstrap', (Join-Path $repoRoot "build\windows-vs2022\src\producer\$Configuration\d3d12.dll"))
)
$files = @($filePaths | ForEach-Object { Get-FileIdentity $_[0] $_[1] })

. (Join-Path $PSScriptRoot 'source-checkout-identity.ps1')
$sourceIdentity = Get-SourceCheckoutIdentity -Root $repoRoot

$xrSmoke = $null
$smokeFailure = $null
if ($Mode -eq 'Ready') {
    if (Get-Process darktidevr-xr-harness -ErrorAction SilentlyContinue) {
        throw 'Stop the existing XR viewer before running a new rendering preflight; use -Mode Inventory for a read-only report.'
    }
    $harness = Join-Path $repoRoot `
        "build\windows-vs2022\tests\xr_harness\$Configuration\darktidevr-xr-harness.exe"
    if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
        throw "$Configuration XR harness not found: $harness"
    }

    $smokeArguments = "--frames 30 --debug-layer --require-openxr --require-rendering --xr-frames $XrFrames"
    if ($RuntimeD3D11Diagnostics) { $smokeArguments += ' --runtime-d3d11-diagnostics' }
    if ($ProbeSharedImportAdapters) { $smokeArguments += ' --probe-shared-import-adapters' }
    $smokeProcess = Invoke-BoundedXrSmoke -FilePath $harness -Arguments $smokeArguments
    $smokeOutput = @($smokeProcess.output)
    $smokeExitCode = $smokeProcess.exit_code
    $resultLine = $smokeOutput | Where-Object { $_ -match '^result=' } |
        Select-Object -Last 1
    $stateLines = @($smokeOutput | Where-Object {
        $_ -match '^openxr\.(runtime_name|recommended_size|session_state|frames|submitted_frames|not_rendered_frames|submit_hz|lifecycle|extension\.XR_(EXT_frame_synthesis|FB_space_warp))='
    })
    $xrSmoke = [ordered]@{
        exit_code = $smokeExitCode
        timed_out = $smokeProcess.timed_out
        timeout_seconds = $smokeProcess.timeout_seconds
        output_complete = $smokeProcess.output_complete
        result = if ($resultLine) { $resultLine.Substring(7) } else { 'missing' }
        state = $stateLines
        output = $smokeOutput
    }
    if ($smokeProcess.timed_out -or -not $smokeProcess.output_complete) {
        $smokeFailure = "XR rendering test timed out or its output was incomplete. See $outputFullPath for runtime diagnostics; no restart was attempted."
    } elseif ($smokeExitCode -ne 0 -or $xrSmoke.result -ne 'pass') {
        $smokeFailure = "XR rendering is unavailable (exit $smokeExitCode, result $($xrSmoke.result)). See $outputFullPath for runtime diagnostics. If Quest passthrough suspended VD, resume streaming and retry; no restart was attempted."
    }
}

$report = [ordered]@{
    schema_version = 2
    mode = $Mode
    readiness_verified = ($Mode -eq 'Ready' -and -not $smokeFailure)
    captured_utc = (Get-Date).ToUniversalTime().ToString('o')
    git = $sourceIdentity
    quest = [ordered]@{
        authorized_device_count = $authorizedDevices.Count
        authorized_physical_quest_count = $physicalQuestCount
        duplicate_transports_resolved = $duplicateTransports
        selection = $deviceSelection
        device_query_exit_code = $deviceQueryExitCode
        model = $questModel
        proximity_override_applied = $proximityApplied
        power = $powerLines
    }
    runtime = [ordered]@{
        virtual_desktop_streamer_processes = $vdProcesses.Count
        steamvr_server_processes = $steamVrProcesses.Count
        active_openxr_runtime = $activeRuntime
        openxr_runtime_profile = $runtimeProfile
        quest_expected = $questExpected
        darktide_processes = $gameProcesses.Count
        launcher_processes = $launcherProcesses.Count
        crash_reporter_processes = $crashProcesses.Count
        eac_status = if ($eac) { $eac.Status.ToString() } else { 'not-installed' }
    }
    files = $files
    xr_smoke = $xrSmoke
}

$outputDirectory = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputFullPath -Encoding utf8

Write-Output "report=$outputFullPath"
$report | ConvertTo-Json -Depth 8
if ($smokeFailure) {
    throw $smokeFailure
}
