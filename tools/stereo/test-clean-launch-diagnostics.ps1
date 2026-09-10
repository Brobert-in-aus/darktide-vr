$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'clean-launch-diagnostics.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('dtvr-clean-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $root | Out-Null
try {
    $names=@('darktidevr_resource_handle_trace.flag','darktidevr_streamline_copy_probe.flag',
        'darktidevr_performance_profile.flag','darktidevr_body_ik_trace.flag',
        'darktidevr_streamline_stereo_submit_probe.flag','darktidevr_hud_panel.flag')
    foreach($name in $names){[IO.File]::WriteAllBytes((Join-Path $root $name),[byte[]](49,13,10,0))}
    $saved=@{}
    Set-CleanLaunchDiagnostics -ModRoot $root -Saved $saved
    if(Test-Path (Join-Path $root $names[0])){throw 'Presence flag not removed'}
    if(Test-Path (Join-Path $root $names[1])){throw 'Copy flag not removed'}
    if((Get-Content (Join-Path $root $names[2]) -Raw).Trim() -ne 'disabled'){throw 'Profiler not disabled'}
    foreach($name in $names[4..5]){if((Get-Item (Join-Path $root $name)).Length -ne 4){throw 'Functional flag changed'}}
    Restore-CleanLaunchDiagnostics -Saved $saved
    foreach($name in $names){if([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root $name))) -ne 'MQ0KAA=='){throw 'Bytes not restored'}}
    $saved=@{}
    Set-CleanLaunchDiagnostics -ModRoot $root -Saved $saved -ResourceHandleTrace $true -CopyProbe $true -PerformanceProfile $true
    foreach($name in $names[0..2]){if([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root $name))) -ne 'MQ0KAA=='){throw 'Explicit diagnostic overridden'}}
    Restore-CleanLaunchDiagnostics -Saved $saved
    'clean_launch_diagnostics=pass'
} finally {
    foreach($name in $names){Remove-Item -LiteralPath (Join-Path $root $name) -ErrorAction SilentlyContinue}
    Remove-Item -LiteralPath $root
}
