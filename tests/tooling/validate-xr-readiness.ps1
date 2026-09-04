$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tools/unattended/xr-readiness.ps1')
function Test-Path { param($LiteralPath, $PathType) return $LiteralPath -eq 'C:\fixture\virtualdesktop-openxr.json' }
$valid = @{
    StreamerCount = 1; Runtime = 'C:\fixture\virtualdesktop-openxr.json'
    PowerLines = @('mWakefulness=Awake', 'mHoldingDisplaySuspendBlocker=true')
    PowerExitCode = 0
}
Assert-XrReadiness @valid
foreach ($change in @(
    @{ StreamerCount = 0 }, @{ Runtime = 'C:\fixture\other.json' },
    @{ Runtime = '' }, @{ PowerExitCode = 1 },
    @{ PowerLines = @('mWakefulness=Asleep', 'mHoldingDisplaySuspendBlocker=false') },
    @{ PowerLines = @() }
)) {
    $candidate = $valid.Clone()
    foreach ($key in $change.Keys) { $candidate[$key] = $change[$key] }
    $rejected = $false
    try { Assert-XrReadiness @candidate } catch { $rejected = $true }
    if (-not $rejected) { throw 'Readiness accepted an invalid fixture' }
}
Write-Output 'xr_readiness=pass cases=7'
