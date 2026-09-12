[CmdletBinding()]
param([Parameter(Mandatory)][string] $PackageRoot)
# Verifies a staged or extracted release package against its manifest: every
# listed file present with its recorded size and hash, no entry outside the
# root, the game-folder layout complete, and any component build record
# consistent. It does not compile Lua or touch the game; those gates run in
# the repository when the package is built.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$root = (Resolve-Path -LiteralPath $PackageRoot).Path.TrimEnd('\', '/')
# The manifest lives inside the mod folder like everything else in the archive.
$manifestPath = Join-Path $root 'mods\darktidevr_stereo_probe\package-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema_version -ne 2 -or $manifest.platform -cne 'windows-x64' -or $manifest.layout -cne 'game_folder' -or
        $manifest.release_state -cnotin @('development_candidate', 'release_candidate')) {
    throw 'Unsupported runtime package manifest.'
}
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
if ($manifest.PSObject.Properties['binary_source_provenance'] -and
        $manifest.binary_source_provenance -cne 'not_recorded') {
    if ($manifest.binary_source_provenance -cne 'recorded_hash_matched_claims') {
        throw 'Unsupported binary provenance status.'
    }
    . (Join-Path $PSScriptRoot 'component-provenance.ps1')
    Assert-ComponentProvenance -Receipt $manifest.component_provenance -Files @($manifest.files) `
        -ProjectBinaries @($manifest.project_binaries)
} elseif ($manifest.PSObject.Properties['component_provenance'] -and $null -ne $manifest.component_provenance) {
    throw 'Component provenance conflicts with its declared status.'
}
# The game-folder layout: everything a player needs sits under the mod folder.
$required = @(
    'mods/darktidevr_stereo_probe/darktidevr_stereo_probe.mod'
    'mods/darktidevr_stereo_probe/Darktide VR Mode.bat'
    'mods/darktidevr_stereo_probe/darktidevr-mode.ps1'
    'mods/darktidevr_stereo_probe/tools/set-skinner-assert-patch.ps1'
    'mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua'
    'mods/darktidevr_stereo_probe/bin/d3d12.dll'
    'mods/darktidevr_stereo_probe/bin/darktidevr_native_capture.dll'
    'mods/darktidevr_stereo_probe/bin/darktidevr-xr-harness.exe'
    'mods/darktidevr_stereo_probe/bin/openxr_loader.dll'
    'mods/darktidevr_stereo_probe/bin/dxcompiler.dll'
    'mods/darktidevr_stereo_probe/bin/billboard_shaders/vs-42e436fb1ef1b392.dxil'
    'mods/darktidevr_stereo_probe/LICENSE'
    'mods/darktidevr_stereo_probe/THIRD_PARTY_NOTICES.md'
    'mods/darktidevr_stereo_probe/README.txt'
)
foreach ($relative in $required) {
    if (-not $seen.Contains([IO.Path]::GetFullPath((Join-Path $root $relative)))) {
        throw "Required runtime package file is not listed: $relative"
    }
}
foreach ($relative in @($manifest.project_binaries)) {
    if (-not $seen.Contains([IO.Path]::GetFullPath((Join-Path $root $relative)))) {
        throw "Project binary is not in the package: $relative"
    }
}
# A stray Lua file in the package would be loaded by the mod's module loader.
$luaRoot = Join-Path $root $manifest.lua_directory
foreach ($file in Get-ChildItem -LiteralPath $luaRoot -Filter '*.lua' -File) {
    if (-not $seen.Contains($file.FullName)) { throw "Unlisted runtime Lua module: $($file.Name)" }
}
foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File) {
    if ($file.FullName -eq [IO.Path]::GetFullPath($manifestPath)) { continue }
    if (-not $seen.Contains($file.FullName)) { throw "Unlisted file in package: $($file.FullName.Substring($root.Length + 1))" }
}
Write-Output "runtime_package=pass files=$($seen.Count) state=$($manifest.release_state) layout=game_folder headset_tested=false"
