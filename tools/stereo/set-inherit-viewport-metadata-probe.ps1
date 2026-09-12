param(
    [ValidateSet('Disabled', 'Layer', 'Callback', 'Both')]
    [string]$Mode = 'Disabled',
    [string]$GameModDirectory = 'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\darktidevr'
)

$ErrorActionPreference = 'Stop'
$flagPath = Join-Path $GameModDirectory 'darktidevr_inherit_viewport_metadata.flag'
$value = $Mode.ToLowerInvariant()
Set-Content -LiteralPath $flagPath -Value $value -Encoding ascii

Write-Output "inherit_viewport_metadata_probe=$value"
Write-Output "flag=$flagPath"
