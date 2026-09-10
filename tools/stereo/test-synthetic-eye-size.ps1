$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'resolve-synthetic-eye-size.ps1')
$path = Join-Path ([IO.Path]::GetTempPath()) ('dtvr-size-' + [guid]::NewGuid() + '.json')
function Reject([scriptblock] $Action) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Expected invalid size source to be rejected.' }
}
try {
    $receipt = @{mode='Ready'; readiness_verified=$true; captured_utc=[DateTimeOffset]::UtcNow.ToString('o'); xr_smoke=@{
        result='pass'; exit_code=0; timed_out=$false; output_complete=$true
        state=@('openxr.runtime_name=VirtualDesktopXR','openxr.recommended_size=2496x2688')
    }}
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path
    $size = Resolve-SyntheticEyeSize -VdxrReadinessPath $path
    if ($size.width -ne 2496 -or $size.height -ne 2688 -or $size.receipt_sha256 -ne (Get-FileHash $path).Hash) { throw 'VDXR size/provenance mismatch.' }
    Reject { Resolve-SyntheticEyeSize }
    Reject { Resolve-SyntheticEyeSize -EyeWidth 2112 }
    Reject { Resolve-SyntheticEyeSize -VdxrReadinessPath $path -EyeWidth 2112 -EyeHeight 2304 }
    $explicit = Resolve-SyntheticEyeSize -EyeWidth 2112 -EyeHeight 2304
    if ($explicit.source -ne 'explicit_control') { throw 'Explicit resolution must be labelled.' }
    $receipt.captured_utc = [DateTimeOffset]::UtcNow.AddDays(-2).ToString('o')
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path
    Reject { Resolve-SyntheticEyeSize -VdxrReadinessPath $path }
    $receipt.captured_utc = [DateTimeOffset]::UtcNow.ToString('o')
    $receipt.xr_smoke.state += 'openxr.recommended_size=2112x2304'
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path
    Reject { Resolve-SyntheticEyeSize -VdxrReadinessPath $path }
    $receipt.xr_smoke.state = @('openxr.runtime_name=OpenXR Simulator','openxr.recommended_size=2496x2688')
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path
    Reject { Resolve-SyntheticEyeSize -VdxrReadinessPath $path }
    $receipt.readiness_verified = $false
    $receipt.xr_smoke.state[0] = 'openxr.runtime_name=VirtualDesktopXR'
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path
    Reject { Resolve-SyntheticEyeSize -VdxrReadinessPath $path }
    'synthetic_eye_size=pass'
} finally { Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue }
