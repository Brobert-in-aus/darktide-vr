param(
    [ValidateSet('Enabled', 'Disabled')]
    [string]$Mode = 'Disabled',
    [string]$GameModDirectory = 'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\darktidevr'
)

$ErrorActionPreference = 'Stop'
$flagPath = Join-Path $GameModDirectory 'darktidevr_reverse_eye_order.flag'
$value = if ($Mode -eq 'Enabled') { 'enabled' } else { 'disabled' }
Set-Content -LiteralPath $flagPath -Value $value -Encoding ascii

Write-Output "reverse_eye_order_probe=$($Mode.ToLowerInvariant())"
Write-Output "flag=$flagPath"
