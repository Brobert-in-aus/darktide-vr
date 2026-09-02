# Development-session handoff — 2026-09-02

This is the entry point for the next fresh session. Read `AGENTS.md`, this file,
and [`../phase1/todo-2026-09-03.md`](../phase1/todo-2026-09-03.md) before editing,
building, synchronizing or launching. The detailed history through the previous
day remains in
[`2026-09-01-fresh-session-handoff.md`](2026-09-01-fresh-session-handoff.md).

## Repository and shutdown state

- Workspace: `D:\Projects\games-xr\Warhammer 40k Darktide VR`
- Branch: `phase0/feasibility-bootstrap`
- The complete development batch is committed and pushed to the branch. Use
  `git log -1 --oneline` for the authoritative checkpoint.
- The unrelated user-owned `Codex Image 25 Aug 2026, 08_53_34.jpg` remains
  untracked and was deliberately not added to Git.
- Darktide and the XR harness were both stopped after the final bounded run.
- The performance-profile flag was restored to `disabled`; the production
  clustered-light correction flag remains enabled by normal deployment.
- The 20-minute workday heartbeat is paused.
- No desktop-control session is held.

## Mandatory first action tomorrow

Before any edit, build, synchronization, launch or unattended run:

1. verify Virtual Desktop Streamer is running and VirtualDesktopXR is the
   active/available OpenXR runtime;
2. verify exactly one authorized Quest is visible through one working ADB
   client, without recording its serial or network address;
3. run `tools\quest\set-proximity-override.ps1 -Action Disable`, then the same
   helper with `-Action Status` and the same verified ADB client;
4. confirm the Quest is awake and Virtual Desktop can create a renderable XR
   session.

Virtual Desktop suspension while Quest passthrough is active is normal and
recoverable. Do not fail closed or restart VD solely because of that state.

## Confirmed product state at shutdown

- The transparent/zoomed duplicate image remains fixed. The root fix is the
  startup window-procedure lifecycle and real client-resize path; do not replace
  it with a delayed or periodic resize.
- Sharpening and the Virtual Desktop-derived `2496x2688` per-eye extent looked
  correct in the headset.
- Loading/character-select billboard recentering and the misplaced loading
  crosshair were reported fixed.
- Bracers were acceptable as a temporary state, although their remaining
  third-person animation wobble is not final-quality embodiment.
- Hands/fleshy fingers are still absent. Earlier glove geometry stretched back
  toward the bracers; the current acceptance target is independent visible
  default hands/gloves driven by the tracked hand proxies.
- Settings/menu extent and pointer mapping, HUD/world-marker resolution and
  overlay placement remain open.

## Clustered-light root cause and candidate fix

The Penances-light issue was isolated without relying on camera, shadow-camera
or resolution guesses:

- zero IPD did not remove the eye asymmetry;
- matching the two eye orientations did remove it;
- a 20% wider engine visibility FOV admitted the light to both eyes, but raw
  widening caused broad edge-lighting artefacts;
- exact tracing identified clustered-light grid/list shaders
  `356241c9944b66e7` / `68d5ef81edcce164`, raster shaders
  `5c6cd369626f261a` / `be559cb63c32aa02`, and an 84-byte root-0/root-2 raster
  constant buffer;
- visibility widening changes only the FOV scalar at byte 72 from `1.72788` to
  `1.90448`; the cluster pixel shader consumes that scalar but not Lua's
  compensating post-projection transform.

The production candidate widens only CPU light admission, then restores the
runtime FOV scalar at byte 72 immediately before the exact Stingray constant
upload. It is shader-pair-, root-, resource-, signature- and age-gated. Lua
widens visibility only when the native hook reports active, so a missing native
hook leaves the established projection untouched.

Normal synchronization enables
`darktidevr_cluster_light_visibility_fix.flag` and removes the diagnostic
cluster-trace flag. The final synthetic Psykhanium run reached 110,818/110,818
eligible constant patches with zero rejects, root misses or resource misses.
There were no mod errors, DRED/device-removal signatures or engine crashes.

This proves the mechanism and lifecycle only. First worn test tomorrow must
reproduce the Penances position and confirm both:

1. the original left/right lighting asymmetry is absent;
2. the broad edge-lighting artefacts caused by raw visibility padding are also
   absent.

If either fails, disable the production flag and use the preserved narrow trace
evidence. Do not re-enable the older broad per-draw resolution trace; it was
large enough to deadlock the game.

## Performance result from the final run

The final bounded run used the actual VDXR-derived `2496x2688` per-eye extent,
entered Psykhanium from a closed game, enabled the opt-in GPU profiler and ran a
synthetic head sweep for 240 seconds.

Harness totals:

- 17,755/17,755 OpenXR frames submitted;
- 10,258 fresh stereo pairs after the loading/fallback period;
- 7,477 flat fallback frames while the game loaded;
- zero reused shared frames in pair-driven world presentation;
- one startup pose mismatch;
- 20 pair-driven timeouts, concentrated around transitions;
- 1.83 pose sequences / 0.55 degrees average rendered-pair lag;
- no capture failure, stale-frame failure or resize event.

Once true stereo attached, interval OpenXR submissions and unique fresh pairs
were the same population and were commonly about 58-62 Hz, with direction- and
scene-dependent intervals extending into the low 50s and upper 60s. This
explains why the headset felt closer to the game's roughly 48-60 fps source than
to Steam's approximately 115 fps frame-generation number: the bridge was not
delivering 115 unique stereo pairs. Pair-driven presentation intentionally does
not claim reused pairs as new application frames; VDXR remains responsible for
display-rate reprojection.

The GPU profiler produced 57 warmed windows. Across those windows its left and
right eye intervals averaged 9.331 ms and 5.849 ms, with the reported interval
sum averaging 15.180 ms (12.743-23.708 ms by window). The stage averages were
3.519 ms / 5.876 ms before/after the left full-output boundary and 3.470 ms /
2.377 ms before/after the right boundary. Synthetic turning moved the expensive
post-boundary portion between eyes, so there is no permanently slow physical
eye.

Important interpretation constraint: these timestamp intervals can overlap in
the shared D3D12 queue. Their arithmetic sum is a profiling comparison, not an
end-to-end stereo-pair latency. The defensible conclusions are that Lua/callback
time is negligible, the limiting work is downstream on the GPU queue, and the
second view remains materially expensive. Next measurement is a bounded pass
trace plus a matched uninstrumented fixed-pose baseline at `2496x2688`, followed
by a worn Virtual Desktop overlay capture to distinguish source pairs from
runtime reprojection and stream/display cadence.

The older accepted fixed-pose results at `2112x2304` were around 94-97 fresh
pairs/s. The current extent contains about 38% more stereo output pixels, so do
not compare these rates as though resolution were constant.

## DLSS Frame Generation for XR research addendum

The user's observation that DLSS Frame Generation affects only the desktop
mirror is consistent with the current architecture. Darktide's installed
Streamline/DLSS-G integration operates on the DXGI backbuffer at `Present`,
while the bridge captures the left/right resources and signals them to the XR
harness before that boundary. Consequently, generated mirror presents do not
become new binocular XR pairs. The inspected installation contains Streamline
`2.7.30.0` and `nvngx_dlssg.dll` `310.2.1.0`; these are observations, not stable
identifiers, and the planned probe must log the loaded runtime versions.

NVIDIA's public [DLSS Frame Generation programming
guide](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_G.md)
confirms that DLSS-G intercepts the swapchain backbuffer at `Present`, requires
frame-matched depth, motion vectors and common constants, and supports multiple
viewports only when they render into the same backbuffer. Multiple swapchains
are not supported. NVIDIA's [integration
guidance](https://developer.nvidia.com/blog/how-to-successfully-integrate-dlss-3)
also requires Reflex, recommends hudless/UI resources and calls for explicit
disable/restore handling around menus, loading and resolution transitions.

The first candidate is therefore a proof-only side-by-side Streamline
prototype: pack both eyes into one backbuffer, tag two independent viewports
and their per-eye colour/depth/motion/UI inputs under one frame token, and issue
one `Present`. Before implementation proceeds, instrumentation must prove that
the proxy can identify and access every generated backbuffer with its exact
generation index. If generated output is not available before scanout, the
public API cannot feed the XR bridge directly; recapturing the desktop mirror
is specifically rejected because it loses clean eye, pose and timing ownership
and adds latency.

Even if the generated texture is accessible, each synthetic pair needs pose
correction for its own predicted OpenXR display time. Reusing the rendered
pair's pose would make head motion lag. The parallel fallback is to probe
VirtualDesktopXR for the multi-vendor
[`XR_EXT_frame_synthesis`](https://registry.khronos.org/OpenXR/specs/1.1/man/html/XR_EXT_frame_synthesis.html)
and legacy `XR_FB_space_warp` extensions. Runtime synthesis takes per-eye depth,
motion vectors and application-space delta pose and can preserve compositor
timing, but it is not DLSS and support must be measured rather than assumed.

The complete measurement gates, prototype sequence and acceptance criteria are
in [`../phase1/todo-2026-09-03.md`](../phase1/todo-2026-09-03.md). No runtime
code was changed during this documentation/research addendum.

Evidence:

- `artifacts/unattended/preflight-20260902T105728Z.json`
- `C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-02-10.58.05-4afa12ca-ca71-4b68-be28-9650a5ee893a.log`
- `artifacts/phase1/cluster-light-trace-20260902.tsv`
- `artifacts/phase1/cluster-light-binding-trace-20260902.tsv`
- `artifacts/phase1/cluster-light-c0-deferred-trace-20260902.tsv`
- `artifacts/phase1/cluster-light-transform-trace-20260902.tsv`
- `artifacts/phase1/cluster-light-visibility-padding-trace-20260902.tsv`
- `artifacts/phase1/cluster-light-fov-corrected-trace-20260902.tsv`

`artifacts/` and local game logs are intentionally not committed.

## Validation completed

The clustered-light production path was validated with:

```powershell
.\tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 120
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr_native_capture darktidevr_d3d12_bootstrap
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release -R 'native_capture_hooks|shared_eye_surfaces' --output-on-failure
.\tools\stereo\test-darktide-lua-source.ps1
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 240 -GameStartTimeoutSeconds 600 -EnterPsykhanium -SyntheticHeadSweep -EnablePerformanceProfile -SkipDeploymentSync
```

Before committing, the complete applicable source/native test suite was rerun;
the exact final result and commit are recorded in the closing section of this
file.

## Tomorrow's order

Follow [`../phase1/todo-2026-09-03.md`](../phase1/todo-2026-09-03.md). In short:

1. mandatory XR preflight;
2. worn acceptance/rejection of the clustered-light candidate;
3. restore visible fleshy hands/default gloves while retaining acceptable
   bracer tracking;
4. fix settings/menu extents and pointer mapping;
5. fix HUD and world-marker resolution/placement independently of the desktop
   mirror;
6. complete the matched performance/pass-trace comparison and start the
   proof-first DLSS-G-for-XR instrumentation in the todo; and
7. continue the comprehensive bug/lifetime pass.

## Final validation and commit

Final shutdown validation:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release

& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release --output-on-failure
# pass: 33/33, including xr_projection_smoke, xr_theatre_smoke and
# xr_stereo_sbs_smoke against VirtualDesktopXR

python .\tools\stereo\test-analyze-gpu-batch-trace.py
# pass: analyze_gpu_batch_trace_tests=pass

python -m py_compile `
  .\tools\stereo\analyze-gpu-batch-trace.py `
  .\tools\stereo\test-analyze-gpu-batch-trace.py

# PowerShell AST parse of all 12 changed/new .ps1 files: pass
git diff --check
# pass: no whitespace errors; line-ending conversion warnings only
```

Darktide count and XR harness count were both zero after the bounded run.
The final commit was pushed to `origin/phase0/feasibility-bootstrap`; use
`git log -1 --oneline` for its immutable hash and subject.
