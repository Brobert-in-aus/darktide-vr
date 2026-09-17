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
    # Select this character card (by its name) before pressing Play, so a run
    # carries a particular loadout. Empty: whichever card is selected.
    [string] $StartCharacter = '',
    # Other mod request files to set for this run, e.g. @{ 'darktidevr_gameplay_input_test.flag' = 'enabled' }.
    [hashtable] $RequestFiles = @{},
    # After the scene is reached: open and close stock chat this many times
    # through the session control request file (open-chat stutter checks).
    [ValidateRange(0, 20)] [int] $ChatCycles = 0,
    # With -ChatCycles: toggle one engine call instead of chat (clip, show, cursor).
    [ValidateSet('', 'clip', 'show', 'cursor')] [string] $ChatProbe = '',
    # With -ChatCycles: log engine resource and GUI creation around each action.
    [switch] $ChatTrace,
    # Extra arguments for an external viewer, e.g. @('--debug-layer').
    [string[]] $ViewerArguments = @(),
    [string] $OutputDirectory,
    [ValidateRange(60, 3600)] [int] $StartTimeoutSeconds = 900,
    [ValidateRange(10, 600)] [int] $ExitTimeoutSeconds = 180,
    # Seconds into the hold at which to ask the viewer for an eye readback.
    # The viewer serves %TEMP%\darktidevr-projected-eye-readback.request and
    # writes one PPM per eye; nothing automated that before, so every readback
    # was hand-driven and none was repeatable (18 September survey).
    [int[]] $EyeReadbackAtSeconds = @()
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$modRoot = Join-Path $GameRoot 'mods\darktidevr'
$gameExe = (Resolve-Path -LiteralPath (Join-Path $GameRoot 'binaries\Darktide.exe')).Path
$consoleRoot = Join-Path $env:APPDATA 'Fatshark\Darktide\console_logs'
$viewerLogRoot = Join-Path $env:LOCALAPPDATA 'DarktideVR'
if ($SyntheticControllerPath -or $RuntimeJson -or $ViewerArguments.Count -gt 0) { $ExternalViewer = $true }
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
    # Every request the mod reads is a *.flag; a bare name would write a file
    # nothing polls, and the run would silently measure nothing (16 September).
    if ($Name -notlike '*.flag') { $Name += '.flag' }
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
    Set-RequestFile 'darktidevr_start_character.flag' $(if ($Scene -eq 'Title') { 'disabled' } elseif ($StartCharacter) { "start:$StartCharacter" } else { 'start' })
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
        $arguments += $ViewerArguments
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

    if ($ChatCycles -gt 0) {
        Set-Content -LiteralPath (Join-Path $modRoot 'darktidevr_quit_game.flag') -Value $(if ($ChatProbe) { "probe $ChatProbe $ChatCycles" } else { "chat $ChatCycles" + $(if ($ChatTrace) { ' trace' } else { '' }) }) -Encoding ascii
        $summary.chat_cycles = $ChatCycles
        $HoldSeconds = [math]::Max($HoldSeconds, $ChatCycles * 6 + 10)
        $summary.hold_seconds = $HoldSeconds
    }
    $holdEnd = (Get-Date).AddSeconds($HoldSeconds)
    $holdMid = (Get-Date).AddSeconds($HoldSeconds / 2)
    $midSampled = $false
    # Eye readbacks: a stale request file from an earlier run would be served
    # at once and the PPMs would show that run's frame (16 September), so
    # clear both the request and the outputs before the first one.
    # Two kinds, asked for together. The shared-eye readback is the game's
    # own rendered pair and is written in ordinary gameplay; the projected one
    # is what the viewer submits, but it is only copied on a frame that draws
    # the tracked cuffs or a board, so on its own a gameplay run consumes the
    # request and writes nothing (18 September).
    $readbackRequests = @(
        (Join-Path $env:TEMP 'darktidevr-shared-eye-readback.request'),
        (Join-Path $env:TEMP 'darktidevr-projected-eye-readback.request'))
    $readbackOutputs = @('darktidevr-shared-eye-left.ppm', 'darktidevr-shared-eye-right.ppm',
        'darktidevr-projected-eye-left.ppm', 'darktidevr-projected-eye-right.ppm')
    $readbackSchedule = @()
    if ($EyeReadbackAtSeconds.Count -gt 0) {
        foreach ($request in $readbackRequests) {
            Remove-Item -LiteralPath $request -ErrorAction SilentlyContinue
        }
        foreach ($name in $readbackOutputs) {
            Remove-Item -LiteralPath (Join-Path $env:TEMP $name) -ErrorAction SilentlyContinue
        }
        $holdStart = Get-Date
        foreach ($offset in ($EyeReadbackAtSeconds | Sort-Object)) {
            $readbackSchedule += [pscustomobject]@{
                At = $holdStart.AddSeconds([math]::Min($offset, [math]::Max(0, $HoldSeconds - 5)))
                Offset = $offset
                Taken = $false
            }
        }
        $summary.eye_readbacks = @()
    }
    while ((Get-Date) -lt $holdEnd) {
        Start-Sleep -Seconds 2
        if ($game.HasExited) { throw 'Darktide exited during the hold.' }
        if (-not $midSampled -and (Get-Date) -ge $holdMid) {
            # The headset's wakefulness and the streamer's presence at the
            # hold's midpoint: a run whose headset slept sees less encoder
            # contention and is not comparable (16 September, hub-gpuprio-high1).
            # Guarded: never fails the run, records 'unknown' when adb or the
            # device is unavailable.
            $midSampled = $true
            $summary.headset_wakefulness_mid = 'unknown'
            try {
                $adbCandidate = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
                if (-not (Test-Path -LiteralPath $adbCandidate -PathType Leaf)) {
                    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
                    $adbCandidate = if ($adbCommand) { $adbCommand.Source } else { $null }
                }
                if ($adbCandidate) {
                    # The Quest is usually two transports (USB and Wi-Fi), and a
                    # bare `adb shell` refuses with "more than one device"; take
                    # the first authorized serial, preferring the USB one (no
                    # colon), as the preflight's transport resolver does.
                    $serials = @(& $adbCandidate devices 2>$null |
                        Select-String -Pattern '^(\S+)\s+device\s*$' |
                        ForEach-Object { $_.Matches[0].Groups[1].Value })
                    $serial = @($serials | Where-Object { $_ -notmatch ':' })[0]
                    if (-not $serial) { $serial = $serials[0] }
                    $adbArguments = @()
                    if ($serial) { $adbArguments = @('-s', $serial) }
                    $powerLines = @(& $adbCandidate @adbArguments shell dumpsys power 2>$null)
                    $wake = ($powerLines | Select-String -Pattern 'mWakefulness=(\w+)' | Select-Object -First 1)
                    if ($wake) { $summary.headset_wakefulness_mid = $wake.Matches[0].Groups[1].Value }
                    $summary.headset_serial_mid = $serial
                }
            } catch {}
            try {
                $summary.streamer_processes_mid = @(Get-Process -Name 'VirtualDesktop.Streamer' -ErrorAction SilentlyContinue).Count
            } catch {}
        }
        foreach ($readback in $readbackSchedule) {
            if ($readback.Taken -or (Get-Date) -lt $readback.At) { continue }
            $readback.Taken = $true
            $record = [ordered]@{ offset_seconds = $readback.Offset; served = $false; files = @() }
            try {
                foreach ($request in $readbackRequests) {
                    Set-Content -LiteralPath $request -Value 'readback' -Encoding ascii
                }
                # The viewer polls each request four times a second and writes
                # its eyes on the next frame that can serve it.
                $deadline = (Get-Date).AddSeconds(20)
                while ((Get-Date) -lt $deadline -and
                        @($readbackRequests | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0) {
                    Start-Sleep -Milliseconds 250
                }
                $record.served = @($readbackRequests | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0
                Start-Sleep -Seconds 1
                foreach ($name in $readbackOutputs) {
                    $source = Join-Path $env:TEMP $name
                    if (-not (Test-Path -LiteralPath $source)) { continue }
                    $destination = Join-Path $outputDirectory ("eye-{0}s-{1}" -f $readback.Offset, $name)
                    Copy-Item -LiteralPath $source -Destination $destination -Force
                    $item = Get-Item -LiteralPath $destination
                    # A PPM's own header carries the size the viewer wrote, so
                    # the summary records what was captured rather than what
                    # anything assumed (the analysers still default to 2112).
                    $reader = [System.IO.File]::OpenRead($destination)
                    $bytes = New-Object byte[] 32
                    [void]$reader.Read($bytes, 0, 32)
                    $reader.Close()
                    $text = ([System.Text.Encoding]::ASCII.GetString($bytes) -split "`n")
                    $record.files += [ordered]@{
                        name = $item.Name
                        bytes = $item.Length
                        extent = if ($text.Count -ge 2) { $text[1] } else { 'unknown' }
                    }
                    Remove-Item -LiteralPath $source -ErrorAction SilentlyContinue
                }
            } catch {
                $record.error = $_.Exception.Message
            }
            $summary.eye_readbacks += $record
        }
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
        if ($ChatCycles -gt 0) {
            $summary.chat_actions = @([regex]::Matches($text, 'DARKTIDEVR_SESSION (?:chat|probe)_(open|close|\w+_on|\w+_off) ') | ForEach-Object { $_.Groups[1].Value }).Count
            $summary.chat_frame_spikes = @([regex]::Matches($text, 'DARKTIDEVR_SESSION frame_spike dt_ms=([0-9.]+) since_(\w+)_ms=([0-9.]+)') |
                ForEach-Object { '{0} {1}ms after {2}' -f $_.Groups[1].Value, $_.Groups[3].Value, $_.Groups[2].Value })
        }
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
