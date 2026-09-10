# Worker-thread residency

`read-benchmark-threads.ps1` records thread names and a roughly one-second CPU
delta from an active run-owned benchmark process. It verifies the executable
hash, path and process lifetime. Names are observations, not authoritative role
identification, and CPU deltas include active waits. The inventory stays in the
ignored benchmark directory.

`capture-thread-residency.ps1 -ThreadId` selects an explicitly observed thread
from that same process. Its default remains the observed Present thread. The
engine layout option is rejected for other threads. Separate output directories
prevent worker captures from replacing the render-thread receipt. Native capture
still verifies process ownership and lifetime and preserves foreign suspensions.

The stack excerpt is now bounded at 512 bytes (64 words), so a worker wait can
be followed beyond Windows and C++ wrappers when their exact prologs establish
the return slots. This is not a general unwinder. The reader additionally reports
module-relative hot locations; old 32-word receipts remain readable.

## First mission capture

The inventory exposed `renderer`, `main`, and six threads named `wt_0`–`wt_5`.
The busiest worker in that one-second window used 562.5 ms CPU, versus 984.38 ms
for renderer. Two sequential captures collected 1,000 and 500 samples from
workers `wt_2` and `wt_0`. The former had 595 samples in the local ntdll
`ZwWaitForAlertByThreadId` syscall return. Of those, 566 follow the verified
`RtlSleepConditionVariableSRW` and KernelBase wrapper return slots into the C++
runtime. The 256-byte excerpt ended before the engine caller; a larger bounded
repeat is required to classify idle-work waiting versus a rendering dependency.

These are instruction residency observations, not CPU-time shares or frame
performance measurements. The first benchmark exits cleanly and restores all
files. Windows x64 sampler build and `thread_residency_self` pass after expanding
the excerpt, and both PowerShell scripts parse successfully.

Local evidence: `synthetic-solo-worker-residency-a-20260910`, including its
thread inventory and separate worker capture directories, under ignored
`artifacts/unattended`.

## Larger repeat

The 1,000-sample repeat on `wt_1` resolves 570 waits through this manually
verified chain on the captured machine's DLLs:

| Stack word | Return location |
| --- | --- |
| 0 | ntdll `5fc6e`, inside `RtlSleepConditionVariableSRW` |
| 20 | KernelBase `22cd8`, condition-variable wrapper |
| 28 | MSVCP140 `176ea`, C++ condition-variable wait |
| 34 | engine `70f2bf`, primary `70f200`, wait-on-value helper |
| 40 | engine `6f6eae`, primary worker loop `6f6db0` |

The engine caller checks both work queues before entering this no-work wait.
Thus these observations are idle-worker waits, not 570 active command-building
samples. They do not establish overlap with a render-thread dispatch wait:
the threads were sampled separately. More workers are not justified by these
snapshots; work availability and dependency timing remain useful next targets.

Mean pause was 57.07 microseconds and maximum 351.2. The repeat exits cleanly
and restores exactly. Evidence: `synthetic-solo-worker-residency-b-20260910`,
`worker1-summary-b-20260910.json`, and `engine-worker-wait-caller-20260910.txt`.
Windows DLL offsets are machine-build-specific and must not become a generic
unwinder without validating those DLLs and the intervening prologs.
