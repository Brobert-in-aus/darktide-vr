[CmdletBinding()]
param(
    [string] $OutputPath = (Join-Path $PSScriptRoot '..\..\artifacts\packages\component-provenance.json'),
    # Rebuild the project binaries from this checkout before hashing them, so
    # the record describes the build that produced the files.
    [switch] $SkipBuild
)
# Writes the component build record that build-runtime-package.ps1 embeds.
# The record binds the three project binaries to a clean checkout revision and
# to the commands, toolchain and dependencies used; it is a build record, not
# a signature or a reproducibility proof.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'tools/unattended/source-checkout-identity.ps1')
$identity = Get-SourceCheckoutIdentity -Root $root
if (-not $identity.available) { throw 'Record build records from a source checkout.' }
if ($identity.dirty) { throw "Record build records from a clean checkout; uncommitted changes: $($identity.status -join '; ')" }

$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmake) {
    $candidate = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (-not (Test-Path -LiteralPath $candidate)) { throw 'cmake not found.' }
    $cmake = Get-Command $candidate
}
$buildDirectory = 'build/windows-vs2022'
$components = @(
    @{ name = 'producer'; targets = @('darktidevr_native_capture', 'darktidevr_d3d12_bootstrap')
       outputs = @('mods/darktidevr_stereo_probe/bin/darktidevr_native_capture.dll', 'mods/darktidevr_stereo_probe/bin/d3d12.dll')
       dependencies = 'MinHook c3fcafdc10146beb5919319d0683e44e3c30d537 (BSD-2-Clause, static); Windows SDK and D3D12/DXGI/DXC headers from the toolchain; no NVIDIA Streamline code (project-declared ABI 2.7.30)' },
    @{ name = 'viewer'; targets = @('darktidevr-xr-harness')
       outputs = @('mods/darktidevr_stereo_probe/bin/darktidevr-xr-harness.exe')
       dependencies = 'Khronos OpenXR SDK loader release 1.1.61 commit 5267613 (Apache-2.0, app-local openxr_loader.dll); Windows SDK D3D12/D3D11/DXGI' }
)
$spec = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'runtime-package-files.psd1')
$sourceByDestination = @{}
foreach ($file in $spec.Files) { $sourceByDestination[[string]$file.Destination] = [string]$file.Source }

$cmakeVersion = (& $cmake.Source --version | Select-Object -First 1).Trim()
$msvcRoot = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC'
$msvc = if (Test-Path -LiteralPath $msvcRoot) { (Get-ChildItem -LiteralPath $msvcRoot -Directory | Sort-Object Name | Select-Object -Last 1).Name } else { 'unknown' }
$sdk = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SDKs\Windows\v10.0' -Name ProductVersion -ErrorAction SilentlyContinue).ProductVersion
$toolchain = "Visual Studio 17 2022 generator, MSVC $msvc, Windows SDK $sdk, $cmakeVersion"

$records = @()
foreach ($component in $components) {
    $buildCommand = "cmake --build $buildDirectory --config Release --target " + ($component.targets -join ' ')
    if (-not $SkipBuild) {
        & $cmake.Source --build (Join-Path $root $buildDirectory) --config Release --target @($component.targets) | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Build failed: $buildCommand" }
    }
    $files = @()
    foreach ($output in $component.outputs) {
        if (-not $sourceByDestination.ContainsKey($output)) { throw "Package spec does not list $output" }
        $path = Join-Path $root $sourceByDestination[$output]
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Build output missing: $path" }
        $files += [ordered]@{ path = $output; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    }
    $records += [ordered]@{
        name = $component.name
        source_revision = $identity.head
        source_dirty = $false
        build_command = $buildCommand
        toolchain = $toolchain
        build_options = 'Release, x64, /W4 /WX /permissive-, NOMINMAX WIN32_LEAN_AND_MEAN UNICODE, CMake cache in build/windows-vs2022 (configure: cmake -S . -B build/windows-vs2022 -G "Visual Studio 17 2022" -A x64)'
        dependencies = $component.dependencies
        files = $files
    }
}
$receipt = [ordered]@{ schema_version = 1; kind = 'component_build_records'; recorded_utc = (Get-Date).ToUniversalTime().ToString('o'); components = $records }
[IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output "component_provenance=$OutputPath revision=$($identity.head) components=$($records.Count)"
