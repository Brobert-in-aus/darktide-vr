[CmdletBinding()]
param(
    [string] $SettingsPath = (Join-Path $env:APPDATA 'Fatshark\Darktide\user_settings.config')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Get-Process Darktide -ErrorAction SilentlyContinue) {
    throw 'Close Darktide before applying the VR window mode.'
}
$text = [IO.File]::ReadAllText($SettingsPath)
# Match active and detected settings. Startup uses the desktop mirror extent;
# the mod establishes the independent headset render extent after loading.
# [^\r\n] keeps CRLF files intact; '.' would consume the carriage return.
$modePattern = '(?m)^(?<indent>[\t ]*)screen_mode[\t ]*=[^\r\n]*$'
$fullscreenPattern = '(?m)^(?<indent>[\t ]*)fullscreen[\t ]*=[^\r\n]*$'
if (-not [regex]::IsMatch($text, $modePattern) -or
    -not [regex]::IsMatch($text, $fullscreenPattern)) {
    throw 'Display mode settings were not found; refusing an unverified launch.'
}
$updated = [regex]::Replace($text, $modePattern, '${indent}screen_mode = "window"')
$updated = [regex]::Replace($updated, $fullscreenPattern, '${indent}fullscreen = false')
$resolutionPattern = '(?ms)^(?<indent>[\t ]*)(?<name>screen_resolution|last_windowed_resolution)[\t ]*=\s*\[.*?\]'
if (-not [regex]::IsMatch($updated, $resolutionPattern)) {
    throw 'Startup resolution was not found; refusing an unverified launch.'
}
$updated = [regex]::Replace($updated, $resolutionPattern,
    '${indent}${name} = [1920 1080]')
if ($updated -ne $text) {
    $backupDirectory = Join-Path $PSScriptRoot '..\..\artifacts\phase1\render-settings'
    New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    $backup = Join-Path $backupDirectory ('user_settings.pre-windowed-' +
        (Get-Date -Format 'yyyyMMdd-HHmmss-ffff') + '.config')
    Copy-Item -LiteralPath $SettingsPath -Destination $backup
    [IO.File]::WriteAllText($SettingsPath, $updated, [Text.UTF8Encoding]::new($false))
}
if ([IO.File]::ReadAllText($SettingsPath) -ne $updated) {
    throw 'VR window mode did not verify after writing.'
}
Write-Output 'display.windowed=verified startup_mirror=1920x1080'
