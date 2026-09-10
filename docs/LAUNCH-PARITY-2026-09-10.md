# Simulator/physical launch parity

The physical shared-eye runner unconditionally passed `--debug-layer`; normal
synthetic controls did not. It also starts a desktop fallback capture thread,
which calls the existing PrintWindow/rescale/pixel-conversion path every 33 ms
even during stereo gameplay. The simulator did not request this capture path.
These are real source-level workload differences, not measured proof of their
individual contributions to the physical deficit.

A 60-second high-resolution simulator debug-layer control reported 88.18 distinct
FPS versus the earlier 112.68 without it. The user subsequently noted that the
dip may have been caused by their interaction. **Treat this result as provisional;
do not claim that debug validation explains the gap without an uninterrupted
matched repeat.** The attempted follow-up capture control was stopped to correct
launch parity and produced no accepted performance result. No capture-load
diagnostic was retained in production code.

## Corrections

- Physical launch validation is now explicit: `-XrDebugLayer` on launch/start,
  or `-DebugLayer` on the shared-eye runner. The default is off, matching the
  ordinary simulator performance control. The runner prints its chosen state.
  Readiness validation remains separate and unchanged.
- Simulator runs now enable the accepted world-space HUD panel and menu input.
  The HUD flag has exact backup/restoration. Run receipts record both settings.
  Completed runs must report HUD enabled and create the expected-width target;
  evidence is copied from the run-selected console to `hud-panel.log`.
- Simulator preview is explicit through `-SimulatorPreviewFps 0|30|60|90|120`.
  Both eyes are selected in side-by-side layout. Zero remains the performance
  default; the black window at zero was intentional. Visible preview adds work
  and must be matched between compared runs.

The 30 FPS preview check at 2496x2688 loaded cm_archives difficulty 3, with Quality
DLSS and FG. Logs confirm HUD enabled and a 2496x1404 target. **The user confirmed
both eyes and the world-space HUD in the preview.** This is visual configuration
acceptance, not a performance comparison. The bounded session then closed and
its restoration receipt reports success. Physical VR remained closed.

Validation: PowerShell parser checks passed on the four changed scripts; actual
run logs satisfy the new HUD evidence requirements; zero pose mismatches and
clean exit are recorded for the preview check. The post-run HUD evidence gate
was added after this invocation had started, so its conditions were separately
checked against that completed run rather than claiming it executed inline.

Local evidence: `resolution-cause-debug-high-20260910`,
`resolution-cause-capture-control-20260910` (cancelled), and
`resolution-cause-hud-preview-20260910` under ignored artifacts/unattended.

## Still not identical

Physical tracking, FOV, camera position, runtime/compositor/streaming and desktop
fallback capture differ. The changes above remove known option mismatches;
they do not establish complete scene/workload equivalence. Next use a stationary,
foreground comparison with matched HUD and debug settings before assigning the
remaining difference to resolution or a particular runtime bottleneck.
