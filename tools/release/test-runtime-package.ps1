[CmdletBinding()]
param([string] $PackageRoot = (Join-Path $PSScriptRoot '..\..'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
$root = (Resolve-Path -LiteralPath $PackageRoot).Path.TrimEnd('\', '/')
$manifest = Get-Content -LiteralPath (Join-Path $root 'package-manifest.json') -Raw | ConvertFrom-Json
if ($manifest.schema_version -ne 1 -or $manifest.platform -cne 'windows-x64' -or
        $manifest.release_state -cne 'development_candidate') { throw 'Unsupported runtime package manifest.' }
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $manifest.files) {
    if ([IO.Path]::IsPathRooted($entry.path)) { throw 'Package entries must use relative paths.' }
    $path = [IO.Path]::GetFullPath((Join-Path $root $entry.path))
    if (-not $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or -not $seen.Add($path)) {
        throw 'Package entry is outside its root or duplicated.'
    }
    $cursor = $path
    while ($cursor -ne $root) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Package content contains a reparse point.'
            }
        }
        $cursor = Split-Path -Parent $cursor
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-Item -LiteralPath $path).Length -ne $entry.bytes -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256) {
        throw "Runtime package file is missing or changed: $($entry.path)"
    }
}
if ($seen.Count -lt 1) { throw 'Runtime package manifest is empty.' }
$spec = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'tools/release/runtime-package-files.psd1')
foreach ($required in $spec.Files) {
    if (-not $seen.Contains([IO.Path]::GetFullPath((Join-Path $root $required)))) {
        throw "Required runtime package file is not listed: $required"
    }
}
# A later user-added Lua file would also be deployed by the module enumerator.
$luaRoot = Join-Path $root 'mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe'
foreach ($file in Get-ChildItem -LiteralPath $luaRoot -Filter '*.lua' -File) {
    if (-not $seen.Contains($file.FullName)) { throw "Unlisted runtime Lua module: $($file.Name)" }
}
& (Join-Path $root 'tools/stereo/test-darktide-lua-source.ps1')
. (Join-Path $root 'tools/stereo/production-billboard-shader.ps1')
Assert-ProductionBillboardShader -ShaderPath (Join-Path $root 'build/generated/billboard_shaders/vs-42e436fb1ef1b392.dxil') `
    -SourcePath (Join-Path $root 'tools/stereo/particle-horizon-lock.vs.hlsl')
Write-Output "runtime_package=pass files=$($seen.Count) state=development_candidate headset_tested=false"
