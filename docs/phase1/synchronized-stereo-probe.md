# Synchronized stereo probe

The first engine-stereo experiment uses a facility already present in
Darktide's Stingray Lua layer: one world may own multiple active viewports, and
`ScriptWorld.render` renders every viewport in layer order during the same
simulation tick.

`darktidevr_stereo_probe` is inert on load. The `dtvr_stereo_on` DMF command
waits for the gameplay `player1` viewport, creates a second camera/viewport,
splits the desktop back buffer into left and right halves, and applies symmetric
32 mm eye offsets after `CameraManager._update_camera` has finalized the clean
game camera. The original camera is rebuilt by the game on every frame, so the
probe never accumulates offsets.

This is a deliberately narrow feasibility probe. It does not yet supply the
runtime's asymmetric per-eye projection matrices, isolate temporal histories,
separate the HUD, or copy the two renders into OpenXR swapchains. It also does
not alter simulation, networking, input, matchmaking, or time. If setup or an
eye update throws, it disables itself, destroys its extra viewport, and restores
the primary viewport to the full back buffer.

Commands:

```text
/dtvr_stereo_on
/dtvr_stereo_off
```

Initial validation is desktop-only in a private/offline gameplay state. Success
means one frame visibly contains two horizontally separated views of the same
world state with the expected parallax. Only after that gate passes should the
capture bridge route the halves to the corresponding OpenXR eyes.

The character-select scene was identified as `ui_main_menu_world` with viewport
`ui_main_menu_world_viewport`. The experiment targets only this exact scene,
allowing the same-tick render path to be checked without pressing START or
entering the social hub. Menu UI remains a separate full-resolution layer; only
the 3D scene viewport is split.

## First result: engine gate found

The exact-target experiment successfully created the second viewport and began
the second same-frame world render. The renderer then asserted in
`deferred_skinning_kernel`:

```text
Bad Skinner!
Assertion failed `bones_buffer.last_frame_accessed != frame`
```

This is strong negative evidence against naive multi-viewport synchronized
stereo. Darktide's deferred skinner treats a second access to the same animated
character's bone buffer during one engine frame as invalid. The experiment is
now disarmed by default and requires the explicit `dtvr_ui_stereo_on` command.
It must not be repeated until the second view has isolated skinning state or a
different renderer boundary is identified.

Disassembly of the exact executable shows both guards compare a resource's
stored `last_frame_accessed` value with the current frame, call the assertion on
equality, then store the current frame value on the non-assert path. The guarded
branches are at RVAs `0x7a7f86` and `0x7a8082` (raw file offsets `0x7a7586`
and `0x7a7682`). This makes a narrow bypass test possible by changing each
two-byte `jne +0x31` instruction (`75 31`) to `jmp +0x31` (`eb 31`).

`tools/stereo/set-skinner-assert-patch.ps1` implements that experiment. It
accepts only the known executable hash, verifies both original bytes, retains a
hash-checked pristine backup, refuses to run while Darktide is active, and will
restore only if reversing those exact two bytes reproduces the pristine hash.
It does not suppress any other assertion. EAC must remain stopped for the test.

With those two guards bypassed, Darktide remained running and briefly produced
two plausible views of the animated character-select scene. The cameras then
translated into empty space because the first probe symmetrically modified the
engine-owned primary camera on a callback that can execute more than once
without rebuilding the clean pose. The corrected probe never writes the primary
camera: it treats that as the left eye and positions only the duplicate camera
one full 64 mm IPD to the right. This removes the accumulation path while
retaining distinct same-tick views for the feasibility test.

The first non-accumulating run exposed a second coordinate bug: the UI spawner
animates its camera *unit* directly, while the probe read and wrote the nested
`Camera.local_*` pose. Combining that nested pose with the unit's quaternion
produced a large apparent vertical eye separation. The probe now copies and
offsets `Unit.local_position`/`Unit.local_rotation` consistently for both UI
camera units; projection parameters still come from the Camera objects.

## First OpenXR stereo submission

The first live desktop SBS pair was consumed as two eye-selective OpenXR quad
layers. That proved left/right routing, but headset testing showed that the old
theatre geometry still presented the result as a cropped flat panel. The SBS
path now submits one `XrCompositionLayerProjection` containing two projection
views. Each view samples its matching half of the shared capture swapchain and
uses the runtime-located pose and asymmetric eye FOV, filling the headset view
instead of placing the image on a small head-locked quad.

This is genuine same-tick scene stereo, but it remains a feasibility view:
camera frusta are symmetric rather than runtime-derived, the flat UI is still
part of both cropped halves, and GDI capture limits source updates to 30 Hz.

The first headset check confirmed eye-selective routing, but each eye appeared
cropped because the original vertical FOV was reused after the viewport aspect
ratio was halved. The UI probe now preserves the original horizontal coverage
by scaling projection in tangent space:

```text
stereo_vertical_fov = 2 * atan(2 * tan(base_vertical_fov / 2))
```

This is a temporary symmetric-frustum correction for the SBS feasibility path;
the production path still needs the asymmetric per-eye frusta reported by the
OpenXR runtime.

For an unambiguous visual check, the feasibility mod also suppresses
`MainMenuView.draw` while leaving its update/input lifecycle intact. The
`/dtvr_ui_hide_on` and `/dtvr_ui_hide_off` commands toggle that foreground UI;
the 3D `ui_main_menu_world` continues rendering in stereo underneath it.

Run the exact guarded configuration with:

```powershell
tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 300
```

## Headset stereo validation and image cleanup

The first projection-layer run exposed a capture-coordinate error rather than
an engine stereo error. Windows reported the 3840-pixel desktop through a
125%-scaled, DPI-unaware coordinate space, moving the apparent SBS split from
output x=960 to x=1200. The capture thread now temporarily uses per-monitor-v2
DPI awareness while measuring and copying the Darktide client area. Exact
post-resize source-eye captures can be recorded with:

```powershell
build\windows-vs2022\tests\xr_harness\Release\darktidevr-eye-capture.exe `
  artifacts\phase1\eye-captures\manual-check
```

The OpenXR runtime also reports asymmetric per-eye FOVs, while this feasibility
probe currently renders symmetric game frusta. Submitting each symmetric image
with the runtime's asymmetric optical bounds displaced the two views relative
to one another. Until the game cameras accept runtime-derived asymmetric
frusta, the harness submits one centered FOV of equal total angular extent to
both projection views. Headset testing then confirmed a coherent, genuinely 3D
character-select view with convincing depth.

Darktide's default High profile enables several screen-space effects that are
unsuitable for this initial stereo baseline. In particular, the color-fringe
pass can produce visibly different chromatic aberration between the two
side-by-side viewport regions. Apply the reversible baseline before launch:

```powershell
tools\stereo\set-vr-render-settings.ps1 -Action Apply
```

The profile switches both launcher and in-game quality selectors to `custom`,
then disables color fringe, lens distortion, depth of field, motion blur,
bloom, display noise, sharpening, light shafts, and lens flares. It preserves
the exact pre-VR user configuration on first use. Inspect or restore it with:

```powershell
tools\stereo\set-vr-render-settings.ps1 -Action Inspect
tools\stereo\set-vr-render-settings.ps1 -Action Restore
```

The clean reference pair for this checkpoint is stored under
`artifacts/phase1/eye-captures/menu-64mm-postprocess-off`.

## Coincident-eye differential diagnosis

The feasibility mod exposes two diagnostic commands that preserve the normal
projection while changing only eye separation:

```text
/dtvr_ui_coincident_eyes_on
/dtvr_ui_coincident_eyes_off
```

`tools/stereo/compare-eye-captures.py` compares the exact 960x1080 capture
halves and writes raw/amplified difference images plus JSON metrics. Initial
coincident captures exposed two independent problems. First, the main-menu
level story can animate the primary camera after `UIWorldSpawner.update`, so
the duplicate camera remained at an earlier pose even though the update hook
copied it. The mod now synchronizes the final primary pose immediately before
`ScriptWorld.render`. Across three captures this reduced mean absolute error
from 6.36 to about 3.29 and improved PSNR from 25.2 dB to about 33.5 dB.

Second, a residual illumination difference remains even with identical final
camera poses. Reversing viewport render order did not reverse the difference,
so it follows the left/right back-buffer region rather than render order.
Disabling DLSS, GTAO, SSR, decals, and volumetrics reduced the changed-pixel
rate only from roughly 77.5% to 70.3% before the final-pose fix and did not
remove the lighting gap. Those over-broad diagnostic settings were therefore
reverted. The next renderer experiment should give each eye a full-origin
offscreen render target and compose the two targets afterward; this avoids the
deferred renderer's half-viewport coordinate assumptions.

## Validated checkpoint and output architecture

Headset validation confirms that final-pose synchronization produces correctly
aligned, convincing stereo. The remaining direct-SBS defects are localized to
rendering: lighting, decals, and small scene details can differ between the two
physical halves of the back buffer. The view is also visibly undersampled in
the headset.

An offscreen compositor diagnostic proved that the GUI composition pass can
draw into the final back buffer. However, two `R8G8B8A8` resources supplied as
`back_buffer` targets to the full deferred main-menu viewports remained black.
Changing those resources to `R16G16B16A16F` is not accepted by this renderer
path: `Renderer.create_resource` led to `E_INVALIDARG` in the D3D12 assertion
layer. The experiment has therefore been returned to its safe state:
offscreen mode is disabled by default and the known-good direct SBS path uses
`R8G8B8A8` only.

The production output contract is now:

- two independent eye surfaces at the OpenXR runtime's recommended resolution;
- the eye surfaces, rather than the desktop back buffer, are authoritative;
- a low-resolution desktop mirror copies one already-rendered eye by default;
- right-eye, side-by-side diagnostic, and disabled mirror modes remain options;
- changing or disabling the mirror never changes headset resolution.

## Evidence ledger: direct-SBS parity investigation

This ledger freezes the investigation before the primary/duplicate
viewport-role swap. It deliberately separates direct observations from
renderer-trace evidence and from hypotheses that still need causal tests.

### Directly observed in the desktop/headset output

- Once camera drift, the UI-camera coordinate mismatch, projection cropping,
  and final-pose synchronization were corrected, the character-select scene
  formed a coherent stereo image. Headset inspection described the depth as
  convincing and the view alignment as correct.
- Darktide's color-fringe post-process affected the two halves differently.
  Disabling color fringe and the other initial lens/screen effects removed
  that specific chromatic-aberration mismatch.
- With coincident cameras, residual differences remained. Repeated inspection
  found brighter or additional lighting on the physical right half and small
  scene details on the right that were absent from the left. Reported examples
  include floor cracks, a vent-like feature, overhead doodads, and lighting on
  background characters.
- The floor cracks were observed to appear incrementally over roughly half a
  second. Later direct inspection refined this: the cracks are present on the
  right from the first frame, while additional detail on them resolves over
  roughly half a second. The persistent eye difference therefore precedes the
  later refinement and cannot be explained solely by that refinement step.
- No confirmed example has yet been recorded of a detail that is present only
  on the left. The current human-observed pattern is therefore "right appears
  complete/richer; left is missing detail," not merely an arbitrary mismatch.
- The in-headset result is visibly undersampled. The intended output contract
  remains high-resolution eye-exclusive surfaces plus a cheap low-resolution
  desktop mirror, normally copied from one already-rendered eye.

### Controlled tests already completed

- Setting eye separation to zero and synchronizing the duplicate at the final
  pre-render boundary removed camera-pose drift as the main source of the
  residual image difference. Across three captures, mean absolute error fell
  from 6.36 to about 3.29 and PSNR improved from about 25.2 dB to 33.5 dB, but
  the lighting/detail mismatch remained.
- Reversing viewport render order did not reverse the richer-right/dimmer-left
  pattern. This proves the pattern does not simply follow which viewport is
  submitted first. It does **not** constitute a swap of the engine-owned
  primary viewport and the duplicate viewport.
- Broadly disabling DLSS, GTAO, SSR, decals, and volumetrics did not isolate the
  problem. Before final-pose synchronization, it reduced the changed-pixel
  rate only from about 77.5% to 70.3%. Those settings were restored because the
  experiment removed desired content without explaining the asymmetry.
- Rendering the world twice with one active viewport per submission returned
  successfully in a bounded test. There is no demonstrated top-level
  `ScriptWorld.render` assertion forbidding two submissions. The earlier
  `Bad Skinner!` assertion belongs to repeated deferred-skinning resource use,
  not to the Lua wrapper itself.
- Full-origin offscreen eye resources supplied to the deferred viewport were
  accepted as `R8G8B8A8` resources but rendered black. The attempted
  `R16G16B16A16F` variant reached a D3D12 `E_INVALIDARG` assertion. This did not
  test image parity because neither path produced two valid scene images.
- Mid-frame native copies raced asynchronous renderer transitions and produced
  a GPU hang. That path is permanently disabled. Present-boundary copies are
  stable and publish two named 1920x2160 shared D3D12 resources plus a fence.

### D3D12 trace evidence

- The two eye regions execute many of the same pipeline/root-signature
  families. In 37 conservatively paired records using the dominant root
  signature, root CBV slot 1 and descriptor tables 4 and 7 frequently differed,
  while the unbounded material/texture tables remained the same.
- Descriptor-table provenance resolved slot 4 for 5,556 main-view pass records.
  In the dominant signature, slot 4 contains exactly two vertex-shader SRVs.
  They are structured ranges with a 64-byte stride, commonly slicing a shared
  64 MiB buffer.
- Across 105 conservatively paired pass records, slot-4 resources matched in
  57 pairs and differed in 48; the described ranges matched in 36 and differed
  in 69. Total described element counts were larger on the left in 13 pairs,
  larger on the right in 12, and equal in 80. Slot-7 CBV handles matched in 82
  pairs and differed in 23.
- One capped provenance log contained 3,566 left-half and 3,894 right-half main
  pass records, with slot 4 resolved in 2,599 and 2,957 respectively. Because
  the file stopped at its 100,000-record cap, those totals are not a balanced
  whole-frame comparison and cannot establish that the right eye performs more
  work.
- The first slot-4 alias attempt never engaged because the two eye submissions
  used different command-list objects. A later frame-global/order-based alias
  did engage, but corrupted and flickered right-eye geometry, including the
  player character, while leaving the left untouched. It was disabled
  immediately. This proves that slot 4 participates in general geometry or
  instance processing; it does not prove slot 4 causes the missing cracks,
  vent, or lighting, and it proves that draw-order matching is unsafe.

Trace artifacts:

- `artifacts/phase1/pass-census/stereo-binding-roots.log`
- `artifacts/phase1/pass-census/stereo-root-signatures.log`
- `artifacts/phase1/pass-census/stereo-descriptor-provenance-v2.log`
- `artifacts/phase1/pass-census/stereo-table4-alias-unsafe.log`

### Established conclusions and remaining unknowns

The residual output difference follows the physical back-buffer half when
only render order is reversed, and it persists when the cameras are
coincident. The trace also establishes per-eye differences in structured
vertex data and some root bindings. It has **not** yet established that the
missing visible features are caused by culling, streaming, a particular
descriptor table, a later draw phase, or a specific deferred-renderer pass.
The cracks and vent also remain unclassified: either could be conventional
geometry, projected/decal geometry, or another detail representation.

The controlled role-swap test assigned the engine-owned primary viewport to the
physical right half and the duplicate viewport to the physical left half while
keeping both cameras coincident. The floor cracks and stronger lighting
remained on the physical right. Previously those same classes of differences
were on the right while the duplicate viewport occupied that half. Therefore,
the observed richer-right pattern survives swapping primary/duplicate viewport
identity and follows the physical output region in this direct-SBS path.

The exact capture and differential artifacts are under
`artifacts/phase1/eye-captures/coincident-primary-right-duplicate-left`. The
capture comparison reported 65.900% changed pixels, mean absolute error 4.5024,
maximum channel error 218, and PSNR 30.9925 dB. Those whole-frame metrics
quantify the difference but do not classify its individual causes. The normal
primary-left/duplicate-right mapping was restored immediately after the test.

### Focused draw A/B and first causal falsification

An observer-only trace then recorded the same stabilized character-select
scene with the primary viewport first on the left and then on the right in one
process. Draw identity included PSO, root signature, draw arguments, topology,
index buffer, and eight vertex-buffer bindings. The reproducible analyzer is
`tools/stereo/analyze-focused-ab-trace.py`; its report is under
`artifacts/phase1/pass-census/focused-primary-half-ab-analysis`.

For the two complete common frames in phase A, each physical half submitted
1,010 draw records. Coarse draw multisets shared 1,008 records with only two
unmatched per side (0.996 overlap). Exact geometry/IA multisets shared 1,000
with ten unmatched per side (0.980 overlap). Adding root constants did not
change that result. This is strong evidence against the residual detail being
caused by one eye broadly omitting draw calls.

For those same exact draw identities, adding the resolved table-4 signature
reduced overlap to 103 shared records with 907 unmatched per side (0.054
overlap). Table 7 differed less dramatically (about 0.611 overlap). The
remaining asymmetry is therefore concentrated in per-eye bound data,
especially structured table-4 ranges, or in a later stage consuming that data.
This does not by itself prove table 4 is the cause of the visible cracks,
vent, or lighting.

One exact trace delta was deliberately tested before making any broader data
substitution. A stable cached PSO fingerprint (`6427276088126068298`) issued a
six-index instanced draw with 18 instances on the physical left and 19--20 on
the physical right in the sampled A/B frames. A bounded native probe clamped
only that PSO's physical-right instance count to 18. The hook engaged 2,203
times during the character-select run, while the right-only floor cracks,
vent-like detail, and stronger lighting remained visible. This causally
falsifies that instance-count delta as the source of those features. The clamp
was disabled immediately after capture.

Artifacts for the falsification are under
`artifacts/phase1/eye-captures/candidate-instance-clamp-right-18`. SHA-256:

- `left-eye.bmp`: `6F4CCAC2FA5D50ECD3375277A023539B117C729A6A8BEDA4586E8A0DB4CF52E3`
- `right-eye.bmp`: `6E8E6836DD3259BB6C23BFD88188976B901FCADAF4B14891A84BBB5D39F7CED1`

The next causal test must keep exact draw/IA identity and operate on a single
resolved table-4 descriptor range, with explicit match and ambiguity counters.
The earlier order-based whole-table alias is not suitable because it changed
unrelated skinned geometry and did not establish exact draw correspondence.

An initial follow-up attempted to pair that same PSO using the previously
observed fixed 18-vs-19/20 instance-count pattern. The run recorded zero
matches, aliases, ambiguities, and clamps while the cracks remained. This is an
invalid intervention, not a table-4 falsification: the prerequisite count
pattern did not recur in that run. Its images are retained under
`artifacts/phase1/eye-captures/candidate-table4-alias-right-to-left`, but they
must not be interpreted as an alias-on result.

A revised occurrence-based pairing also recorded zero matches, aliases,
ambiguities, and clamps. Both table-4 attempts therefore failed to exercise an
intervention and provide no causal evidence. Further draw-data mutation was
stopped in favor of auditing the known construction differences between the
engine-owned primary camera/viewport and the mod-created duplicate.

The pre-test outcome rules were:

- richer content remains on the physical right: the asymmetry follows output
  region or half-viewport state;
- richer content moves to the physical left: it follows the primary/duplicate
  viewport identity;
- the pattern changes in another way: viewport identity and output region
  interact, requiring a four-configuration matrix rather than a single cause.

### Camera and viewport construction audit

The engine-owned primary and mod-created duplicate are not constructed by the
same Lua path:

- `UIWorldSpawner` creates and retains the primary camera unit, camera,
  viewport, and viewport metadata. The mod receives these as
  `spawner._camera_unit`, `spawner._camera`, and `spawner._viewport`.
- The duplicate is created later by calling `ScriptWorld.create_viewport`
  directly. Its camera-unit arguments are `nil`, so Stingray supplies the
  duplicate camera owned by that viewport. The mod then copies transform,
  vertical FOV, near range, and far range from the primary.
- Both use viewport type `default`, the same shading-environment name, and the
  same shading callback. The primary's observed layer is 1 and the duplicate's
  explicit layer is 2. Both render into the same desktop back buffer in the
  direct-SBS configuration.
- Their persistent output-state difference is the normalized viewport rect:
  the left half maps to D3D viewport/scissor origin x=0 and the right half to
  x=960, both 960x1080 internally.

The controlled rect swap is decisive when interpreting those differences.
The same primary camera/viewport that was on the left and missing detail gained
the richer output when moved to the physical right; the duplicate moved to the
left and lost it. Therefore camera-unit ownership, primary/duplicate creation
path, viewport layer, and creation order are not sufficient explanations for
the cracks or lighting mismatch. Any remaining camera-state hypothesis must be
state recomputed from the assigned rect. The proven discriminator is the
physical half/full-buffer origin, not camera identity.

That finding motivated rendering each unchanged camera through the same
full-origin viewport geometry into independent eye surfaces. The successful
pair tested the half-origin hypothesis and established the required production
architecture without mutating individual downstream draws.

That full-origin A/B was completed with coincident cameras and timestamped
captures. The primary capture at `14:46:43` followed the logged primary-phase
start at `14:46:29`; the duplicate capture at `14:48:13` followed the logged
duplicate-phase start at `14:47:46`. At the same full-buffer rect, both camera
instances showed the vent-like feature and the same intermediate amount of
foreground floor cracking: more than the normal physical-left half, but less
than the normal physical-right half. This rules out persistent camera creation
identity as the cause of that geometry/detail population. It also shows the
population is not a simple binary left-camera/right-camera choice.

A lighting difference remained visible between the two time-separated
full-origin captures. That observation is retained, but the test does not yet
attribute it to camera identity because the captures were about 90 seconds
apart and the menu scene contains animated lights, particles, and actors. The
lighting hypothesis requires a frozen camera and adjacent-frame camera A/B at
one unchanged rect. Geometry/detail is now tested separately with one frozen
primary camera across left-half, centered-half, right-half, and full-buffer
rects. The three half-width phases hold width and projection constant while
varying only normalized x origin; the full phase then tests width/aspect.

The frozen single-camera rectangle matrix completed on 2026-08-24 without a
Lua error or GPU failure. The durable camera pose was locked at present 665,
and the log recorded these phase boundaries:

- `15:06:07`: left half, `x=0.00`, `width=0.50`;
- `15:06:51`: centered half, `x=0.25`, `width=0.50`;
- `15:07:32`: right half, `x=0.50`, `width=0.50`;
- `15:08:13`: full buffer, `x=0.00`, `width=1.00`;
- `15:08:57`: side-by-side viewports restored.

The observed detail tiers were respectively: no foreground cracks and no
vent; partial cracks with the vent; full cracks with the vent; and partial
cracks with the vent. Timestamped captures are under
`artifacts/phase1/eye-captures/frozen-rect-matrix`. Because the centered-half
and full-buffer rectangles have different origins and widths but the same
horizontal center (`0.50`) and the same detail tier, the tighter discriminator
is the rectangle's absolute horizontal center, not origin or width
independently. The normal SBS centers (`0.25` and `0.75`) reproduce the normal
missing-left/rich-right endpoints. This causally rules out camera creation
identity, viewport layer, elapsed texture streaming, and scripted camera
motion for these geometry/detail differences. It points to renderer state
derived from the absolute screen center, such as visibility/culling,
streaming/LOD selection, or a screen-space pass.

Visual switching between the normal left and right outputs further grouped the
floor cracks and vent with what appears to be an ambient-occlusion difference:
the AO-like contribution is present on the crack-rich side and absent on the
no-crack side. This is an observation rather than a pass-level identification,
but it strengthens the deferred/screen-space-pass hypothesis over independent
late texture or mesh streaming.

The next bounded implementation test keeps both logical eye rectangles near
the known-rich right-half center so Stingray builds equivalent detail state,
then remaps their D3D12 viewport/scissor output to distinct physical halves.
Using slightly different logical X values provides a native eye tag without
changing the effective detail tier. This directly tests the intended fix
architecture before attempting more draw-level mutations.

That first remap implementation was invalid and is now disabled. It rewrote
matching `RSSetViewports` calls globally and translated only matching
half-width scissors. In the live result, the physical left half showed an
enormous close-up of the player mesh against a solid blue background while the
physical right half retained the normal scene. The game did not report a
D3D12 assertion or PSO failure, but the output proves that moving raster
viewports and selected scissors after Stingray has constructed the passes does
not preserve the deferred render-target and composition topology. This result
does not identify one offending pass, so it is evidence against the naive
global remap rather than evidence for a specific replacement.

Further renderer work must therefore be observational first: correlate
viewport/scissor changes with render-target bindings, PSOs, draws, and compute
dispatches across the frozen left/center/right/full matrix. A production fix
will likely need two coherent per-eye deferred target bundles, followed by a
separate composition step, rather than relocating selected raster state inside
the existing shared deferred graph.

A subsequent alternating-full-origin diagnostic rendered only one full-width
eye per game frame. It is not an acceptable production stereo mode, but it
provided a useful causal control: the user observed the same vent, partial
floor cracks, and AO in both alternating camera views. This confirms that both
camera instances can independently produce the richer population when their
logical viewport has full-origin coordinates.

A same-frame top/bottom test then gave both eyes the same horizontal origin and
center while placing them in separate vertical halves. With normal eye
separation it appeared stable and plausibly stereo in-headset. A coincident
camera capture at 3840x1080 per region is retained under
`artifacts/phase1/eye-captures/top-bottom-coincident-20260824`. Geometry and
detail visually align, including the previously missing population, but the
pixel diff exposes a broad screen-space shading mismatch:

- 48.8809% of pixels differ by more than 2/255 in at least one channel;
- mean absolute error is 3.0775/255 and PSNR is 33.3053 dB;
- per-channel affine normalization changes the mismatch only to 48.1401%;
- normalized edge correlation is 0.9642.

The top/bottom result therefore shows that a shared target can carry two
same-frame views, but merely moving the views to another pair of physical
regions trades the horizontal detail asymmetry for a vertical screen-space
shading asymmetry. It is retained as a diagnostic and not as the target
architecture.

A follow-up top/bottom run used a physically tall source so each stacked eye
could retain an approximately square 2160x2160 region. In that run the user
observed the floor cracks in the top region and no floor cracks in the bottom
region. The asymmetry therefore reproduces on the vertical axis as well as the
horizontal axis. Together with the frozen horizontal rectangle matrix, this
rules out a durable left-camera/right-camera property and strongly localizes
the fault to two views sharing subdivisions of one renderer output graph.

Shared SBS and top/bottom layouts are now shelved as production candidates.
They remain useful controls, but the implementation target is two complete,
independent per-eye render paths, each with full-origin viewport coordinates
and its own coherent deferred attachments, followed by OpenXR submission and a
cheap one-eye desktop mirror.

The harness's current 3840x2160 capture path gives each eye 1920x2160 and has
passed the full automated suite, but it still captures the desktop back buffer.
It cannot realize the contract above on its own. The next native renderer
boundary must expose the two game eye textures directly (preferably as shared
D3D12 resources), after which the bridge can open them, copy them into separate
OpenXR swapchains, and derive the cheap mono desktop mirror from the same left
eye texture.

## Double-render and native shared-eye findings

`ScriptWorld.render` is not guarded against rendering one world twice. Its own
implementation iterates the active viewport queue and calls
`Application.render_world` once per viewport. A bounded probe also invoked the
wrapper twice in one frame with one viewport active per invocation: both calls
returned successfully and the game remained stable. There is therefore no
Stingray assertion to bypass for the second world submission.

Attaching `R8G8B8A8` eye targets through the creation-time `render_targets`
argument is accepted and remains stable, but the main deferred viewport still
renders those targets black. This confirms that the unsupported part is the
deferred target layout, not world submission count.

That initial test passed `{ back_buffer = resource }`. A later native trace of
an offscreen duplicate while the primary remained a normal visible control
showed why it failed. Across four settled frames, the custom 1920x2160 texture
was bound only for three late draws per frame: one fullscreen triangle and two
297-index draws, all without a depth attachment. The thousands of world and
deferred draws continued to bind the engine-owned 1920x1080 attachment set.
The table form therefore redirects a late composite destination; it does not
instantiate an independent deferred eye path.

The shipping Lua source supplies a concrete correction. Its
`CrypticCharacterCreateVoiceScreen` creates an engine render-target resource
and passes that resource directly as the final argument to
`ScriptWorld.create_viewport`; `ScriptWorld` forwards the value unchanged to
`Application.create_viewport`. The next bounded test uses that exact resource
form for only the duplicate eye, retains the primary viewport as a normal
full-origin control, and repeats the attachment census. The trace from the
table-form control is retained at
`artifacts/phase1/pass-census/offscreen-duplicate-20260824`.

The direct-resource correction was then tested against a normal primary
control. For the deferred `default_with_alpha` viewport, no 1920x2160 RTV was
bound at all; the resource form is specific to the shipped `overlay` example
and is ignored by this deferred template. That trace is retained at
`artifacts/phase1/pass-census/offscreen-direct-resource-20260824`.

The exact current renderer contract has since been extracted read-only from
the installed `render_config` bundle and decoded to typed SJSON. The
`default_with_alpha` template declares `output_rt = "output_target"` and
`output_dst = "depth_stencil_buffer"`; its layer config then consumes the
global G-buffers, HDR targets, AO, decals, lighting, and post-processing graph.
The next probe therefore binds the custom eye texture to the template's actual
`output_target` slot instead of guessing `back_buffer` or using the
overlay-only bare-resource form.

An attempted copy immediately after each Lua render exposed two separate
hazards. The first C++ exception was our producer mutex being re-entered by its
own `ExecuteCommandLists` hook. Narrowing the lock allowed submission, but the
copy still raced the renderer's asynchronous state transitions and produced a
GPU hang. That path is disabled and its console command now refuses to arm it.

The safe native boundary is `IDXGISwapChain::Present`: all game work is already
queued and the current image is in `PRESENT`. The producer now submits one copy
list there, retains its command allocator/list until the shared fence completes,
and splits the 3840x2160 SBS image into named 1920x2160 resources:

- `Local\\DarktideVR-eye-left`
- `Local\\DarktideVR-eye-right`
- `Local\\DarktideVR-eye-ready`
- `Local\\DarktideVR-eye-consumed`

The feature is dormant by default and can be toggled with
`/dtvr_present_capture_on` and `/dtvr_present_capture_off`. A live receiver on
the OpenXR adapter opened both resources at 1920x2160 while Darktide was running;
the producer fence advanced from 6819 to 6839 in 250 ms. The next bridge step is
to use a multi-buffered eye set (or consumer acknowledgement fence) so OpenXR
can copy a stable published pair without racing the producer's next frame.

## Same-frame intermediate-target stereo breakthrough

Back-buffer capture cannot distinguish the two sequential camera renders.
This is now proven rather than inferred:

- A 200 mm identity-control run set the two camera transforms apart, but the
  two Lua-boundary back-buffer copies were byte-for-byte identical (MAE and
  RMSE both zero).
- Consuming eye tags at the next direct-queue submission changed only 0.0200%
  of pixels above 2/255. The difference was confined to animated content and
  was not stereo.
- A PRESENT-boundary queue accepted one eye tag per display frame while Lua
  produced two. The queue overflowed with code 61, and headset inspection
  confirmed the resulting alternating-frame pair was not stereo. These were
  probe warnings, not engine or D3D12 errors.

A read-only legacy `ResourceBarrier` census then identified the actual split.
For every complete settled frame sampled, exactly two worker command lists
transitioned the same 3840x2160 `DXGI_FORMAT_R8G8B8A8_UNORM` resource from the
combined shader-resource state (`192`) back to `RENDER_TARGET` (`4`). The two
events correspond to the two one-viewport `ScriptWorld.render` submissions.
Only after both events does the main thread transition the final result toward
PRESENT. Frames 1261 through 1289 each contained exactly two such transitions.

The producer now arms eye 0 before the primary render and eye 1 before the
duplicate render. After each identified worker command list is submitted, it
copies the still-complete RGBA8 intermediate target into the matching named
shared eye surface, temporarily transitioning only that source from
`RENDER_TARGET` to `COPY_SOURCE` and back. The second camera can no longer
overwrite the first camera before publication.

The 200 mm control pair under
`artifacts/phase1/stereo-identity-intermediate-rgba8-20260824` provides strong
image evidence:

- 70.1721% of pixels differ by more than 2/255;
- mean absolute error is 8.5750/255;
- the near-character translation estimate is horizontal only
  (`x=-21`, `y=0`), with correlation 0.8558;
- the red/cyan overlay shows depth-dependent separation throughout the scene.

After restoring the real 64 mm IPD, the proof pair under
`artifacts/phase1/stereo-proof-intermediate-ipd064-20260824` retained coherent
parallax:

- 56.6717% of pixels differ by more than 2/255;
- mean absolute error is 6.1909/255;
- the near-character estimate is `x=-5`, `y=0`, correlation 0.9786;
- the distant and near estimates differ, as expected for true scene depth.

The Quest compositor screenshot `quest-vd-status.png` in that artifact folder
also shows the two distinct eye images routed to separate compositor eyes.
After restarting Virtual Desktop Streamer and Darktide, the continuous VDXR
session ran at approximately 110 compositor FPS. Headset validation reported
flawless stereo with no frame-rate or per-eye stutter. Only very minor edge
differences remained, consistent with expected temporal-AA sampling between
offset cameras; they are non-blocking for this checkpoint. The live compositor
capture is `quest-live-check.png` in the same artifact folder.

This implementation is still a build-scoped probe. Candidate dimensions now
follow the selected swapchain, while renderer pass identity remains tied to the
observed pair of worker transitions. Shared surfaces are single-buffered. A
consumer acknowledgement fence prevents overwrite races: after waiting on
`eye-ready`, the XR queue signals the same value on `eye-consumed` only after
both copies have been ordered. If that acknowledgement is late, the producer
drops the next complete pair and keeps the last stable publication; it never
blocks Darktide's render queue. A ring remains a possible later optimization if
measured drop rates justify it.

An initial headset test beyond character select established a world-transition
boundary: the private lobby rendered normally on the desktop with EAC disabled,
but did not appear in XR. This historical failure motivated the gameplay-camera
and flat-fallback work below.

The subsequent implementation now arms the `CameraManager`/`player1` path by
default. Once a gameplay world appears, it creates the second viewport and uses
the same two full-origin `ScriptWorld.render` submissions and native eye tags as
the proven UI-world path. Subsequent Quest 3 validation successfully traversed
the flat loading fallback and entered the private lobby in stereo.

The XR bridge also runs a low-rate flat-window capture alongside shared-eye
consumption. If the ready sequence does not advance for 500 ms, it duplicates
the current 1920x2160 flat frame into the two stacked eye regions; a new shared
sequence switches back to stereo automatically. The producer remains
non-blocking throughout loading and transition gaps.

## Completed-pass eye-sized checkpoint

The final boundary investigation separated two superficially similar resource
events. At pass start, the full-size RGBA8 ping-pong resource transitions from
shader resource (`192`) to render target (`4`). Captures there contained partial
compositor state and an exact 1280x768 clear rectangle. At pass completion, the
known resource transitions from render target (`4`) back to shader resource
(`192`). There are exactly two such completed matches per settled game frame,
with queued eye identities 0 then 1. The producer now learns candidates at the
first transition and captures only the latter transition.

The first clean completed-pass pair still had effectively zero disparity. Code
inspection then found that `apply_ui_eye_offsets` force-updated the primary
camera at the center pose, moved its unit to the left-eye pose, and rendered it
without refreshing the camera cache. The duplicate right camera was refreshed.
Adding `ScriptCamera.force_update` after moving the primary camera resolved the
fault. The resulting pair in
`artifacts/phase1/logical-eye-pair-primary-refresh-20260824` has 25.3178% changed
pixels and zero vertical phase shift. Horizontal phase shifts vary with scene
depth: 9 pixels at the ceiling, 15 pixels in the rear-left region, and 20 pixels
on the character. This is direct evidence of two distinct same-frame camera
views, not a temporal pair.

The logical render extent is now 1920x2160 independently of the 1280x768
physical desktop client. In a live Quest 3/VirtualDesktopXR stability sample,
the shared-eye projection submitted 6,000/6,000 frames in 50.44 seconds with no
unrendered frames, capture failures, or stale-capture frames. It averaged
118.95 compositor submissions/s and 51.05 fresh complete stereo pairs/s. Two
startup pose mismatches did not increase during the run. Boundary census output
is disabled by default after this diagnosis; set the process environment value
`DARKTIDEVR_BOUNDARY_CENSUS=1` only for a bounded renderer investigation.

A census-off deployment smoke test then submitted 1,200/1,200 frames at 118.0
submissions/s and 50.64 fresh stereo pairs/s. The corresponding live eye dump
is `artifacts/phase1/logical-eye-pair-clean-census-off-20260824`. Its two
1920x2160 images differ in 26.4395% of pixels; registration found a 19-pixel
horizontal offset in the distant upper scene and a 32-pixel offset on the near
character. This revalidates depth-dependent stereo on the deployed clean build.

Validation commands run on the Windows PC:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build --preset windows-vs2022-release --target darktidevr_native_capture
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' `
  --test-dir build/windows-vs2022 -C Release --output-on-failure `
  -R 'native_capture|shared_eye'
build\windows-vs2022\tests\shared_eye_surfaces\Release\darktidevr-shared-eye-surfaces-tests.exe `
  --live-dump artifacts\phase1\stereo-proof-intermediate-ipd064-20260824
python tools\renderer_probe\diff-eye-captures.py `
  artifacts\phase1\stereo-proof-intermediate-ipd064-20260824\left.ppm `
  artifacts\phase1\stereo-proof-intermediate-ipd064-20260824\right.ppm `
  artifacts\phase1\stereo-proof-intermediate-ipd064-20260824
build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe `
  --frames 30 --debug-layer --require-rendering --xr-frames 6000 `
  --shared-eyes --capture-window-title 'Warhammer 40,000: Darktide'
```

The focused native tests passed 2/2. No Mac-only validation applies to this
Windows/D3D12 renderer work.

## Real client-area resize and final live checkpoint (2026-08-24)

### Resize-path finding

The synthetic `WM_SIZE` startup nudge was not equivalent to a real resize. It
caused the active Darktide configuration to become 1279x768 even though the
requested and detected configuration remained 1920x2160. Both headset eyes
initially showed the same incomplete scene: only an upper portion rendered and
the lower region was black. Resizing the window by any amount corrected both
eyes simultaneously.

A second artifact was viewport-dependent. Roughly one second after a resize, a
mostly transparent lighting-like layer appeared instantly. It disappeared on
each resize and returned when the physical client remained far from the logical
1920x2160 size; it stayed absent when the client was close to that size. These
observations point to inconsistent viewport-dependent resources, not gradual
temporal-history convergence.

The deployed producer now calls `SetWindowPos` to establish a real client-area
extent after `Present`; it no longer posts the fake one-pixel `WM_SIZE`. This
makes Stingray rebuild the dependent viewport resources through its normal
window path. Visual validation found the startup render, lighting, decals,
ambient occlusion, and overall appearance correct in both eyes.

### Extent layers

The accepted working state has three distinct resolution layers:

| Layer | Measured extent | Evidence |
| --- | ---: | --- |
| Windows physical client | 1920x2135 | `GetClientRect`, scaled by 120-DPI/96 |
| Darktide active setting | 1920x2135 | active `screen_resolution` block |
| Shared left eye | 1920x2160 | receiver rejects any other resource description |
| Shared right eye | 1920x2160 | receiver rejects any other resource description |
| XR top/bottom atlas | 1920x4320 | harness swapchain construction |
| Submitted XR subimage | 1920x2160 per eye | projection-view image rectangles |
| VDXR recommended eye size | 2688x2880 | runtime view configuration |

The 25-pixel client-height difference is caused by the decorated window being
clamped to a 2160-pixel monitor. It did not crop the shared eye resources or
reintroduce the viewport artifacts. Because the result is visually correct,
this state is the baseline. Do not force exact numerical equality without a
separate A/B test. The local, undeployed experiment to put the non-client frame
above the monitor was reverted.

### Long XR run

Command used on the Windows PC:

```powershell
build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe `
  --frames 30 --debug-layer --require-rendering --xr-frames 36000 `
  --shared-eyes --capture-window-title 'Warhammer 40,000: Darktide'
```

Observed result:

```text
openxr.frames=36000
openxr.submitted_frames=36000
openxr.not_rendered_frames=0
openxr.elapsed_ms=301857
openxr.presentation=shared-eye-projection
openxr.theatre_capture_failures=0
openxr.theatre_stale_frames=0
openxr.flat_fallback_frames=3
openxr.flat_fallback_transitions=2
openxr.fresh_shared_pairs=14899
openxr.reused_shared_frames=21098
openxr.pair_pose_mismatches=2
result=pass
```

This is approximately 119.25 compositor submissions/s and 49.36 fresh stereo
pairs/s. Headset motion looked substantially smoother than in earlier runs.

### Unresolved left-eye motion flicker

When looking around, the user observed intermittent left-eye flicker resembling
a positional change; the right eye remained smooth. Current evidence narrows
but does not yet identify the cause:

- only two explicit left/right pose-sequence mismatches occurred in 14,899
  fresh pairs, and those mismatched pairs were discarded;
- the shared resources are single-slot but protected by a consumed fence;
  Darktide drops the next whole pair instead of overwriting either eye while
  XR's GPU is still reading the previous pair;
- both eyes of an accepted pair carry the same render-pose sequence;
- most compositor submissions reuse the last accepted pair, while a fresh pair
  replaces it about 49 times per second.

Therefore neither mismatched sequence tags nor an unfenced new-left/old-right
read is supported by the implementation or counters. This checkpoint is
historical: the later motion follow-up below added per-pair sequence/angular-lag
instrumentation and pair-driven submission. The residual asymmetric flicker is
still open and must be headset-validated against those counters.

### Wrap-up validation

The undeployed exact-height experiment was reverted, then the local native DLL
was rebuilt from the accepted source. The focused tests passed 3/3:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build build/windows-vs2022 --config Release `
  --target darktidevr_native_capture
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' `
  --test-dir build/windows-vs2022 -C Release `
  -R 'native_capture_hooks|shared_eye_surfaces|core_math' `
  --output-on-failure
```

Result: `core_math`, `native_capture_hooks`, and `shared_eye_surfaces` all
passed. No Mac-only validation applies. Darktide was closed, no crash-report
windows remained, and normal Quest proximity behavior was restored before
ending the session.

## 2026-08-25 motion-flicker and render-reuse follow-up

The reported motion artifact is directional and velocity-dependent: while
turning left, the apparent displaced image lies farther left as turn speed
increases. A similar but rare large displacement can be induced in the other
eye with very rapid motion. This signature prompted an audit of the render FOV
used by the compositor rather than another eye-order experiment.

The audit found that the two FOV values differ, but the first interpretation
was falsified in-headset. Submitting `Camera.vertical_fov` as literal OpenXR
angular coverage produced a narrow central window of roughly 38 by 42.5
degrees. The accepted runtime-centered wide submission was restored. The
shared pose packet remains version 2 and carries the reported camera FOV/aspect
as diagnostic metadata, not compositor projection truth.

Fresh-pair instrumentation now accumulates:

- rendered-to-current pose sequence lag, average and maximum;
- rendered-to-current angular lag in degrees, average and maximum;
- existing fresh/reused pair and tag-mismatch counters.

These metrics are now the evidence base for the next headset comparison; the
FOV experiment itself did not remove the visible flicker.

The 18,000-frame live run completed without capture or stale-frame failures.
Fresh pairs lagged the current compositor pose by 2.61 sequence samples on
average, with 0.42 degrees average angular separation. The corrected subjective
signature is opposite-direction flashing during head turns, in both eyes but
far more often in the left. A controlled `-2` pose-sequence association was
added for bounded A/B testing; it does not alter camera transforms or captures.

VDXR's overlay also exposed a cadence error in the bridge. Reusing a 51--58 Hz
game pair while calling `xrEndFrame` at 119 Hz makes VDXR count the bridge as a
full-rate application. Shared-eye mode now begins the next OpenXR frame by
default when the ready fence advances. After the producer has been stale for
500 ms, a 33 ms timeout keeps flat loading/failure fallback responsive.
`--continuous-shared` retains the old cadence as a diagnostic control. During the valid
live interval it submitted 72--76 fresh pairs/s with almost no reuse, while the
headset compositor remained responsible for display-rate reprojection. The game
then exited; the observed fallback decay toward 30 Hz was the intentional
timeout path, not a producer stall.

The same investigation established a performance direction. Two complete
renders are a correctness baseline rather than the intended architecture.
Trace overlap is extremely high before per-view resource binding: 1,008/1,010
coarse draws and 1,000/1,010 exact geometry/IA draws match between eyes. Scene
and geometry work should be shared, while the per-eye deferred resources must
remain isolated because sharing their physical output graph previously caused
the missing decals/detail/AO and lighting failures.

Stingray's documented instanced-stereo renderer is the first candidate in
principle. Static inspection found its public Lua/settings names absent from
the Darktide executable and current decompiled scripts, suggesting the feature
was compiled out of Fatshark's fork. A live read-only namespace census confirmed
`SteamVR`, `SteamVRSystem`, and `OpenVR` are absent. The next bounded work is to timestamp and classify the two
command streams, identify common skinning/visibility/LOD work, and prototype
sharing only a proven common pass. D3D12 view instancing is potentially useful
for geometry, but it requires shader/PSO support for per-view transforms and
cannot safely be enabled as a presentation-only hook.

The local RTX 4090 was queried through
`D3D12_FEATURE_D3D12_OPTIONS3` and reports view-instancing tier 3. Hardware is
therefore not the blocker. A safe prototype still requires a shader/PSO path
that consumes `SV_ViewID` (or equivalent per-instance eye data) and writes into
two coherent target slices; the tier cannot retrofit that behavior onto an
already closed mono command list.

Validation commands run from the repository root:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build --preset windows-vs2022-release
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' `
  --test-dir build/windows-vs2022 -C Release --output-on-failure
```

Result: all 18 non-headset tests passed. `xr_projection_smoke`,
`xr_theatre_smoke`, and `xr_stereo_sbs_smoke` reached VirtualDesktopXR but
failed their required-session gate because the HMD was unavailable. The DLL
and Lua deployed to the game mod directory match the Release/source SHA-256
hashes. No Mac-only validation applies.

## 2026-08-25 pair-driven/FOV acceptance and band investigation

Headset validation accepted the pair-driven presentation path: the prior
left-dominant motion flicker is gone, the corrected runtime-derived symmetric
projection has the expected scale and FOV, and throughput improved. The
remaining smoke tilt is consistent with camera-facing particle billboards and
is deferred.

The next visible defect is a set of horizontal camera-relative distortion
lines. They also appear, more subtly, in the desktop eye mirror and in dumps of
the raw named eye surfaces. This places the defect before the bridge's OpenXR
copy/submission boundary.

Disabling Darktide render jitter while retaining the otherwise working DLSS
path did not change the lines and made the image blurrier. During that test the
bridge sustained roughly 85--89 submissions and fresh pairs per second, reused
zero frames, and held pair-pose mismatches at the two startup samples. The
setting was restored.

A no-DLSS run was then instrumented with the existing bounded barrier census.
It proved that native rendering still uses 1920x2160 resources, but changes the
capture graph: completed full-size scene buffers are format 26
(`R11G11B10_FLOAT`), and the format-28 swapchain is the direct final target.
The current eye selector requires a format-28 intermediate transitioning from
render target to shader resource. Consequently it learned zero outputs and
never created the named handles. This is a limitation of the selected capture
boundary, not evidence that Darktide or stereo rendering inherently requires
DLSS. The 10,000-line trace and summary are retained at
`artifacts/phase1/no-dlss-boundary-census-20260825`.

Focused validation for the temporary census build and the restored clean build:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build --preset windows-vs2022-release --target darktidevr_native_capture
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' `
  --test-dir build/windows-vs2022 -C Release --output-on-failure `
  -R 'native_capture|shared_eye'
```

Both focused tests passed for both builds. The temporary unconditional census
change was reverted. The restored source and deployed DLL hashes both equal
`7343A4D9F6FFA23BCB3521C543B1914FDE98F20B633817AD036253B0950D3082`.

## Known-good control before resolution/upscaler A/B (2026-08-25)

The horizontal-band investigation was rolled back to the accepted engine
intermediate path. The control uses hardcoded 1920x2160 eye surfaces with DLSS
Ultra Performance enabled. Offscreen diagnostic targets, camera freeze,
focused pass tracing, the native observer, and unconditional resource census
are disabled. Headset validation found the image correct apart from the known
fixed horizontal bands. Pair-driven throughput was approximately 112--113
fresh stereo pairs/s with zero reused frames and two startup pose mismatches.

The exact Lua, native source/DLL, XR harness, graphics configuration, hashes,
and validation record are preserved under
`artifacts/phase1/known-good-1920x2160-dlss-20260825`.

## Medium-derived extent and native-upscaler A/B (2026-08-25)

VirtualDesktopXR Medium reported 2112x2304 per eye. Rendering that extent
directly made Darktide's decorated client clamp to 2112x2135. The resulting
169-row logical/client divergence reproduced the earlier viewport failure:
lighting/post-processing was misregistered, the lower render boundary became
visible, and head pitch exposed projection-like distortion. Changing only the
detected/default configuration entries did not fix it and was reverted.

Uniformly scaling the recommendation to a 2160-line engine extent and rounding
width to 16 pixels produced 1984x2160. Headset validation accepted this state:
the viewport was complete, lighting/post-processing aligned, head movement had
the expected projection, and throughput reached roughly 113--116 fresh pairs/s
with DLSS Ultra Performance. The exact control is preserved under
`artifacts/phase1/known-good-1984x2160-dlss-medium-derived-20260825`.

A proper native-rendering A/B then disabled both DLSS selectors, the DLSS
feature flag, upscaling, and render jitter. Native rendering bypasses the
format-28 DLSS intermediate, so the guarded direct-swapchain capture copied the
finished tonemapped back buffer after each isolated eye submission. Native
stereo was correct, proving that the renderer does not require DLSS. The fixed
horizontal bands remained, excluding DLSS and its intermediate as their cause.
Aliasing increased and pair throughput fell to roughly 66--80 Hz. Head motion
looked substantially more stuttery in the 120 Hz headset than in the desktop
eye mirror, consistent with application cadence below compositor refresh rather
than a capture-tag failure: reuse remained zero and pose mismatches remained at
the two startup samples. The accepted DLSS configuration and intermediate
capture path were restored afterward.

The viewport result establishes an architectural requirement rather than a
reason to cap final support at 2160 rows. Runtime-sized eye resources, including
the Godlike 2688x2880 class, must be detached from the physical Windows client
and the DXGI presentation swapchain. Darktide should eventually initialize XR
before scene rendering, render into two headset-only eye targets, and expose an
optional low-cost one-eye desktop mirror whose size and presence cannot alter
the headset render graph.

## Client-lock removal experiment (2026-08-25)

A D3D12 allocation census during the accepted 1984x2160 control found that
all large viewport-dependent textures were committed resources. The completed
DLSS replacement output and the principal deferred-resource family were
1984x2160 even though the decorated window did not physically occupy that
many screen pixels.

Disabling the persistent client-size lock without another resize left the
renderer at its launcher extent of 1280x768. A follow-up used a genuine
one-pixel client resize followed by restoration while the DXGI ResizeBuffers
hook retained 1984x2160. DXGI switched to 1984x2160 on frame 3 and the later
1984x2160 resource family was created, but the original 1280x768 family stayed
live. Headset validation showed an extremely low-resolution base scene with a
strongly offset full-resolution lighting/post-process layer. The desktop
window showed the same split directly: a small scene in the upper-left under
a later full-viewport layer.

This falsifies swapchain-only decoupling. Stingray's early deferred resources
derive their extent independently from the physical client, while later
resources inherit the forced DXGI/output extent. The next bounded path is to
virtualize the game-side client-size query at the time of the genuine rebuild,
while leaving the OS window and DXGI presentation behavior untouched. The
deployed game files were restored byte-for-byte from the accepted
`known-good-1984x2160-dlss-medium-derived-20260825` checkpoint after the test.

## Runtime-asymmetric FOV without an asymmetric engine projection

The exact 2112x2304 WM_SIZE-virtualized render graph established that remaining
lighting failures were projection-state failures rather than resource-size
failures. Two bounded projection tests localized the mismatch:

1. Direct `Camera.set_frustum_half_angles` changed geometry and destabilized
   deferred/screen-space lighting.
2. A symmetric camera plus `Camera.set_post_projection_transform` produced
   correct geometry, stereo and headset coverage, but lighting remained aligned
   to the symmetric base projection.

The working representation uses the fact that an OpenXR projection view is a
matched pose/FOV pair. For each runtime eye, the implementation takes the
horizontal and vertical angular centers, rotates a conventional symmetric
camera toward that optical center, and derives a symmetric horizontal FOV from
the engine's vertical FOV and the exact 2112/2304 render aspect. The bridge
applies the same local rotation to the submitted eye pose and supplies the same
symmetric FOV. Stingray therefore uses one coherent projection throughout its
deferred stack while VirtualDesktopXR receives metadata that exactly describes
the rendered rays.

The user accepted the live character-select result with lighting, geometry,
stereo depth, FOV and tracking all correct. Runtime telemetry settled near 115
fresh pairs/s, zero reuse and two unchanged startup pose mismatches. Focused
`core_math`, `native_capture_hooks`, `shared_eye_surfaces` and
`shared_head_pose` tests all passed. The source and binaries are preserved in
`artifacts/phase1/known-good-medium-recentered-symmetric-20260825`.

## Additive room-scale camera translation

The first 6DoF implementation deliberately stops at the camera boundary. The
XR harness publishes a recenter-local head pose clamped to a 0.25 m horizontal
radius and +/-0.18 m vertical travel. Lua maps that translation into Stingray's
axes and adds it in the untracked game-camera basis before applying symmetric
IPD offsets. No character or controller transform is written.

The compositor pose must move with the rendered cameras. The former
`orientation_only_delta` submission was therefore replaced by
`anchored_recentered_eye_pose`: it retains the runtime eye-from-head transform,
composes the full clamped delta onto the XR recenter anchor, then applies the
already accepted per-eye optical-center rotation at submission. This makes the
game-camera and projection-layer translations two consumers of one pose sample
instead of independently timed estimates.

The gameplay camera hook was also brought onto the accepted recentered
symmetric projection path. It had retained a stale call to the removed direct-
frustum experiment; the corrected path now applies per-eye optical rotations
without reintroducing the lighting failure.

Validation commands:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build --preset windows-vs2022-release --target `
  darktidevr_native_capture darktidevr-xr-harness `
  darktidevr-shared-head-pose-tests darktidevr-core-math-tests
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' `
  --test-dir build/windows-vs2022 -C Release --output-on-failure `
  -R 'shared_head_pose|native_capture_hooks|shared_eye_surfaces|core_math'
.\tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 300
```

All four focused tests passed. The deployed DLL and Lua matched their sources
at SHA-256
`8FDDEE7153ACE7B915D6D19B0805C25DEAFDE8680DE8B35943022EE53E0504B0` and
`C65E5B2060A513513832FDFD8EE51CB28F093E785160638398ABC22C0BB936B3`.
The live run completed 20,406/20,406 submissions, 19,994 fresh shared pairs,
zero reused/stale frames, two startup pose mismatches and a passing result.
Physical leaning in all six directions at character select was reported
flawless with no distortion. The follow-up lobby test also allowed normal
locomotion and looking around without tracking or movement problems, closing
the initial camera/controller-independence gate.

The lobby transition itself exposed a broken loading presentation. The stale-
pair path copied the desktop capture but still selected the stereo projection
layer because layer selection depended only on the global stereo mode. On the
accepted separate-eye-swapchain path, the copy loop additionally used
`height / 2` even though the window capture and each eye texture were full
height, repeating only half the image.

The corrected path records fallback selection per frame, copies the full
captured height, and submits a dedicated `XrCompositionLayerQuad` only for that
frame. It is visible to both eyes and positioned two metres forward. The first
live transition used a one-metre-wide, aspect-preserving image and accepted its
image and size but found VIEW-space parenting uncomfortable. The follow-up snapshots the
head pose on fallback entry, composes the two-metre forward offset once, and
submits the quad in LOCAL space until stereo resumes. The next requested size
revision makes the panel 2 m by 2 m while retaining that room anchor and
distance. Fresh tagged pairs
immediately return to the recentered stereo projection. Seven focused tests passed:
`core_math`, `native_capture_hooks`, `shared_eye_surfaces`, `shared_head_pose`,
`presentation_policy`, `window_capture_recovery`, and `xr_harness_help`. Live
loading-transition validation is still required.

The active user settings were also compared field-by-field with the reversible
VR profile after the lobby run. Three expensive-looking flags had drifted on:
`ao_enabled`, `gtao_enabled`, and `baked_ddgi`. A launch-order check established
that menu-level `ambient_occlusion_quality = "low"` regenerates both AO flags;
setting it to `"off"` keeps them false after relaunch. Darktide still regenerates
`baked_ddgi = true` with `gi_quality = "off"`, so this is recorded as an
apparently required baked-lighting baseline rather than repeatedly overriding
an unsupported derived flag. The profile also preserves
`upscaling_quality = "ultra_performance"` rather than raising it to Performance
during reapplication. This does not solve the dual-render architecture cost,
and DLSS Ultra Performance may contribute to the reported shimmer; those are
separate performance and temporal-quality investigations.

The latest Quest recording was pulled without modifying the device copy to
`artifacts/phase1/quest-recording-20260825-125708/VirtualDesktop.Android-20260825-125028-0.mp4`.
It is a 44.025-second, 1920x1080 HEVC capture with SHA-256
`DE1A961975884137F58D1E32108A552D3835C32FA7A255F4249916277C446256`.
Its average recorded cadence is approximately 30 fps despite a nominal 120 Hz
stream rate, so it is suitable for visual inspection but not direct runtime
performance measurement.

## 4K single-render performance baseline and timing instrumentation

For a bounded control, both project mods were commented out of DMF's load order
and Darktide was launched normally in exclusive 3840x2160. The same minimum
quality selectors and DLSS Ultra Performance were retained. Runtime inspection
confirmed a 3840x2160 active resolution, no loaded native-capture DLL, and no
stereo/camera-probe initialization in the new log. The observed frame rate was
about 150 fps average and 120 fps minimum.

The control renders 8.29 million output pixels per frame versus 9.73 million
for the two 2112x2304 runtime eyes. That 17% output-pixel difference cannot by
itself explain the lobby's approximately 50 fresh stereo pairs/s. A purely
serial double render would already consume much of the difference, but the
observed threefold frame-time increase also leaves measurable overhead to
localize. The prior VR settings and mod order were restored byte-for-byte after
the control.

The profiling build exports QueryPerformanceCounter timestamps through the
already loaded native module. Lua measures each left and right `ScriptWorld`
submission and the containing pair, then reports 240-sample average and maximum
wall times under `DARKTIDEVR_PERF`. The XR harness now reports instantaneous
interval rates for submissions, fresh pairs, and fallback alongside cumulative
rates. These measurements distinguish engine submission/capture time from
bridge pacing at negligible sampling cost, but do not claim to be GPU-pass
timestamps.

The follow-up native profiler placed D3D12 timestamp queries before each armed
eye and after the corresponding completed camera-output command list, before
the shared-resource copy. A single-active-sample implementation was rejected
because it collected roughly 190 left samples but only 2--9 right samples per
window: Darktide can arm the right eye before the left end marker is observed.
Independent per-eye in-flight slots corrected that sampling bias.

At character select, stable windows reported about 3.5--4.3 ms for each eye and
108--117 fresh pairs/s. In the lobby, repeated 240-pair windows reported a
24--27 ms left interval and an 11--13 ms right interval; instrumented fresh-pair
rate generally ranged from the mid-30s to upper-40s. These intervals overlap in
queue time, so adding them is invalid: the left interval covers most of the
complete pair while the right interval is nested within it. The defensible
conclusions are that Lua submission is negligible, the loss is downstream on
the render queue, and the second view contributes a material roughly 11--13 ms
GPU interval. The profiler is opt-in after measurement to remove its allocator
and command-list overhead from normal VR runs. The next classification step is
timestamping the existing marker/pass groups, not suppressing draws based only
on their similar signatures.

## Shared preparation and pooled capture optimization

The first optimization stage deliberately completed reusable work before
attempting queue parallelism. The primary eye still enters the shipping
`ScriptWorld.render` wrapper, but the second eye calls
`Application.render_world` directly with the primary eye's prepared shading
environment. This removes the duplicate shading blend/callback/apply,
shadow-bake check and LOD update while preserving a full second native render.
Headset testing accepted stereo, lighting and tracking and reported a large
subjective lobby improvement. Live lobby intervals frequently reached the
90--120 fresh-pair/s range, although differing camera views prevent treating
that as a controlled percentage.

Capture command allocators/lists and harness vectors are now retained and
reset. The production native build no longer installs renderer-investigation
hooks for draws, roots, descriptors, markers, clears or output-merger binds.
The required runtime output learner remains dynamic across process launches
and target recreation; only its steady-state candidate filtering was narrowed.
Paired capture counts remained coherent in both live runs.

The next architectural investigation is view-instanced geometry, based on the
existing 98% exact input/geometry overlap and completely distinct per-eye
binding signatures. Independent full-render queue submission is not yet safe:
the two views retain shared scene, history, streaming and lighting resources
whose hazards have not been mapped.

## Fixed-pose post-optimization baseline

A clean launch and stationary headset removed the prior camera-direction and
pose-motion variables. Character select delivered 17,220 fresh stereo pairs
in 180.009 seconds (95.65 pairs/s, 10.45 ms/pair). A keyboard-only transition
then loaded the lobby without pointer motion; its untouched spawn camera
delivered 16,966 fresh pairs in 180.015 seconds (94.25 pairs/s, 10.61 ms/pair).
Both runs had zero reuse and zero pair-driven timeouts. Each retained only the
two known startup fallback/mismatch frames.

Lobby one-second intervals were normally above 90 pairs/s but included
occasional approximately 84--89 pairs/s dips. The controlled result therefore
places average delivery above the 90 Hz budget while showing inadequate slow-
tail margin. Subsequent optimization claims should compare against this exact
clean-launch, stationary-headset, untouched-camera procedure.

## XR-only resource boundary census

The native diagnostic render hooks are selectable before hook installation and
remain disabled in production. This makes focused renderer investigations
available without permanently paying their per-command-list overhead.

A bounded trace started only after the first valid XR pose at Virtual Desktop
Medium (2112x2304 per eye) with DLSS Ultra Performance. In each sampled phase,
the principal color/G-buffer/depth attachments were 704x768. Additional
352x384 and 512x512 attachments appeared alongside 2112x2304 format-26 and
format-28 resources. The same distinct resource counts
and dimensions appeared in both phases, and all observed attachments used
`array=1`.

No D3D12 semantic `BEGIN` or `MARK` records were emitted, so the trace cannot
assign engine pass names. A follow-up GPU profiler timestamped the first
full-size resource transition observed after internal-size work. During the
final stationary 30-second XR run, that transition appeared in 2,232/2,290
left-eye samples and 2,692/2,701 right-eye samples. Weighted averages were
1.92 ms before and 2.45 ms after it for the left eye, and 1.81 ms before and
2.74 ms after it for the right eye. Whole-eye averages were 4.28 ms and
4.53 ms respectively.

The experiment rejects a simple semantic resolution boundary. Resource
barriers show full-size resources transitioning while internal-size work is
still in flight, and output-merger-only detection identifies a different,
later point. The profiler therefore labels these intervals only as pre-full
and post-full; neither is equated with world rendering or post-processing.
Resolution remains valuable resource evidence, but the next optimization pass
must classify command-list/PSO dependencies before sharing or parallelizing
work. A final-target-only substitution still cannot merge the duplicated
internal geometry work.
