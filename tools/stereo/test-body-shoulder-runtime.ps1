[CmdletBinding()]
param(
    [string] $LogPath,

    [ValidateRange(3, 10000)]
    [int] $MinimumSamples = 12,

    [ValidateRange(0.000001, 0.01)]
    [double] $MaximumHandErrorMetres = 0.001,

    [ValidateRange(0.1, 10)]
    [double] $BilateralYawToleranceDegrees = 3.0
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

foreach ($pattern in @(
    '\[Script Error\]',
    'DARKTIDEVR_IK shoulder_reach_blocked',
    'DARKTIDEVR_IK presentation_disabled',
    'DXGI_ERROR_DEVICE_(HUNG|REMOVED|RESET)',
    'd3d_assert')) {
    $hit = $lines | Select-String -Pattern $pattern | Select-Object -First 1
    if ($hit) {
        throw "Runtime log contains a fatal shoulder/stereo error: $($hit.Line)"
    }
}

$samples = @()
foreach ($line in $lines) {
    if ($line -match 'DARKTIDEVR_IK presentation_writes=(\d+) post_error_m=([\d.]+).*shoulder_request_m=([\d.]+),([\d.]+) shoulder_applied_m=([\d.]+),([\d.]+) shoulder_yaw_deg=([-\d.]+) shoulder_chain=([^ ]+) character_scale=([\d.]+) arm_length_m=([\d.]+),([\d.]+) shoulder_width_m=([\d.]+)') {
        $samples += [pscustomobject]@{
            Writes = [int] $Matches[1]
            HandError = [double] $Matches[2]
            LeftRequest = [double] $Matches[3]
            RightRequest = [double] $Matches[4]
            LeftApplied = [double] $Matches[5]
            RightApplied = [double] $Matches[6]
            Yaw = [double] $Matches[7]
            Chain = $Matches[8]
            CharacterScale = [double] $Matches[9]
            LeftArm = [double] $Matches[10]
            RightArm = [double] $Matches[11]
            ShoulderWidth = [double] $Matches[12]
        }
    }
}
if ($samples.Count -lt $MinimumSamples) {
    throw "Only $($samples.Count) shoulder samples were found; require $MinimumSamples."
}

$invalidGeometry = $samples | Where-Object {
    $_.CharacterScale -lt 0.5 -or $_.CharacterScale -gt 1.5 -or
    $_.LeftArm -lt 0.3 -or $_.LeftArm -gt 1.5 -or
    $_.RightArm -lt 0.3 -or $_.RightArm -gt 1.5 -or
    $_.ShoulderWidth -lt 0.2 -or $_.ShoulderWidth -gt 1.0 -or
    $_.Chain -notmatch 'j_spine:' -or
    $_.Chain -notmatch 'j_spine1:' -or
    $_.Chain -notmatch 'j_spine2:'
} | Select-Object -First 1
if ($invalidGeometry) {
    throw "Scaled rig geometry or constrained spine chain is invalid at write $($invalidGeometry.Writes)."
}

$leftOnly = $samples | Where-Object {
    $_.LeftApplied -gt 0.01 -and $_.LeftApplied -gt $_.RightApplied + 0.008
} | Sort-Object { [math]::Abs($_.Yaw) } -Descending | Select-Object -First 1
$rightOnly = $samples | Where-Object {
    $_.RightApplied -gt 0.01 -and $_.RightApplied -gt $_.LeftApplied + 0.008
} | Sort-Object { [math]::Abs($_.Yaw) } -Descending | Select-Object -First 1
$bilateral = $samples | Where-Object {
    $_.LeftApplied -gt 0.01 -and $_.RightApplied -gt 0.01 -and
    [math]::Abs($_.LeftApplied - $_.RightApplied) -lt 0.005
} | Sort-Object { [math]::Abs($_.Yaw) } | Select-Object -First 1
if (-not $leftOnly -or -not $rightOnly -or -not $bilateral) {
    throw 'Synthetic path did not exercise left-only, right-only, and equal bilateral shoulder reach.'
}
if ($leftOnly.Yaw * $rightOnly.Yaw -ge 0) {
    throw 'Left-only and right-only reaches did not request opposing girdle yaw.'
}
if ([math]::Abs($bilateral.Yaw) -gt $BilateralYawToleranceDegrees) {
    throw "Equal bilateral reach left $([math]::Abs($bilateral.Yaw)) degrees of girdle yaw."
}
$maximumError = ($samples | Measure-Object HandError -Maximum).Maximum
if ($maximumError -gt $MaximumHandErrorMetres) {
    throw "Maximum hand error $maximumError m exceeds $MaximumHandErrorMetres m."
}

Write-Output (
    ('body_shoulder_runtime_check=pass samples={0} max_hand_error_m={1:F6} ' +
    'scale={2:F4} arms_m={3:F4},{4:F4} shoulder_width_m={5:F4} ' +
    'left_yaw_deg={6:F2} right_yaw_deg={7:F2} bilateral_yaw_deg={8:F2} log={9}') -f
        $samples.Count,
        $maximumError,
        $samples[-1].CharacterScale,
        $samples[-1].LeftArm,
        $samples[-1].RightArm,
        $samples[-1].ShoulderWidth,
        $leftOnly.Yaw,
        $rightOnly.Yaw,
        $bilateral.Yaw,
        $resolvedLog)
