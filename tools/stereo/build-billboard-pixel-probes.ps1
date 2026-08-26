[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $CapturedShaderDirectory,

    [string] $OutputDirectory = (Join-Path $PSScriptRoot '..\..\build\generated\billboard_shaders'),

    [string] $DxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\dxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $DxcPath -PathType Leaf)) {
    throw "DXC not found: $DxcPath"
}
if (-not (Test-Path -LiteralPath $CapturedShaderDirectory -PathType Container)) {
    throw "Captured shader directory not found: $CapturedShaderDirectory"
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory)
$sourceOutput = Join-Path $resolvedOutput 'generated_hlsl'
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
New-Item -ItemType Directory -Path $sourceOutput -Force | Out-Null

$built = 0
foreach ($shader in Get-ChildItem -LiteralPath $CapturedShaderDirectory -Filter 'ps-*.bin' -File) {
    if ($shader.Name -notmatch '^ps-([0-9a-fA-F]{16})\.bin$') {
        continue
    }
    $hash = $Matches[1].ToLowerInvariant()
    $dump = & $DxcPath -dumpbin $shader.FullName
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Skipping shader DXC cannot inspect: $($shader.Name)"
        continue
    }

    $inputStart = [Array]::IndexOf($dump, '; Input signature:')
    $outputStart = [Array]::IndexOf($dump, '; Output signature:')
    if ($inputStart -lt 0 -or $outputStart -le $inputStart) {
        Write-Warning "Skipping shader without a pixel input signature: $($shader.Name)"
        continue
    }

    $fields = [Collections.Generic.List[string]]::new()
    $fieldIndex = 0
    for ($lineIndex = $inputStart + 1; $lineIndex -lt $outputStart; ++$lineIndex) {
        $line = $dump[$lineIndex]
        if ($line -notmatch '^;\s+(\S+)\s+(\d+)\s+([xyzw]+)\s+(\d+)\s+(\S+)\s+(\S+)') {
            continue
        }
        $name = $Matches[1]
        $index = [int]$Matches[2]
        $mask = $Matches[3]
        $format = $Matches[6].ToLowerInvariant()
        $componentCount = $mask.Length
        $scalar = switch ($format) {
            'float' { 'float' }
            'uint' { 'uint' }
            'sint' { 'int' }
            'int' { 'int' }
            default { throw "Unsupported signature format '$format' in $($shader.Name)" }
        }
        $type = if ($componentCount -eq 1) { $scalar } else { "$scalar$componentCount" }
        $semantic = if ($name.StartsWith('SV_') -and $index -eq 0) {
            $name
        } else {
            "$name$index"
        }
        $fields.Add("  $type value$fieldIndex : $semantic;")
        ++$fieldIndex
    }
    if ($fields.Count -eq 0) {
        Write-Warning "Skipping shader with an empty pixel input signature: $($shader.Name)"
        continue
    }

    $sourcePath = Join-Path $sourceOutput "ps-$hash.hlsl"
    $source = @(
        'struct PixelInput {'
        $fields
        '};'
        ''
        'float4 ps_main(PixelInput input) : SV_Target0 {'
        '  return float4(1.0, 0.0, 1.0, 1.0);'
        '}'
    )
    [IO.File]::WriteAllLines($sourcePath, $source)

    $outputPath = Join-Path $resolvedOutput "ps-$hash.dxil"
    & $DxcPath -T ps_6_0 -E ps_main -Fo $outputPath $sourcePath
    if ($LASTEXITCODE -ne 0) {
        throw "DXC could not compile probe for $($shader.Name)"
    }
    ++$built
}

Write-Output "Built $built interface-matched billboard pixel probes in $resolvedOutput"
