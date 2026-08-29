[CmdletBinding()]
param(
    [ValidateSet('Enabled', 'Disabled')]
    [string] $Mode = 'Disabled',

    [string] $GameModDirectory =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\darktidevr_stereo_probe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $GameModDirectory -PathType Container)) {
    throw "Darktide VR mod directory not found: $GameModDirectory"
}

$flagPath = Join-Path $GameModDirectory 'darktidevr_force_hub_first_person.flag'
$value = $Mode.ToLowerInvariant()
Set-Content -LiteralPath $flagPath -Value $value -Encoding ascii
Write-Output "hub_first_person_diagnostic=$value"
Write-Output "flag=$flagPath"
