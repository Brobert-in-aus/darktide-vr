# Paired render and worker observation

Separate thread samples could not establish whether a worker was idle during
the render dispatcher wait. The bounded residency sampler now accepts one
optional peer thread. It pauses the primary, reads its existing context, pauses
the peer, reads its context and 512-byte stack, resumes the peer, then resumes
the primary. Both handles must belong to the verified process. Existing suspend
counts are preserved and cause capture rejection after both increments are
undone. No logging, allocations or waits occur while either target is paused.

Use `capture-thread-residency.ps1 -PeerThreadId ID` with a freshly observed
worker from `read-benchmark-threads.ps1`. The reader reports peer locations for
all samples and for the exact-build verified dispatcher-wait subset. Windows
locations remain unresolved in generic output; raw stack words are not a
general-purpose unwind. Existing single-thread captures remain readable.

## 10 September capture

Two 1,000-sample captures used the same stationary SoloPlay mission with FG off,
120 Hz simulator, uncapped native rendering and the focused Present-CPU native
candidate. Each paired the renderer with one observed worker:

| Peer | Verified dispatcher waits | Peer idle-wait chain | Mean primary pause | Maximum pause |
| --- | ---: | ---: | ---: | ---: |
| wt_1 | 84 | 32 | 84.07 us | 1,228.3 us |
| wt_0 | 86 | 49 | 83.22 us | 255.2 us |

All counted idle samples match the previously inspected machine-specific chain:
ntdll `163fd4`, stack words 0=`ntdll+5fc6e`, 20=`KernelBase+22cd8`,
28=`MSVCP140+176ea`, 34=`engine+70f2bf`, 40=`engine+6f6eae`.
The engine worker loop checks both work queues before this idle wait. The
second capture explicitly confirms the final two engine return slots in all
49 samples; the first has the same slots in all 32.

These are perturbed overlaps: the worker can finish work while the primary is
paused before the peer read. They are not atomic running-state snapshots,
CPU-time percentages, or proof that all workers are idle. They support further
investigation of work availability and dispatch tail balance, not more workers
or a speculative engine patch.

Windows x64 Release build and `thread_residency_self` pass, including paired
capture and preservation of a pre-existing peer suspension. The prior queue
capture remains readable with peer data absent. Both new captures completed
1,000 samples. Mission cleanup and exact restoration passed; performance under
debugger sampling is not an optimisation result.

Local evidence: ignored `synthetic-solo-paired-residency-a-20260910`, its two
`thread-residency-peer-*` directories and thread inventory. No raw machine
artifacts or binaries are committed.

## 11 September, after descriptor and native-ring improvement

A new 1,000-sample capture uses the preserved ring/Present-CPU diagnostic
`83E4D445...`, the unchanged sampler `0C23557A...`, Quality DLSS at 2496x2688,
FG off and the same stationary mission. A fresh one-second thread inventory
selected `wt_0`, the busiest observed named worker (593.75 ms CPU in that
inventory). This is a selected worker, not a representative whole-pool sample.

The capture spans 15.56325 seconds, with mean primary pause 85.636 us,
p95 171.4 us and maximum 650.2 us. It identifies 40 render-dispatch waits;
25 coincide with the peer's verified idle-worker chain. Across all samples,
691 match that complete idle chain, out of 698 at the Windows wait instruction.
The remaining seven are not classified from the instruction pointer alone.

The current Windows implementation has different offsets from the older
capture. Fresh inspection resolves ntdll `a298e` through its chained unwind
entry to exported `RtlSleepConditionVariableSRW` at `a27b0`. Its five pushes
and 0x70-byte allocation establish the next return slot. The current chain is:

| Stack word | Return location |
| --- | --- |
| 0 | ntdll `a298e`, after `NtWaitForAlertByThreadId` |
| 20 | KernelBase `22a58`, condition-variable wrapper |
| 28 | MSVCP140 `176ea`, C++ condition-variable wait |
| 34 | engine `70f2bf`, wait-on-value helper |
| 40 | engine `6f6eae`, worker loop after checking both queues |

KernelBase and MSVCP prologs establish the intervening eight-word and six-word
steps. The exact engine build is unchanged from the prior worker-loop analysis.
Current module hashes and chain counts are saved in `worker-wait-chain.json`;
the local disassembly is `ring-paired-wait-windows-20260911.txt`.

Idle overlap therefore persists after the descriptor improvement, making work
availability and dispatch tail balance useful leads. Sequential suspension can
allow the worker to finish before observation. These counts do not prove all
workers are idle, quantify wasted frame time or justify adding workers.

The diagnostic run delivered 89.55375 native FPS, exited cleanly, restored files
and reported zero pose mismatches. There were 27 valid GPU observations and one
missing, with no Streamer activity in valid records. This is not a clean speed
comparison. Evidence: `synthetic-descriptor-demand-ring-paired-20260911`, including
its paired capture directory, selected-peer record and thread inventory.
