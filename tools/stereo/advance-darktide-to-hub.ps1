[CmdletBinding()]
param(
    [ValidateRange(10, 1800)]
    [int] $TimeoutSeconds = 600,

    [switch] $StopAtCharacterSelect,

    [string] $ConsoleLogRoot =
        (Join-Path $env:APPDATA 'Fatshark\Darktide\console_logs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

$started = Get-Date
$deadline = $started.AddSeconds($TimeoutSeconds)
$title = Wait-DarktideLogMatch -Patterns @(
    'Entering Game State StateTitle'
) -Deadline $deadline -NotBefore $started
Start-Sleep -Seconds 1
Send-DarktideKey -Process $title -Keys ' '

$characterSelect = Wait-DarktideLogMatch -Patterns @(
    'Entering Game State StateMainMenu',
    'DARKTIDEVR_PRESENTATION open view=main_menu_view active=true'
) -Deadline $deadline -NotBefore $started
if ($StopAtCharacterSelect) {
    Write-Output 'Darktide title advanced to character select without mouse input.'
    return
}
Start-Sleep -Seconds 1
Send-DarktideKey -Process $characterSelect -Keys '{ENTER}'

Write-Output 'Darktide title and character select advanced without mouse input.'
