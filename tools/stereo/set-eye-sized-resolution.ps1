[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Apply', 'Inspect', 'Restore')]
    [string] $Action,

    [ValidateRange(640, 7680)]
    [int] $Width = 1920,

    [ValidateRange(640, 7680)]
    [int] $Height = 2160,

    [string] $SettingsPath =
        (Join-Path $env:APPDATA 'Fatshark\Darktide\user_settings.config'),

    [string] $BackupPath =
        (Join-Path $PSScriptRoot '..\..\artifacts\phase1\render-settings\user_settings.pre-eye-sized.config')
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
        throw "Eye-sized settings backup not found: $backup"
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
        '(?m)^\s*(screen_mode|fullscreen)\s*=[^\r\n]*$'
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
$replacement = '${indent}${name} = [' + "`r`n" + '${indent}' +
    "`t$Width`r`n" + '${indent}' + "`t$Height`r`n" + '${indent}]'
$text = [regex]::Replace($text, $resolutionPattern, $replacement)
$text = [regex]::Replace(
    $text,
    '(?m)^(?<indent>\s*)screen_mode\s*=[^\r\n]*$',
    '${indent}screen_mode = "window"'
)
$text = [regex]::Replace(
    $text,
    '(?m)^(?<indent>\s*)fullscreen\s*=[^\r\n]*$',
    '${indent}fullscreen = false'
)
[System.IO.File]::WriteAllText(
    $settings,
    $text,
    [System.Text.UTF8Encoding]::new($false)
)

$verified = [System.IO.File]::ReadAllText($settings)
$escapedExtent = [regex]::Escape("$Width $Height").Replace('\ ', '\s+')
if (([regex]::Matches(
            $verified,
            "(?ms)=\s*\[\s*$escapedExtent\s*\]"
        )).Count -ne 4 -or
        ([regex]::Matches(
            $verified,
            '(?m)^\s*screen_mode\s*=\s*"window"\s*$'
        )).Count -lt 1) {
    throw 'Eye-sized display settings did not verify after writing.'
}
Write-Output "Applied reversible ${Width}x${Height} eye-sized window profile."
