[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Manifest,
    [string] $GameRoot,
    [switch] $AllowChangedFiles
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if (Get-Process Darktide -ErrorAction SilentlyContinue) { throw 'Darktide must be fully closed before restoring deployment files.' }
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'resolve-darktide-game-root.ps1')
. (Join-Path $PSScriptRoot 'restore-deployment-transaction.ps1')
$root = Resolve-DarktideGameRoot -GameRoot $GameRoot
Restore-DarktideDeploymentTransaction -Root $root -Manifest $Manifest `
    -BackupRoot (Join-Path $repoRoot 'artifacts\deployment-backups') -AllowChangedFiles:$AllowChangedFiles
