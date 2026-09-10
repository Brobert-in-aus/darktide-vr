# CPU diagnosis after the native delivery improvement

Quality delivers about 89.5 native FPS with the descriptor/ring candidate;
Performance delivers 95.80. Three further hook optimisations do not demonstrate
a live gain. Two isolated observations now investigate the remaining cost.

## Presentation-thread observation

Focused `a7ba197` adds the unchanged `PresentCpuProfile` observer to ring source
`10550a4`, without the additional hook-cost candidate. It records 240 intervals
after a 600-call stable-generation warm-up, measuring thread CPU and wall time
inside the outer Present hook and between its entries. Windows CPU accounting
is quantized; use aggregate means rather than per-frame CPU percentiles.

DLL SHA-256:
`83E4D445F4C4DBA3747A1F12FC87484815257E3523D6C2259BAC1875862EAF10`.
Windows x64 Release build and focused `native_capture_hooks` pass. The identical
profile header has no Git diff from the tested source; the root module's two
disabled/enabled checks pass after building their initially absent executable.
Receipts: `artifacts/unattended/ring-cpu-profile-*-20260911.log`.
The runner enables/restores the profile flag and requires the full 240-record
window. The completed mission capture contains 240 records on thread 42188,
generation 66. Mean frame interval: 11.78474 ms wall / 10.80729 ms thread CPU.
Mean outer Present hook wall time: 0.47953 ms. The continuous frame window
therefore indicates roughly 92% of one logical core in use, with most wall time
outside Present. It does not identify which engine function owns that time.

The short hook CPU intervals average 0.71615 ms, exceeding their measured wall
time, consistent with the 15.625 ms CPU-accounting updates aliasing these
discontinuous sub-millisecond scopes. Do not use this value to partition hook CPU costs.
The continuous between-entry CPU sum is the more useful observation.

The full diagnostic run delivered 89.22609 native FPS, exited cleanly, restored
files and reported zero pose mismatches. Its 27 valid GPU activity records
contained no observed busy Streamer sample, with one missing record. The
240-frame profiling window differs from the longer FPS analysis window.
Evidence: `artifacts/unattended/synthetic-descriptor-demand-ring-cpu-20260911`,
including `cpu-summary.json` and the owned PID's original profile log.

## Descriptor-binding follow-up

Focused `3267863` applies only the descriptor-copy metadata guard to the previous
stage observer `0f53d13`. DLL SHA-256:
`46D98E6514C37BACF59E334DA30933BFE76FC2238FCC3C38202CB0B1A8B1BF09`.
The original observer DLL is preserved at
`artifacts/native-baselines/56A5A086-compute-stages.dll`. Release compilation
passes. The observer itself is unchanged; this comparison will use the same
4,096-record capture and reader checks. Its purpose is to compare instrumented
binding stages, not derive a whole-frame speedup from overlapping worker times.

All three captures contain 4,096 valid calls across eight threads, with 4,096
successful bindings. Means in microseconds per admitted dispatch:

| Scope | Original A | Descriptor guard B | Original reversal A2 |
| --- | ---: | ---: | ---: |
| Outer dispatch preparation | 8.318 | 2.728 | 8.135 |
| Total binding | 7.673 | 1.857 | 7.503 |
| Resource stage `7dec60` | 2.039 | 0.587 | 2.080 |
| Constant stage `7db0a0` | 0.991 | 0.520 | 0.995 |
| Descriptor stage `7e0fe0` | 4.451 | 0.510 | 4.225 |
| Table stage `7dc320` | 0.049 | 0.054 | 0.047 |

The reversal supports a roughly 75% reduction in instrumented binding wall
time, with descriptor binding no longer dominating the remaining stages.
Timer overhead, overlapping worker execution and sample boundaries prevent
converting these figures into a frame-time share. The stage spread also argues
against assuming that further descriptor-only work offers the earlier scale
of improvement. A new broader Present-thread residency capture is next.

Candidate B exited cleanly with exact runner restoration and zero pose
mismatches. It delivered 54.05 native pairs/sec through the unchanged legacy
mailbox; this diagnostic build deliberately lacks the new native ring.
All 22 GPU activity samples were valid, with no observed busy Streamer sample.
The original reversal also exited cleanly, restored files and had zero pose
mismatches: 73.87 native pairs/sec, 22 valid GPU samples, none missing and no
observed busy Streamer sample.
Evidence directories: `synthetic-compute-stages-20260911`,
`synthetic-compute-descriptor-cost-20260911`, and
`synthetic-compute-stages-recheck-20260911`, under `artifacts/unattended`.
