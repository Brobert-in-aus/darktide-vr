[CmdletBinding()]
param(
    [string] $GameRoot = 'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE',
    [string] $SourceRoot = (Join-Path $PSScriptRoot '../../_downloads/custom_hud')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Get-Process Darktide -ErrorAction SilentlyContinue) {
    throw 'Close Darktide before installing the optional editor.'
}
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$game = (Resolve-Path -LiteralPath $GameRoot).Path
$bootstrap = Join-Path $source 'custom_hud.mod'
if (-not (Test-Path -LiteralPath $bootstrap)) { throw 'Custom HUD source is missing.' }
$chunks = @((Get-ChildItem -LiteralPath (Join-Path $source 'scripts/mods/custom_hud') -Filter '*.lua').FullName) + $bootstrap
& (Join-Path $PSScriptRoot '../lua/test-lua-syntax.ps1') -SourcePaths $chunks
$destination = Join-Path $game 'mods/custom_hud'
if (Test-Path -LiteralPath $destination) {
    throw 'Custom HUD is already installed; preserve the existing installation and settings.'
}
Copy-Item -LiteralPath $source -Destination $destination -Recurse
$orderPath = Join-Path $game 'mods/mod_load_order.txt'
$order = @(Get-Content -LiteralPath $orderPath)
if (-not ($order | Where-Object { $_.Trim() -eq 'custom_hud' })) {
    $updated = foreach ($line in $order) {
        if ($line.Trim() -eq 'darktidevr_stereo_probe') { 'custom_hud' }
        $line
    }
    if (-not ($order | Where-Object { $_.Trim() -eq 'darktidevr_stereo_probe' })) {
        $updated += 'custom_hud'
    }
    Copy-Item -LiteralPath $orderPath -Destination ($orderPath + '.before-custom-hud-editor')
    Set-Content -LiteralPath $orderPath -Value $updated
}
Write-Output 'Optional Custom HUD installed without altering its source. F3 toggles editing.'
