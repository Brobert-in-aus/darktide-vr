# Phase 1 - native stereo VR vertical slice

**Status:** In progress
**Started:** 24 August 2026
**Safety posture:** Build-scoped private testing only while EAC is explicitly
inactive; no bypass, concealment, or interaction with other players.
**Latest engineering gate:** [25 August bug review](bug-review-2026-08-25.md)

## Exit criterion

Complete a 60-minute headset session with correct pose/FOV, no game-thread XR
wait, no crash, and deterministic theatre fallback across loading, menu, and
cutscene states.

## Current slice

The Darktide adapter now parses the versioned semantic camera contract into a
typed native pose. The parser fails closed on unrelated lines, unknown schemas,
non-finite fields, non-unit quaternions, and vertical FOV outside `(0, pi)`.

A single-writer/multi-reader atomic snapshot publishes only monotonic validated
pose packets. Readers make bounded retries and classify the newest packet as
fresh, stale, or empty without waiting on a mutex. The presentation policy uses
that state conservatively: only fresh gameplay camera data permits mono
projection; stale/missing data and non-gameplay states select theatre, while
emergency disable and a non-renderable XR session select disabled.

Recenter math now expresses HMD motion in recenter-local OpenXR coordinates and
clamps horizontal and vertical translation independently while preserving head
orientation. This establishes the validation and fallback boundary before a
future non-blocking semantic transport feeds camera data to the mono viewer.

## Live theatre milestone

The harness now supports an `XrCompositionLayerQuad` in VIEW space. It can show
either a diagnostic pattern or an externally captured Windows client area on a
1920x1080 head-locked surface two metres ahead. Theatre mode creates only its
mono swapchain; unused full-resolution projection swapchains are not allocated.

Window acquisition requires one unique visible title. Capture and BGRA-to-RGBA
conversion run on a 30 Hz producer thread, while the OpenXR loop continues to
submit the newest immutable frame at compositor rate. The XR thread never waits
for a desktop capture. If the window is minimized or disappears, the producer
holds the last valid image, records failures/stale submissions, and keeps the XR
session alive so capture can resume after the window returns.

With Darktide stopped at character select, the end-to-end run completed
1,200/1,200 quad submissions in 10.144 seconds (118.3 Hz) and consumed 307
capture updates (30.3 Hz), with the D3D12 debug gate clean. This is a mono source
presented binocularly; it is not genuine left/right scene stereo.

Run a bounded session after Darktide has reached character select:

```powershell
tools\theatre\run-darktide-theatre.ps1 -DurationSeconds 300
```

The wrapper verifies the exact known executable hash, requires one responsive
Darktide window, and refuses to run while the EAC service is active.

The 1 Hz Phase 0 log probe is evidence and replay input only; it is not a
frame-critical transport. A real transport must be versioned, non-blocking,
sequence-numbered, bounded, and stale-sample aware. It must not poll files per
frame.

## Same-frame native stereo milestone

The producer now captures the two sequential camera results at their completed
render-pass boundary. A bounded barrier census proved that each settled display
frame contains exactly two completed 1920x2160 RGBA8 results: the same
ping-pong resource transitions from `RENDER_TARGET` to shader resource once for
eye 0 and once for eye 1. Capturing the earlier shader-resource-to-render-target
transition was falsified because it sampled pass-start state, including partial
compositing and a 1280x768 clear. Copies are now queued only after the matching
completed worker submission and published as separate 1920x2160 shared eye
textures.

The logical swapchain extent is 1920x2160. The earlier synthetic one-pixel
`WM_SIZE` nudge was falsified: it persisted a 1279x768 active resolution while
leaving viewport-dependent resources inconsistent. At startup this produced a
partly rendered image with a black lower region; manually resizing the window
made both eyes correct at once. A mostly transparent lighting/viewport overlay
also disappeared on resize and returned immediately when the client was far
from the logical aspect and extent. The deployed fix performs a real client-
area resize and holds the physical client near the requested eye extent.

The final zero-disparity fault was a camera-cache bug rather than a renderer
limit. The primary camera was force-updated at the center pose, moved to the
left-eye pose, and rendered without another update; only the duplicate right
camera was refreshed. Force-updating the primary after applying its eye offset
produced depth-dependent horizontal disparity with zero vertical registration
error. The proof pair is under
`artifacts/phase1/logical-eye-pair-primary-refresh-20260824`: 25.3178% of pixels
changed, with measured horizontal translations of 9, 15, and 20 pixels across
different depth regions and zero vertical translation in each region.

Both a 200 mm identity control and the restored 64 mm IPD produce broad,
depth-dependent horizontal disparity with zero measured vertical shift around
the near character. The normal-IPD proof pair is under
`artifacts/phase1/stereo-proof-intermediate-ipd064-20260824`. The path remains
build-scoped. Candidate dimensions now follow the selected swapchain instead
of a hard-coded 3840x2160 extent. The single shared pair uses a consumer-
acknowledgement fence: the producer drops a whole pair instead of overwriting
surfaces still being read by the XR queue. A multi-buffered ring is still a
later throughput optimization.

Live Quest 3 validation through VDXR subsequently held approximately 110
compositor FPS with smooth output in both eyes. Headset inspection described
the stereo result as flawless, with only very minor edge differences consistent
with temporal AA. This completes the true-stereo feasibility gate.

The same path now arms the existing `player1` gameplay camera when a level world
replaces the character-select UI world. During transition gaps, the XR bridge
treats a shared-eye sequence as stale after 500 ms and duplicates the current
flat Darktide frame into both eye regions. It automatically returns to stereo
on the first newly published pair. Quest 3 validation confirmed that character
select can transition through the flat loading fallback and enter the private
lobby in stereo with EAC disabled.

## Pose-associated 3DoF and throughput evidence

The OpenXR harness publishes recentered head poses through named shared memory.
The Lua cameras consume an orientation-only transform; physical translation is
transported but remains disabled until the 3DoF stability gate passes. Each eye
capture is tagged with the exact pose sequence used to build its camera. The
producer publishes that sequence with the ready-fence value, and the harness
submits the pair using the matching historical OpenXR view poses rather than
the latest pose at consumption time.

The first live association run exposed a deterministic recovery defect: a pair
whose pose tag could not be matched was left unacknowledged, pinning the single
shared slot and forcing flat fallback forever. Rejected pairs are now explicitly
discarded and acknowledged. A subsequent live run recovered from initial tag
mismatches and continued accepting fresh stereo pairs.

With the minimum test graphics profile, the earlier 3840x2160 proof measured
approximately 118 OpenXR submissions per second but only 24 fresh stereo pairs
per second. The logical eye-sized path now renders both eyes at 1920x2160 with
no discarded horizontal pixels. A 6,000-frame VDXR stability run completed
6,000/6,000 submissions with zero unrendered or stale-capture frames at 118.95
submissions/s and 51.05 fresh stereo pairs/s. The only two pose mismatches were
startup events and did not increase during the 50.44-second run. Repeated
compositor frames intentionally reuse the last complete pair; the game render
queue is never blocked. The pre-change settings remain under
`artifacts/phase1/render-settings/user_settings.pre-eye-sized.config`.

After disabling the census and redeploying, a 1,200-frame smoke run again
completed 1,200/1,200 submissions with zero misses at 118.0 submissions/s and
50.64 fresh pairs/s. The clean live dump under
`artifacts/phase1/logical-eye-pair-clean-census-off-20260824` changed 26.4395%
of pixels. Registration measured depth-varying horizontal offsets of 19 pixels
in the distant upper scene and 32 pixels on the nearer character, confirming
that the deployed non-instrumented build retains true stereo.

Startup head motion also exposed a pose-space error. The game consumes head
orientation relative to the first valid tracked pose, but the harness had
submitted that relative delta directly in an absolute OpenXR `LOCAL` space.
Depending on movement during initialization, the projection could therefore
start at the wrong physical angle. Projection poses now anchor the relative
delta back onto the exact first tracked pose before submission. Pure-roll and
anchored-roll math tests confirm that the third rotational axis survives both
recenter and projection anchoring. Headset validation must distinguish correct
world locking (the desktop mirror counter-rotates while the virtual world stays
gravity-level) from a true 2DoF failure (the world rotates with the headset).

## 2026-08-24 end-of-night checkpoint

The real client-area lock produced a visually correct character-select scene
immediately at startup. Headset inspection confirmed that both eyes retained
the correct geometry, decals, ambient occlusion, and lighting. The prior black
lower region and transparent viewport-dependent overlay were absent. No manual
resize was needed.

The resulting dimensions are intentionally recorded without normalizing them:

- the physical Windows client and Darktide's active `screen_resolution` were
  both measured at 1920x2135 because the decorated window was clamped against
  the 2160-pixel monitor edge;
- the producer's completed-pass shared resources remained exactly 1920x2160
  per eye, as required by the receiver's resource-description validation;
- the XR harness copied those eyes into a 1920x4320 top/bottom swapchain and
  submitted two 1920x2160 subimages;
- VirtualDesktopXR recommended 2688x2880 per eye and therefore scaled the
  submitted images.

This mixed client/resource extent looked correct on the desktop and in the
headset. Do not change it merely to make the numbers match. An undeployed
experiment that would move the window frame above the monitor to force an exact
2160-pixel client was reverted before wrap-up.

The final 36,000-frame VDXR run completed normally in 301.857 seconds:

- 36,000/36,000 compositor submissions and zero unrendered frames;
- approximately 119.25 submissions/s;
- 14,899 fresh shared stereo pairs (49.36 pairs/s);
- 21,098 intentional reuse/reprojection frames;
- two pose-tag mismatches, both associated with startup;
- three flat-fallback frames across two startup transitions;
- zero capture failures and zero stale-capture frames.

Subjective headset motion was much smoother than earlier runs. One unresolved
issue remains: while turning the head, the left eye intermittently appears to
flicker or change position while the right eye remains smooth. The evidence does
not support calling this an unequal eye-tag problem: only two explicit tag
mismatches occurred in the entire run, and rejected pairs were not submitted.
It is also not the obvious single-buffer overwrite race. The producer refuses
to begin the next left-eye copy until the consumer fence acknowledges the prior
pair, and XR signals that fence only after its GPU copy of both eye resources is
ordered.

This checkpoint motivated the fresh-pair transition instrumentation described
below: game pose sequence, submitted historical pose, angular lag, and whether
the compositor frame reused or replaced the prior pair. The residual timing
explanation remains a hypothesis until those counters correlate with a headset
event.

## 2026-08-25 projection and motion follow-up

The velocity-dependent direction and magnitude of the reported flicker first
led to a projection audit. The character-select cameras render with a final
vertical FOV of approximately 92.3 degrees and a 1920/2160 aspect ratio, which
implies approximately 85.5 degrees horizontally. The XR harness instead
labels those images with its empirically accepted runtime-centered fallback,
approximately 94 by 99 degrees. The initial hypothesis that the camera FOV
should replace that value was tested and falsified below.

The producer now snapshots each eye's reported vertical FOV and aspect ratio
with its render-pose tag under a versioned shared-memory contract. A live test
proved that this camera value does not map directly to the completed image's
OpenXR angular coverage: submitting it produced a narrow central window of
roughly 38 by 42.5 degrees. The accepted runtime-centered wide FOV was therefore
restored, while the render value remains diagnostic metadata. The stable
pre-adjustment camera FOV is retained so repeated callbacks cannot compound the
tangent scaling.

The harness additionally records fresh-pair pose-sequence lag and angular lag
relative to the current compositor pose. This distinguishes any residual
capture latency from the corrected projection mismatch without changing the
accepted 1920x2135 client / 1920x2160 eye-resource arrangement.

Live validation subsequently completed 18,000/18,000 frames. Fresh pairs were
tagged an average 2.61 OpenXR pose samples behind the current compositor pose;
average angular separation was 0.42 degrees. The user corrected the apparent
flicker direction: flashes oppose head motion, occur in both eyes, and are much
more frequent in the left eye. This is consistent with stale content or a tag
ahead of its pixels, but does not by itself identify which boundary is wrong.

The bridge previously called `xrEndFrame` at about 119 Hz even when only 51--58
new Darktide pairs arrived. VDXR counts those calls as application FPS, masking
the true content rate and potentially preventing automatic SSW engagement.
Shared-eye mode now waits on the producer ready fence by default before
beginning the next OpenXR frame, with a 33 ms escape timeout for loading or
fallback state after the existing 500 ms producer-stale threshold. Its valid
live interval submitted 72--76 new pairs/s with
essentially zero reuse; the lower bridge overhead also increased producer
throughput. The compositor still runs at headset refresh and owns
reprojection/SSW between submissions. `--continuous-shared` retains the old
behavior as an explicit diagnostic control.

## Stereo performance investigation

The current correctness path deliberately performs two complete
`Application.render_world` calls. Darktide's shipping `ScriptWorld.render`
also repeats shading setup, shading callbacks, shadow-bake checks, and
`World.update_lod_levels` for each active viewport. Some CPU scene preparation
can therefore be shared immediately, but that alone will not recover the GPU
cost of the second deferred render.

Existing settled command traces quantify the reusable boundary. The two eyes
each issue 1,010 draws; coarse draw signatures overlap for 1,008/1,010 draws
(99.6%), and exact geometry/input-assembler signatures overlap for 1,000/1,010
(98.0%). Per-view bindings differ much more often (notably descriptor table 4),
which is consistent with common scene geometry feeding distinct camera and
deferred target state. The production target is consequently:

1. update animation, skinning inputs, visibility, LOD, and other scene data
   once for the union of both eye frusta;
2. retain isolated per-eye depth, G-buffer, AO, lighting, decal, and temporal
   resources;
3. use a view-instanced geometry path where supported, or otherwise reuse the
   shared preparation while issuing the unavoidable per-eye raster and
   screen-space work;
4. mirror one completed eye cheaply to the desktop.

Autodesk Stingray 1.6 documented instanced stereo in its default renderer and
VR-enabled material/post shaders. However, the current Darktide executable has
none of the public `SteamVR`, `vr_supported`, `vr_hmd_resolution`, or related
symbol/setting strings, and the latest decompiled Darktide Lua contains no VR
integration. This is strong negative evidence that Fatshark retained the
public Stingray VR subsystem. A live read-only namespace census confirmed
`SteamVR`, `SteamVRSystem`, and `OpenVR` are all absent. The next evidence-driven
optimization step is GPU timestamp/pass classification followed by a narrow
shared-skinning or view-instancing prototype, not blind command-list suppression.

The local RTX 4090 reports `D3D12_VIEW_INSTANCING_TIER_3`, the highest D3D12
tier, so hardware can share all pre-raster work that does not depend on
`SV_ViewID`. This establishes capability only: Darktide's shaders, root data,
render-target layout, and PSOs still need an explicit two-view variant.

References:

- https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/stingray_help/release_notes/readme_1.6.html
- https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/stingray_help/reference/engine_settings.html
- https://learn.microsoft.com/en-us/windows/win32/api/d3d12/ne-d3d12-d3d12_view_instancing_tier
- https://learn.microsoft.com/en-us/windows/mixed-reality/develop/native/rendering-in-directx

## Next implementation gates

1. Identify the horizontal camera-relative bands now proven to exist in the
   raw shared eye surfaces. Preserve DLSS jitter: a headset A/B showed that
   disabling it leaves the bands present and makes the image blurrier.
2. Add and validate a native-resolution capture boundary if native rendering
   is pursued. Without DLSS the full-size completed scene buffers are HDR
   `R11G11B10_FLOAT`, while the final SDR swapchain is written directly; the
   current post-upscale format-28 intermediate therefore does not exist.
3. Enable translation coherently on both the Darktide camera and submitted XR
   projection poses, then validate bounded 6DoF before raising the clamp.
4. Timestamp and classify the two render command streams before selecting a
   shared skinning, visibility/LOD, or view-instanced geometry prototype.
5. Complete a long lobby session covering loading fallback, camera recreation,
   headset removal, and producer recovery with no stale-session metadata.

## 2026-08-25 projection and horizontal-band follow-up

Pair-driven submission removed the previously reported motion flicker in both
eyes. The accepted live build also transports the runtime-derived render FOV
through the shared pose packet and submits the corresponding symmetric OpenXR
projection. The user confirmed correct scale/FOV, no flicker, and improved
frame rate. Smoke particles remain camera-facing billboards and tilt with the
headset; this is documented as a deferred content/shader issue.

A separate artifact remains: horizontal lines of distortion fixed to the
camera image rather than world space. They are visible in the desktop eye
mirror as well as the headset, and raw shared-eye dumps contain the same row
discontinuities. OpenXR/VDXR can therefore amplify their visibility but is not
their origin.

A controlled graphics A/B retained the working DLSS capture path and disabled
only `jitter_enabled`. The XR run produced about 85--89 fresh pairs/s with no
reused frames and only the two stable startup tag mismatches. The bands were
unchanged and the image became visibly blurrier. Jitter was restored; it is
required for acceptable DLSS reconstruction and is not supported as the cause.

The attempted no-DLSS run initially produced no named eye handles. A bounded
D3D12 boundary census then established why instead of assuming an upscaler
requirement. At 1920x2160, completed scene resources transition as
`DXGI_FORMAT_R11G11B10_FLOAT` (format 26), while the format-28 SDR swapchain is
rendered directly. The current selector learns a full-size format-28
render-target-to-shader-resource intermediate, which exists on the DLSS path
but not the native path. The capped 10,000-line census recorded 2,493 completed
full-size transitions across six resources, with zero satisfying the current
known-output predicate. Evidence is saved under
`artifacts/phase1/no-dlss-boundary-census-20260825`.

## Validation record

Run on the Windows PC from the repository root:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --preset windows-vs2022
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build --preset windows-vs2022-release
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' `
  --test-dir build\windows-vs2022 -C Release --output-on-failure
build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe `
  --frames 30 --debug-layer --require-rendering --xr-frames 6000 `
  --shared-eyes --capture-window-title 'Warhammer 40,000: Darktide'
build\windows-vs2022\tests\shared_eye_surfaces\Release\darktidevr-shared-eye-surfaces-tests.exe `
  --live-dump artifacts\phase1\logical-eye-pair-clean-census-off-20260824
python tools\renderer_probe\diff-eye-captures.py `
  artifacts\phase1\logical-eye-pair-clean-census-off-20260824\left.ppm `
  artifacts\phase1\logical-eye-pair-clean-census-off-20260824\right.ppm `
  artifacts\phase1\logical-eye-pair-clean-census-off-20260824
```

Result: 17/17 tests passed, including compositor-visible OpenXR projection and
theatre gates, semantic-camera parser, pose snapshot, presentation policy,
recenter, translation-clamp, and minimize/restore capture recovery coverage. A
separate live Darktide theatre run completed 1,200/1,200 submissions. The new
eye-selective SBS smoke test also passed 300/300 compositor-visible frames.

No Mac-only validation applies to this Windows PCVR phase.

## Exact runtime extent with recentered symmetric projection (2026-08-25)

VirtualDesktopXR Medium reports 2112x2304 per eye. Virtualizing the game-side
WM_SIZE/client extent made Stingray build a coherent render graph at that exact
size while the physical desktop mirror remained independent. This removed the
horizontal row discontinuities that had been caused by mismatched client and
render extents.

Direct asymmetric Stingray frusta produced invalid screen-space lighting. A
symmetric circumscribed render followed by an affine post-projection transform
fixed geometry and headset coverage, but lighting still used the untransformed
projection and remained misaligned. The accepted solution instead decomposes
each runtime eye into a normal symmetric projection and a local optical-center
rotation. Darktide renders that rotated symmetric camera, and the OpenXR layer
submits the identical rotated pose and symmetric FOV. The compositor still owns
lens distortion and hidden-area sampling; no application-side crop or overscan
texture is used.

Headset validation confirmed correct stereo depth, FOV, head movement, lighting
and overall appearance. The run sustained approximately 115 fresh stereo
pairs/s with no reused frames; the pose-mismatch counter remained at its two
startup samples. This is now the preferred exact-resolution baseline, preserved
under
`artifacts/phase1/known-good-medium-recentered-symmetric-20260825`.
