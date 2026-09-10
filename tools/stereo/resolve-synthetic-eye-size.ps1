function Resolve-SyntheticEyeSize {
    param([string] $VdxrReadinessPath, [int] $EyeWidth, [int] $EyeHeight)
    if ($EyeWidth -or $EyeHeight) {
        if ($VdxrReadinessPath -or $EyeWidth -lt 512 -or $EyeWidth -gt 4096 -or
            $EyeHeight -lt 512 -or $EyeHeight -gt 4096) {
            throw 'Supply both explicit eye dimensions (512..4096), or a VDXR readiness receipt, not both.'
        }
        return [pscustomobject]@{width=$EyeWidth; height=$EyeHeight; source='explicit_control'; receipt_sha256=$null; captured_utc=$null}
    }
    if (-not $VdxrReadinessPath) {
        throw 'Supply -VdxrReadinessPath from a fresh Ready preflight to match Virtual Desktop resolution. Explicit -EyeWidth and -EyeHeight are only for deliberate resolution controls.'
    }
    $path = (Resolve-Path -LiteralPath $VdxrReadinessPath).Path
    $bytes = [IO.File]::ReadAllBytes($path)
    $receipt = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xfeff) | ConvertFrom-Json
    if ($receipt.mode -cne 'Ready' -or $receipt.readiness_verified -cne $true -or
        $receipt.xr_smoke.result -cne 'pass' -or $receipt.xr_smoke.exit_code -ne 0 -or
        $receipt.xr_smoke.timed_out -ne $false -or $receipt.xr_smoke.output_complete -ne $true -or
        @($receipt.xr_smoke.state) -cnotcontains 'openxr.runtime_name=VirtualDesktopXR') {
        throw 'Resolution requires a successful, complete VDXR Ready receipt.'
    }
    # New PowerShell versions deserialize ISO dates to DateTime; retain its Kind.
    $captured = if ($receipt.captured_utc -is [DateTime]) {
        [DateTimeOffset]$receipt.captured_utc
    } else { [DateTimeOffset]::Parse($receipt.captured_utc) }
    $age = [DateTimeOffset]::UtcNow - $captured
    if ($age.TotalHours -gt 24 -or $age.TotalMinutes -lt -5) {
        throw 'VDXR resolution receipt is stale or future-dated; capture current settings again.'
    }
    $sizes = @($receipt.xr_smoke.state | Where-Object { $_ -cmatch '^openxr.recommended_size=[0-9]+x[0-9]+$' } | Select-Object -Unique)
    if ($sizes.Count -ne 1) { throw 'VDXR receipt must contain one unambiguous recommended eye size.' }
    $match = [regex]::Match($sizes[0], '=([0-9]+)x([0-9]+)$')
    $width = [int]$match.Groups[1].Value; $height = [int]$match.Groups[2].Value
    if ($width -lt 512 -or $width -gt 4096 -or $height -lt 512 -or $height -gt 4096) {
        throw 'VDXR eye dimensions are outside the supported simulator range.'
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','') }
    finally { $sha.Dispose() }
    [pscustomobject]@{width=$width; height=$height; source='vdxr_ready_recommended_size'; receipt_sha256=$hash; captured_utc=$captured.ToString('o')}
}
