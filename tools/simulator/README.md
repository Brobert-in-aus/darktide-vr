# OpenXR simulator dependency

The synthetic frame-generation benchmark uses the existing D3D12 XR consumer
with a process-local simulator runtime. It does not change the system OpenXR
registration or certify physical headset readiness.

Upstream: [OpenXR Simulator](https://github.com/elliotttate/OpenXR-Simulator),
[v1.5.0 release](https://github.com/elliotttate/OpenXR-Simulator/releases/tag/v1.5.0).
The Windows archive SHA-256 published by GitHub is
`2a67596a20d106e3f54e455533149fce8454e1d9f8959cb38daaabe9f65a1768`.
Its DLL SHA-256 is
`4b80eb1d85e3c61bfebd7dc5076086d1c74f53806530dac1a86f21d8f903bded`.

The release rendered 120/120 frames with our consumer, but `xrRequestExitSession`
reported EXITING immediately, leaving the application waiting for STOPPING.
The adjacent patch makes that request enter STOPPING, then makes `xrEndSession`
enter IDLE and EXITING. It checks the session handle and expected state. This
is a focused local compatibility fix, not a claim of full runtime conformance.
The upstream MIT license is included beside the patch.

## Reproduce the local runtime

1. Extract the v1.5.0 source archive, whose root identifies commit `88e18ed`.
   The downloaded GitHub zipball SHA-256 was
   `a6df91cb42bbeb0108e9f95c3a630b95801f26b87d00022d0bf0a1cb58b2cbbe`.
2. Apply `openxr-simulator-v1.5.0-shutdown.patch` from the source root with
   `git apply --check`, then `git apply`.
3. Configure the upstream CMake project for VS 2022 x64, setting
   `SIMXR_VULKAN_INCLUDE_DIR` to extracted Vulkan-Headers v1.4.321 `include`.
   Its tag archive SHA-256 was
   `cace1d5832fc00287c9b10b27577c41033b2c86434e884eef5c8dcea098d5118`.
4. Build Release. Use the generated `bin/openxr_simulator.json`, which contains
   the absolute DLL path. The release's bare DLL filename did not resolve with
   our app-local loader; no registry registration is needed.
5. Set `XR_RUNTIME_JSON` only in the test process, run the harness with
   `--flush-log --require-openxr --require-rendering --xr-frames 120`, and
   restore the prior environment value. Require 120 submitted frames, zero
   non-rendered frames, `openxr.lifecycle=stopped`, and `result=pass`.

The locally built DLL tested on 10 September 2026 had SHA-256
`fb154e4496611c111e757b8cc4c523d1f77543a7a69eff3387bb6021d5a02aa6`.
Rebuilt binary hashes can differ; the benchmark requires the explicitly chosen
DLL's hash rather than accepting any runtime manifest silently.

The optional `openxr-simulator-v1.5.0-refresh.patch`, applied after the shutdown
patch, adds process-local `DTVR_SIMULATOR_REFRESH_HZ=120` and `144` clock selections.
Unset or other values preserve upstream 90 Hz. The wrapper exposes this as
`-SimulatorRefreshRate 90|120|144`, records it and restores the previous environment
value. Use the patched runtime for 120 Hz; older binaries ignore this setting.
The rebuilt DLL SHA-256 was
`c08da02708dcb68d450409118936034478cc98e3810b19d2788f5946ad618309`.
Its 120-frame smoke test rendered every frame, exited cleanly and passed;
elapsed time was 992.77 ms (the first frame does not wait a full period).

The later 144 Hz extension built DLL SHA-256
`3c3f41c34414ab9782d9a9e0dc8710bbe5b8af636722dcb0ac26a33681d133a1`.
Its smoke test rendered 144/144 frames in 994.218 ms and exited cleanly.
The wrapper verifies the runtime-reported frame period before launching the
game. This simulator clock does not establish physical Quest support for an
experimental refresh mode.

The simulator defaults to a 90 Hz frame clock. The benchmark disables desktop preview
copies and fixes Quest 3, 64 mm IPD and the requested eye resolution for both
frame-generation settings. Simulator submission rate is not headset latency or
a measurement of Virtual Desktop SSW. Neither `XR_EXT_frame_synthesis` nor
`XR_FB_space_warp` was advertised by this runtime in the smoke test.

## Optional display prediction experiment

Apply `openxr-simulator-v1.5.0-display-prediction.patch` after the shutdown and
refresh patches. Use `git apply --check --ignore-space-change` followed by
`git apply --ignore-space-change` when the extracted source uses CRLF endings.
The experiment is opt-in: `DTVR_SIMULATOR_FIXED_DISPLAY_CLOCK=1` predicts the
next fixed-refresh slot and skips missed slots after a host stall. Otherwise
the previous wake-time-plus-period prediction remains active.

The benchmark exposes `-SimulatorDisplayClock Legacy|Fixed` (default Legacy),
records the selection, restores the prior environment value, and requires the
runtime's `fixed_refresh` confirmation before launching a Fixed run. The local
experimental DLL SHA-256 is
`f3c9b45f932227c86dbf8a49503bbeacd628ee27d4d547966a67dd53190e5dba`.
The patched viewer passes its strict 120-frame DirectX validation smoke check
with this runtime. Simulator timeline
changes do not establish engine performance gains or physical display latency.
The viewer also uses predicted display time for original-frame reservation.
Compare Legacy and Fixed on the same viewer build: the experiment can change
selection timing, not just the cadence report's gap values.

The first Fixed 120 Hz/cap120 stationary SoloPlay FG run delivered 119.66
distinct pairs/s, split equally between original and generated frames. Across
110.32 analyzed seconds it recorded no repeats or clock breaks, but the largest
predicted-time gap was 25 ms. Missed runtime slots can therefore exist even
without repeated submitted images. The run exited cleanly with zero pose
mismatches and exact file restoration.
Evidence: ignored `synthetic-solo-fixed-clock-120-a-20260910` artifacts.

The matched Legacy control on the same viewer and experimental runtime binary
delivered 118.87 distinct pairs/s and 1.13 cached repeats/s. Its 110.00-second
analysis window contains 124 repeats, a longest repeat run of two, no clock
breaks and a maximum predicted gap of 23.40 ms. Clean exit, zero pose mismatches
and exact restoration pass. Evidence: `synthetic-solo-legacy-clock-120-a-20260910`.
The normal runtime DLL was restored after both runs. These are single captures,
not a repeatability or physical-runtime benefit claim; retain Legacy as default.

## Disabled-preview focus

The optional `openxr-simulator-v1.5.0-preview-focus.patch`, applied after the
shutdown and refresh patches, prevents a disabled preview (`preview_fps=0`)
from activating its window. The earlier runtime could take focus after the game
reached its title screen, causing the correctly foreground-gated startup helper
to wait indefinitely until focus was returned. Enabled previews retain their
activation behaviour, and disabled previews can still be clicked by the user.

The locally built DLL SHA-256 is
`cb8b520236bfcdbe03e57b46bd14f505c21a39c1cbe00b658d267f0aea121689`.
The strict 120-frame DirectX rendering check passes with preview disabled.
The 30-second unattended SoloPlay FG validation advanced into the mission
without focus recovery, exited cleanly with zero pose mismatches and restored
the installation and settings exactly. The normal simulator DLL and source
were restored afterward. Evidence: ignored `synthetic-solo-preview-focus-120-a-20260910`
and `simulator-preview-focus-smoke-20260910` artifacts. This patch changes
window behaviour, not the simulator display clock or rendering work. Both
forward application on the normal source and combination with the optional
display-prediction patch pass their patch checks.

## Runtime-initiated stop (headset asleep)

The optional `openxr-simulator-v1.5.0-runtime-stop.patch`, applied after the
shutdown and refresh patches, reproduces what Virtual Desktop does when the
headset is taken off and sleeps. With process-local
`DTVR_SIMULATOR_STOP_FILE` set, creating that file stops the running session
(FOCUSED, VISIBLE, SYNCHRONIZED, STOPPING) without an exit request; the
simulator deletes the file. After the application's `xrEndSession` the
session goes IDLE and at once READY again. An application exit request keeps
the shutdown patch's behaviour.

Built 14 September 2026, DLL SHA-256
`f2299d3b06ad8ddea016eb530aa2e3f145603da15dcbceab4753e726647b56bf`. The
viewer run with the play command line (no game, deferred capture window) and
two stop requests paused and resumed twice and passed; the 12 September
viewer exited at the first stop. Evidence: ignored
`artifacts/unattended/viewer-runtime-stop-20260914`. The previous 144 Hz DLL
is kept beside it as `openxr_simulator.dll.before-runtime-stop`.

[Meta XR Simulator](https://developers.meta.com/horizon/documentation/native/xrsim-intro/)
is another documented Windows D3D12 option. It has not been installed or tested
for this project. The selected open-source simulator allows the full existing
consumer to run; no separate buffer-drain implementation was needed.
