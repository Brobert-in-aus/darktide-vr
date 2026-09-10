# Development handoff — 10 September 2026

Development stopped at the user's home/stop instruction. The 20-minute
`keep-darktide-vr-work-moving` heartbeat is paused. No new live workload was
started for this handoff. Earlier work is committed and pushed as review branches;
no performance candidate was promoted over the accepted mixed installation.

## Measured outcomes

- The reversible SoloPlay benchmark now loads `cm_archives` at difficulty 3.
  At 120 Hz, frame generation delivered approximately 119.4–119.5 distinct
  images/s (about 60 original plus 60 generated). Native-only throughput was
  approximately 73–75 FPS. These are stationary mission-start results, not combat
  or traversal acceptance. See [mission measurements](SOLO-MISSION-PERFORMANCE.md).
- The 144 Hz simulator stretch achieved 141.85 distinct images/s with frame
  generation, versus approximately 74 native. Physical VDXR readiness still
  reported HMD unavailable on the afternoon recheck; physical 144 Hz remains
  untested. See [stretch comparison](144HZ-STRETCH.md).
- Disabling mesh streaming improved native results to 79.08/79.88 FPS from
  approximately 74.76, at roughly 1.7 GiB additional VRAM. It did not improve the
  capped FG result. Normal streaming remains accepted because traversal, memory
  pressure and visual consequences are unvalidated.
- DLSS Performance reduced GPU load and power versus Quality without improving
  native throughput. Worker-count and Reflex controls likewise showed no useful
  throughput gain. Evidence points toward CPU-side rendering limits in this scene.

## Fixes and investigative tools

- Corrected runtime-owned OpenXR color swapchain states. The strict D3D12 smoke
  test went from 358 reported errors to passing; the FG mission validation also
  completed with no pose mismatches.
- Batched independent stereo copy and FG color-pack transitions. Focused trials
  did not demonstrate a reliable FPS gain; candidates remain reviewable separately.
- Fixed disabled simulator previews stealing foreground focus, and added an
  optional fixed display-prediction clock. Legacy prediction remains the default;
  fixed-clock cadence results are not a physical-headset performance claim.
- Added bounded CPU/render API timing, thread residency, paired worker sampling,
  queue observations, weighted dispatch category/chunk observations, and optional
  GPU-stage profiling. Samples implicate engine D3D12 dispatch and active waits;
  sampled residency is not a CPU-time percentage or proof of a safe engine patch.
- Added bounded DLSS/FG observations. Active observed FG features were created at
  per-eye dimensions; earlier wide creation attempts do not establish steady-state
  double-width FG overhead. Scoped FG evaluation spans were about 1.81 ms left
  and 1.73 ms right, not total asynchronous FG cost or end-to-end latency.
- Retained unresolved HUD blur and worn visual acceptance. No basic gameplay
  verification was added.

Relevant detailed records include [engine investigation](STEREO-ENGINE-PERFORMANCE-2026-09-10.md),
[GPU profiling](SYNTHETIC-GPU-STAGE-PROFILE.md), and
[FG dimensions](FG-FEATURE-DIMENSIONS.md).

## Completed final investigation: a more active mission workload

This was a read-only feasibility investigation when the stop instruction arrived.
No enemy spawning, invulnerability, or workload modifications were deployed.

The available game source provides `MinionSpawnManager.queue_minion_to_spawn`
in `scripts/managers/minion/minion_spawn_manager.lua`. It copies position and
rotation into boxed queue entries and returns the entry for optional parameters.
The ambush horde template uses this API with `optional_aggro_state`,
`optional_target_unit`, `optional_group_target`, and `optional_group_id`.
`NavQueries.position_on_mesh_with_outside_position` provides a possible projection
helper and can return nil. These are source observations, not runtime validation.

A future opt-in stress workload should resolve the actual enemy side and nav world,
bound spawning against queue capacity, validate placements, observe successful
spawns and surviving enemies, and delay measurement until the workload is ready.
Any player protection must be explicit and restored. It must retain the existing
single-player/mission identity gates, exact file restoration and LuaJIT gate.
Artificial crowd results must be labelled as synthetic stress, separately from
ordinary mission traversal or combat. This is sufficient to close the investigation;
implementation and live validation are future work, not unfinished changes.

## Validation and shutdown

Code branches record their Windows builds, isolated tests and mission receipts.
The final investigation and this handoff change documentation only; source APIs
were inspected and `git diff --check` is the appropriate final validation.
The accepted installation and normal simulator runtime were restored after trials.
No running game or benchmark is required to retain these results.
