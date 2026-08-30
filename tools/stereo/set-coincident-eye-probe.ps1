param(
    [ValidateSet('Enabled', 'Disabled')]
    [string]$Mode = 'Disabled',
    [string]$GameModDirectory = 'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\darktidevr_stereo_probe'
)

$ErrorActionPreference = 'Stop'
$flagPath = Join-Path $GameModDirectory 'darktidevr_coincident_eyes.flag'
$value = if ($Mode -eq 'Enabled') { 'enabled' } else { 'disabled' }
Set-Content -LiteralPath $flagPath -Value $value -Encoding ascii

Write-Output "coincident_eye_probe=$($Mode.ToLowerInvariant())"
Write-Output "flag=$flagPath"
