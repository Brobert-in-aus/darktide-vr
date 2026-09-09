# Stereo copy-barrier hardware comparison

The isolated RTX 4090 experiment supports a small CPU recording reduction, not
a GPU or game-frame improvement. Across 20 alternating paired observations:

| Time per four-input capture | Serial median | Batched median | Median paired difference |
| --- | ---: | ---: | ---: |
| CPU command recording | 3.9125 us | 3.4016 us | -0.5047 us |
| GPU timestamp interval | 88.656 us | 94.304 us | +0.528 us |

Batched CPU recording was faster in 18/20 pairs; GPU time was faster in 10/20.
Independent medians and the median of paired differences are different
statistics. Do not describe this as a consistent GPU win. The CPU saving is
roughly half a microsecond per eye, so this candidate is not a major stereo
performance result. Larger engine preparation and reconstruction costs remain
the priority.

## Experiment

`darktidevr-stereo-input-copy-benchmark` is a manual target, not an automatic
CTest. It selects the high-performance hardware adapter and logs its identity,
creates four separate sources/destinations and alternates the original recording
loop with the production batching helper. Each row contains 32 repeated copies;
the first two of 22 pairs are warmup and excluded. Fence completion precedes
allocator reuse and query readback. CPU timing covers recording only; GPU timing
covers the repeated copy/barrier sequence.

The final format configuration is depth 1664x1792 format 19, motion 1664x1792
format 33, and two 2496x2688 format-27 colours. The first three source descriptions
match the saved input capture; final colour uses the continuous owner's colour
description and COMMON state for this experiment. First three source states are
PIXEL_SHADER_RESOURCE. There are no preceding game render writes, no UI input,
no temporal processing and no XR consumer. Repeated reuse/cache behaviour is
not a replacement for live frame measurement. The debug layer is disabled for
timing; correctness was separately checked by the debug-enabled WARP test.

An initial exploratory run used typed motion format 34. Its receipt is retained,
but the table above uses the corrected typeless format 33 run only.

```powershell
cmake --build build/xr-frame-stage-timing --config Release --target darktidevr-stereo-input-copy-benchmark
build/xr-frame-stage-timing/tests/streamline_stereo_inputs/Release/darktidevr-stereo-input-copy-benchmark.exe
```

Receipts under `artifacts/unattended`: `stereo-copy-hardware-matched-formats-20260910.log`,
`stereo-copy-hardware-summary-20260910.json`, and final build log. The earlier
`stereo-copy-hardware-comparison-20260910.log` is the format-34 exploratory run.
The benchmark builds and finishes successfully. It does not launch or modify
Darktide. The focused candidate remains built only; accepted native is unchanged.
