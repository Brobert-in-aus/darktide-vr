# Physical session closeout and frame-rate gap

The user authorized a final measurement, session closure and investigation.
Captured the final viewer tail, ten GPU samples, native process logs, Streamline
records and game console. No video was needed for the timing question.
The game received a close-window request; the viewer stopped with `result=pass`
and destroyed its XR session. The launcher's orphan cleanup terminated the
remaining game process. Both processes are now absent, all six temporary file
records report restored, and normal Quest proximity automation was reapplied.
One cumulative startup pose mismatch remained; `result=pass` does not erase it.

## What the captured intervals show

Comparison below uses the final ten eligible live intervals in each log, not the
whole-session average. Physical capture is after enabling the accepted HUD.
The simulator tail is from the uninstrumented high-resolution FG mission run.

| Metric | Physical | Simulator |
|---|---:|---:|
| Selected live interval duration | 12.88 s | 10.00 s |
| Original images delivered/s | 46.49 | 56.19 |
| Generated images delivered/s | 46.49 | 56.19 |
| Distinct images delivered/s | 92.99 | 112.38 |
| Repeated images/s | 0.16 | 7.60 |
| Producer original/generated publication, each | 46.65/s | 56.22/s |
| Viewer loop mean | 10.73 ms | 8.22 ms |
| Source-pair wait mean | 6.58 ms | 3.26 ms |
| xrWaitFrame mean | 0.046 ms | 2.20 ms |
| GPU-fence wait mean | 3.52 ms | 2.53 ms |
| xrEndFrame mean | 0.242 ms | 0.026 ms |

Rate means are weighted by each live interval duration. Stage means use the last
ten 120-loop reports; publication rates use sequence deltas across the last ten
selection records and exclude their first interval. These windows are adjacent
log tails, not exactly timestamp-aligned captures. Durations are CPU wall waits,
not GPU execution times, and must not be summed into a causal GPU cost model.

The physical selection window reports 600 generated selections, zero metadata,
order, history or missing-original rejections, and zero `no_new` outcomes. It
delivers nearly the producer's publication rate. Thus the shortfall is already
present at publication; it is not predominantly a queue of ready FG images being
discarded by selection. Producer publication can itself be affected by shared GPU
contention and runtime feedback, so this does not assign all cost to the engine.

Ten final GPU samples show 91–96% utilisation, 300–307 W and a steady reported
2715 MHz graphics clock. The earlier multi-millisecond xrEndFrame stall is absent
from these means. Network/decoder delay was not measured; no conclusion about
those subsystems follows from these counters alone.

## Remaining uncontrolled differences

- Eye dimensions, native/viewer binaries, Quality DLSS, FG, 120 cap and precise
  polling match. Earlier resolution controls showed only 118.33 -> 112.68 FPS
  with FG, and 70.56 -> 70.85 native; resolution alone did not reproduce ~80 FPS.
- The simulator's vertical FOV is slightly narrower. Physical left-eye angles
  are -0.942478, 0.698132, 0.767945, -0.959931 radians; simulator angles are
  -0.942478, 0.698132, 0.767596, -0.947190. Resolution matching does not match FOV.
- Simulator position stays at 335.1354,111.0239,-20.4500. The physical final
  console position is 338.5370,111.3277,-20.4500, approximately 3.4 m away.
  Actual head/controller poses also differ; final controller tracking was false.
  This is not a fixed-camera worn-performance acceptance capture.
- The final physical sample has the HUD panel enabled; the simulator did not.
  Earlier physical HUD-off samples were also around 92 FPS, so enabling the panel
  does not visibly explain the large gap, but no controlled HUD A/B was performed.
- Physical VDXR adds actual compositor/streaming work and different scheduling;
  the simulator's runtime and static tracking cannot represent those costs.

## Conclusion and next decisive controls

The higher resolution creates additional GPU pressure in FG mode, but there is
no evidence that it accounts for the entire physical deficit. Physical publication
is about 17% slower in these selected tails, with higher fence wait, while almost
all published originals/generated images reach submission. This narrows the
investigation to work before publication and shared GPU scheduling rather than a
large generated-selection loss or the previously observed runtime submission stall.

Next compare fixed position/orientation and matching FOV/HUD first; then collect
the same scoped GPU and presentation-thread timings on physical and simulator
runs. Separate framegen evaluation, engine rendering and runtime/compositor
contention. An FG-off physical control would help distinguish the cost added by
FG from the native rendering/runtime baseline. These are future controls; no new
session was launched after the user requested closure.

Evidence is retained under ignored `artifacts/unattended/physical-matched-mission-20260910`,
including `gap-summary.json`, `final-viewer-sample.log`, `final-gpu.csv`, native
logs, `game-console.log`, `recovery.json` and `restoration.json`. The comparison
uses `resolution-cause-high-a-20260910/consumer.log`. See also
[resolution controls](RESOLUTION-BOTTLENECK-2026-09-10.md).
