Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/stereo/shared-stereo-evidence.ps1')

function Check-Evidence([string[]] $Lines, [bool] $Expected) {
    $evidence = @{}
    foreach ($line in $Lines) { Add-SharedStereoEvidence -Evidence $evidence -Line $line }
    $passed = $false
    try {
        $result = Assert-SharedStereoEvidence -Evidence $evidence
        if ($result -notmatch '^stereo.delivery=verified .*visual_acceptance=pending$') {
            throw 'Unexpected evidence result'
        }
        $passed = $true
    } catch {
        if ($_.Exception.Message -notlike 'Automatic gameplay run did not verify*') { throw }
    }
    if ($passed -ne $Expected) { throw "Shared stereo evidence acceptance mismatch: $($Lines -join '; ')" }
}
$valid = @('openxr.presentation=shared-eye-projection',
    'openxr.fresh_shared_pairs=12', 'openxr.submitted_frames=1200')
Check-Evidence ($valid + @('openxr.flat_fallback_frames=30','result=pass')) $true
Check-Evidence @('openxr.presentation=shared-eye-projection',
    'openxr.fresh_shared_pairs=0','openxr.submitted_frames=1200','result=pass') $false
Check-Evidence @('openxr.presentation=shared-eye-projection',
    'openxr.fresh_shared_pairs=0','openxr.reused_shared_frames=1200',
    'openxr.submitted_frames=1200') $false
foreach ($index in 0..2) {
    Check-Evidence @($valid[@(0..2 | Where-Object { $_ -ne $index })]) $false
    Check-Evidence ($valid + $valid[$index]) $false
}
foreach ($bad in @('-1','NaN','18446744073709551616','0')) {
    Check-Evidence @($valid[0],"openxr.fresh_shared_pairs=$bad",$valid[2]) $false
    Check-Evidence @($valid[0],$valid[1],"openxr.submitted_frames=$bad") $false
}
Check-Evidence @('openxr.presentation=theatre-quad',$valid[1],$valid[2]) $false
Check-Evidence @('openxr.live tick=10 shared_ready=1000 fresh_pair_fps=90','result=pass') $false
Check-Evidence @() $false

# Execute the real start-script argument expression without setup, and verify
# the runner routes native text into evidence before its final check.
$tokens = $errors = $null
$tree = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $repo 'tools/stereo/start-darktide-vr.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw $errors[0] }
$assignment = $tree.Find({ param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$runnerArguments'
}, $true)
$argumentsBlock = [ScriptBlock]::Create($assignment.Extent.Text)
$DurationSeconds=5; $GameStartTimeoutSeconds=10; $ProjectionTranslationScale=1.0; $GameRoot=$repo
foreach ($AutoEnterHub in @($false,$true)) {
    foreach ($EnterPsykhanium in @($false,$true)) {
        . $argumentsBlock
        if ($runnerArguments.RequireSharedStereo -ne ($AutoEnterHub -or $EnterPsykhanium)) {
            throw 'Automatic gameplay launch lost its stereo requirement'
        }
    }
}
$runner = Get-Content (Join-Path $repo 'tools/stereo/run-darktide-shared-eyes.ps1') -Raw
if ($runner -notmatch 'Add-SharedStereoEvidence -Evidence \$sharedStereoEvidence -Line \$line' -or
        $runner -notmatch 'Assert-SharedStereoEvidence -Evidence \$sharedStereoEvidence') {
    throw 'Runner lost shared stereo evidence routing'
}
Write-Output 'launcher_shared_stereo_evidence=pass flat_fallback missing duplicate invalid counts automatic_gameplay'
