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

$flagPath = Join-Path $GameModDirectory 'darktidevr_weapon_inventory.flag'
Set-Content -LiteralPath $flagPath -Value 'scan' -Encoding ascii
Write-Output 'weapon_inventory=scan'
Write-Output "flag=$flagPath"
