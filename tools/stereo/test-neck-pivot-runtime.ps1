param(
    [string] $LogPath,
    [int] $MinimumSamples = 20,
    [double] $MinimumRawRangeMetres = 0.05,
    [double] $MaximumCompensatedMetres = 0.005,
    [double] $MaximumRequestedCrouchMetres = 0.001
)

$ErrorActionPreference = 'Stop'

if (-not $LogPath) {
    $logDirectory = Join-Path $env:APPDATA 'Fatshark\Darktide\console_logs'
    $LogPath = Get-ChildItem -LiteralPath $logDirectory -Filter '*.log' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $LogPath -or -not (Test-Path -LiteralPath $LogPath)) {
    throw "Darktide console log not found: $LogPath"
}

$pattern = 'neck_height raw_m=(?<raw>-?[0-9.]+) arc_m=(?<arc>-?[0-9.]+) compensated_m=(?<comp>-?[0-9.]+) requested_crouch_m=(?<crouch>-?[0-9.]+) generation=(?<generation>[0-9]+)'
$samples = foreach ($line in Get-Content -LiteralPath $LogPath) {
    if ($line -match $pattern) {
        [pscustomobject]@{
            Raw = [double] $Matches.raw
            Arc = [double] $Matches.arc
            Compensated = [double] $Matches.comp
            Crouch = [double] $Matches.crouch
            Generation = [int] $Matches.generation
        }
    }
}

if ($samples.Count -lt $MinimumSamples) {
    throw "neck_pivot_runtime=fail samples=$($samples.Count) minimum=$MinimumSamples log=$LogPath"
}

$rawValues = @($samples.Raw)
$rawRange = ($rawValues | Measure-Object -Maximum).Maximum -
    ($rawValues | Measure-Object -Minimum).Minimum
$maximumCompensated = ($samples | ForEach-Object {
    [Math]::Abs($_.Compensated)
} | Measure-Object -Maximum).Maximum
$maximumCrouch = ($samples | ForEach-Object {
    [Math]::Abs($_.Crouch)
} | Measure-Object -Maximum).Maximum
$minimumGeneration = ($samples.Generation | Measure-Object -Minimum).Minimum

$failures = @()
if ($rawRange -lt $MinimumRawRangeMetres) {
    $failures += "raw_range=$rawRange<$MinimumRawRangeMetres"
}
if ($maximumCompensated -gt $MaximumCompensatedMetres) {
    $failures += "max_compensated=$maximumCompensated>$MaximumCompensatedMetres"
}
if ($maximumCrouch -gt $MaximumRequestedCrouchMetres) {
    $failures += "max_crouch=$maximumCrouch>$MaximumRequestedCrouchMetres"
}
if ($minimumGeneration -lt 1) {
    $failures += "minimum_generation=$minimumGeneration<1"
}

if ($failures.Count -gt 0) {
    throw "neck_pivot_runtime=fail samples=$($samples.Count) $($failures -join ' ') log=$LogPath"
}

Write-Output (
    'neck_pivot_runtime=pass samples={0} raw_range_m={1:F4} max_compensated_m={2:F4} max_crouch_m={3:F4} generation_min={4} log={5}' -f
    $samples.Count, $rawRange, $maximumCompensated, $maximumCrouch,
    $minimumGeneration, $LogPath)
