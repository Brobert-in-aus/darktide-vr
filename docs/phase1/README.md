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

## Camera-only 6DoF gate (2026-08-25)

Headset translation is now composed additively onto Darktide's completed base
camera pose. It moves the two eye cameras together but does not modify the
player unit, controller, locomotion input, aim state, or collision transform.
The initial safety envelope clamps recenter-local translation to a 0.25 m
horizontal radius and +/-0.18 m vertically.

The OpenXR layer now reconstructs its absolute eye poses from that same full
recentered head delta. Previously it intentionally retained orientation only;
enabling translation on the game cameras without removing that restriction
would have caused the rendered viewpoint and compositor image plane to diverge.
A shared core helper and focused math test now require translated eye-pair
midpoint reconstruction while preserving the runtime 64 mm IPD.

Character-select headset validation covered left/right, forward/back and
up/down physical leaning. The user reported flawless 6DoF with no distortion.
The five-minute run submitted 20,406 frames, including 19,994 fresh stereo
pairs, with zero reused or stale frames and only the two known startup pose-tag
mismatches. The subsequent lobby test also passed: the player could move and
look around without tracking, distortion, IPD, locomotion, or recentering
problems. This closes the initial camera-only 6DoF gate.

The same lobby run exposed four separate follow-ups:

- the loading interval was incorrectly presented as full-FOV stereo rather
  than a comfortable flat panel;
- world-space UI differed or disappeared between eyes, and the menu was visible
  only in the desktop mirror and could not be interacted with in VR;
- minor inter-eye differences and shimmer remain, plausibly involving the
  temporal upscaler but not yet causally isolated;
- heavy lobby areas had poor frame rate despite the strong GPU.

The loading fault was concrete: the fallback capture was submitted through the
stereo projection layer and, on the separate-eye path, its height was also
incorrectly halved and repeated. Fallback frames now use the complete flat
capture on a mono quad two metres square and two metres forward. Its first live
test at the original one-metre, aspect-preserving size confirmed the panel
image was correct but rejected VIEW-space head locking. The revised quad
is anchored in LOCAL space from the headset pose when each fallback transition
begins, so it remains fixed in the room until stereo resumes. Gameplay frames
retain the stereo projection layer. The LOCAL-space revision and enlarged
square geometry were exercised during the performance-profile loading
transition; explicit comfort acceptance of the new size remains pending.

The active render configuration audit found AO, GTAO and baked DDGI enabled
despite the low/custom menu profile. `ambient_occlusion_quality = "low"` was
confirmed to regenerate AO/GTAO as enabled, so the profile now sets it to
`"off"`; both active flags remain false after relaunch. Darktide still forces
`baked_ddgi = true` even with `gi_quality = "off"`, indicating an engine-required
baked-lighting baseline rather than a working user quality toggle. Ray tracing,
shadows, volumetrics, decals, SSR, motion blur and lens effects were already
off; DLSS remains at Ultra Performance for the lowest-cost initial dual-render
test. The latter is a quality/performance tradeoff and remains a candidate for
the shimmer A/B rather than an assumed cause.

## Single-render 4K performance control (2026-08-25)

Both DarktideVR mods were removed from the effective DMF load order and the
game was launched normally at exclusive 3840x2160 with the same minimum profile
and DLSS Ultra Performance. Process-module inspection confirmed that
`darktidevr_native_capture.dll` was not loaded, and the fresh console log had no
camera/stereo-probe initialization. The user observed approximately 150 fps on
average with a lowest observed value of 120 fps.

3840x2160 is 8.29 million output pixels per frame; two 2112x2304 eyes are 9.73
million, only about 17% more. The prior lobby XR run produced roughly 50 fresh
pairs/s. The resulting approximately threefold frame-time increase is too large
to attribute to output-pixel count alone. It includes the expected cost of two
complete Stingray world submissions plus additional render/capture/scheduling
overhead. The VR configuration was restored from the exact pre-control backup.

The profiling build records high-resolution wall time separately around
the left world submission, right world submission, and complete pair, reporting
240-pair averages and maxima. The XR harness now reports interval submission,
fresh-pair, and fallback rates in addition to lifetime averages. This is CPU
submission/pacing evidence. D3D12 timestamp queries then bracketed each eye's
queued camera work while excluding the shared-surface copy. At character select
the stable intervals were approximately 3.5--4.3 ms per eye and fresh-pair rate
was 108--117/s. In the lobby the left interval was approximately 24--27 ms and
the right interval 11--13 ms while fresh pairs generally ranged from the
mid-30s to upper-40s during the instrumented soak. The intervals overlap: the
left marker spans most of the complete queued pair and the right marker is
nested inside it, so their sum is not a pair duration. The result localizes the
loss downstream of Lua and confirms a material roughly 11--13 ms second-view
GPU interval, but does not yet assign cost to individual renderer passes.
Timestamp profiling is opt-in after this run so its command-list allocation
overhead is absent from normal testing.

## Shared-work performance pass (2026-08-25)

Inspection of Darktide's shipping `ScriptWorld.render` established a concrete
duplicated CPU boundary. Calling the wrapper once per eye repeated shading
blend/callback/apply, the shadow-bake check, and `World.update_lod_levels`
before each `Application.render_world` submission. The stereo hook now uses the
normal wrapper for the primary eye, then submits the second camera directly
with the already prepared primary shading environment. The second eye remains
a complete native world render with isolated depth, G-buffer, lighting and
temporal output; only frame preparation is shared. A guarded fallback restores
the full wrapper if the camera or shading environment is unavailable or the
direct submission raises a Lua error.

The native producer now retains completed capture command allocators/lists for
reuse instead of creating them per eye, and the XR harness retains its
per-frame image/resource/barrier arrays. Production also omits the dormant
draw, dispatch, root-binding, descriptor, marker and render-target diagnostic
detours. Boundary capture still dynamically learns the runtime output resource
because resource identities change across runs and render-target rebuilds, but
steady-state inspection is restricted to plausible shader-resource/render-
target transitions. Output names are queried only for previously unknown
resources. The expensive boundary census remains opt-in.

Headset validation found unchanged stereo, lighting, tracking and overall
appearance, with a clearly smoother lobby. During the first accepted run,
post-loading fresh-pair intervals commonly reached roughly 80--119/s rather
than the earlier instrumented mid-30s to upper-40s. A second run with the
narrowed native path commonly reported roughly 90--120/s in the lobby. These
are strong directional results but not a controlled percentage: the player
moved and the final camera direction differed between runs. Character select
was also affected by animated scene content. A fixed-pose gameplay benchmark
is required before claiming a precise gain.

The existing focused command trace remains the evidence for the next larger
target: same-frame eyes contain 1,010 draws each, with 1,000/1,010 exact
geometry/input signatures shared, while scissor and complete binding
signatures differ for every draw. This supports view-instanced geometry with
separate per-eye targets; it does not support replaying one completed image or
blindly aliasing the per-eye descriptor state. Queue parallelism is deferred
until that shared geometry boundary is implemented or ruled out.

### Fixed-pose performance baseline

A clean process launch supplied repeatable initial camera positions. Quest
proximity automation was disabled, the headset was left untouched, and no
pointer input was sent after scene initialization. Character select produced
17,220 fresh pairs in 180.009 seconds: 95.65 pairs/s, or 10.45 ms per pair on
average. The only fallback frames and pose mismatches were the two expected at
startup; there were no reused frames or pair-driven timeouts.

After the first soak, a keyboard-only Enter input loaded the lobby without
moving the camera. The untouched spawn view produced 16,966 fresh pairs in
180.015 seconds: 94.25 pairs/s, or 10.61 ms per pair on average. Again there
were zero reused frames and zero pair-driven timeouts, with only two startup
fallback/mismatch frames. One-second intervals were usually in the low-to-high
90s but occasionally fell to approximately 84--89 pairs/s. The fixed lobby
view therefore costs only about 0.16 ms per pair relative to character select;
tail variance, rather than average throughput, is the immediate 90 Hz risk.

These runs replace the earlier moving-camera observations as the controlled
post-optimization baseline. They do not establish headroom for 120 Hz, and
they do not justify risky queue parallelism by themselves.

### Reflex and Reflex Boost samples

Reflex was originally disabled. A short standard-Reflex character-select run
produced 2,628 fresh pairs in 30.005 seconds (87.59 pairs/s), but one short run
below the fixed-pose baseline is not sufficient to assign causality. With
Reflex Boost enabled and the game restarted, character select produced 3,076
fresh pairs in 30.010 seconds (102.50 pairs/s, 9.76 ms/pair). A subsequent
keyboard-only lobby transition produced 2,922 fresh pairs in 30.005 seconds
(97.38 pairs/s, 10.27 ms/pair). Both Boost samples had zero reuse and zero
pair-driven timeouts.

The Boost lobby sample is 3.3% faster than the 94.25-pairs/s controlled
no-Reflex lobby baseline, equivalent to about 0.34 ms/pair. This remains an
exploratory 30-second versus 180-second comparison; reverse A/B and longer
repeats are required before treating the difference as a Reflex gain.

### Focused XR resource census

Diagnostic command-list hooks are now opt-in and must be selected before
`dtvr_install()`. Production leaves them disabled, avoiding thousands of
per-draw detours per stereo pair. A bounded XR-only census at the Virtual
Desktop Medium eye extent (2112x2304) with DLSS Ultra Performance found the
following repeatable resource structure in both sampled phases:

- the main color, G-buffer and depth attachments are 704x768, exactly one
  third of the output width and height;
- smaller 352x384 and 512x512 attachments also occur;
- full-size 2112x2304 format-26 and format-28 resources are also bound;
- every observed attachment has a single array slice.

The engine emitted no usable D3D12 semantic `BEGIN` or `MARK` events, so pass
names cannot currently be recovered from PIX-style markers. GPU timestamps
then tested whether resolution alone supplied a pass boundary. In the final
30-second XR run, the first full-size transition after internal-size work
occurred after 1.92 ms in the left eye and 1.81 ms in the right; 2.45 ms and
2.74 ms respectively remained. Whole-eye averages were 4.28 ms and 4.53 ms,
and the structural transition was found for 97.5% and 99.7% of samples.

This is not a world/post split. Barrier traces show internal- and full-size
resources interleaving, and an earlier output-merger-only detector found a
different later transition. Resolution is therefore useful for resource
classification but unsafe as a semantic optimization boundary. View
instancing still requires array-aware internal, history and output resources,
while the next pass must classify work by command-list/PSO dependencies rather
than treating the first size change as the end of scene rendering.

Validation commands for this pass:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build --preset windows-vs2022-release --target `
  darktidevr_native_capture darktidevr-xr-harness `
  darktidevr-core-math-tests darktidevr-shared-head-pose-tests
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' `
  --test-dir build/windows-vs2022 -C Release --output-on-failure
.\tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 30
```

All 21 non-interactive tests passed. The deployed/source DLL SHA-256 is
`37726227B61483F2A0F66E493347CFFDDD264F3BEA36EF498D1B9E935A3BA095`;
the deployed/source Lua SHA-256 is
`333EBAED070BE67696744A20803791F61770E51D3FE0FEC79EE9BEF5D6C28CC1`.
No Mac-only validation applies to these Windows/D3D12/OpenXR changes.

## Runtime-directed extent, startup presentation, and camera ownership

The shared head-pose contract is now version 5 and carries the OpenXR runtime's
recommended per-eye width and height. The harness publishes those dimensions
before the game creates its eye resources, and the Lua producer consumes them
before both gameplay and character-select viewport creation. The prior
2112x2304 Virtual Desktop Medium extent remains a bounded fallback only. The
harness also retries shared-eye attachment instead of requiring the game
producer to exist when the OpenXR session starts.

A separate named projection-active event distinguishes completed stereo scenes
from startup and loading intervals. Until the producer marks projection active,
the harness presents the live desktop capture on the fixed 2x2 m spatial panel
and acknowledges stale eye pairs without blocking the producer. A direct
startup run remained on the panel through splash/title, attached the shared eye
resources after they appeared, and transitioned to stereo before character
select. The user accepted that transition timing.

Gameplay camera translation remains game-authoritative, but the game no longer
contributes pitch or roll to VR orientation. The default `fixed` rotation mode
stores only the scene's initial yaw, then composes the complete current OpenXR
headset rotation onto that heading. This removes the lobby camera's scripted
vertical-movement orbit and its downward initial presentation pitch while
preserving the physical headset's pitch, yaw offset, and roll from the first
frame. A dormant `yaw_only` route preserves a future thumbstick-turning seam;
it admits game yaw changes while continuing to reject game pitch and roll.
Headset validation accepted the initial physical-angle match and confirmed that
vertical movement no longer tilts the view.

## Frame-generation sample and spatial-HUD finding

With DLSS Quality, one generated frame, standard Reflex, and a 120 fps cap, a
30.005-second character-select sample delivered 2,843 fresh real stereo pairs
(94.75 pairs/s, 10.55 ms/pair). The keyboard-only lobby sample delivered 1,783
pairs in 30.012 seconds (59.41 pairs/s, approximately 16.83 ms/pair). Both had
zero reuse and zero pair-driven timeouts. The bridge observes real completed
eye pairs, not Darktide's generated display frames, so the lobby result is
consistent with a roughly 60 real / 120 displayed configuration rather than a
regression to 59 displayed fps.

Lobby world markers exposed a separate UI limitation. Darktide's
`HudElementWorldMarkers` stores one `_player_camera`, projects every marker with
`Camera.world_to_screen`, and submits one world-global screen-GUI draw list.
That list is consumed by both sequential eye renders. The left marker therefore
matches the left eye, while the right eye receives the same eye-relative pixel
coordinate rather than a projection through the right camera. A constant pixel
shift is not a valid correction because stereo disparity depends on each
marker's world depth. The implemented path retains the left marker primitives,
removes them between submissions, applies the exact right-minus-left
`Camera.world_to_screen` delta from each marker's stored world position, and
replays the marker draw for the right camera. Headset validation confirmed NPC
markers and player names at the correct position in both eyes with no duplicate
left projection.

Markers configured to remain on-screen after their world anchor leaves the
frustum exposed a second ordering boundary. Darktide clamps the primary-eye
widget to an edge before the stereo replay. Applying the ordinary world-space
right-minus-left projection delta to that already-clamped coordinate could
push a left-edge cue completely out of the right eye, or make a right-edge cue
travel across the right eye while remaining fixed in the left. Clamped markers
cannot simply reuse one pixel coordinate: headset testing showed that this
clamps independently to each physical eye edge because the runtime frusta are
asymmetric. The revised branch intersects the two runtime angular frusta,
chooses one shared clamped direction inside that binocular overlap, then maps
that direction separately into each eye image. In-frustum markers retain their
depth-correct per-eye projection. The first angular test correctly found the
overlap but assigned its inset to the opposite physical eye; the runtime frusta
are now associated with the accepted capture/submission eye mapping rather
than the Darktide camera names. Headset validation of that identity correction
remains pending.

`HudElementInteraction` is a second screen-GUI layer which copies the active
marker widget into its own scenegraph pivot. Its normal update could precede
the marker projection in the same frame, producing a stable right replay but a
one-frame-old left `[F] Inspect Operative` prompt. Refreshing the dependent
pivot at the draw boundary fixed that ordering fault; lobby validation accepted
the prompt as stable in both eyes. Full menus remain candidates for the fixed
spatial panel. Particle smoke is a separate native billboard path and still
needs cylindrical, world-up alignment; it is not part of marker reprojection.

## Billboard shader checkpoint and next target

The native DLL now supports fail-closed, whitelist-only billboard vertex-shader
substitution at PSO construction time across ordinary, stream, and pipeline-
library creation paths. It validates the complete reflected shader interface,
clears incompatible cached blobs, falls back to the original PSO on any failure,
and reports aggregate plus per-hash results. An unchanged-payload control applied
all seven observed substitutions with no rejects and no failures across 3,839
PSO-cache operations. A modified single-permutation run was equally stable but
did not affect the observed smoke, ruling that permutation out for those
sources.

The four-permutation horizon test was not a valid visual result: only three
substitutions applied and four were rejected, with safe fallback to originals.
The remaining fifth permutation is axial/tangent-driven and cannot safely use
the same edit. The next investigation will therefore trace the CPU writer of
the shared `c_billboard` camera basis and patch that producer before command
recording. This is a more fundamental blanket boundary than editing every
particle asset or guessing at individual shader permutations. Captured and
generated game shader binaries remain external test artifacts and are not
committed.

## Source-space fullscreen-menu input checkpoint

The desktop mirror's apparent click failure is an XR coordinate-space
misalignment, not an absence of callbacks. Darktide's normal hotspots did not
hover at the visible cursor; a native control click over the drawn `Options`
row could select `Party Finder`. The bridge now publishes an atomic pointer
sample in the fullscreen-menu render source's pixel space, sourced from either
the right-controller panel ray or the foreground Darktide desktop cursor. A
desktop button-down temporarily overrides a simultaneously tracked controller
ray, so desktop debugging stays deterministic without changing normal headset
ownership.

Lua validates sample freshness, maps source pixels through `RESOLUTION_LOOKUP`
to widget scenegraph rectangles, and arms the exact engine hotspot with
`force_input_pressed`. An input edge remains available to all stacked view
draws until a matching widget consumes it. Dedicated hooks cover SystemView's
dynamic content grid and both OptionsView grids; BaseView covers conventional
static widgets. Live validation opened `options_view` through
`grid_content_pivot_widget_11`, then activated OptionsView's first category
widget, with both exact source coordinates recorded in the game log.
OptionsView's native `grid_interaction` hotspot initially force-disabled the
correct child because native hover remained false; asserting that gate only
for a source-space hit allowed Audio to populate the complete settings pane.
The transport is now version 3 and carries persistent monotonically increasing
sequences for primary activation, Back and scroll. This is necessary because
the OpenXR compositor and Darktide UI loops run at different rates: a one-frame
edge could otherwise be published and overwritten between two Lua reads. Lua
consumes each sequence exactly once. The first nonzero sequence observed after
attachment is actionable rather than being mistaken for initialization state.

Source-space hover is asserted through each matched hotspot's `force_hover`.
Back is routed semantically to the top engine view's own back/close callback;
one live event returned from Audio/Options to SystemView and a second closed
SystemView, with no synthetic Escape. Scroll resolves OptionsView's
`settings_grid_interaction` overlay to its owning `_settings_content_grid` and
uses the engine grid's scrollbar API. A live XR scroll moved Audio from its top
rows to Headshot/Backstab Sound and logged one consumed sequence. Click, hover,
scroll and nested Back therefore have desktop/live-log validation.

A sleeping controller produced one short-lived Back transition immediately
after the first SystemView was opened. The native input state now requires a
continuous 100 ms released level before arming Back on menu entry. Tests cover
both transient suppression and re-arming for the next intentional press; a
live sleeping-controller confirmation remains outstanding.

The clean first-menu test also exposed a separate zero/nil initialization bug:
Lua's consumed counters were nil, so the bridge's valid initial zero looked
like a pending event. Primary, Back and scroll consumed counters now start at
zero, and the first SystemView remained open in live XR. The harness advances
Back only from the debounced menu-input event; the former parallel raw-edge
detector has been removed so it cannot bypass the 100 ms arming state machine.

Widget hit testing now walks every hotspot pass and uses its authored
visibility function, size, alignment and offset. This is required for compound
controls such as dropdowns, whose visible options are nested hotspots on the
same widget. Hidden options fail closed and expanded options participate only
while the widget has exclusive focus. Opening a dropdown is routed through
OptionsView's exclusive-focus coordinator rather than pretending it is a
normal button press. The base Screen Mode row is live-reachable; selecting an
expanded option is now also live-reachable. A strict named-button run logged
`widget_setting_84:option_hotspot_1` at source `(1482,515)/2112x2304`, proving
that the nested option was selected by the shared XR edge rather than only by
Darktide's desktop cursor. XR option activation now schedules the matching
cursor-mode focus close one completed OptionsView update later.

Slider discovery uses the widgets' engine-authored pass geometry rather than
screen estimates. The Video FOV `value_slider` reported a 550-source-pixel
`track_hotspot`, a normalized value of `0.5`, and a `0.025` step. XR slider
dragging now captures the widget on trigger-down, snaps the source-space ray to
the authored step, retains capture if a presentation sample is temporarily
inactive, and releases only on a fresh button-up sample. The held-trigger test
controls provide separate primary-down/up events for deterministic unattended
drag tests. The final live gate began and ended the Video FOV drag at normalized
`0.5000`; after release the visible setting remained at 65 degrees. This
confirms that transient engine resynchronization no longer overwrites the last
XR-authored value and accepts sliders for this menu milestone. A subsequent
worn pass confirmed that XR focus on DMF's category filter accepts ordinary
physical-keyboard text input. Controller-only text entry still needs an
in-headset surface or explicit text transport.

That worn pass also showed that Back works but selection and scrolling provide
no useful visible feedback, with no controller model or laser present. The
logs prove trigger and stick events reached the shared transport. Named test
mode was incorrectly allowing desktop hover to replace a valid controller ray,
so the physical controller could operate a stale desktop position. A tracked
controller ray now remains authoritative; desktop hover is only a fallback and
an actual desktop button retains temporary ownership. A visible spatial ray or
reticle and a clean controller acceptance pass are still required.
The initial acceptance implementation submits two crossed 8 mm cyan quad
layers from the right-hand aim pose to the panel hit plus a 3.5 cm impact quad.
They sample one reserved opaque pixel from the existing menu swapchain, so the
laser adds no extra swapchain or copy synchronization. The crossed geometry
keeps one face visible across controller roll. This is deliberately a simple
selection laser; controller models remain a separate presentation task.

The first worn pass accepted that laser and all tested controls except expanded
dropdown options: their overlay was visible, but the ray could activate the
widget behind it. OptionsView hit testing now treats `exclusive_focus` as
modal, so only the expanded dropdown's visible option passes participate until
focus closes. This awaits one live option-selection check.

Recenter and initial anchoring now use headset position plus yaw only. Pitch and
roll remain in the live relative pose, preventing a leaned or tilted headset at
initialization/reset from redefining the virtual horizon. The tilted-pose unit
test verifies a level anchor and exact reconstruction of the original pose.

For the current billboard acceptance loop, exact particle PS
`6020f2548f29fd47` has an interface-matched magenta diagnostic compiled by
`build-particle-horizon-lock.ps1 -DiagnosticMagenta`. That diagnostic was
disabled after the user confirmed cylindrical behavior and does not broaden
shader ownership beyond the confirmed particle pair.

A stale native DLL in the mod-local `bin` directory initially made the new
mapping appear unreadable even though the harness published it correctly. Lua
loads that copy, while other native paths used the `binaries` copy. The
development launcher now synchronizes the source Lua plus the Release DLL to
both destinations and verifies SHA-256 equality before opening the launcher.

The installed desktop shortcut `Darktide VR` is the normal user entry point.
It runs `tools/stereo/launch-darktide-vr.ps1`, which opens the ordinary Steam
game URI, leaves the mandatory Fatshark launcher and its PLAY action intact for
authentication, waits up to 30 minutes for the Darktide splash window, and then
starts the production XR bridge automatically. The bridge session allows up to
eight hours. Failures are shown in a dialog and recorded at
`%LOCALAPPDATA%\DarktideVR\launcher.log`. Recreate the shortcut after moving the
repository with:

```powershell
.\tools\stereo\install-darktide-vr-shortcut.ps1
```

All 30 automated tests pass, including the shared pointer transport, native
export contract, and bidirectional desktop/source mapping tests. Remaining
menu work is a visible spatial controller laser/reticle, controller-only text
entry, remaining custom-grid classes, the fixed spatial menu panel itself, and
an in-headset controller acceptance pass.

## 2026-08-27 spatial-menu follow-up

The compositor/shared-desktop-menu experiment is retired as the active design.
It repeatedly replaced live stereo with cached or mono imagery, introduced
blur and flicker on menu entry/exit, inherited desktop-window occlusion, and
could not make NPC views reliably interactive. Keeping the world alive behind
a compositor quad did not satisfy the requirement that menus exist inside the
game's ordinary stereo scene.

The replacement experiment redirects fullscreen menu drawing to an engine
render target named `darktidevr_menu_ui` and creates a `World.create_world_gui`
surface in the active gameplay world. Escape now leaves presentation mode 1
and live stereo running; the old one-eye blur renderer is destroyed instead of
being transported through the XR bridge. Runtime telemetry proves both the
2112x1188 menu target and a 2.000x1.125 m surface at 2 m were created. The
latest worn test proves the surface is visible in-game, but it is black and
lies horizontally. These are two bounded defects: fix the world-GUI basis so
the plane is vertical, then prove that the menu target is populated and that
the chosen material/render-pass ordering samples it. The opaque backing quad
is diagnostic and must be removed after the texture is visible.

NPC vendor/facility views do not yet use the replacement path successfully.
They retain the prior failure: the UI appears only in the desktop view while
XR becomes mono/flickers or freezes, and the shop cannot be clicked. A
`contracts_background_view` hook now requests `disable_game_world = false`,
but the live result proves that another view/presentation path still wins.
Trace the complete NPC view lifecycle and all remaining presentation-mode
writes before adding more capture workarounds.

Broad UI-renderer interception temporarily captured the gameplay HUD while a
menu was active, causing world markers to stop tracking their targets. Capture
now excludes renderers attached to the active gameplay world. Normal marker
tracking is confirmed; tracking while the Escape surface is active still needs
one explicit regression check.

The splash-screen XR regression was operational rather than architectural: a
test was started without the project launcher/harness wrapper. Launching with
`start-darktide-vr.ps1` again attached XR at the splash screen. Use that known
workflow before diagnosing future splash attachment failures.

Options-grid scrolling and pointer fixes remain useful but are not the current
gate. Interaction should be reconnected only after the correct menu pixels are
visible on a correctly oriented engine-world surface.

Outstanding rendering defect: some assets select different LODs between the
two sequential eye renders. This causes binocular geometry/detail glitches and
needs a shared per-frame visibility/LOD decision (or an eye-union LOD policy)
before the optimized stereo path is production-ready.

Assess light culling at the same visibility boundary: the user reports that
some lighting effects switch off near the left and right edges of each eye.
Determine whether those lights use the stock primary-camera frustum, a
per-submission frustum, or an undersized screen-space bounds test. Validate an
eye-union/overscan policy for both geometry LOD and light visibility rather
than treating the edge symptom as a post-processing artifact.

Enemy shadows have a related but distinct binocular defect: at particular
distances a shadow is present in only one eye. Rotating the head far enough to
swap which physical eye is closer does not swap the affected rendered eye, so
simple distance-to-eye LOD is ruled out. Correlate the asymmetry with render
submission identity, shadow-caster culling, cascade selection and retained
per-eye shadow state alongside the broader visibility/LOD probe.

The 31 August exact-pose A/B narrowed and then resolved this defect. The bridge
captured both completed shared-eye resources from one synchronized pair after
its copy fence, while the gameplay cameras shared position and optical/frustum
rotation. The prepared second-eye path and the complete second
`ScriptWorld.render` wrapper were statistically indistinguishable: respectively
8.0127% and 8.0049% of pixels changed above RGB threshold 2, with PSNR 34.5915
and 34.5431 dB. Reused Lua preparation and the skipped second wrapper were
therefore falsified. Resetting DLSS per eye worsened parity and throughput and
was rejected.

Generation-aware completed-output attribution then found stable opaque/depth
draw populations on the right that were absent from the left. They stayed with
the right viewport when render order was reversed and survived primary layer
and shading-callback inheritance. The actual structural split was Darktide's
dedicated primary shadow-cull camera: CameraManager updated it before the late
VR pose, while the duplicate viewport had no shadow-cull camera. Both viewports
now use the already tracked primary render camera for culling. In a corrected
42-frame trace the eyes issued 21,454 and 21,449 attributed draws and no stable
opaque/depth family differed by even one draw per frame. Exact-pose pixel
mismatch fell to 0.0948%, MAE to 0.0308, PSNR rose to 48.72 dB, and affine edge
correlation reached 0.99830. This shared tracked-camera cull is the production
default; an explicit `disabled` flag remains for regression diagnosis.

### Next session order

1. Present the now-complete transparent Escape capture on the vertical
   `World.create_world_gui` surface and validate pointer coordinates against the
   cropped 2112x1188 menu region.
2. Add repeatable on-demand menu readback so submenu, dropdown, toggle, and shop
   captures can be compared without restarting XR.
3. Instrument the full NPC shop view lifecycle, find the remaining mono or
   desktop-only presentation transition, and route the UI into a world-space
   panel without freezing the stereo NPC scene.
4. Remove the opaque backing quad and old shared-menu transport only after the
   Escape and NPC paths both pass in-headset.
5. Run a worn natural-size acceptance pass for the strict cylindrical,
   zero-spin particle shader, then broaden shader-family coverage.
6. Resume per-eye LOD unification, synthetic controller-path limits, and
   first-person/Psykhanium input and IK work after the menu gate.
7. Fix range locomotion ownership: neutral VR input must not erase WASD, the
   left thumbstick must reach the movement frame, and mixed inputs must combine
   predictably before the gameplay adapter becomes default-on.
8. Replace the visible first-person rig with the headless third-person body,
   then connect controller arm IK and weapon aiming without changing the
   game-authoritative attack origin, reach or timing.

The first implementation of items 7 and 8 is now deployed for a range-only
live gate. The movement injector reads the movement cache that Darktide has
already populated, converts it to a signed two-axis vector, adds active VR
thumbstick input, clamps the result, and writes it back. A neutral VR stick no
longer writes four zeroes over WASD/gamepad input. Logs now include raw left
and right OpenXR stick values, the existing game vector, the combined vector,
and whether the VR stick claimed movement ownership.

The body visibility gate uses Darktide's stock
`EquipmentComponent.update_item_visibility` seam with its visual selection
set to third person. It does not change `wants_1p_camera`, gameplay state, or
the first-person component consumed by weapon logic. After that stock swap it
hides only the third-person face, facial-hair, hair, and headgear slot units.
The existing post-animation two-arm IK writer can therefore drive the visible
third-person skeleton while the hidden first-person rig remains the gameplay
driver. Both features remain explicit flags and are restricted to
`shooting_range`/`training_grounds` until the live body, duplicate-weapon, and
locomotion gates pass.

The optimized/full-wrapper shadow A/B is also ready. A prior focused trace
captured 25,728 primary-eye draw records and 10,469 prepared-frame second-eye
records over the same 29 frames. This is expected evidence that the optimized
right eye omits preparation work, not proof that those missing records cause
the visible shadow defect. `darktidevr_full_second_eye.flag` now switches only
the second-eye submission back to the complete `ScriptWorld.render` wrapper at
runtime. If the enemy-shadow asymmetry disappears, the defect belongs to the
reused preparation boundary; if it persists, the next trace must isolate
per-eye native culling, shadow resources, or temporal state.

Validation on 29 August: the Release build completed; all 27 software/non-HMD
CTest cases passed; Lua parsing, PowerShell parsing for both new flag tools,
and `git diff --check` passed. The three strict OpenXR smoke cases were also
run and failed closed because VirtualDesktopXR reported `hmd-unavailable`.
That is the remaining external live-test gate, not a software-suite failure.

## 2026-08-28 bounded menu and billboard corrections

Engine-source inspection established that Stingray world-GUI content occupies
transform X/Z, not X/Y. The Escape plane now uses camera-right/world-up axes
with horizontal camera-forward as its normal. It also samples the redirected
menu target through `Gui2.bitmap_3d` with explicit 0..1 UVs; the previous
screen-derived render-target-mask UVs could return black on world geometry. A
temporary magenta-top/cyan-left target mark makes the next worn test distinguish
target/sample success from widget-redirection failure.

The native completed-output learner also had an identified NPC-view collision.
After the two exact named eye finals are observed, anonymous same-resolution
resources are no longer learned as eyes. This excludes the full-size UI world
created by `contracts_background_view`, while retaining fallback discovery at
startup and clean relearning after swapchain resize.

The XR harness now has `--synthetic-billboard-sweep`: a magenta spherical quad
and cyan cylindrical quad are rendered side by side under repeatable synthetic
pitch/roll motion. This is an unambiguous reference independent of Darktide's
small particles. Reflection identifies registers 8..11 as the column-major
view matrix. Registers 8 and 10 are the stock spherical right/up inputs;
register 9 is camera forward. The replacement now matches the controlled cyan
reference by flattening forward register 9, deriving a perpendicular right
axis, and forcing world-Z up. Its requested magenta diagnostic remains deployed
pending worn validation.

The sweep now also performs deterministic GPU readback of the left submitted
eye at neutral, pitch, roll, and combined checkpoints.  It removes the resting
HMD's common pose while preserving the runtime-reported inter-eye displacement,
so the four images are comparable even when the unattended headset is lying at
an arbitrary angle.  In the captured roll frame the magenta spherical control
remains display-upright while the cyan cylindrical control follows the rolled
world horizon.  This directly validates the basis construction used by the
native replacement; the remaining native difference was stock per-particle
spin rotating the completed quad back out of the world-up plane.

Release native/harness builds, Lua parsing, shader interface smoke checks, and
the focused native-capture/synthetic-head/harness tests pass. Live validation
is pending because the Quest was not present over ADB; the PC Virtual Desktop
Streamer remained running.

### Additive shared-menu checkpoint

The shared menu surface is now a proven additive OpenXR layer rather than a
presentation fallback. Escape publishes mode 4 while the normal two-eye
projection remains active; native capture matches the exact
`darktidevr_menu_ui` hash (`0xaf0f1409769cf92b`), transports its typeless RGBA
resource, and the harness attaches the 2112x1188 shared surface. A clean hub
run retained exact stereo eye attachment with no pose mismatches and attached
the menu layer after its expected one-frame shared-handle creation race.

The texture-population gate is narrower now. Diagnostic rectangles written to
the target are visible, but SystemView's widgets are not. Redirecting both the
outer renderer field and the authoritative renderer argument passed to its
dynamic `_draw_widgets` path produced the same empty target, ruling out a late
renderer-selection bug. Trace the actual `to_screen` UI draw target at D3D12
level next; do not regress to replacing stereo projection with a desktop
capture.

The paired D3D12 trace and direct GPU readback corrected the initial
interpretation of the named 2112x1188 target. Its menu-phase draw signatures
were the resource renderer's background/registration diagnostics repeated
twice, not stock `SystemView` geometry. Every pixel containing RGB also had
non-zero alpha (`rgb_nonzero_alpha_zero=0`), and an opaque-quad test did not
expose native widgets. Neither D3D12 bundles nor render-pass APIs are involved;
RTV-zero deltas were explicit depth-only world passes. The broad renderer
replay is disabled; production work now targets the stock UI's actual completed
resource or exact compositing boundary so only that native layer is duplicated
into the additive menu transport.

The stock menu boundary is now known. VS `4066249119808695432` / PS
`160970739098383160` is stable in pause/options frames and absent from the hub
baseline. Native capture copies the completed 16:9 swapchain crop into a
`2112x1188` UNORM shared surface, and OpenXR attaches it as an additive quad
over the still-live stereo projection. Pair-driven waiting now remains enabled
during menus, so no compositor-rate cached-pair loop is used. Capture is gated
by the authoritative presentation mode and stops on menu close even though the
shader can also occur in normal HUD frames. Darktide's menu-related frame-rate
drop and delayed recovery remain separate performance work.

The exact magenta particle family can now be built at a bounded 1--20x
diagnostic scale. A 10x run made the target quads plainly visible. The current
live build uses natural 1x geometry with the requested magenta diagnostic;
10x remains available for unattended motion analysis.

The menu-input path now has a live unattended regression as well. The source,
crop, shared texture, pointer overlay, and Lua input transport all agree on
2112x1188 at the current runtime/UI scale. The six-phase synthetic controller
path covers both hands, crossing, panel exit, a 4.5 m over-reach case, and
tracking loss. A bounded live run produced 200 valid hits from 240 eligible
rays and cleanly dispatched all 675 pointer updates.

During that run the D3D12 debug layer found that a no-pair fallback frame could
clear a theatre image left in `COPY_DEST`. Theatre images now enter
`COPY_DEST` only when a shared/cached eye copy will occur; diagnostic fallback
frames enter `RENDER_TARGET`. Focused tests and a repeated bounded live run pass
without debug-layer errors.

The menu cadence regression was diagnostic self-interference, not an inherent
cost of the additive board. A retired focused command trace started a
post-`SystemView.on_exit` baseline whose frame budget could only be decremented
by `SystemView.update`; it therefore stayed armed forever after the view had
closed. Menu tracing and marker logging are now opt-in, and exit explicitly
sets the native trace phase to zero. A stationary clean run held approximately
44--49 fresh stereo pairs/sec before, during, and after the menu instead of
falling persistently to 22--24.

The LOD boundary is now evidence-backed as well. A bounded hook recorded 32
gameplay calls to `World.update_lod_levels(world, camera)`; every call used the
stock `player1` camera and none used the added right-eye camera. This matches
the optimized submission path: primary `ScriptWorld.render` prepares shading
and LOD once, then the right eye calls `Application.render_world` directly.
Reported per-eye object differences therefore do not come from two independent
Lua-visible LOD updates. Diagnose per-camera native visibility/draw selection,
sequential resource transitions, and per-eye temporal state before changing
global LOD policy.

The billboard path also has a repeatable native A/B. At 10x diagnostic scale
with per-particle spin disabled, the synthetic head sweep makes the corrected
world-Z quads rotate with the rolled scene; the stock camera-right/up control
remains display-horizontal while the world rolls. A connected-component PCA
cross-check measured 15.5 degrees of isolated-component mean-axis span for the
cylindrical run versus 13.7 degrees for the spherical control. The visual A/B
is stronger than that population statistic because moving/overlapping quads
contaminate component axes. Production is restored to 1x, zero local spin, and
cylindrical orientation; the temporary magenta pixel diagnostic was retired
after worn acceptance. Retaining the
stock local spin rotates the quad out of the world-Z cylindrical plane and
defeats a strict horizon lock; it is now available only as an explicit
shader-build option for comparison.

The final native trace located this PSO on `ExecuteIndirect` (command-list
vtable slot 59) and captured 2,048 clean 512-byte `c_per_object` bindings.
Quaternion-correlated samples prove registers 8--10 contain the XR camera
basis. The user then confirmed the enlarged magenta particles follow the world
horizon under the synthetic head-roll sweep. Shader ownership, basis causality,
and the worn orientation gate are therefore closed for this particle family;
only broader material/scene compatibility remains.

### Psykhanium body/weapon presentation checkpoint

The one-shot semantic navigation path now enters and verifies the private
Shooting Range without mouse movement. Synthetic body and first-person weapon
presentation are gated to `shooting_range`/`training_grounds` and remain
test-flag controlled.

The visual weapon rig no longer drops a write when the controller exceeds the
temporary 0.75 m presentation envelope. Its target is clamped continuously to
that boundary while gameplay aim/origin/reach remain engine-owned. Live
telemetry covered over 1,600 writes with repeated 1.11 m requested excursions:
all resolved to exactly 0.7500 m, weapon-attachment error stayed 0, and maximum
post-write hand error was 0.000001 m. The test flags were disabled after the
run. Next first-person work can build input/aim semantics on this continuous
visual foundation rather than debugging a synthetic-path snap.

### Controller input delivery checkpoint

The private Shooting Range synthetic path now validates both native edge masks
and the exact Darktide ephemeral actions they reach. Every mapped gameplay
name was present in the active input table across repeated cycles
(`missing=none`): both attack families, weapon extra, grenade ability,
interact/reload, quick wield, jump/dodge, crouch, and sprint. Smart tag and menu
remain separate consumers by design. This closes the previous gap where logs
proved only that a native bit mask existed, not that Lua found and injected
the corresponding game action.

Do not restart only the XR harness while retaining the game process for visual
acceptance. That can attach to an obsolete shared-eye epoch and submit fallback
frames despite a healthy desktop mirror. The accepted run used a full clean
producer/consumer restart and recovered to roughly 48--60 fresh pairs/sec with
zero pose mismatches. Raw ADB `screenrecord` is also black for the Virtual
Desktop OpenXR compositor on this setup and cannot replace a worn visual check.

### Native analog locomotion checkpoint

Left-stick locomotion now uses Darktide's own fixed-update movement actions
instead of moving the VR camera or player unit. The OpenXR mapper exports a
radial-deadzoned analog vector; Lua populates the stock directional float
caches and leaves the engine's locomotion, acceleration, collision, and
platform handling intact. A clean Shooting Range run exercised forward,
right, backward, and left phases. Downstream cache telemetry matched every
phase and player-unit world coordinates changed by metres along the expected
axes, proving real native locomotion rather than camera-only displacement.
All existing mapped button actions still resolved with `missing=none`.

This is the controller-movement half of the intended hybrid model. Physical
room-scale displacement still needs a separate body-root policy that drags the
allowed translation region with the headset and reconciles absolute physical
motion with the native locomotion controller without bypassing collision.

### Configurable movement-reference checkpoint

The release-facing mod options now expose headset-relative movement (the
default) and left-hand-relative movement. Only VR controller axes are rotated;
keyboard and other stock accessibility inputs keep their existing semantics.
The left-hand policy projects the tracked controller aim onto the horizontal
plane and deterministically falls back to headset-relative movement whenever
orientation tracking is stale or the controller points too nearly vertical.
The same policy drives the special hub movement seam, so hub and mission zones
do not maintain separate definitions of forward.

The XR harness has a purpose-specific
`--synthetic-movement-reference-path`, exposed through
`start-darktide-vr.ps1 -SyntheticMovementReferencePath`. It holds left-stick
forward while cycling the left aim through forward, +90 degrees, -90 degrees,
and invalid tracking. A clean authenticated hub run delivered 6,448 fresh
stereo pairs with zero shared-frame reuse, timeouts, pose mismatches, script
errors, or engine errors. Lua observed projected movement vectors of
approximately `(0,-1)`, `(1,0)`, and `(-1,0)`, then selected
`head_fallback` only during the invalid-tracking phase. This closes unattended
coordinate/basis validation; worn comfort and preference acceptance remain.

### Hybrid room-scale locomotion checkpoint

The body-root half now has a tested collision-aware transport. Head motion is
split into bounded camera lean and a cumulative body-follow offset in the XR
harness, then carried through the versioned shared-head mapping. Lua consumes
only new offset deltas and injects them as a one-fixed-tick addition to
Darktide's existing `velocity_wanted` immediately before
`_update_script_driven_movement`. That stock method applies drag, push and
minion constraints and ultimately calls `Mover.move`; the original steering
velocity is restored afterward so controller acceleration state is not
replaced.

This design is based on source and live evidence. `target_translation` is
initialized and retained by the steering component but is not read by normal
script-driven locomotion; a live write produced no movement. The velocity
adapter produced matching position changes in a clean Shooting Range run.
Running synthetic stick locomotion and synthetic room-scale motion together
showed both contributions in the same fixed update without retained input,
script errors, or runaway accumulation. Production enablement remains gated
until a worn comfort/collision acceptance pass.

### Transparent native menu checkpoint

Do not reintroduce completed-swapchain menu capture. The swapchain is opaque
and contains the mono/blurred world, which caused the previous freeze,
flicker, and delayed stereo recovery. Production now intercepts the exact
stock Escape-menu draw batch instead: 28 blended, depth-free draws across
seven measured shader pairs are redirected into a transparent 2112x2304
shared render target while the original game RTV is restored after each draw.

The menu batch crosses command-list boundaries. Clear the shared target only
once per game frame and publish its ready fence once at Present after all
direct-queue work has been submitted. Signaling from each
`ExecuteCommandLists` call yields a partial menu and is not valid. The OpenXR
consumer crops source `(0,558,2112,1188)` into the 16:9 panel and applies the
same source-to-panel mapping to controller input.

An unattended live capture now contains the complete Escape menu—text, icons,
button fills, arrows, and footer—while fresh stereo eye pairs continue behind
it. Remaining gates are a worn appearance/pointer pass, options/dropdown
coverage, and a separate trace/interception policy for NPC shop views.

### 2026-08-29 current implementation order

The accepted hub embodiment baseline now retains server-authoritative
`hub_jog`, applies HMD-relative visual heading before sampling the common
camera/controller body anchor, and uses a 0.25 m visual-only horizontal lean
envelope. The planted-foot body follows the constrained HMD pose without
moving the public-hub collision root or taking a room-scale step. The local VR
body also suppresses Darktide's lateral `idle_fullbody` variants while retaining
its subtle base stance sway. Head position, stable hands, head-look steering
and hub motion otherwise passed worn validation. The calibrated OpenXR
grip-to-model-wrist translation is now
3 cm away from the body centreline, 4 cm body-back and 1 cm world-down in
addition to the previously accepted anatomical grip-origin correction.

Crouch height is now derived from an estimated anatomical neck point rather
than raw headset height. The headset-to-neck rotation arc is subtracted before
pelvis/leg IK, so ordinary +/-45-degree looking does not crouch the body while
real simultaneous vertical movement remains intact. XR recenter generation is
carried in shared head-pose transport v8 so a tilted reset rebases cleanly.

Shoulder reach has passed its launch-baseline worn gate. The earlier direct
`j_spine2` approximation has been replaced by a scaled constrained solve over
the live `j_spine`/`j_spine1`/`j_spine2` chain. Each arm independently requests
opposing girdle yaw near 90% of its measured reach; equal requests cancel to a
square shoulder line, while unequal requests advance the reaching shoulder and
retract the opposite one. Each clavicle retains independent protraction capped
at 3% of that live arm length. A 200-sample in-game synthetic pass proved
opposing unilateral yaw, 0.00-degree bilateral cancellation, and at most
0.000017 m tracked-hand error. The rejected shared-protraction version gave
bilateral extension an erroneous 10 cm-per-arm bonus and must not be restored.

Continue in this order:

1. Extend Hadron's accepted flat-interactive mode-5 route across every shop
   family, preserving child-view input, strict one-eye desktop mirroring and
   generation-synchronised stereo restoration. Contracts Events now uses the
   same mode-5 family route: this removes a reproducible mode-4 D3D12 page fault
   and passes automated open/close lifecycle testing. Worn Events content and
   input alignment remain. Then repair the Escape menu.
2. Worn-validate hybrid hub avatar ownership: stock locomotion/legs plus the
   VR-authored upper body, with no whole-body flicker or visible waist seam.
3. Complete HUD/UI coverage while preserving 6DoF, binocular-overlap marker
   clamping and pointer crop-local coordinates.
4. Continue ranged weapon aim, binocular crosshair/reticle policy and optional
   controller laser presentation after the UI gates.
5. **Implemented; worn regression remains:** per-eye detail, lighting and
   shadow population now use the same tracked primary render camera for culling.
   Completed-output attribution and exact-pose readback reduced the mismatch
   from about 8.01% to 0.0948%. Worn-check enemy shadows, edge lights and the
   previously missing floor/detail examples with normal eye separation. Keep
   no-DLSS output discovery as an independent compatibility task rather than a
   prerequisite for this accepted causal fix.
6. Attribute and remove duplicated render work before attempting evidence-based
   pooling, multiview, view instancing or safe queue parallelism.
7. Finish locomotion and controls: configurable head/hand-relative movement,
   turning, room-scale collision semantics, crouch polish and button coverage.
8. Revalidate the disputed identified-particle cylindrical substitution in a
   worn native scene, then extend only an accepted path to remaining native
   smoke and particle families.
9. Stage remote presentation: stock replicated `aim_direction` first, then a
   private versioned mod-to-mod head/two-wrist channel with interpolation and
   stock-husk fallback. See
   [networked VR IK feasibility](networked-vr-ik-feasibility.md).
10. Worn-validate height-first calibration across human/Ogryn size limits and
    standing, seated, bilateral and single-arm flows.
11. Complete XR lifecycle robustness, authenticated release startup, packaging,
    configuration, rollback and diagnostics.
12. Defer transition polish, including the brief post-shop mono flash, until the
    feature gates above are complete.

The private-range ranged-aim prototype now composes the right controller aim
pose with the body/world anchor and preserves Darktide's stock recoil, sway,
aim-assist and spread as a local rotation delta. It also writes the native
replicated `aim_direction`. Load, synthetic tracking, automated Psykhanium
entry and stereo-readiness gates pass. Synthetic gameplay buttons are now
suppressed outside `stereo_world`, preventing their Back/Menu phase from
interrupting loading or automated training-menu transitions. Simultaneous
projectile groups follow
Darktide's own first-projectile ownership rule so reused prepared rotations
cannot receive the controller transform twice. Firearm/projectile shots now
prefer Darktide's registered third-person muzzle attachment as their origin and
fall back to the engine's stock position if that node is unavailable. The
available unattended Psyker loadout now has explicit source ownership. Normal
staff fire originates at the tracked left hand but aims from the right hand;
charged/ADS fire originates at the live staff-tip attachment and also aims from
the right hand. Chain-lightning targeting, smart-target acquisition and damage
run against a scoped right-aim proxy without writing Darktide's read-only
first-person component. Clean live runs logged both projectile owners and four
lightning updates with nonzero stereo `shared_ready`. A non-Psyker firearm shot,
worn alignment and the production laser/reticle policy remain.

An opt-in compositor reticle now supplies the first binocular presentation
candidate. `start-darktide-vr.ps1 -EnableGameplayReticle` places a 6 cm cyan
quad 8 m down the tracked right-controller aim ray only for fresh synchronized
`stereo_world` pairs; loading and menu modes cannot receive it. It reuses one
reserved texel in the existing capture swapchain rather than allocating another
overlay resource. A clean authenticated hub run submitted 1,653 reticle frames
across 4,840 fresh pairs with zero reuse and zero pose mismatches. Worn testing
must still judge alignment, size, depth and off-axis skew. The diagnostic is
intentionally always visible and head-parallel, so target occlusion, raycast
depth and production coupling to controller-authored aim remain open policy.

Unattended range launches are now self-contained: `-EnterPsykhanium` implies
the guarded hub advance required by its hub-gated Lua state machine, and
`-SyntheticGameplayInput` enables its test-only Lua adapter only for the XR
runner lifetime before restoring the prior flag in `finally`. This prevents a
nominal range test from either stopping at operative select or publishing
synthetic actions which Lua deliberately ignores.

### Hybrid hub upper-body ownership

The hub no longer needs to choose between stock locomotion and a wholly
VR-authored avatar.  The current prototype leaves the authoritative player's
root, collision, legs and stock gait untouched, hides only its visible upper
body, and spawns a local profile-matched upper-body proxy for torso and arm IK.
This follows the live evidence: IK cadence matched stereo cadence and solved
transforms survived both eye boundaries, while stock hub animation rebuilt the
upper chain before each solve.  The proxy therefore isolates render ownership
without replacing hub locomotion or duplicating the lower body.

`UIProfileSpawner` requires `slot_unarmed` even when weapon geometry is not
wanted, and its hair-state-machine path assumes a hair slot exists.  The proxy
retains invisible unarmed equipment plumbing and does not enable the ignored
hair path.  A fresh authenticated hub launch completed with the proxy active,
no Lua errors after activation, and nonzero XR `shared_ready`.  Worn visual
acceptance remains: verify stock animated legs, VR-authored upper body, no
torso/arm flicker and no visible waist seam.

The harness also has a fixed 70-degree look-down body-inspection pose which can
be combined with the synthetic controller, reach and locomotion paths. In a
clean authenticated hub run, twelve short-interval desktop-mirror captures
showed a continuously visible torso and smooth arm travel without the previous
alternating-authority signature. The run delivered 6,763 fresh pairs with no
capture failure, frame reuse or pose mismatch. This narrows the remaining gate
to a worn stereo check for subtle flicker and the waist seam; it does not replace
that human acceptance test.

### Quantile-based hub profiling

The opt-in profiler now reports actual CPU wrapper p50/p95 samples and native
D3D12 per-eye interval p50/p95 samples.  In a stationary authenticated hub run
with the hybrid proxy and IK active, the final twelve warmed 240-frame windows
had a median summed-eye average of 26.998 ms (26.075-28.414 ms range), a median
sum of eye p50s of 26.390 ms, and a median sum of eye p95s of 34.873 ms.  The
last two are sums of independent eye quantiles, not a paired-distribution
quantile.  The Lua render wrapper's actual pair p50/p95 were 0.242/0.564 ms;
body plus weapon IK averaged about 0.417 ms CPU.

Per-eye attribution shifts between configurations while total work is more
stable, so optimization decisions use the sum.  The native stage boundary is
also only the first transition to a full-output-sized resource, not a semantic
world/post boundary.  Roughly 6-8 ms remains before that transition in both
eyes, making prepared-frame shared-work ownership the next evidence-gathering
target before pooling or queue parallelism.  GPU profiling is disabled in the
production-clean build. The disputed billboard shader substitution plumbing is
now separated from its retired per-draw selector census. Native cylindrical
behavior still requires a fresh worn acceptance pass. That census
installed the full diagnostic D3D12 hook set and locked renderer metadata on
every draw despite having no active write path. It is disabled in production,
and ordinary draws skip the remaining menu classifier metadata lookup whenever
direct menu capture is inactive. Worn visual and repeatable frame-time
validation remain before claiming the size of the CPU-side gain.

Earlier retained-HUD migration attempts produced a valid panel with no fixed
content. Source inspection found the missing ownership seam: the element
lookup did not override retained mode on individual widget passes, and their
existing retained IDs short-circuited the replay. The safer default-off
candidate now preserves the stock HUD as the sole update/event owner,
temporarily forces only fixed live widget passes through an immediate VR-owned
target, and restores all retained fields afterward. A fresh hub gate populated
the target and retained visible fixed player/team content while spatial
elements stayed in the per-eye pass. Worn depth, parity and coverage remain
pending; do not enable the older duplicate-update prototype.

The default-off candidate can now be enabled for one guarded run with
`start-darktide-vr.ps1 -EnableHudPanel`; the launcher restores the exact prior
flag state in `finally`. A clean fixed-look-down hub run created the 1920x1080
HUD target, kept interaction/world-marker/nameplate elements spatial, delivered
6,612 fresh pairs with no capture failure/reuse/pose mismatch, and restored the
flag to disabled. Source auditing also places damage numbers and smart tags
under the world-marker owner. The stock crosshair is the only remaining direct
HUD `Camera.world_to_screen` consumer and is intentionally assigned to the
right-controller aiming work rather than the fixed panel.

### Hadron transition checkpoint

Hadron's 16:9 flat-interactive panel is now usable with the XR ray, and
presentation-entry input arming prevents the interaction used to open the shop
from selecting its first option. Shop exit also preserves the VR-owned
Darktide-coordinate gameplay heading, so locomotion and interaction facing do
not inherit the shop camera rotation.

Resume synchronization is generation-based rather than time- or frame-count-
based. Lua commits the gameplay-orientation generation after restoration, the
native eye producer stamps each completed pair, and the harness resumes on the
first pose-synchronised matching pair while consuming hidden outgoing pairs.
Observed resume latency is about 20--21 ms. A tolerably brief mono flash remains
and is deferred as transition-quality polish.

The generic shop policy now has independent semantic-input results across the
four ordinary hub shop families. Concrete landing-view draw hooks transform the
published landscape XR ray into the retained portrait eye canvas, clear every
previous semantic hover owner on every draw, suppress the competing native
input service while the XR ray is present, and arm only the matching engine
hotspot. Source-pixel probes activated these stock transitions in clean
authenticated XR runs:

- Contracts `option_button_1` -> `contracts_view`;
- Contracts `option_button_2` -> `marks_vendor_view`;
- Armoury `option_button_1` -> `credits_vendor_view`;
- Cosmetics `option_button_1` -> `cosmetics_vendor_view`;
- Barber `option_button_2` -> `character_appearance_view`.

The shared stereo-ready counter continued advancing and no script or device
error followed any accepted route. The Contracts Events route remains
explicitly unaccepted: a prior `option_button_4` activation opened
`live_events_view` and was followed by a GPU hang. Treat that child as an
independent blocker rather than evidence against the landing owner.

The generic shop policy originally gained an independent contracts-family
live result.
Programmatic `contracts_background_view` entry produced a correctly
proportioned 2496x1404 mode-5 source, and exit returned to fresh stereo in 28 ms
without script errors or pose mismatches. The guarded hub harness exposes the
remaining armoury, cosmetics, barber, marks and premium-store landing views for
the same one-family-at-a-time gate. Their primary child transitions now pass
unattended semantic activation; worn XR corner alignment, scrolling, nested
actions and Back remain user gates.

Armoury, cosmetics and barber landing views now also have unattended visual,
lifecycle and primary-child activation passes at the same 2496x1404 source
extent. Direct marks entry is
explicitly rejected: `marks_vendor_view` requires context supplied by its
contracts parent, and constructing it without that context corrupts the UI
view stack. Marks must be exercised through the stock contracts transition;
the guarded harness no longer exposes the unsafe shortcut. Premium-store
landing and all interactive child pages remain pending.

Normal deployment now owns the pre-Lua D3D12 bootstrap configuration. It
removes stale diagnostic/shader-dump flags and retains only billboard shader
substitution by default. This prevents a prior diagnostic session from both
reintroducing per-draw overhead and causing the production Lua configuration
to fail closed after hooks are already installed.

Premium store is a distinct native-aspect case. Its first generic shop run
rendered the full landing page, but a worn check found the cursor offset because
the mode-5 compositor treated its already-landscape client as a portrait
eye-encoded image. Presentation mode 6 now shares mode 5's capture and input
semantics while fitting the native client aspect. `store_view` and
`store_item_detail_view` use mode 6. A clean live run published 2496x1404 on a
2x1.125 m panel without script errors.

Live Store geometry shows that its retained widget scenegraph remains authored
in the portrait eye canvas even though mode 6 presents a native-landscape
client. A source click at `(626,297)/1024x576` reported the full-grid rectangle
near `(142,863)` with extent `2210x1040`, directly falsifying the earlier
crop-local-scenegraph assumption. Mode 6 now keeps the panel, laser and visible
cursor in native landscape coordinates while transforming semantic Store hit
tests into the portrait eye canvas. The stock Windows hover is suppressed while
XR owns the pointer; it was the offset second owner seen during the worn test.

Store item cards use a private `StoreView._draw_grid` path rather than
BaseView's conventional widget list. The generic hook could correctly hit only
the full-grid catcher. Mode 6 now leaves that catcher inert and resolves the
transformed XR ray against the real `_grid_widgets`, arming only the matching
item card. While
the XR ray is active, StoreView's stock grid receives a null input service so
the mis-normalized native cursor cannot highlight a second card. The Lua safety
gate remains at 198/198 locals, both Release targets build, and all 30 CTest
cases pass. Worn corner alignment and landing-to-detail navigation are the
first worn gate. A source-pixel synthetic pointer probe provides unattended
activation evidence without treating Windows mouse injection as XR input. A
live `pointer_500_360_1280_720` run activated a real Store card and opened
`store_item_detail_view`. Store samples full-grid focus before applying card
hotspots, so the hook now publishes the interaction catcher's `is_hover` and
`force_hover` on the same trigger frame; otherwise the correctly matched card
was force-disabled despite the activation log.

SystemView has the same presentation/semantic split. Its Escape panel is
landscape while a live hotspot inventory placed retained rows in the portrait
eye canvas (Options near `240,1539` with extent `650x65`). Escape semantic hit
testing therefore transforms the source ray while leaving the visible laser in
panel pixels. A corrected source probe at `(290,421)/1280x720` activated the
real Options row, opened `options_view`, and cleanly returned through SystemView
to fresh stereo gameplay. Worn laser alignment remains pending.

The nested OptionsView requires a second, explicit semantic owner. Its retained
category/settings grids, dropdowns and sliders are still authored in the
2496x2688 eye canvas even though the enclosing Escape panel and XR pointer are
1280x720 landscape pixels. BaseView now excludes OptionsView's broad dynamic
grid catchers, and `OptionsView._draw_grid` transforms the hit pointer for row,
dropdown, slider, scroll and drag geometry while leaving the visible pointer
and event sequence source-local. An unattended two-stage probe activated the
real System Options row and then logged
`options_source_activate widget=grid_content_pivot_widget_3` for nested source
point `(180,144)/1280x720`; the previous full-grid false owner did not fire.
The 600-second run passed with `shared_ready=6628`, no capture failures, no
shared-frame reuse and no pose mismatch. Worn corner alignment and representative
dropdown/slider/toggle interaction are still required before Escape settings
input is accepted.

Synthetic menu-input probes now explicitly rejoin the native primary-button
sequence after their one diagnostic edge is consumed. Previously a synthetic
sequence greater than the underlying native counter made the returning native
value look permanently unconsumed and could repeatedly exercise settings-grid
diagnostics. A fresh run activated Video once with no repeated slider event,
then `(995,105)/1280x720` opened the real Resolution dropdown
(`widget_setting_82`). The focused dropdown reported its header and five modal
option rectangles in the same portrait semantic space. No option was selected,
so the release-critical custom render resolution was not changed; actual option
selection, toggles and slider drag remain acceptance gates.

An adjacent performance audit removed per-frame diagnostic filesystem probes.
System/vendor menu and input-inventory flags poll every 15 UI updates;
Psykhanium and hotspot inventory poll at 250 ms; movement inventory retains a
60-fixed-frame gate. Active close state still advances each frame.

A subsequent matched culling A/B quantified the cost of the visual-parity fix.
Across the last twelve warmed stationary-hub windows, shared tracked-camera
culling measured 33.773 ms summed-eye GPU average versus 30.942 ms for the old
independent/stale-cull regression. Summed independent-eye p95s were 40.699 and
37.312 ms respectively, while the corrected Lua pair wrapper was only
0.324/0.582 ms average/p95. The restored geometry, shadow and lighting work is
the source of that roughly 2.8 ms GPU difference; shared-camera culling does
not itself share prepared visibility. It remains mandatory for parity. The next
renderer optimization target is reusable visibility/draw preparation before
the per-eye camera-dependent work. Focused command-list attribution is now
inactive-cost-gated, and GPU profiling remains fresh-process, diagnostic-only.

The next diagnostic step now times the direct-queue submission batches inside
one focused stereo sample and joins every submitted command list to its
recording generation and PSO sequence. The stationary hub trace contained two
terminal-delimited eye renders: right-eye batches accounted for 5.499 ms of
timed direct-queue execution and left-eye batches for 6.955 ms. They shared 239
of 271 unique PSOs (88.2% Jaccard); bind-count multiset overlap was 70.3%.
This is concrete evidence that most pipeline families are common while the
per-eye command populations are not identical. The safe next target is shared
visibility/draw preparation and state assembly before eye-dependent command
recording. It is not blind command-list replay or queue parallelism. The
fresh-process trace is armed with `set-performance-pass-trace.ps1`; analyze it
with `analyze-gpu-batch-trace.py`. Both remain diagnostic-only.

### Depth-aware controller aim checkpoint

The diagnostic compositor reticle is no longer hardcoded at 8 m. During a
private Psykhanium run, Darktide now performs an all-hit query from the tracked
right controller using the shipping player-shooting collision filter, skips the
local avatar that encloses the hand origin, and publishes the first remaining
surface distance over a validated shared-memory state. The harness consumes
that state only for stereo-world frames and applies a distance-scaled reticle
size to keep its apparent angular extent bounded.

A clean synthetic-controller run recorded 7,571 transport updates and 3,450
reticle frames, all with scene hits. Distances varied with the synthetic sweep
from about 10 to 33 m rather than collapsing to the initial 0.05 m self-hit.
Stereo delivery remained stable at 10,175 fresh pairs, no shared-frame reuse
and no pair-driven timeout; both test-only flags restored automatically. This
is an unattended depth/transport pass, not worn acceptance. Perceived alignment,
occlusion and comfort still need a headset check, and deterministic weapon
selection/firing must separately cover sword, lightning, staff primary
(left-hand origin/right-hand direction) and staff charged
(staff-tip origin/right-hand direction).

### Deterministic Psyker weapon matrix checkpoint

`start-darktide-vr.ps1 -SyntheticWeaponAimMatrix` now runs a clean, repeatable
private-range weapon sequence instead of reusing the broad controller diagnostic
whose simultaneous actions made weapon ownership ambiguous. The matrix waits
for the typed gameplay-aim state to become active before starting its own frame
clock, resets every gameplay control between stages, then performs: sword-to-
staff quick-wield, staff primary, held alternate plus staff charged, chain-
lightning equip plus primary, staff-to-sword quick-wield and sword primary.

A 140-second authenticated run completed four cycles. Darktide logged four
normal-staff projectiles with tracked-left-hand origin/right-hand direction,
four charged projectiles with live staff-tip origin/right-hand direction, and
four chain-lightning right-aim updates. Each sword stage had ordered quick-wield
and primary input delivery, but melee action start/hit completion has not been
instrumented and is not claimed. The run delivered 4,185 fresh stereo pairs,
zero shared-frame reuse, zero pair-driven timeouts, no Lua or engine errors, and
restored its temporary flags. This closes unattended source/direction coverage
for the available Psyker ranged attacks; worn aim/reticle acceptance and a
non-Psyker firearm remain open.

### Identified-particle billboard revalidation checkpoint

The exact VS/PS pair `42e436fb1ef1b392` / `6020f2548f29fd47` has now been
revalidated from synchronized shared-eye captures. A fresh-cache 10x magenta
diagnostic made the family unambiguous in the hub while the deterministic head
sweep supplied level and rolled views. Thirty captured stereo pairs show the
quads rotating with the rolled world instead of remaining display-upright, so
this exact family is cylindrically billboarded. The reported spherical smoke
belongs to another material family and must be identified independently.

Normal development deployment is now fail-safe for this feature: enabling
billboard substitution also rebuilds/copies the natural 1x vertex replacement,
and sync removes a stale magenta diagnostic unless explicitly requested. This
prevents both a clean install with only the bootstrap flag and leakage from a
prior enlarged colour probe. The captured run delivered 3,250 fresh pairs with
no reuse, timeout or pose mismatch, after which production 1x/natural output
was restored.
