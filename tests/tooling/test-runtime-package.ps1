# Integrity/orchestration fixture only; the real built archive is also validated
# separately by the packager after the repository-side Lua/shader/dependency gates.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $tempBase ('dtvr-pkg-test-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$modRelative = 'mods/darktidevr'
$luaRelative = $modRelative + '/scripts/mods/darktidevr'
$verifier = (Resolve-Path (Join-Path $PSScriptRoot '..\..\tools\release\test-runtime-package.ps1')).Path
function Write-Fixture([string] $Relative, [string] $Text) {
    $path = Join-Path $testRoot $Relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path, $Text)
}
function Assert-Rejected([string] $Message) {
    $failed = $false
    try { & $verifier -PackageRoot $testRoot | Out-Null } catch { $failed = $_.Exception.Message.Contains($Message) }
    if (-not $failed) { throw "Expected package rejection: $Message" }
}
function Get-Files {
    @(Get-ChildItem -LiteralPath $testRoot -Recurse -File | Where-Object Name -ne 'package-manifest.json' | ForEach-Object {
        [pscustomobject]@{path=$_.FullName.Substring($testRoot.Length + 1).Replace('\','/');bytes=$_.Length;
            sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
}
try {
    # The game-folder layout the verifier requires.
    foreach ($relative in @(
            "$modRelative/darktidevr.mod", "$modRelative/Darktide VR Mode.bat", "$modRelative/darktidevr-mode.ps1",
            "$modRelative/tools/set-skinner-assert-patch.ps1", "$luaRelative/darktidevr.lua",
            "$modRelative/bin/d3d12.dll", "$modRelative/bin/darktidevr_native_capture.dll", "$modRelative/bin/darktidevr-xr-harness.exe",
            "$modRelative/bin/openxr_loader.dll", "$modRelative/bin/dxcompiler.dll",
            "$modRelative/bin/billboard_shaders/vs-42e436fb1ef1b392.dxil", "$modRelative/LICENSE", "$modRelative/THIRD_PARTY_NOTICES.md", "$modRelative/README.txt")) {
        Write-Fixture $relative ('fixture-' + $relative)
    }
    Write-Fixture ($luaRelative + '/module.lua') 'return {}'
    $projectBinaries = @("$modRelative/bin/d3d12.dll", "$modRelative/bin/darktidevr_native_capture.dll", "$modRelative/bin/darktidevr-xr-harness.exe")
    $files = Get-Files
    $manifest = @{schema_version=2;platform='windows-x64';layout='game_folder';release_state='development_candidate';
        project_binaries=$projectBinaries;lua_directory=$luaRelative;files=$files}
    $manifestPath = Join-Path $testRoot "$modRelative/package-manifest.json"
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    & $verifier -PackageRoot $testRoot | Out-Null
    $manifest.binary_source_provenance = 'recorded_hash_matched_claims'
    $manifest.component_provenance = @{schema_version=1;kind='component_build_records';components=@(
        @{name='fixture';source_revision=('1' * 40);source_dirty=$false
          build_command='fixture';toolchain='fixture';build_options='fixture';dependencies='fixture'
          files=@($files | Where-Object { $projectBinaries -contains $_.path })}
    )}
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    & $verifier -PackageRoot $testRoot | Out-Null
    $manifest.component_provenance.components[0].files = @($files | Where-Object path -eq "$modRelative/bin/d3d12.dll")
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Assert-Rejected 'lacks a component build record'
    $manifest.component_provenance.components[0].files = @($files | Where-Object { $projectBinaries -contains $_.path })
    $manifest.component_provenance.components[0].source_dirty=$true
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Assert-Rejected 'clean source revision'
    $manifest.binary_source_provenance='not_recorded'
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Assert-Rejected 'conflicts with its declared status'
    $manifest.Remove('component_provenance')
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    & $verifier -PackageRoot $testRoot | Out-Null
    Write-Fixture "$modRelative/bin/darktidevr_native_capture.dll" 'damaged-fixture'
    Assert-Rejected 'Runtime package file is missing or changed'
    Write-Fixture "$modRelative/bin/darktidevr_native_capture.dll" ('fixture-' + "$modRelative/bin/darktidevr_native_capture.dll")
    Write-Fixture ($luaRelative + '/unexpected.lua') 'unexpected'
    Assert-Rejected 'Unlisted runtime Lua module'
    Remove-Item -LiteralPath (Join-Path $testRoot ($luaRelative + '/unexpected.lua'))
    Write-Fixture 'stray.txt' 'stray'
    Assert-Rejected 'Unlisted file in package'
    Remove-Item -LiteralPath (Join-Path $testRoot 'stray.txt')
    $manifest.files = @($files | Where-Object path -ne "$modRelative/LICENSE")
    Remove-Item -LiteralPath (Join-Path $testRoot "$modRelative/LICENSE")
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Assert-Rejected 'Required runtime package file is not listed'
    Write-Fixture "$modRelative/LICENSE" ('fixture-' + "$modRelative/LICENSE")
    $manifest.files = @($files) + @($files[0])
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Assert-Rejected 'outside its root or duplicated'
    $manifest.files = @([pscustomobject]@{path='../outside';bytes=0;sha256='none'})
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Assert-Rejected 'outside its root or duplicated'
    Write-Output 'runtime_package_integrity=pass layout provenance changed missing unlisted stray duplicate path_escape'
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path -Leaf $resolved).StartsWith('dtvr-pkg-test-')) { throw 'Refusing cleanup outside the temporary test directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
