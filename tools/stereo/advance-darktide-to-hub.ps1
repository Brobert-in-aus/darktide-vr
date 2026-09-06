[CmdletBinding()]
param(
    [ValidateRange(10, 1800)]
    [int] $TimeoutSeconds = 600,

    [switch] $StopAtCharacterSelect,

    [int] $GameProcessId = 0,

    [string] $GameExe =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\binaries\Darktide.exe',

    [string] $ConsoleLogRoot =
        (Join-Path $env:APPDATA 'Fatshark\Darktide\console_logs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $GameExe -PathType Leaf)) {
    throw "Darktide executable not found: $GameExe"
}
$resolvedGameExe = (Resolve-Path -LiteralPath $GameExe).Path
$script:ownedProcess = $null
$script:ownedProcessStart = $null
$script:ownedLogPath = $null
$script:startupKeyAttempts = @{ StateTitle = 0; StateMainMenu = 0 }

function Assert-DarktideStartupOwner {
    if (-not $script:ownedProcess) { return }
    $current = Get-Process -Id $script:ownedProcess.Id -ErrorAction SilentlyContinue
    if (-not $current -or $current.StartTime -ne $script:ownedProcessStart) {
        throw 'The launch-owned Darktide process exited; startup automation is finished.'
    }
}

function Get-DarktideStartupState {
    if (-not $script:ownedLogPath) { return '' }
    $text = Get-Content -LiteralPath $script:ownedLogPath -Raw -ErrorAction SilentlyContinue
    if (-not $text) { return '' }
    $states = [regex]::Matches($text, 'Entering Game State (State[A-Za-z0-9_]+)')
    if (-not $states.Count) { return '' }
    return $states[$states.Count - 1].Groups[1].Value
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DarktideStartupFocus {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
}
'@

function Wait-DarktideLogMatch {
    param(
        [Parameter(Mandatory)]
        [string[]] $Patterns,

        [Parameter(Mandatory)]
        [datetime] $Deadline,

        [datetime] $NotBefore = [datetime]::MinValue
    )

    while ((Get-Date) -lt $Deadline) {
        Assert-DarktideStartupOwner
        $process = Get-Process Darktide -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    $_.Path -ieq $resolvedGameExe -and
                        ($GameProcessId -eq 0 -or $_.Id -eq $GameProcessId) -and
                        (-not $script:ownedProcess -or $_.Id -eq $script:ownedProcess.Id)
                }
                catch {
                    $false
                }
            } |
            Select-Object -First 1
        if ($process) {
            if (-not $script:ownedProcess) {
                $script:ownedProcess = $process
                $script:ownedProcessStart = $process.StartTime
            }
            $log = if ($script:ownedLogPath) {
                Get-Item -LiteralPath $script:ownedLogPath -ErrorAction SilentlyContinue
            } else { Get-ChildItem -LiteralPath $ConsoleLogRoot -Filter '*.log' `
                    -ErrorAction SilentlyContinue |
                # Windows may retain the creation-time LastWriteTime until the
                # game closes its log handle. Bind by process/log creation.
                Where-Object { $_.CreationTime -ge $script:ownedProcessStart.AddSeconds(-1) } |
                Sort-Object CreationTime -Descending |
                Select-Object -First 1
            }
            if ($log) {
                $script:ownedLogPath = $log.FullName
                $text = Get-Content -LiteralPath $log.FullName -Raw `
                    -ErrorAction SilentlyContinue
                $matched = $true
                foreach ($pattern in $Patterns) {
                    if ($text -notmatch $pattern) {
                        $matched = $false
                        break
                    }
                }
                if ($matched) {
                    return $process
                }
            }
        }
        Start-Sleep -Milliseconds 250
    }
    throw "Timed out waiting for Darktide state: $($Patterns -join ', ')"
}

function Send-DarktideKey {
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process,

        [Parameter(Mandatory)]
        [string] $Keys,

        [Parameter(Mandatory)]
        [string] $ExpectedState
    )

    Assert-DarktideStartupOwner
    # A readiness line remains in the log after the player advances manually.
    # Check the newest state before sending, not after the first key attempt.
    if ((Get-DarktideStartupState) -ne $ExpectedState) { return }
    # Alt-Tab belongs to the user. Retry state observation in the caller, but
    # never activate the game or send keys to another foreground application.
    $foregroundProcessId = [uint32] 0
    [DarktideStartupFocus]::GetWindowThreadProcessId(
        [DarktideStartupFocus]::GetForegroundWindow(),
        [ref] $foregroundProcessId) | Out-Null
    if ($foregroundProcessId -ne $Process.Id) { return }
    $shell = New-Object -ComObject WScript.Shell
    $shell.SendKeys($Keys)
    ++$script:startupKeyAttempts[$ExpectedState]
}

function Wait-DarktideLeavesTitle {
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process,

        [Parameter(Mandatory)]
        [datetime] $Deadline,

        [Parameter(Mandatory)]
        [datetime] $NotBefore
    )

    # StateTitle is logged before its foreground input becomes reliable.  A
    # single Space can therefore be delivered successfully but discarded by
    # the title view. Retry only while waiting for the next log-owned state
    # boundary so input cannot leak through character select or into the hub.
    while ((Get-Date) -lt $Deadline) {
        Send-DarktideKey -Process $Process -Keys ' ' -ExpectedState 'StateTitle'
        $retryDeadline = (Get-Date).AddSeconds(2)
        if ($retryDeadline -gt $Deadline) {
            $retryDeadline = $Deadline
        }
        try {
            Wait-DarktideLogMatch -Patterns @(
                'Entering Game State StateMainMenu'
            ) -Deadline $retryDeadline -NotBefore $NotBefore | Out-Null
            return
        }
        catch {
            # Retry until the overall launch deadline. The state gate above
            # stops retries as soon as character select begins loading.
        }
    }
    throw 'Timed out advancing Darktide from the title screen.'
}

function Wait-DarktideLeavesCharacterSelect {
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process,

        [Parameter(Mandatory)]
        [datetime] $Deadline,

        [Parameter(Mandatory)]
        [datetime] $NotBefore
    )

    # Character-select can silently discard a correctly delivered Enter while
    # its selected operative or foreground focus is settling.  A single input
    # therefore is not a reliable unattended boundary.  Retry only Enter and
    # stop as soon as the log proves that StateMainMenu has begun leaving; this
    # avoids advancing any subsequent gameplay UI.
    while ((Get-Date) -lt $Deadline) {
        Send-DarktideKey -Process $Process -Keys '{ENTER}' -ExpectedState 'StateMainMenu'
        $retryDeadline = (Get-Date).AddSeconds(2)
        if ($retryDeadline -gt $Deadline) {
            $retryDeadline = $Deadline
        }
        try {
            Wait-DarktideLogMatch -Patterns @(
                'Entering Game State StateMainMenu',
                'Entering Game State StateLoading'
            ) -Deadline $retryDeadline -NotBefore $NotBefore | Out-Null
            return
        }
        catch {
            # Retry until the overall launch deadline.  The state gate above
            # ensures that repeated input cannot leak past character select.
        }
    }
    throw 'Timed out advancing Darktide from character select.'
}

$started = Get-Date
$deadline = $started.AddSeconds($TimeoutSeconds)
$title = Wait-DarktideLogMatch -Patterns @(
    'Entering Game State StateTitle'
) -Deadline $deadline -NotBefore $started
Start-Sleep -Seconds 1
Wait-DarktideLeavesTitle -Process $title `
    -Deadline $deadline -NotBefore $started

$characterSelect = Wait-DarktideLogMatch -Patterns @(
    'Entering Game State StateMainMenu',
    'DARKTIDEVR_PRESENTATION open view=main_menu_view active=true',
    # Current game logs no longer emit the old UIProfileSpawner completion.
    # The mod observes the actual stock Start widget and input gates instead.
    'DARKTIDEVR_MENU_READINESS view=main_menu .*start_ready=true reason=ready'
) -Deadline $deadline -NotBefore $started
if ($StopAtCharacterSelect) {
    Write-Output 'Darktide title advanced to character select without mouse input.'
    return
}
Start-Sleep -Seconds 1
Wait-DarktideLeavesCharacterSelect -Process $characterSelect `
    -Deadline $deadline -NotBefore $started

Write-Output 'Darktide title and character select advanced without mouse input.'
Write-Output "startup.character_select.enter_attempts=$($script:startupKeyAttempts.StateMainMenu)"
