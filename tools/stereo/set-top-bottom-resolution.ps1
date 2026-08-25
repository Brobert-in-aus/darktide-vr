[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Apply', 'Inspect', 'Restore')]
    [string] $Action,

    [string] $SettingsPath =
        (Join-Path $env:APPDATA 'Fatshark\Darktide\user_settings.config'),

    [string] $BackupPath =
        (Join-Path $PSScriptRoot '..\..\artifacts\phase1\render-settings\user_settings.pre-top-bottom.config')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$settings = [System.IO.Path]::GetFullPath($SettingsPath)
$backup = [System.IO.Path]::GetFullPath($BackupPath)

if (Get-Process -Name Darktide -ErrorAction SilentlyContinue) {
    throw 'Close Darktide before changing its display settings.'
}

if ($Action -eq 'Restore') {
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
        throw "Top/bottom settings backup not found: $backup"
    }
    Copy-Item -LiteralPath $backup -Destination $settings -Force
    Write-Output "Restored Darktide display settings from $backup"
    exit 0
}

$text = [System.IO.File]::ReadAllText($settings)
if ($Action -eq 'Inspect') {
    [regex]::Matches(
        $text,
        '(?ms)^\s*(screen_resolution|last_fullscreen_resolution)\s*=\s*\[.*?\]'
    ).Value
    [regex]::Matches(
        $text,
        '(?m)^\s*(screen_mode|fullscreen)\s*=.*$'
    ).Value
    exit 0
}

if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force |
        Out-Null
    Copy-Item -LiteralPath $settings -Destination $backup
}

$resolutionPattern =
    '(?ms)^(?<indent>\s*)(?<name>screen_resolution|last_fullscreen_resolution)\s*=\s*\[.*?\]'
$resolutionMatches = [regex]::Matches($text, $resolutionPattern)
if ($resolutionMatches.Count -ne 4) {
    throw "Expected four resolution arrays; found $($resolutionMatches.Count)."
}
$text = [regex]::Replace(
    $text,
    $resolutionPattern,
    '${indent}${name} = [' + "`r`n" + '${indent}' + "`t2160`r`n" +
        '${indent}' + "`t4320`r`n" + '${indent}]'
)
$text = [regex]::Replace(
    $text,
    '(?m)^(?<indent>\s*)screen_mode\s*=.*$',
    '${indent}screen_mode = "windowed"'
)
$text = [regex]::Replace(
    $text,
    '(?m)^(?<indent>\s*)fullscreen\s*=.*$',
    '${indent}fullscreen = false'
)
[System.IO.File]::WriteAllText(
    $settings,
    $text,
    [System.Text.UTF8Encoding]::new($false)
)

$verified = [System.IO.File]::ReadAllText($settings)
if (([regex]::Matches($verified, '(?ms)=\s*\[\s*2160\s+4320\s*\]')).Count -ne 4 -or
        ([regex]::Matches($verified, '(?m)^\s*screen_mode\s*=\s*"windowed"\s*$')).Count -lt 1) {
    throw 'Top/bottom display settings did not verify after writing.'
}
Write-Output 'Applied reversible 2160x4320 windowed top/bottom profile.'
