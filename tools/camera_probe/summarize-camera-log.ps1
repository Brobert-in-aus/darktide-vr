[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $LogPath,

    [string] $OutputJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$number = '[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?'
$pattern = "DARKTIDEVR_CAMERA schema=1 viewport=(\S+) " +
    "position=($number),($number),($number) " +
    "rotation=($number),($number),($number),($number) " +
    "vfov(?:_rad)?=($number)"
$culture = [Globalization.CultureInfo]::InvariantCulture
$samples = @()

foreach ($line in Get-Content -LiteralPath $LogPath) {
    $match = [regex]::Match($line, $pattern)
    if (-not $match.Success) {
        continue
    }

    $values = @()
    for ($index = 2; $index -le 9; ++$index) {
        $value = [double]::Parse(
            $match.Groups[$index].Value,
            [Globalization.NumberStyles]::Float,
            $culture)
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) {
            throw "Camera probe contains a non-finite value"
        }
        $values += $value
    }

    $quaternionNorm = [math]::Sqrt(
        $values[3] * $values[3] + $values[4] * $values[4] +
        $values[5] * $values[5] + $values[6] * $values[6])
    if ([math]::Abs($quaternionNorm - 1.0) -gt 0.01) {
        throw "Camera probe contains a non-unit quaternion"
    }

    $samples += [ordered]@{
        viewport = $match.Groups[1].Value
        position = @($values[0], $values[1], $values[2])
        rotation = @($values[3], $values[4], $values[5], $values[6])
        vertical_fov_rad = $values[7]
    }
}

if ($samples.Count -eq 0) {
    throw "No valid DARKTIDEVR_CAMERA samples found in $LogPath"
}

$uniquePositions = @(
    $samples |
        ForEach-Object { $_.position -join ',' } |
        Sort-Object -Unique
)
$summary = [ordered]@{
    schema_version = 1
    source = 'Darktide semantic camera manager'
    sample_count = $samples.Count
    viewports = @($samples.viewport | Sort-Object -Unique)
    unique_position_count = $uniquePositions.Count
    first_sample = $samples[0]
    last_sample = $samples[-1]
}

$json = $summary | ConvertTo-Json -Depth 8
if ($OutputJson) {
    $parent = Split-Path -Parent $OutputJson
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputJson -Value $json -Encoding utf8
}
$json
