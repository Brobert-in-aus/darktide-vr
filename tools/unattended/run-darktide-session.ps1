# Unattended Darktide session on the standard-mod install (the game starts the
# viewer itself since 12 September 2026). Launches through Steam and the
# Fatshark launcher, advances to the requested scene with the mod's one-shot
# requests, holds, then quits through the in-game Quit route (session control
# flag) and records whether the game shut down cleanly.
#
# -ExternalViewer (implied by -SyntheticControllerPath or -RuntimeJson) makes
# the mod skip its own viewer and starts one here instead, so synthetic inputs
# or the OpenXR simulator runtime can be used while the headset is asleep.
# Every request file this script writes is restored in `finally`.
[CmdletBinding()]
param(
    [string] $GameRoot = 'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE',
    [ValidateSet('Title', 'Hub', 'Psykhanium')] [string] $Scene = 'Psykhanium',
    [ValidateRange(0, 7200)] [int] $HoldSeconds = 60,
    # Quit: in-game Quit route through the mod's request file. CloseWindow: the
    # window's close message (works without the mod, e.g. a flat-mode control).
    [ValidateSet('Quit', 'CloseWindow', 'LeaveRunning')] [string] $End = 'Quit',
    [switch] $ExternalViewer,
    # With -ExternalViewer semantics for the mod (it skips its viewer) but no
    # viewer at all: a control run for stereo-dependent behaviour.
    [switch] $NoViewer,
    [switch] $SyntheticControllerPath,
    [string] $RuntimeJson,
    # Other mod request files to set for this run, e.g. @{ 'darktidevr_gameplay_input_test.flag' = 'enabled' }.
    [hashtable] $RequestFiles = @{},
    [string] $OutputDirectory,
    [ValidateRange(60, 3600)] [int] $StartTimeoutSeconds = 900,
    [ValidateRange(10, 600)] [int] $ExitTimeoutSeconds = 180
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$modRoot = Join-Path $GameRoot 'mods\darktidevr'
$gameExe = (Resolve-Path -LiteralPath (Join-Path $GameRoot 'binaries\Darktide.exe')).Path
$consoleRoot = Join-Path $env:APPDATA 'Fatshark\Darktide\console_logs'
$viewerLogRoot = Join-Path $env:LOCALAPPDATA 'DarktideVR'
if ($SyntheticControllerPath -or $RuntimeJson) { $ExternalViewer = $true }
if ($NoViewer -and ($SyntheticControllerPath -or $RuntimeJson)) { throw '-NoViewer cannot be combined with a viewer option.' }
if ($RuntimeJson -and -not (Test-Path -LiteralPath $RuntimeJson -PathType Leaf)) { throw "Runtime JSON not found: $RuntimeJson" }
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot ("artifacts\unattended\session-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
if (Get-Process Darktide, darktidevr-xr-harness -ErrorAction SilentlyContinue) {
    throw 'Close Darktide and any viewer before an unattended session.'
}
. (Join-Path $repoRoot 'tools\stereo\psykhanium-launch-request.ps1')

$summary = [ordered]@{
    scene = $Scene; hold_seconds = $HoldSeconds; end = $End
    external_viewer = [bool]$ExternalViewer; no_viewer = [bool]$NoViewer; synthetic_controller_path = [bool]$SyntheticControllerPath
    runtime_json = $RuntimeJson; request_files = @($RequestFiles.Keys)
    started_utc = (Get-Date).ToUniversalTime().ToString('o')
}
$saved = @{}
function Set-RequestFile([string] $Name, [string] $Value) {
    $path = Join-Path $modRoot $Name
    if (-not $saved.ContainsKey($path)) {
        $saved[$path] = if (Test-Path -LiteralPath $path -PathType Leaf) { [IO.File]::ReadAllBytes($path) } else { $null }
    }
    Set-Content -LiteralPath $path -Value $Value -Encoding ascii
}
function Write-Summary { $summary | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDirectory 'summary.json') -Encoding utf8 }

$viewer = $null
$game = $null
$advance = $null
$psykhaniumRequest = $null
$consoleLog = $null
$launchStart = Get-Date
$stopFile = Join-Path $OutputDirectory 'viewer-stop.flag'
try {
    Remove-Item -LiteralPath (Join-Path $modRoot 'darktidevr_quit_game.flag') -ErrorAction SilentlyContinue
    Set-RequestFile 'darktidevr_start_character.flag' $(if ($Scene -eq 'Title') { 'disabled' } else { 'start' })
    $psykhaniumRequest = Set-PsykhaniumLaunchRequest -GameRoot $GameRoot -Action $(if ($Scene -eq 'Psykhanium') { 'enter' } else { 'disabled' })
    if ($ExternalViewer -or $NoViewer) { Set-RequestFile 'darktidevr_external_viewer.flag' 'external' }
    foreach ($name in $RequestFiles.Keys) { Set-RequestFile $name ([string]$RequestFiles[$name]) }

    if ($ExternalViewer) {
        # Same play configuration as the game-started viewer
        # (src/producer/viewer_process.cpp), deferred window capture because
        # the game window does not exist yet, plus the requested synthetic path.
        $harness = Join-Path $modRoot 'bin\darktidevr-xr-harness.exe'
        $arguments = @('--flush-log', '--shared-eyes', '--require-rendering', '--frames', '30',
            '--xr-seconds', ($StartTimeoutSeconds + $HoldSeconds + $ExitTimeoutSeconds + 300),
            '--capture-window-title', '"Warhammer 40,000: Darktide"', '--capture-window-deferred',
            '--enable-menu-input', '--enable-gameplay-reticle', '--projection-translation-scale', '1.0',
            '--stop-file', ('"' + $stopFile + '"'))
        if ($SyntheticControllerPath) { $arguments += '--synthetic-controller-path' }
        $priorRuntime = $env:XR_RUNTIME_JSON
        try {
            if ($RuntimeJson) { $env:XR_RUNTIME_JSON = (Resolve-Path -LiteralPath $RuntimeJson).Path }
            $viewer = Start-Process -FilePath $harness -ArgumentList $arguments -WindowStyle Hidden -PassThru `
                -WorkingDirectory (Split-Path $harness) `
                -RedirectStandardOutput (Join-Path $OutputDirectory 'viewer.log') `
                -RedirectStandardError (Join-Path $OutputDirectory 'viewer-error.log')
            $null = $viewer.Handle
            $deadline = (Get-Date).AddSeconds(30)
            do {
                Start-Sleep -Milliseconds 250
                $text = [string](Get-Content -LiteralPath (Join-Path $OutputDirectory 'viewer.log') -Raw -ErrorAction SilentlyContinue)
                $runtime = [regex]::Match($text, 'openxr\.runtime_name=([^\r\n]+)')
            } while (-not $runtime.Success -and -not $viewer.HasExited -and (Get-Date) -lt $deadline)
            if (-not $runtime.Success) { throw 'External viewer did not report an OpenXR runtime; see viewer.log.' }
            $summary.viewer_runtime = $runtime.Groups[1].Value.Trim()
        } finally {
            # A Steam client started by the protocol handler must not inherit it.
            $env:XR_RUNTIME_JSON = $priorRuntime
        }
    }

    $launchStart = Get-Date
    Start-Process 'steam://rungameid/1361210'
    & (Join-Path $repoRoot 'tools\stereo\invoke-darktide-launcher-play.ps1') -GameRoot $GameRoot -TimeoutSeconds 300 |
        Out-File (Join-Path $OutputDirectory 'launcher-play.log') -Encoding utf8
    $deadline = (Get-Date).AddSeconds($StartTimeoutSeconds)
    do {
        Start-Sleep -Seconds 1
        $game = Get-Process Darktide -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $gameExe } | Select-Object -First 1
    } while (-not $game -and (Get-Date) -lt $deadline)
    if (-not $game) { throw 'Darktide did not start.' }
    $null = $game.Handle
    $summary.game_pid = $game.Id

    if ($Scene -ne 'Title') {
        $powershell = (Get-Process -Id $PID).Path
        $advance = Start-Process -FilePath $powershell -WindowStyle Hidden -PassThru -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            ('"' + (Join-Path $repoRoot 'tools\stereo\advance-darktide-to-hub.ps1') + '"'),
            '-TimeoutSeconds', $StartTimeoutSeconds, '-GameExe', ('"' + $gameExe + '"'), '-GameProcessId', $game.Id) `
            -RedirectStandardOutput (Join-Path $OutputDirectory 'advance.log') `
            -RedirectStandardError (Join-Path $OutputDirectory 'advance-error.log')
    }

    $marker = switch ($Scene) {
        'Title' { 'Entering Game State StateTitle' }
        'Hub' { 'GameplayStateInit -> GameplayStateRun' }
        'Psykhanium' { 'DARKTIDEVR_PSYKHANIUM result=pass' }
    }
    $deadline = (Get-Date).AddSeconds($StartTimeoutSeconds)
    $reached = $false
    $windowSeen = $null
    do {
        Start-Sleep -Seconds 2
        if ($game.HasExited) { throw "Darktide exited before reaching $Scene." }
        if (-not $consoleLog) {
            $consoleLog = Get-ChildItem $consoleRoot -File -ErrorAction SilentlyContinue |
                Where-Object { $_.CreationTime -ge $launchStart.AddSeconds(-5) } |
                Sort-Object CreationTime | Select-Object -Last 1
        }
        if ($consoleLog) {
            $reached = [bool](Select-String -LiteralPath $consoleLog.FullName -SimpleMatch $marker -Quiet)
        }
        # Without the mod (flat-mode controls) the console log is buffered
        # until exit, so the title marker never appears in time. The title is
        # the first interactive screen; accept it once the window has been up
        # for 45 seconds.
        if (-not $reached -and $Scene -eq 'Title') {
            $game.Refresh()
            if ($game.MainWindowHandle -ne [IntPtr]::Zero) {
                if (-not $windowSeen) { $windowSeen = Get-Date }
                elseif (((Get-Date) - $windowSeen).TotalSeconds -ge 45) { $reached = $true; $summary.scene_assumed_from_window = $true }
            }
        }
    } while (-not $reached -and (Get-Date) -lt $deadline)
    $summary.scene_reached = $reached
    $summary.scene_reached_seconds = [math]::Round(((Get-Date) - $launchStart).TotalSeconds, 1)
    if (-not $reached) { throw "Did not reach $Scene within $StartTimeoutSeconds s." }

    $holdEnd = (Get-Date).AddSeconds($HoldSeconds)
    while ((Get-Date) -lt $holdEnd) {
        Start-Sleep -Seconds 2
        if ($game.HasExited) { throw 'Darktide exited during the hold.' }
    }

    if ($End -ne 'LeaveRunning') {
        if ($End -eq 'Quit') {
            Set-Content -LiteralPath (Join-Path $modRoot 'darktidevr_quit_game.flag') -Value 'quit' -Encoding ascii
        } else {
            $game.Refresh()
            $summary.close_message_sent = $game.CloseMainWindow()
        }
        $quitStart = Get-Date
        $exited = $game.WaitForExit($ExitTimeoutSeconds * 1000)
        $summary.exited = $exited
        $summary.exit_seconds = [math]::Round(((Get-Date) - $quitStart).TotalSeconds, 1)
        if ($exited) { $summary.exit_code = $game.ExitCode }
        else { throw "Darktide did not exit within $ExitTimeoutSeconds s of the quit request." }
    }
} catch {
    $summary.failure = [string]$_
} finally {
    if ($advance -and -not $advance.HasExited) { $advance.Kill() }
    if ($viewer) {
        Set-Content -LiteralPath $stopFile -Value 'stop' -Encoding ascii
        if (-not $viewer.WaitForExit(15000)) { $viewer.Kill(); $summary.viewer_killed = $true }
    }
    if ($End -ne 'LeaveRunning' -and $game -and -not $game.HasExited) {
        # Never leave an owned game behind; recorded as a forced stop.
        Stop-Process -Id $game.Id -Force
        $summary.game_force_stopped = $true
    }
    foreach ($path in $saved.Keys) {
        if ($null -ne $saved[$path]) { [IO.File]::WriteAllBytes($path, $saved[$path]) }
        elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if ($psykhaniumRequest) { Clear-PsykhaniumLaunchRequest -Request $psykhaniumRequest }
    if ($End -eq 'Quit') { Remove-Item -LiteralPath (Join-Path $modRoot 'darktidevr_quit_game.flag') -ErrorAction SilentlyContinue }
    if (-not $consoleLog) {
        $consoleLog = Get-ChildItem $consoleRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationTime -ge $launchStart.AddSeconds(-5) } |
            Sort-Object CreationTime | Select-Object -Last 1
    }
    if ($consoleLog) {
        Start-Sleep -Seconds 2
        Copy-Item -LiteralPath $consoleLog.FullName -Destination (Join-Path $OutputDirectory 'console.log') -Force
        $text = Get-Content -LiteralPath $consoleLog.FullName -Raw
        $crash = [regex]::Match($text, '<<Crash>>([^\r\n]*)')
        $summary.console_log = $consoleLog.Name
        $summary.crash = $crash.Success
        if ($crash.Success) {
            $summary.crash_line = $crash.Groups[1].Value.Trim()
            $summary.crash_shutdown = [bool]([regex]::Match($text, 'shutdown = true').Success)
        }
        $quit = [regex]::Match($text, 'DARKTIDEVR_SESSION quit_requested source=flag route=(\S+)')
        if ($quit.Success) { $summary.quit_route = $quit.Groups[1].Value }
    }
    if ($game) {
        $viewerLog = Join-Path $viewerLogRoot "viewer-$($game.Id).log"
        if (Test-Path -LiteralPath $viewerLog) { Copy-Item -LiteralPath $viewerLog -Destination (Join-Path $OutputDirectory 'game-viewer.log') -Force }
    }
    # A fault after the engine's own log ends never reaches the game's crash
    # handler; Windows Error Reporting records it instead.
    if ($game -and $summary.Contains('exit_code') -and $summary.exit_code -ne 0) {
        $events = @(Get-WinEvent -FilterHashtable @{LogName = 'Application'; ProviderName = 'Application Error'; StartTime = $launchStart} -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match 'Darktide\.exe' -and $_.Message -match ('0x{0:x}' -f $game.Id) })
        if ($events) {
            $offset = [regex]::Match($events[0].Message, 'Fault offset: (0x[0-9a-fA-F]+)')
            $module = [regex]::Match($events[0].Message, 'Faulting module name: ([^,\r\n]+)')
            $summary.wer_fault = ('{0}+{1}' -f $module.Groups[1].Value.Trim(), $offset.Groups[1].Value)
        }
    }
    $summary.finished_utc = (Get-Date).ToUniversalTime().ToString('o')
    Write-Summary
}
$summary | ConvertTo-Json -Depth 4
if ($summary.Contains('failure')) { exit 1 }
