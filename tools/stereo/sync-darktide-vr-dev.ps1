[CmdletBinding()]
param(
    [string] $GameRoot =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE',

    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Release',

    [switch] $ParticleHorizonLock,

    [switch] $ParticleDiagnosticMagenta
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop

if (Get-Process Darktide -ErrorAction SilentlyContinue) {
    throw 'Darktide must be fully closed before synchronizing development files.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$gameRootPath = (Resolve-Path -LiteralPath $GameRoot).Path
$modRoot = Join-Path $gameRootPath 'mods\darktidevr_stereo_probe'
$sourceLua = Join-Path $repoRoot `
    'mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua'
$sourceNative = Join-Path $repoRoot `
    "build\windows-vs2022\src\producer\$Configuration\darktidevr_native_capture.dll"
$destinations = @(
    [pscustomobject]@{
        Source = $sourceLua
        Destination = Join-Path $modRoot `
            'scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua'
    },
    [pscustomobject]@{
        Source = $sourceNative
        Destination = Join-Path $modRoot 'bin\darktidevr_native_capture.dll'
    },
    [pscustomobject]@{
        Source = $sourceNative
        Destination = Join-Path $gameRootPath `
            'binaries\darktidevr_native_capture.dll'
    }
)

$billboardShaderDestination = Join-Path $modRoot 'bin\billboard_shaders'
if ($ParticleHorizonLock) {
    $destinations += [pscustomobject]@{
        Source = Join-Path $repoRoot `
            'build\generated\billboard_shaders\vs-42e436fb1ef1b392.dxil'
        Destination = Join-Path $billboardShaderDestination `
            'vs-42e436fb1ef1b392.dxil'
    }
}
if ($ParticleDiagnosticMagenta) {
    $destinations += [pscustomobject]@{
        Source = Join-Path $repoRoot `
            'build\generated\billboard_shaders\ps-6020f2548f29fd47.dxil'
        Destination = Join-Path $billboardShaderDestination `
            'ps-6020f2548f29fd47.dxil'
    }
}

foreach ($entry in $destinations) {
    if (-not (Test-Path -LiteralPath $entry.Source -PathType Leaf)) {
        throw "Development source file not found: $($entry.Source)"
    }
    $destinationParent = Split-Path -Parent $entry.Destination
    if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
        throw "Installed Darktide VR directory not found: $destinationParent"
    }
}

foreach ($entry in $destinations) {
    Copy-Item -LiteralPath $entry.Source -Destination $entry.Destination -Force
    $sourceHash = (Get-FileHash -LiteralPath $entry.Source -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $entry.Destination `
        -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) {
        throw "Development deployment hash mismatch: $($entry.Destination)"
    }
    Write-Output "Synchronized $($entry.Destination) sha256=$sourceHash"
}
