[CmdletBinding()]
param(
    [string] $LogPath,

    [ValidateRange(2, 10000)]
    [int] $MinimumSamples = 5,

    [ValidateRange(0.2, 1.0)]
    [double] $MinimumCrouchMetres = 0.58,

    [ValidateRange(0.000001, 0.01)]
    [double] $MaximumFootErrorMetres = 0.001
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
    'DARKTIDEVR_IK presentation_disabled',
    '\[MOD\]\[darktidevr_stereo_probe\].*\[(ERROR|EXCEPTION)\]',
    'DXGI_ERROR_DEVICE_(HUNG|REMOVED|RESET)',
    'd3d_assert'
)
foreach ($pattern in $fatalPatterns) {
    $hit = $lines | Select-String -Pattern $pattern | Select-Object -First 1
    if ($hit) {
        throw "Runtime log contains a fatal crouch/stereo error: $($hit.Line)"
    }
}

if (-not ($lines -match 'DARKTIDEVR_PSYKHANIUM result=pass')) {
    throw 'The log does not contain a successful unattended Psykhanium entry.'
}

$samples = @()
foreach ($line in $lines) {
    if ($line -match 'DARKTIDEVR_IK presentation_writes=(\d+).*crouch_m=([\d.]+) crouch_result=([^ ]+) crouch_foot_error_m=([\d.]+) max_crouch_foot_error_m=([\d.]+)') {
        $samples += [pscustomobject]@{
            Writes = [int] $Matches[1]
            Crouch = [double] $Matches[2]
            Result = $Matches[3]
            FootError = [double] $Matches[4]
            MaximumFootError = [double] $Matches[5]
        }
    }
}
if ($samples.Count -lt $MinimumSamples) {
    throw "Only $($samples.Count) crouch samples were found; require $MinimumSamples."
}
if (-not ($samples | Where-Object { $_.Crouch -le 0.001 })) {
    throw 'Synthetic crouch never returned to its standing endpoint.'
}
$maximumCrouch = ($samples | Measure-Object Crouch -Maximum).Maximum
if ($maximumCrouch -lt $MinimumCrouchMetres) {
    throw "Maximum crouch $maximumCrouch m did not reach $MinimumCrouchMetres m."
}
$maximumFootError =
    ($samples | Measure-Object MaximumFootError -Maximum).Maximum
if ($maximumFootError -gt $MaximumFootErrorMetres) {
    throw "Maximum planted-foot error $maximumFootError m exceeds $MaximumFootErrorMetres m."
}
$blocked = $samples | Where-Object {
    $_.Result -ne 'standing' -and $_.Result -ne 'written'
} | Select-Object -First 1
if ($blocked) {
    throw "Crouch solve blocked at presentation write $($blocked.Writes): $($blocked.Result)."
}

Write-Output (
    ('body_crouch_runtime_check=pass samples={0} max_crouch_m={1:F4} ' +
    'max_foot_error_m={2:F6} log={3}') -f
        $samples.Count,
        $maximumCrouch,
        $maximumFootError,
        $resolvedLog)
