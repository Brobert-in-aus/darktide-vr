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
