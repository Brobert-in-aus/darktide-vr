[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $CandidateDirectory,

    [Parameter(Mandatory)]
    [string] $SourceHlslDirectory,

    [Parameter(Mandatory)]
    [string] $OutputDirectory,

    [switch] $HueWheel,

    [string] $DxcPath = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\dxc.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($path in $CandidateDirectory, $SourceHlslDirectory) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "Directory not found: $path"
    }
}
if (-not (Test-Path -LiteralPath $DxcPath -PathType Leaf)) {
    throw "DXC not found: $DxcPath"
}

$palette = [Collections.Generic.List[object]]::new()
$levels = 0.0, 0.2, 0.4, 0.6, 0.8, 1.0
foreach ($red in $levels) {
    foreach ($green in $levels) {
        foreach ($blue in $levels) {
            $maximum = [math]::Max($red, [math]::Max($green, $blue))
            $minimum = [math]::Min($red, [math]::Min($green, $blue))
            $luma = 0.2126 * $red + 0.7152 * $green + 0.0722 * $blue
            if ($maximum -ge 0.6 -and ($maximum - $minimum) -ge 0.4 -and
                $luma -ge 0.12 -and $luma -le 0.95) {
                $palette.Add([pscustomobject]@{
                    Red = $red
                    Green = $green
                    Blue = $blue
                })
            }
        }
    }
}

$candidates = @(Get-ChildItem -LiteralPath $CandidateDirectory `
    -Filter 'ps-*.dxil' -File | Sort-Object Name)
if ($HueWheel) {
    $palette.Clear()
    for ($index = 0; $index -lt $candidates.Count; ++$index) {
        $sectorValue = 6.0 * $index / $candidates.Count
        $sector = [math]::Floor($sectorValue)
        $fraction = $sectorValue - $sector
        $low = 0.1
        $rising = 0.1 + 0.9 * $fraction
        $falling = 1.0 - 0.9 * $fraction
        $red, $green, $blue = switch ($sector) {
            0 { 1.0, $rising, $low; break }
            1 { $falling, 1.0, $low; break }
            2 { $low, 1.0, $rising; break }
            3 { $low, $falling, 1.0; break }
            4 { $rising, $low, 1.0; break }
            default { 1.0, $low, $falling; break }
        }
        $palette.Add([pscustomobject]@{
            Red = $red
            Green = $green
            Blue = $blue
        })
    }
}
if ($candidates.Count -gt $palette.Count) {
    throw "Need $($candidates.Count) ID colours but palette has $($palette.Count)"
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory)
$sourceOutput = Join-Path $resolvedOutput 'generated_hlsl'
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
New-Item -ItemType Directory -Path $sourceOutput -Force | Out-Null

$manifest = [Collections.Generic.List[string]]::new()
$manifest.Add("index`thash`tred`tgreen`tblue")
for ($index = 0; $index -lt $candidates.Count; ++$index) {
    $candidate = $candidates[$index]
    $hash = $candidate.BaseName.Substring(3)
    $sourcePath = Join-Path $SourceHlslDirectory "ps-$hash.hlsl"
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Generated source not found: $sourcePath"
    }
    $colour = $palette[$index]
    $source = Get-Content -LiteralPath $sourcePath -Raw
    $replacement = 'return float4({0:F1}, {1:F1}, {2:F1}, 1.0);' -f `
        $colour.Red, $colour.Green, $colour.Blue
    $source = $source.Replace(
        'return float4(1.0, 0.0, 1.0, 1.0);',
        $replacement
    )
    if ($source -notmatch [regex]::Escape($replacement)) {
        throw "Could not inject shader ID colour into $sourcePath"
    }
    $generatedSource = Join-Path $sourceOutput "ps-$hash.hlsl"
    [IO.File]::WriteAllText($generatedSource, $source)
    $output = Join-Path $resolvedOutput "ps-$hash.dxil"
    & $DxcPath -T ps_6_0 -E ps_main -Fo $output $generatedSource
    if ($LASTEXITCODE -ne 0) {
        throw "DXC could not compile shader ID probe for $hash"
    }
    $manifest.Add(("{0}`t{1}`t{2:F1}`t{3:F1}`t{4:F1}" -f
        $index, $hash, $colour.Red, $colour.Green, $colour.Blue))
}

[IO.File]::WriteAllLines((Join-Path $resolvedOutput 'manifest.tsv'), $manifest)
Write-Output "Built $($candidates.Count) shader-ID probes in $resolvedOutput"
