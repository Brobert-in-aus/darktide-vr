param([Parameter(Mandatory)][string] $Reader)
$ErrorActionPreference='Stop'
$base=Join-Path ([IO.Path]::GetTempPath()) ('ngx-queue-test-' + [guid]::NewGuid())
$outputPath=$base + '-output.log'
$queuePath=$base + '-queue.log'
$header='ngx_output_probe=armed schema=3 runtime=32.0.16.1088 resource_get_slot=9 call_limit=32768 sample_limit=256 wait_for_stereo=0 publication=0'
$record='NGX_EVAL call=7 tick_ms=900 thread=4 commands=0000000000001000 feature=0000000000002000 parameters=0000000000003000 result=0x00000001 captured=1 abi_verified=1 feature_kind=11 feature_lifetime=1 output=0000000000004000 backbuffer=0000000000005000 depth=0000000000006000 motion=0000000000007000 hudless=0000000000008000 get_results=1,1,1,1,1 window_batch=0 window_present=0 window_first_call=0 output_complete=0 publication=0'
$submit='NGX_SUBMIT call=7 commands=0000000000001000 queue=0000000000000050 queue_type=2 tick_ms=901 thread=4 gpu_complete=0'
$signal='NGX_FENCE call=7 ticket=1 queue=0000000000000050 fence=0000000000000060 value=1 result=0x00000000 gpu_complete=0'
$complete='NGX_COMPLETE call=7 ticket=1 fence=0000000000000060 completed=1 gpu_complete=1 publication=0'
function Read-Queue([string[]]$Lines) {
    [IO.File]::WriteAllLines($queuePath,$Lines)
    & $Reader -OutputPath $outputPath -QueuePath $queuePath
}
try {
    [IO.File]::WriteAllLines($outputPath,@($header,$record))
    $report=Read-Queue @($submit,$signal,$complete)
    if (-not $report.EvaluationCommandsCompleted -or $report.GeneratedPublicationVerified -or $report.GpuCompletionVerified) { throw 'Completion evidence failed or authorized output publication.' }
    foreach ($lines in @(@($submit),@($submit,$signal),@($submit,$signal,$complete.Replace('completed=1','completed=18446744073709551615')))) {
        $report=Read-Queue $lines
        if ($report.EvaluationCommandsCompleted) { throw 'Missing/device-removed completion accepted.' }
    }
    foreach ($lines in @(@($submit,$complete),@($submit,$signal,$complete.Replace('ticket=1','ticket=2')),
            @($submit,$signal.Replace('queue=0000000000000050','queue=0000000000000051'),$complete),
            @($submit,$signal,$complete,$complete))) {
        $rejected=$false
        try { $null=Read-Queue $lines } catch { $rejected=$true }
        if (-not $rejected) { throw 'Mismatched/duplicate completion accepted.' }
    }
    'ngx_queue_completion=pass'
} finally {
    Remove-Item -LiteralPath $outputPath,$queuePath -ErrorAction SilentlyContinue
}
