param(
    [Parameter(Mandatory)][string] $Executable,
    [Parameter(Mandatory)][string] $CaptureLibrary,
    [Parameter(Mandatory)][string] $ReflectionLibrary,
    [ValidateSet('apply', 'fallback')][string] $Mode = 'apply'
)
$ErrorActionPreference = 'Stop'
$sdkBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
$dxc = Get-ChildItem -LiteralPath $sdkBin -Directory |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64/dxc.exe' } |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $dxc) { throw 'DXC is required for the isolated pipeline-probe regression.' }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$evidenceRoot = Join-Path $repoRoot 'artifacts/unattended/pipeline-probe-tests'
$testRoot = Join-Path $evidenceRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
Copy-Item -LiteralPath $CaptureLibrary -Destination (Join-Path $testRoot 'darktidevr_native_capture.dll')
Copy-Item -LiteralPath $ReflectionLibrary -Destination (Join-Path $testRoot 'dxcompiler.dll')
foreach ($entry in 'vs_main', 'ps_stock', 'ps_probe', 'ps_invalid') {
    $profile = if ($entry.StartsWith('vs_')) { 'vs_6_0' } else { 'ps_6_0' }
    & $dxc -T $profile -E $entry -Fo (Join-Path $testRoot "$entry.dxil") (Join-Path $PSScriptRoot 'pipeline_probe.hlsl')
    if ($LASTEXITCODE -ne 0) { throw "Could not compile $entry" }
}
# Retain isolated binaries as evidence. No running game/module path is used.
& $Executable $testRoot $Mode
if ($LASTEXITCODE -ne 0) { throw "Pipeline probe regression failed ($Mode): $testRoot" }
