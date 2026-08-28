[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$launcher = Join-Path $PSScriptRoot 'launch-darktide-vr.ps1'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "Darktide VR launcher not found: $launcher"
}

$desktop = [Environment]::GetFolderPath('Desktop')
if (-not (Test-Path -LiteralPath $desktop -PathType Container)) {
    throw "Desktop directory not found: $desktop"
}

$powerShell = Join-Path $env:SystemRoot `
    'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
    $powerShell = Join-Path $PSHOME 'pwsh.exe'
}
if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
    throw 'No supported PowerShell executable was found.'
}

$shortcutPath = Join-Path $desktop 'Darktide VR.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powerShell
$shortcut.Arguments =
    "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`""
$shortcut.WorkingDirectory =
    (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$shortcut.Description =
    'Launch Darktide through Steam and the Fatshark launcher, then start XR automatically.'
$shortcut.WindowStyle = 7
$shortcut.Save()

if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
    throw "Shortcut creation failed: $shortcutPath"
}

Write-Output "Installed $shortcutPath"
