[CmdletBinding()]
param(
    [string] $GameModDirectory =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\darktidevr_stereo_probe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $GameModDirectory -PathType Container)) {
    throw "Darktide VR mod directory not found: $GameModDirectory"
}

$flagPath = Join-Path $GameModDirectory 'darktidevr_primary_action_test.flag'
Set-Content -LiteralPath $flagPath -Value 'fire_once' -Encoding ascii
Write-Output 'primary_action_test=fire_once'
Write-Output "flag=$flagPath"
