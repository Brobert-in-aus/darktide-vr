[CmdletBinding()]
param([string] $OutputDirectory = (Join-Path $PSScriptRoot '..\..\artifacts\packages'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$spec = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'runtime-package-files.psd1')
. (Join-Path $root 'tools/stereo/dxc-runtime.ps1')
@(Get-VerifiedDxcRuntimeFiles) | Out-Null
& (Join-Path $root 'tools/stereo/test-darktide-lua-source.ps1')
. (Join-Path $root 'tools/stereo/production-billboard-shader.ps1')
Assert-ProductionBillboardShader -ShaderPath (Join-Path $root 'build/generated/billboard_shaders/vs-42e436fb1ef1b392.dxil') `
    -SourcePath (Join-Path $root 'tools/stereo/particle-horizon-lock.vs.hlsl')
. (Join-Path $root 'tools/unattended/source-checkout-identity.ps1')
$identity = Get-SourceCheckoutIdentity -Root $root
if (-not $identity.available) { throw 'Build the package from its source checkout to record its revision.' }
$relativeFiles = @($spec.Files)
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root $spec.LuaDirectory) -Filter '*.lua' -File) {
    $relativeFiles += $spec.LuaDirectory + '/' + $file.Name
}
$plan = @()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($relative in $relativeFiles) {
    $source = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if ([IO.Path]::IsPathRooted($relative) -or -not $source.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not $seen.Add($source)) { throw 'Invalid or duplicate package source path.' }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Package input is missing: $relative" }
    $cursor = $source
    while ($cursor -ne $root) {
        if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Package input contains a reparse point: $relative"
        }
        $cursor = Split-Path -Parent $cursor
    }
    $plan += [pscustomobject]@{ path=$relative; source=$source; bytes=(Get-Item -LiteralPath $source).Length;
        sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash }
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
$name = 'darktidevr-candidate-' + $identity.head.Substring(0, 12) + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
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
    schema_version=1; platform='windows-x64'; release_state='development_candidate'
    source_revision=$identity.head; source_branch=$identity.branch; source_dirty=$identity.dirty
    source_revision_scope='packaging_checkout'; binary_source_provenance='not_recorded'
    built_utc=(Get-Date).ToUniversalTime().ToString('o')
    files=@($plan | Select-Object path,bytes,sha256)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $package 'package-manifest.json') -Encoding UTF8
& (Join-Path $package 'tools/release/test-runtime-package.ps1') -PackageRoot $package
$archive = Join-Path $output ($name + '.zip')
Compress-Archive -LiteralPath $package -DestinationPath $archive -CompressionLevel Optimal
[pscustomobject]@{ PackageRoot=$package; Archive=$archive; SHA256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash }
