# Opt-in GPU stage profiling

`run-synthetic-framegen-benchmark.ps1 -GpuProfile` enables the existing native
GPU timestamp diagnostics, records that choice and retains the launch-selected
Lua GPU profile. The outer byte backup restores the profiling flag exactly,
including a previously absent flag. It cannot be combined with the CPU-only
Lua timing control. Normal benchmark runs retain their previous behaviour.

Use `summarize-synthetic-gpu-stages.py RUN_DIRECTORY` for the captured native
NGX and continuous-submission logs. It groups NGX by eye, feature lifetime and
extent, rejects invalid durations and discards the first five full 120-sample
reports per group. This is evaluation-count warmup, not UTC alignment with the
FPS analyzer. Missing measurements remain unknown. These are command-list GPU
spans, not total asynchronous NVIDIA work, CPU costs or display latency.

## 120 Hz mission diagnostic

The 60-second stationary SoloPlay FG profile used DLSS Quality, cap120,
2112x2304 eyes and the diagnostic-cleanup native baseline. After five initial
reports, each group contains 24 reports / 2,880 samples:

| Measured span | Mean ms |
| --- | ---: |
| Left FG evaluation | 1.811 |
| Right FG evaluation | 1.727 |
| Left post-evaluation work | 0.0001 |
| Right post-evaluation work | 0.0595 |
| Left input capture | 0.131 |
| Right input capture | 0.191 |
| Packed color and publication | 0.117 |

Input snapshots and packing are smaller than the measured FG evaluation spans.
Do not add these numbers into a critical-path frame time: queue overlap and
asynchronous operations are not fully represented. Instrumentation also changes
the workload, so its FPS is not a normal baseline comparison.

Wrapper parsing, three analyzer checks and the live diagnostic pass. The
mission produced GPU eye timings, exited cleanly with zero pose mismatches and
restored the installation and flags exactly. The no-preview-activation simulator
was used for this run, then the normal simulator DLL was restored.
Evidence: ignored `synthetic-solo-gpu-stage-profile-120-a-20260910` artifacts.
