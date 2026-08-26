[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path $PSScriptRoot '..\..\build\generated\billboard_shaders'),

    [string] $DxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\dxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

& $DxcPath -T vs_6_0 -E main -Fo $outputPath $sourcePath
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
