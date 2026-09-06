Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$reader = Join-Path $PSScriptRoot '../../tools/stereo/read-streamline-continuous-probe.ps1'
$path = Join-Path $env:TEMP ('dtvr-continuous-' + [guid]::NewGuid().ToString('N') + '.tsv')
$valid = @(
    "STEREO_CONTINUOUS`tphase=ready`tframes=2`teye_width=200`teye_height=240`tpublication=0",
    "STEREO_CONTINUOUS`tphase=present`tframe=1`tpresent_frame=10`tpose=30`tpublication=0",
    "STEREO_CONTINUOUS`tphase=ticket`tframe=1`teye=0`tframes_presented=1`tvalue=0",
    "STEREO_CONTINUOUS`tphase=ticket`tframe=1`teye=1`tframes_presented=1`tvalue=0",
    "STEREO_CONTINUOUS`tphase=present`tframe=2`tpresent_frame=11`tpose=31`tpublication=0",
    "STEREO_CONTINUOUS`tphase=ticket`tframe=2`teye=0`tframes_presented=2`tvalue=1",
    "STEREO_CONTINUOUS`tphase=ticket`tframe=2`teye=1`tframes_presented=2`tvalue=1",
    "STEREO_CONTINUOUS`tphase=stopped`tframes=2`ttags_cleared=1`towners_retained=1`tpublication=0"
)
try {
    Set-Content -LiteralPath $path -Value $valid
    $result = & $reader -Path $path
    if (-not $result.ConsecutiveSubmissionVerified -or $result.GeneratedEyePresentsReported -ne 2 -or
        $result.OutputOwnershipVerified -or $result.GeneratedXrPublicationVerified) { throw 'Invalid positive report.' }
    foreach ($scenario in 1..6) {
        $candidate = @($valid)
        switch ($scenario) {
            1 { $candidate[4] = $candidate[4].Replace('present_frame=11', 'present_frame=12') }
            2 { $candidate = @($candidate[0..6]) }
            3 { $candidate[6] = $candidate[5] }
            4 { $candidate[7] = $candidate[7].Replace('tags_cleared=1', 'tags_cleared=0') }
            5 { $candidate += "STEREO_CONTINUOUS`tphase=failed`treason=foreground_lost" }
            6 { $candidate[6] = $candidate[6].Replace('value=1', 'value=18446744073709551615') }
        }
        Set-Content -LiteralPath $path -Value $candidate
        $rejected = $false
        try { & $reader -Path $path | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw "Invalid scenario $scenario was accepted." }
    }
    'continuous_submission_reader=pass'
} finally {
    Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
}
