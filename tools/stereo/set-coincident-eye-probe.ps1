param(
    [ValidateSet('Coincident', 'ZeroIpd', 'MatchedOrientation', 'VisibilityPadding', 'Disabled')]
    [string]$Mode = 'Disabled',
    [string]$GameModDirectory = 'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\darktidevr_stereo_probe'
)

$ErrorActionPreference = 'Stop'
$flagPath = Join-Path $GameModDirectory 'darktidevr_coincident_eyes.flag'
$value = switch ($Mode) {
    'Coincident' { 'enabled' }
    'ZeroIpd' { 'zero_ipd' }
    'MatchedOrientation' { 'matched_orientation' }
    'VisibilityPadding' { 'visibility_padding' }
    default { 'disabled' }
}
Set-Content -LiteralPath $flagPath -Value $value -Encoding ascii

Write-Output "eye_transform_probe=$($Mode.ToLowerInvariant())"
Write-Output "flag=$flagPath"
