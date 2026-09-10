# Resolution bottleneck controls

The matched synthetic mission comparison does **not** reproduce the entire
physical hub shortfall. Higher resolution adds GPU pressure, especially with FG,
but is not established as the sole cause of approximately 40 native + 40 generated
FPS in the hub. A physical run of the same mission is the next control.

## Method

Stationary SoloPlay `cm_archives`, difficulty 3, DLSS Quality, 120 Hz simulator,
workers 13, Reflex On, normal mesh streaming. FG On uses cap 120; FG Off uses
Unlimited to expose native throughput. Within each pair only eye dimensions
change. Both use precise pair polling, the same FB244186 native build, 216E3F76
viewer and CB8B5202 simulator. Each run lasts 60 seconds after mission readiness;
the analyzer excludes 10 seconds of warm-up. These are one low/high pair per
configuration, not a repeated statistical estimate.

## FG result

| Eye resolution | Original FPS | Generated FPS | Distinct FPS | Cached repeats/s |
|---|---:|---:|---:|---:|
| 2112x2304 | 59.16 | 59.18 | 118.33 | 1.26 |
| 2496x2688 | 56.33 | 56.35 | 112.68 | 7.28 |

The approximately 38% larger output area reduces distinct throughput by 4.8%
in this scene. A high-resolution steady snapshot showed 99% GPU utilisation and
342 W; a low-resolution snapshot showed 73% and 277 W. These snapshots support
GPU pressure but are not full-run utilisation averages. Neither run resembles
the whole physical hub gap.

## Instrumented GPU attribution

The uninstrumented FG-off controls deliver **70.56 FPS at 2112x2304** and
**70.85 FPS at 2496x2688**: no meaningful throughput loss in this pair. Sampled
GPU utilisation rises from 67% to 75% (266 to 314 W). Together with the FG-on
99% snapshot, this supports an additional GPU constraint with FG enabled at
the larger resolution, while native-only retains headroom. It does not prove
which engine function limits native rendering in this exact run.

All six runs report clean exit, zero pose mismatches and restored files. The
user requested a physical headset run of the same mission next. Its initial
Ready check failed; no physical mission was launched on that failed check.

Separate same-settings profiling runs use native GPU timestamps. After discarding
the first five full reports, each eye has 2,760 selected evaluations per size.

| Measured GPU span | Low resolution | High resolution | Change |
|---|---:|---:|---:|
| Left FG evaluation | 1.495 ms | 1.912 ms | +27.9% |
| Right FG evaluation | 1.455 ms | 1.965 ms | +35.0% |

The sum of these scoped spans grows by approximately 0.93 ms. This is not the
total asynchronous NVIDIA FG cost and cannot simply be subtracted from end-to-end
frame time. High-resolution capture-left, capture-right and final pack spans are
0.119, 0.122 and 0.133 ms respectively. Copy/packing is small in these measurements;
there is no valid same-run low-resolution pack comparison because that global
trace was not collected before the next run began.

The instrumented runs delivered 118.89/115.71 distinct FPS, but are not substitutes
for the uninstrumented comparison: profiling changes the workload and the two
pairs show run-to-run variation. Do not interpret the faster instrumented high
result as an optimisation.

## Evidence collection fix

The launch helper can report `Authenticated Darktide process started during
launcher transition: PID ...` as well as the ordinary start message. The benchmark
collector and GPU analyzer now accept both exact forms. Four GPU analyzer tests
pass, including both forms. The low run's process-specific GPU log was recovered
from its unique PID filename; the overwritten global trace remains unknown.
This corrects evidence collection and does not change game rendering.

Local receipts: `artifacts/unattended/resolution-cause-{low-a,high-a,gpu-low,gpu-high,native-low,native-high}-20260910`.
See each configuration, summary and restoration receipt for full provenance.
No raw logs, settings or binaries are committed.
