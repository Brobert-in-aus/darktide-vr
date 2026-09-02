[CmdletBinding()]
param(
    [ValidateRange(10, 1800)]
    [int] $TimeoutSeconds = 600,

    [switch] $StopAtCharacterSelect,

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

function Wait-DarktideLogMatch {
    param(
        [Parameter(Mandatory)]
        [string[]] $Patterns,

        [Parameter(Mandatory)]
        [datetime] $Deadline,

        [datetime] $NotBefore = [datetime]::MinValue
    )

    while ((Get-Date) -lt $Deadline) {
        $process = Get-Process Darktide -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    $_.Path -ieq $resolvedGameExe
                }
                catch {
                    $false
                }
            } |
            Select-Object -First 1
        if ($process) {
            $log = Get-ChildItem -LiteralPath $ConsoleLogRoot -Filter '*.log' `
                    -ErrorAction SilentlyContinue |
                Where-Object LastWriteTime -ge $NotBefore |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($log) {
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
        [string] $Keys
    )

    $shell = New-Object -ComObject WScript.Shell
    if (-not $shell.AppActivate($Process.Id)) {
        throw "Could not activate Darktide process $($Process.Id)"
    }
    Start-Sleep -Milliseconds 150
    $shell.SendKeys($Keys)
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
        Send-DarktideKey -Process $Process -Keys '{ENTER}'
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
Send-DarktideKey -Process $title -Keys ' '

$characterSelect = Wait-DarktideLogMatch -Patterns @(
    'Entering Game State StateMainMenu',
    'DARKTIDEVR_PRESENTATION open view=main_menu_view active=true',
    # MainMenuView exists before its selected operative has finished
    # streaming.  Enter sent in that interval is silently ignored, which made
    # nominal unattended runs stop at character select.  This stock spawner
    # completion is the first observed log-owned readiness boundary after
    # which the same Enter action is accepted.
    'UIProfileSpawner.*cb_on_unit_3p_streaming_complete'
) -Deadline $deadline -NotBefore $started
if ($StopAtCharacterSelect) {
    Write-Output 'Darktide title advanced to character select without mouse input.'
    return
}
Start-Sleep -Seconds 1
Wait-DarktideLeavesCharacterSelect -Process $characterSelect `
    -Deadline $deadline -NotBefore $started

Write-Output 'Darktide title and character select advanced without mouse input.'
