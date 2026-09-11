# Physical streaming gap — 11 September 2026

The user resumed physical testing after the end-of-day handover. Heartbeat
remains paused. The active session uses stacked native `2f2bed3` (SHA
`0E4718A34A553D8336BD15F6D2654818D7907F70FA509AFBA969E7556B603B0F`)
and combined direct-copy/on-demand-capture viewer `0c047c0` (SHA
`E342C7EA26C78C5D9DD3439143E55EF03A866BBF923990B9ED537C1FC407DDCA`).
VDXR recommends 2496x2688 per eye at 120 Hz. Quality DLSS, FG on with one
generated image, 120 cap, stereo HUD and menu input are enabled. Desktop mirror
remains normal. Viewer capture pauses in stereo (`theatre_capture_active=0`).

The preceding native-only launch could not enable the mod's FG path via the
game setting alone. A restart with `-DlssGeneratedStereo` enabled sustained
stereo tags and output publication. Subsequent background/alt-tab intervals
stopped FG evaluation. These are distinct from the sustained foreground deficit.

## Foreground Quality capture

The user stayed still in the hub and kept the game foregrounded. A requested
60-second telemetry capture produced a 69.48-second selected viewer window
because the two samplers and log snapshots started/ended sequentially. Board
samples and stage reports overlap but are not exactly aligned. Exclude the first
partial viewer/stage interval. No builds or configuration changes occurred.

| Measurement | Result |
| --- | ---: |
| Distinct native delivery | 43.9826 FPS |
| Distinct generated delivery | 43.9682 FPS |
| Total distinct delivery | 87.9509 FPS |
| Cached repeats | 0.1295 FPS |
| Producer original publication mean | 43.9675 FPS |
| Foreground producer observations | 71 / 71 |
| Board GPU utilisation, 12 samples | 93.67% |
| Board encoder utilisation | 25.33% |
| Board power / graphics clock | 315.08 W / 2700 MHz |
| Viewer source-pair wait | 7.760 ms |
| Viewer GPU fence wait | 3.296 ms |
| xrWaitFrame / xrEndFrame | 0.0035 / 0.0844 ms |

Producer generated publications advanced 3090, alongside 3090 original
contexts. Context misses, unmapped outputs and output-busy counts did not
increase. The viewer delivers almost exactly the original publication rate and
an equal generated rate. There is no evidence here of a large ready-frame
backlog discarded by the viewer, nor a large xrEndFrame CPU stall. Fence and
pair waits are CPU wall waits, not GPU execution times or additive causal costs.

VD Streamer has active 3D and video-encode counters. Its per-instance video
encode observations average 26.37%; do not sum engine percentages with board
utilisation or convert encoder occupancy into FPS lost. Current saved Streamer
codec is HEVC 10-bit; that is a preference, not verified negotiated session
telemetry. High board load plus active streaming makes GPU contention a lead,
not proof that the encoder accounts for the whole deficit. Network and headset
decode latency were not measured.

The simulator hub reference is 117.35 distinct FG FPS (58.67 native + 58.68
generated). Relative to 87.95, it is about 33% faster, or physical is about 25%
lower. The approximately 89-FPS simulator native result and user's approximately
60-FPS physical native observation suggest a separate roughly 50% ratio. Do not
mix native and FG comparisons. Simulator hub spin versus stationary physical
hub, actual pose/FOV and different component versions remain uncontrolled;
neither ratio is a clean estimate of streaming overhead.

Evidence: ignored `artifacts/unattended/physical-streaming-gap-20260911` contains
viewer/producer snapshots, foreground health counters, board CSV, GPU-engine
JSONL and an analysis receipt. No physical session was closed for this capture.

## Next discriminating controls

1. In the same physical position, compare Quality with Performance DLSS while
   leaving FG, output resolution and VD settings unchanged. This distinguishes
   sensitivity to internal rendering resolution from output/streaming costs.
2. Repeat a simulator control with the exact current native/viewer stack and
   matched camera/FOV/HUD; label the absent streaming path explicitly.
3. Vary negotiated VD encoding settings only with a stable scene, returning to
   the initial state to check drift. Collect runtime compositor/encoding timing
   separately; do not restart VD merely for suspension.

The user has been asked to switch to DLSS Performance for the next capture.
Await their readiness; do not silently substitute a different scene or toggle
settings during a measured interval.

## DLSS mode-change failure: Performance control excluded

The user changed to Performance and reported approximately 43–50 FPS focused,
70 unfocused, with generated frames apparently absent. Settings still contain
`dlss_g=1`, `dlss_g_enabled=true` and one generated frame. The viewer reports
zero generated delivery. Thus this was not a clean FG-enabled Performance run.

Fresh producer counters while focused show approximately 49–51 engine FPS,
about two evaluations per original frame, but `complete=17482`, `paired=8741`,
`published=8739` and `contexts=19042` remain fixed. Original-ring publication
is zero and the legacy feed continues. After losing focus, evaluations stop
at 22974 and engine FPS rises to 62–67 in the observed samples. This is
consistent with paying for evaluations without usable stereo output while
focused; it is not a measurement of pure rendering or encoding overhead.

Source inspection points to the continuous submission/input lifecycle and
output validation as the next investigation: the capture path retains input
owners and has stop/failure guards, while NGX completeness requires valid
packed output dimensions and subregions. The bounded detailed logs contain
earlier evaluations and do not identify which condition failed at the switch.
Do not claim an exact failing guard from stale bounded logs or bypass it.

Record as a DLSS quality-change recovery defect. A fresh Performance launch
with explicit generated-stereo support is needed for the resolution control;
verify growing original/generated publication before comparing FPS. Preserve
the separate valid foreground Quality finding (87.95 distinct FPS).
Ignored snapshots ending `after-quality-switch` preserve the failure evidence.
