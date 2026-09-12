param(
    [ValidateSet('Enabled', 'Disabled')]
    [string]$Mode = 'Disabled',
    [string]$GameModDirectory = 'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\darktidevr'
)

$ErrorActionPreference = 'Stop'
$flagPath = Join-Path $GameModDirectory 'darktidevr_performance_profile.flag'
$value = if ($Mode -eq 'Enabled') { 'enabled' } else { 'disabled' }
Set-Content -LiteralPath $flagPath -Value $value -Encoding ascii

Write-Output "performance_profile=$($Mode.ToLowerInvariant())"
Write-Output 'note=requires a fresh Darktide process; GPU timestamp profiling is diagnostic-only'
Write-Output "flag=$flagPath"
