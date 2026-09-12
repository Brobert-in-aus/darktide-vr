[CmdletBinding()]
param(
    [ValidateSet('Enabled', 'Disabled')]
    [string] $Mode = 'Disabled',

    [string] $GameModDirectory =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\darktidevr'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $GameModDirectory -PathType Container)) {
    throw "Darktide VR mod directory not found: $GameModDirectory"
}

$flagPath = Join-Path $GameModDirectory 'darktidevr_weapon_pose_trace.flag'
$value = $Mode.ToLowerInvariant()
Set-Content -LiteralPath $flagPath -Value $value -Encoding ascii
Write-Output "weapon_pose_trace=$value"
Write-Output "flag=$flagPath"
