param([Parameter(Mandatory)] [string] $Reader)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dtvr-ngx-' + [guid]::NewGuid() + '.log')
$header = 'ngx_output_probe=armed schema=1 runtime=32.0.16.1088 resource_get_slot=9 call_limit=32768 sample_limit=256 publication=0'
$record = 'NGX_EVAL call=7 tick_ms=900 thread=4 commands=0000000000001000 feature=0000000000002000 parameters=0000000000003000 result=0x00000001 captured=1 abi_verified=1 output=0000000000004000 backbuffer=0000000000005000 depth=0000000000006000 motion=0000000000007000 hudless=0000000000008000 get_results=1,1,1,1,1 output_complete=0 publication=0'
function Read-Fixture([string[]] $Lines) {
    [IO.File]::WriteAllLines($fixture, $Lines)
    & $Reader -Path $fixture
}
function Require-NoPublication($Report) {
    if ($Report.GeneratedPublicationVerified -or $Report.GpuCompletionVerified -or
        $Report.StereoAssociationVerified) { throw 'Pointer-only log authorized publication.' }
}
try {
    $report = Read-Fixture @($header,$record)
    if (-not $report.ObservationAvailable -or $report.CompleteObservations -ne 1) {
        throw 'Complete identity observation was not recognized.'
    }
    Require-NoPublication $report
    foreach ($mutation in @(
        @('abi_verified=1','abi_verified=0'),
        @('result=0x00000001','result=0xbad00005'),
        @('get_results=1,1,1,1,1','get_results=1,1,bad00005,1,1'),
        @('depth=0000000000006000','depth=0000000000000000'),
        @('output=0000000000004000','output=0000000000005000'),
        @('commands=0000000000001000','commands=0000000000000000'))) {
        $report = Read-Fixture @($header,$record.Replace($mutation[0],$mutation[1]))
        if ($report.ObservationAvailable -or $report.Rejected.Count -ne 1) {
            throw "Unsafe/incomplete observation accepted: $($mutation[0])"
        }
        Require-NoPublication $report
    }
    foreach ($lines in @(
        @($header,$record,$record),
        @($header,$record.Replace('publication=0','publication=1')),
        @($header,$record.Replace('output_complete=0','output_complete=1')),
        @($header,$record.Replace(' depth=0000000000006000','')),
        @($header,$record.Replace('call=7','call=32769')),
        @($header,$record.Replace('call=7','call=oops')),
        @($header,$record + ' call=8'),
        @($header.Replace('schema=1','schema=2'),$record))) {
        $failed = $false
        try { $null = Read-Fixture $lines } catch { $failed = $true }
        if (-not $failed) { throw 'Malformed/contradictory observation was accepted.' }
    }
    $report = Read-Fixture @($header)
    if ($report.ObservationAvailable -or $report.Records -ne 0) { throw 'Header-only log was treated as output evidence.' }
    $report = Read-Fixture @($header,$record.Replace('captured=1','captured=0'))
    if ($report.ObservationAvailable) { throw 'Noncapture call was treated as output evidence.' }
    # Concurrent callbacks may finish out of call-number order.
    $report = Read-Fixture @($header,$record.Replace('call=7','call=8'),$record)
    if ($report.CompleteObservations -ne 2 -or $report.Observations[0].Call -ne 7) {
        throw 'Out-of-order completion was not normalized by call identity.'
    }
    Require-NoPublication $report
    $windowHeader = $header.Replace('schema=1','schema=2').Replace(' publication=0',' wait_for_stereo=1 publication=0')
    $windowRecord = $record.Replace('call=7','call=1000001') + ' window_batch=1 window_present=12131 window_first_call=1000000'
    $report = Read-Fixture @($windowHeader,$windowRecord)
    if (-not $report.ObservationAvailable -or $report.CaptureWindow -ne '1/12131/1000000') {
        throw 'Long startup consumed the gated observation budget.'
    }
    Require-NoPublication $report
    foreach ($lines in @(
        @($windowHeader,$windowRecord.Replace('call=1000001','call=1000000')),
        @($windowHeader,$windowRecord.Replace('call=1000001','call=1032769')),
        @($windowHeader,$windowRecord.Replace('window_batch=1','window_batch=0')),
        @($windowHeader,$windowRecord,$windowRecord.Replace('call=1000001','call=1000002').Replace('window_batch=1','window_batch=2')))) {
        $failed=$false
        try { $null=Read-Fixture $lines } catch { $failed=$true }
        if (-not $failed) { throw 'Invalid or replenished capture window accepted.' }
    }
    Write-Output 'ngx_observation=pass complete failure missing alias duplicate malformed bounded_window no_publication'
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture }
}
