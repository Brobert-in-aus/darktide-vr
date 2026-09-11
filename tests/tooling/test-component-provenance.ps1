Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tools/release/component-provenance.ps1')
$hash = 'A' * 64
$files = @(
    [pscustomobject]@{path='build/native/darktidevr_native_capture.dll';sha256=$hash},
    [pscustomobject]@{path='build/native/d3d12.dll';sha256=$hash},
    [pscustomobject]@{path='build/viewer/darktidevr-xr-harness.exe';sha256=$hash}
)
function New-Receipt {
    [pscustomobject]@{schema_version=1;kind='component_build_records';components=@(
        [pscustomobject]@{name='native';source_revision=('1' * 40);source_dirty=$false
            build_command='cmake --build build --config Release --target native'
            toolchain='MSVC fixture';build_options='Release x64';dependencies='fixture versions'
            files=@($files[0],$files[1])},
        [pscustomobject]@{name='viewer';source_revision=('2' * 40);source_dirty=$false
            build_command='cmake --build build --config Release --target viewer'
            toolchain='MSVC fixture';build_options='Release x64';dependencies='fixture versions'
            files=@($files[2])}
    )}
}
$script:checks = 0
function Reject([scriptblock] $Change) {
    # Clone to prevent a mutated nested fixture contaminating subsequent cases.
    $receipt = New-Receipt | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    & $Change $receipt
    $rejected = $false
    try { Assert-ComponentProvenance -Receipt $receipt -Files $files } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid provenance was accepted.' }
    $script:checks++
}
Assert-ComponentProvenance -Receipt (New-Receipt) -Files $files
$script:checks++
Reject { param($r) $r.schema_version=2 }
Reject { param($r) $r.components=@() }
Reject { param($r) $r.components=$r.components[0..0] }
Reject { param($r) $r.components[0].source_dirty=$true }
Reject { param($r) $r.components[0].source_dirty='false' }
Reject { param($r) $r.components[0].source_revision='short' }
Reject { param($r) $r.components[0].toolchain='' }
Reject { param($r) $r.components[0].files[0].sha256=('B' * 64) }
Reject { param($r) $r.components[0].files[0].path='../outside.dll' }
Reject { param($r) $r.components[1].files=@($r.components[0].files[0]) }
Reject { param($r) $r.components[0].files=@() }
Write-Output "component_provenance=pass cases=$script:checks"
