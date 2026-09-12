[CmdletBinding()]
param([string] $OutputDirectory = (Join-Path $PSScriptRoot '..\..\artifacts\packages'),
      [string] $ComponentProvenancePath,
      [switch] $RequireComponentProvenance,
      # Public version label for a release archive (for example 0.1.0-alpha.1).
      # Recorded in the manifest and used in the archive name; the source
      # revision is recorded regardless.
      [ValidatePattern('^$|^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$')][string] $ReleaseVersion)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$spec = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'runtime-package-files.psd1')
# Repository-side gates: the pinned reflection runtime, every Lua chunk and the
# production shader identity are checked here, before anything is staged.
. (Join-Path $root 'tools/stereo/dxc-runtime.ps1')
@(Get-VerifiedDxcRuntimeFiles) | Out-Null
& (Join-Path $root 'tools/stereo/test-darktide-lua-source.ps1')
. (Join-Path $root 'tools/stereo/production-billboard-shader.ps1')
Assert-ProductionBillboardShader -ShaderPath (Join-Path $root 'build/generated/billboard_shaders/vs-42e436fb1ef1b392.dxil') `
    -SourcePath (Join-Path $root 'tools/stereo/particle-horizon-lock.vs.hlsl')
. (Join-Path $root 'tools/unattended/source-checkout-identity.ps1')
$identity = Get-SourceCheckoutIdentity -Root $root
if (-not $identity.available) { throw 'Build the package from its source checkout to record its revision.' }
$entries = @()
foreach ($file in $spec.Files) { $entries += [pscustomobject]@{ source = [string]$file.Source; path = [string]$file.Destination } }
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root $spec.LuaDirectory) -Filter '*.lua' -File) {
    $entries += [pscustomobject]@{ source = $spec.LuaDirectory + '/' + $file.Name; path = $spec.LuaDestination + '/' + $file.Name }
}
$plan = @()
$seenSources = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$seenDestinations = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $entries) {
    $source = [IO.Path]::GetFullPath((Join-Path $root $entry.source))
    if ([IO.Path]::IsPathRooted($entry.source) -or [IO.Path]::IsPathRooted($entry.path) -or
            -not $source.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $entry.path -match '(^|/)\.\.(/|$)' -or -not $seenSources.Add($source) -or -not $seenDestinations.Add($entry.path)) {
        throw "Invalid or duplicate package entry: $($entry.source) -> $($entry.path)"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Package input is missing: $($entry.source)" }
    $cursor = $source
    while ($cursor -ne $root) {
        if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Package input contains a reparse point: $($entry.source)"
        }
        $cursor = Split-Path -Parent $cursor
    }
    $plan += [pscustomobject]@{ path=$entry.path; source=$source; bytes=(Get-Item -LiteralPath $source).Length;
        sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash }
}
$provenance = $null
if ($ComponentProvenancePath) {
    . (Join-Path $PSScriptRoot 'component-provenance.ps1')
    $provenance = Get-Content -LiteralPath $ComponentProvenancePath -Raw | ConvertFrom-Json
    Assert-ComponentProvenance -Receipt $provenance -Files $plan -ProjectBinaries @($spec.ProjectBinaries)
} elseif ($RequireComponentProvenance) {
    throw 'Component build records are required before packaging.'
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
$name = if ($ReleaseVersion) { 'darktidevr-' + $ReleaseVersion + '-' + $identity.head.Substring(0, 12) }
        else { 'darktidevr-candidate-' + $identity.head.Substring(0, 12) + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) }
$package = Join-Path $output $name
if (Test-Path -LiteralPath $package) { throw 'Package destination already exists.' }
[IO.Directory]::CreateDirectory($package) | Out-Null
foreach ($entry in $plan) {
    $destination = Join-Path $package $entry.path
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    Copy-Item -LiteralPath $entry.source -Destination $destination
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $entry.sha256) {
        throw "Package source changed during staging: $($entry.path)"
    }
}
[ordered]@{
    schema_version=2; platform='windows-x64'
    release_state=$(if ($ReleaseVersion) { 'release_candidate' } else { 'development_candidate' })
    release_version=$(if ($ReleaseVersion) { $ReleaseVersion } else { $null })
    layout='game_folder'
    source_revision=$identity.head; source_branch=$identity.branch; source_dirty=$identity.dirty
    source_revision_scope='packaging_checkout'
    binary_source_provenance=$(if ($provenance) { 'recorded_hash_matched_claims' } else { 'not_recorded' })
    component_provenance=$provenance
    project_binaries=@($spec.ProjectBinaries)
    lua_directory=$spec.LuaDestination
    built_utc=(Get-Date).ToUniversalTime().ToString('o')
    files=@($plan | Select-Object path,bytes,sha256)
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $package 'mods/darktidevr/package-manifest.json') -Encoding UTF8
& (Join-Path $PSScriptRoot 'test-runtime-package.ps1') -PackageRoot $package
$archive = Join-Path $output ($name + '.zip')
# Archive the contents, not the folder, so extracting into the game folder
# places mods\darktidevr directly.
Compress-Archive -Path (Join-Path $package '*') -DestinationPath $archive -CompressionLevel Optimal
[pscustomobject]@{ PackageRoot=$package; Archive=$archive; SHA256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash }
