[CmdletBinding()]
param(
    [string] $LogPath,

    [ValidateRange(1, 10000)]
    [int] $MinimumSamples = 10,

    # Rapid synthetic locomotion can move the character root between the solve
    # and readback. One millimetre still fails visible drift while allowing the
    # observed one-frame 0.384 mm scheduling residual.
    [ValidateRange(0.000001, 0.01)]
    [double] $MaximumPositionErrorMetres = 0.001,

    [ValidateRange(0.0001, 0.1)]
    [double] $MaximumAngleErrorRadians = 0.005,

    [ValidateRange(45, 180)]
    [double] $MaximumForearmRollDegrees = 100.001
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $LogPath) {
    $logRoot = Join-Path $env:APPDATA 'Fatshark\Darktide\console_logs'
    $latest = Get-ChildItem -LiteralPath $logRoot -Filter 'console-*.log' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) {
        throw "No Darktide console log was found under $logRoot."
    }
    $LogPath = $latest.FullName
}
$resolvedLog = (Resolve-Path -LiteralPath $LogPath).Path
$lines = @(Get-Content -LiteralPath $resolvedLog)

$fatalPatterns = @(
    '\[Script Error\]',
    '\[MOD\]\[darktidevr_stereo_probe\].*\[(ERROR|EXCEPTION)\]',
    'DXGI_ERROR_DEVICE_(HUNG|REMOVED|RESET)',
    'd3d_assert'
)
foreach ($pattern in $fatalPatterns) {
    $hit = $lines | Select-String -Pattern $pattern | Select-Object -First 1
    if ($hit) {
        throw "Runtime log contains a fatal stereo/renderer error: $($hit.Line)"
    }
}

$nodes = @{}
foreach ($line in $lines) {
    if ($line -match 'DARKTIDEVR_IK node name=([^ ]+) index=(\d+) parent=(\d+)') {
        $nodes[$Matches[1]] = @{
            Index = [int] $Matches[2]
            Parent = [int] $Matches[3]
        }
    }
}
foreach ($side in @('left', 'right')) {
    $forearmName = "j_${side}forearm"
    $roll1Name = "j_${side}forearmroll1"
    $roll2Name = "j_${side}forearmroll2"
    foreach ($name in @($forearmName, $roll1Name, $roll2Name)) {
        if (-not $nodes.ContainsKey($name)) {
            throw "Runtime rig inventory did not report required node '$name'."
        }
    }
    $forearmIndex = $nodes[$forearmName].Index
    if ($nodes[$roll1Name].Parent -ne $forearmIndex -or
            $nodes[$roll2Name].Parent -ne $forearmIndex) {
        throw "Runtime $side roll bones are not direct forearm children."
    }
}

$samples = @()
foreach ($line in $lines) {
    if ($line -match 'DARKTIDEVR_IK presentation_writes=(\d+).*max_post_error_m=([\d.]+).*max_angle_error_rad=([\d.]+).*forearm_roll_deg=([-\d.]+),([-\d.]+).*twist_writes=(\d+),(\d+).*twist_chain=j_leftforearmroll1:([\d.]+),j_leftforearmroll2:([\d.]+)\|j_rightforearmroll1:([\d.]+),j_rightforearmroll2:([\d.]+)') {
        $samples += [pscustomobject]@{
            Writes = [int] $Matches[1]
            PositionError = [double] $Matches[2]
            AngleError = [double] $Matches[3]
            LeftRoll = [double] $Matches[4]
            RightRoll = [double] $Matches[5]
            LeftWrites = [int] $Matches[6]
            RightWrites = [int] $Matches[7]
            LeftFirst = [double] $Matches[8]
            LeftSecond = [double] $Matches[9]
            RightFirst = [double] $Matches[10]
            RightSecond = [double] $Matches[11]
        }
    }
}
if ($samples.Count -lt $MinimumSamples) {
    throw "Only $($samples.Count) distributed-twist samples were found; require $MinimumSamples."
}
foreach ($sample in $samples) {
    if ($sample.LeftWrites -ne 2 -or $sample.RightWrites -ne 2) {
        throw "Twist-chain write count regressed at presentation write $($sample.Writes)."
    }
    if ([math]::Abs($sample.LeftRoll) -gt $MaximumForearmRollDegrees -or
            [math]::Abs($sample.RightRoll) -gt $MaximumForearmRollDegrees) {
        throw "Distributed twist exceeded the anatomical limit at presentation write $($sample.Writes)."
    }
    foreach ($pair in @(
        @($sample.LeftFirst, $sample.LeftSecond),
        @($sample.RightFirst, $sample.RightSecond))) {
        if ($pair[0] -le 0 -or $pair[1] -ge 1 -or $pair[0] -ge $pair[1]) {
            throw "Invalid or unordered authored twist fractions: $($pair -join ',')."
        }
    }
}

$maximumPosition = ($samples | Measure-Object PositionError -Maximum).Maximum
$maximumAngle = ($samples | Measure-Object AngleError -Maximum).Maximum
if ($maximumPosition -gt $MaximumPositionErrorMetres) {
    throw "Maximum wrist error $maximumPosition m exceeds $MaximumPositionErrorMetres m."
}
if ($maximumAngle -gt $MaximumAngleErrorRadians) {
    throw "Maximum hand-angle error $maximumAngle rad exceeds $MaximumAngleErrorRadians rad."
}

Write-Output (
    ('body_twist_runtime_check=pass samples={0} max_position_error_m={1:F6} ' +
    'max_angle_error_rad={2:F6} left_fractions={3:F3},{4:F3} ' +
    'right_fractions={5:F3},{6:F3} log={7}') -f
        $samples.Count,
        $maximumPosition,
        $maximumAngle,
        $samples[-1].LeftFirst,
        $samples[-1].LeftSecond,
        $samples[-1].RightFirst,
        $samples[-1].RightSecond,
        $resolvedLog)
