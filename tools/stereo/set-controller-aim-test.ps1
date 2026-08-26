[CmdletBinding()]
param(
    [switch] $Enabled,

    [string] $GameModDirectory =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\darktidevr_stereo_probe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $GameModDirectory -PathType Container)) {
    throw "Darktide VR mod directory not found: $GameModDirectory"
}

$flagPath = Join-Path $GameModDirectory 'darktidevr_controller_aim_test.flag'
$state = if ($Enabled) { 'enabled' } else { 'disabled' }
Set-Content -LiteralPath $flagPath -Value $state -Encoding ascii
Write-Output "controller_aim_test=$state"
Write-Output "flag=$flagPath"
