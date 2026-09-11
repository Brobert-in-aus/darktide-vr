# Integrity/orchestration fixture only; the real built archive is also validated
# separately with its pinned compiler and actual production shader.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $tempBase ('dtvr-pkg-test-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$luaRelative = 'mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe'
$verifier = (Resolve-Path (Join-Path $PSScriptRoot '..\..\tools\release\test-runtime-package.ps1')).Path
$global:PackageFixtureLuaGate = 0
$global:PackageFixtureShaderGate = 0
$global:PackageFixtureDxcGate = 0
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
try {
    Write-Fixture 'tools/stereo/test-darktide-lua-source.ps1' '$global:PackageFixtureLuaGate++'
    Write-Fixture 'tools/stereo/production-billboard-shader.ps1' 'function Assert-ProductionBillboardShader { param($ShaderPath, $SourcePath) $global:PackageFixtureShaderGate++ }'
    Write-Fixture 'tools/stereo/dxc-runtime.ps1' 'function Get-VerifiedDxcRuntimeFiles { $global:PackageFixtureDxcGate++ }'
    Write-Fixture 'tools/release/runtime-package-files.psd1' "@{ Files = @('native.dll') }"
    Write-Fixture 'native.dll' 'native-fixture'
    Write-Fixture ($luaRelative + '/module.lua') 'return {}'
    $files = @(Get-ChildItem -LiteralPath $testRoot -Recurse -File | ForEach-Object {
        [pscustomobject]@{path=$_.FullName.Substring($testRoot.Length + 1).Replace('\','/');bytes=$_.Length;
            sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
    $manifest = @{schema_version=1;platform='windows-x64';release_state='development_candidate';files=$files}
    $manifestPath = Join-Path $testRoot 'package-manifest.json'
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    & $verifier -PackageRoot $testRoot | Out-Null
    if ($global:PackageFixtureLuaGate -ne 1 -or $global:PackageFixtureShaderGate -ne 1 -or $global:PackageFixtureDxcGate -ne 1) { throw 'Package validation bypassed a gate.' }
    $manifest.binary_source_provenance = 'recorded_hash_matched_claims'
    $manifest.component_provenance = @{schema_version=1;kind='component_build_records';components=@(
        @{name='fixture';source_revision=('1' * 40);source_dirty=$false
          build_command='fixture';toolchain='fixture';build_options='fixture';dependencies='fixture'
          files=@($files | Where-Object path -eq 'native.dll')}
    )}
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    & $verifier -PackageRoot $testRoot | Out-Null
    $manifest.component_provenance.components[0].source_dirty=$true
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Assert-Rejected 'clean source revision'
    $manifest.binary_source_provenance='not_recorded'
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Assert-Rejected 'conflicts with its declared status'
    $manifest.Remove('component_provenance')
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Write-Fixture 'native.dll' 'damaged-fixture'
    Assert-Rejected 'Runtime package file is missing or changed'
    Write-Fixture 'native.dll' 'native-fixture'
    Write-Fixture ($luaRelative + '/unexpected.lua') 'unexpected'
    Assert-Rejected 'Unlisted runtime Lua module'
    Remove-Item -LiteralPath (Join-Path $testRoot ($luaRelative + '/unexpected.lua'))
    $manifest.files = @($files | Where-Object path -ne 'native.dll')
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Assert-Rejected 'Required runtime package file is not listed'
    $manifest.files = @($files) + @($files[0])
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Assert-Rejected 'outside its root or duplicated'
    $manifest.files = @([pscustomobject]@{path='../outside';bytes=0;sha256='none'})
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Assert-Rejected 'outside its root or duplicated'
    Write-Output 'runtime_package_integrity=pass gates provenance changed missing unlisted duplicate path_escape'
} finally {
    Remove-Variable -Scope Global -Name PackageFixtureLuaGate,PackageFixtureShaderGate,PackageFixtureDxcGate -ErrorAction SilentlyContinue
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path -Leaf $resolved).StartsWith('dtvr-pkg-test-')) { throw 'Refusing cleanup outside the temporary test directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
