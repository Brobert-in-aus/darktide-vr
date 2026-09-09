# Two-hand rotation allocation review

Decision: retain the existing pose implementation. A scalar rewrite of the two
quaternion products removes temporary source-level tables, but LuaJIT already
eliminates those allocations in the measured workload. The additional arithmetic
duplication is not justified by a demonstrated JIT benefit.

The explicit `tools/stereo/benchmark-two-hand-rotation.lua` harness compares actual
pure geometry modules using 10,000 deterministic groups of proximity, socket,
correction and hand calculations. Quaternion input scales vary from 1e-12 to
1e12. Exact results match across this set and representative non-finite/overflow
inputs; NaN results are compared as NaN, not claimed bit-identical.

Five alternating trials, Windows QPC, pinned LuaJIT, 10,000 groups:

| Mode | Existing median | Scalar experiment median | Typical heap growth, existing / experiment |
| --- | ---: | ---: | ---: |
| JIT enabled | 6.8065 ms | 6.9540 ms | 11,517.2 / 11,517.2 KiB |
| Interpreter | 43.2142 ms | 36.6516 ms | 29,651.8 / 17,365.2 KiB |

JIT timings overlap (existing 6.41-7.19 ms, experiment 6.50-7.64 ms). Interpreter
improvement does not establish a benefit in the JIT workload. Collection is
paused only during each measurement; these numbers are not normal GC pauses,
game FPS or worn acceptance. No game/input/renderer hooks run.

The candidate module is retained only as ignored local evidence:
`artifacts/unattended/two-hand-pose-scalar-experiment-20260909.lua`.
Baseline `61386d9` is copied to `two-hand-pose-before-performance-20260909.lua`.
Receipts there: `two-hand-rotation-performance-{benchmark,interpreter,syntax}-20260909.log`.
The benchmark compiles with the pinned LuaJIT syntax gate. Production pose code
is restored unchanged; no deployment or new basic-gameplay tests were performed.
