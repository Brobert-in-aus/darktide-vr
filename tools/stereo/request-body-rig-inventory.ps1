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

$flagPath = Join-Path $GameModDirectory 'darktidevr_body_rig_inventory.flag'
Set-Content -LiteralPath $flagPath -Value 'scan' -Encoding ascii
Write-Output 'body_rig_inventory=scan'
Write-Output "flag=$flagPath"
