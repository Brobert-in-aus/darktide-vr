param(
    [ValidateSet('Enabled', 'Disabled')]
    [string]$Mode = 'Disabled',
    [string]$GameModDirectory = 'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\darktidevr'
)

$ErrorActionPreference = 'Stop'
$flagPath = Join-Path $GameModDirectory 'darktidevr_shared_shadow_cull.flag'
$value = if ($Mode -eq 'Enabled') { 'enabled' } else { 'disabled' }
Set-Content -LiteralPath $flagPath -Value $value -Encoding ascii

Write-Output "shared_shadow_cull=$($Mode.ToLowerInvariant())"
Write-Output 'note=enabled is the production default; disabled is a diagnostic regression mode'
Write-Output "flag=$flagPath"
