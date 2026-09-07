[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path $PSScriptRoot '..\..\build\generated\billboard_shaders'),

    [string] $DxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\dxc.exe',

    [switch] $DiagnosticMagenta,

    [switch] $DiagnosticZeroSpin,

    [switch] $PreserveParticleSpin,

    [switch] $DiagnosticSpherical,

    [ValidateRange(1, 20)]
    [int] $DiagnosticScale = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop

if (-not (Test-Path -LiteralPath $DxcPath -PathType Leaf)) {
    throw "DXC not found: $DxcPath"
}

$sourcePath = Join-Path $PSScriptRoot 'particle-horizon-lock.vs.hlsl'
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Particle horizon-lock source not found: $sourcePath"
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
$outputPath = Join-Path $resolvedOutput 'vs-42e436fb1ef1b392.dxil'

if ($DiagnosticZeroSpin -and $PreserveParticleSpin) {
    throw '-DiagnosticZeroSpin and -PreserveParticleSpin are mutually exclusive.'
}
# A cylindrical plane alone is insufficient for a strict horizon lock: the
# stock per-particle angle rotates its local up vector away from world Z. Keep
# zero spin as the production default; the opt-out exists only as an A/B
# diagnostic for the original behavior.
$zeroSpin = if ($PreserveParticleSpin) { 0 } else { 1 }
$cylindrical = if ($DiagnosticSpherical) { 0 } else { 1 }
& $DxcPath -T vs_6_0 -E main `
    -D "DTVR_PARTICLE_DIAGNOSTIC_SCALE=$DiagnosticScale" `
    -D "DTVR_PARTICLE_DIAGNOSTIC_ZERO_SPIN=$zeroSpin" `
    -D "DTVR_PARTICLE_CYLINDRICAL=$cylindrical" `
    -Fo $outputPath $sourcePath
if ($LASTEXITCODE -ne 0) {
    throw 'DXC could not compile the particle horizon-lock vertex shader.'
}

$dump = & $DxcPath -dumpbin $outputPath
if ($LASTEXITCODE -ne 0 -or
        -not ($dump -match 'SV_Position') -or
        -not ($dump -match 'TEXCOORD\s+16') -or
        -not ($dump -match 'c_per_objectUBO')) {
    throw 'Compiled particle shader failed its interface smoke check.'
}

Write-Output "Built particle horizon-lock shader: $outputPath"
Write-Output "Particle diagnostic geometry scale: ${DiagnosticScale}x"
Write-Output "Particle horizon-lock zero spin: $($zeroSpin -eq 1)"
Write-Output "Particle diagnostic basis: $(if ($DiagnosticSpherical) { 'spherical' } else { 'cylindrical' })"

if ($DiagnosticMagenta) {
    $pixelSourcePath = Join-Path $PSScriptRoot 'particle-diagnostic-magenta.ps.hlsl'
    if (-not (Test-Path -LiteralPath $pixelSourcePath -PathType Leaf)) {
        throw "Particle diagnostic pixel source not found: $pixelSourcePath"
    }
    $pixelOutputPath = Join-Path $resolvedOutput 'ps-6020f2548f29fd47.dxil'
    & $DxcPath -T ps_6_0 -E ps_main -Fo $pixelOutputPath $pixelSourcePath
    if ($LASTEXITCODE -ne 0) {
        throw 'DXC could not compile the particle diagnostic pixel shader.'
    }
    $pixelDump = & $DxcPath -dumpbin $pixelOutputPath
    if ($LASTEXITCODE -ne 0 -or
            -not ($pixelDump -match 'SV_Position') -or
            -not ($pixelDump -match 'TEXCOORD\s+16') -or
            -not ($pixelDump -match 'CUSTOM\s+4')) {
        throw 'Compiled particle diagnostic shader failed its interface smoke check.'
    }
    Write-Output "Built magenta particle diagnostic shader: $pixelOutputPath"
}

# Packages can carry this verified production output without requiring DXC on
# the destination. Diagnostic builds are stamped too, so they cannot masquerade
# as the production variant merely by sharing its output filename.
$productionProfile = -not $DiagnosticMagenta -and -not $PreserveParticleSpin -and
    -not $DiagnosticSpherical -and $DiagnosticScale -eq 1
[ordered]@{
    schema_version = 1
    profile = if ($productionProfile) { 'production' } else { 'diagnostic' }
    scale = $DiagnosticScale; zero_spin = $zeroSpin; cylindrical = $cylindrical
    source_sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    shader_sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $resolvedOutput 'production-shader.json') -Encoding UTF8
