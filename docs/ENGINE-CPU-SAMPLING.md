# Engine CPU sampling

`tools/renderer_probe/capture-engine-cpu.ps1` records a bounded Windows CPU
sample trace for investigating stereo engine preparation. It checks the exact
running Darktide path and process start time, refuses an existing or unknown WPR
session, and stops only its uniquely named recorder instance. The memory profile
uses 128 MiB of buffers and sampled stacks, process/thread and module metadata.
It does not collect context switches or establish GPU cost.

Run the required Ready preflight before launching a live XR session. Preserve
the accepted mixed installation with `-SkipDeploymentSync`; set
`DTVR_XR_PRECISE_PAIR_WAIT=1` in that launch process when comparing against the
accepted precise-wait baseline. Capture only after fresh stereo initialization
and nonzero shared-ready counters. For example, with the actual owned game PID:

```powershell
tools/renderer_probe/capture-engine-cpu.ps1 -GameProcessId GAME_PID -GameExe PATH_TO_DARKTIDE_EXE -OutputPath artifacts/diagnostics/engine-cpu.etl -Seconds 20
```

WPR samples the system. Filter analysis to the receipt's PID and process lifetime,
check lost events, and resolve engine addresses against the recorded executable
hash. Memory buffers can wrap: requested duration is not proof that every sample
was retained. Sampling attributes CPU execution, not elapsed waits or GPU time.
Keep ETL files and raw process metadata out of Git. If saving fails, the error
identifies the owned instance; do not cancel unrelated recordings.

## 10 September validation

PowerShell parsing passes. Installed WPR accepts
`wpr -profiledetails tools/renderer_probe/engine-cpu.wprp!EngineCpu`, reporting
the intended 128 buffers of 1024 KiB and sampled-profile stacks. No CPU recording
has been made yet. The subsequent Ready check timed out, and resuming the
Virtual Desktop activity followed by another check returned HMD unavailable.
No game was launched for this trial. Proximity automation was restored.

Receipts remain under `artifacts/unattended/engine-cpu-*-20260910.*`.
