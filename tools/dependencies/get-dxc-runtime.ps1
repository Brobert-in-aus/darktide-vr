[CmdletBinding()]
param([string] $ArchivePath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$dependencyRoot = Join-Path $repoRoot 'build/dependencies'
$runtimeRoot = Join-Path $dependencyRoot 'dxc-runtime'
$spec = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'dxc-runtime.psd1')
. (Join-Path $repoRoot 'tools/stereo/dxc-runtime.ps1')
if (Test-Path -LiteralPath $runtimeRoot) {
    @(Get-VerifiedDxcRuntimeFiles -RuntimeRoot $runtimeRoot) | Out-Null
    Write-Output "DXC runtime already verified: $($spec.Version)"
    return
}
[IO.Directory]::CreateDirectory($dependencyRoot) | Out-Null
if (-not $ArchivePath) {
    $ArchivePath = Join-Path $dependencyRoot ('dxc-' + $spec.Version + '.zip')
    if (-not (Test-Path -LiteralPath $ArchivePath)) {
        Invoke-WebRequest -Uri $spec.ArchiveUrl -OutFile $ArchivePath
    }
}
if ((Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash -ne $spec.ArchiveSHA256) {
    throw 'DXC archive does not match the pinned upstream release digest.'
}
$stage = Join-Path $dependencyRoot ('dxc-runtime-stage-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stage) | Out-Null
$zip = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($ArchivePath))
try {
    # Extract only the four named runtime/notice files; no archive paths are
    # interpreted as destination paths and no executable compiler is packaged.
    foreach ($entry in $spec.Files) {
        $source = $zip.GetEntry($entry.ArchivePath)
        if (-not $source) { throw "Pinned DXC archive lacks $($entry.ArchivePath)" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($source, (Join-Path $stage $entry.Name))
    }
} finally { $zip.Dispose() }
@(Get-VerifiedDxcRuntimeFiles -RuntimeRoot $stage) | Out-Null
$boundary = [IO.Path]::GetFullPath($dependencyRoot).TrimEnd('\') + '\'
foreach ($target in $stage, $runtimeRoot) {
    if (-not [IO.Path]::GetFullPath($target).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'DXC staging path escaped its dependency directory.'
    }
}
[IO.Directory]::Move($stage, $runtimeRoot)
Write-Output "DXC runtime prepared: $($spec.Version)"
