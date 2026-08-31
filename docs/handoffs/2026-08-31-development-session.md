# 2026-08-31 development session

## Premium Store coordinate ownership

Live geometry disproved the previous crop-local Store scenegraph assumption.
Mode 6 presents a native-landscape client, laser and visible cursor, but the
retained Store widgets remain in the portrait eye canvas. A source miss at
`(626,297)/1024x576` reported the full-grid rectangle near `(142,863)` with
extent `2210x1040`.

The production contract now keeps presentation pixels landscape, transforms
only semantic Store hit tests into the portrait canvas, and passes a null input
service to the stock grid while XR owns the pointer. This removes the offset
Windows-hover owner. Store also samples its full-grid `is_hover` before the
draw pass applies `force_hover`; the XR hook now publishes both on the same
atomic trigger frame so a matched card is not force-disabled.

An unattended source-pixel pointer probe preserves one synthetic edge across
all hooked UI passes until the semantic owner consumes it. The live proof used
`pointer_500_360_1280_720`: `StoreView._draw_grid` activated the real card and
opened `store_item_detail_view`. Escape then returned to the landing page and
the hub. Worn corner alignment remains the authoritative acceptance gate.

## Escape menu coordinate evidence

The first live Escape inventory found the same split contract. SystemView is
captured through the landscape panel, but its retained grid rectangles occupy
the portrait eye canvas: Options was near `(240,1539)` with extent `650x65`.
The semantic SystemView ray now transforms source pixels into that canvas while
the visible laser remains panel-local. The corrected source probe
`pointer_290_421_1280_720` mapped to portrait position `(566,1572)`, activated
`grid_content_pivot_widget_11`, and opened `options_view`. Two staged Back
inputs then closed Options and SystemView, restored mode 1, and resumed fresh
stereo pairs with no pose-pair mismatches. Worn laser alignment remains the
authoritative visual gate.

## Diagnostic polling overhead

The performance audit found several development flags performing a filesystem
open every UI or fixed-update frame even when consumed or absent. System-menu,
vendor-menu and input-inventory probes now poll every 15 UI updates;
Psykhanium and hotspot inventory poll at 250 ms; movement inventory uses its
existing 60-fixed-frame guard. Active vendor child-close state still advances
every frame. These are diagnostic-only overhead removals and do not change
production pose, rendering or controller semantics.

## Validation

Commands run:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 900 -GameStartTimeoutSeconds 180 -AutoEnterHub -AutoAdvanceSplash -EnableMenuInput -EnableMenuTestControls
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release --output-on-failure
```

The source gate passes at 198/198 file-scope locals. Fresh live runs contained
the stereo mod initialization messages and nonzero advancing `shared_ready`.
All 30 CTest cases pass in Release.
The Premium Store landing-to-detail transition and Escape-to-Options path both
completed without script errors or pose-pair mismatches. The validated Escape
run reached `shared_ready=5850`; back-navigation restored continuously advancing
fresh pairs.

## Fixed HUD target population

Source inspection of `UIWidget` identified why the earlier fixed-HUD resource
target stayed empty. Setting only UIHud's element retained lookup to false did
not change the retained mode stored on each widget pass, and an existing
retained ID caused the draw to short-circuit before the offscreen pass. The
prototype now temporarily sets only fixed-HUD widget passes to immediate mode,
marks those passes dirty, authors the target once per simulation time, and then
restores every stock retained-mode field and ID. The stock HUD remains the only
update/event owner; spatial elements continue drawing once per eye.

The feature remains default-off and can be gated with
`darktidevr_hud_panel.flag` (`enable`/`disable`). In a fresh live hub run the
target was created, the spatial/fixed partition was logged, fixed player/team
HUD content remained visible after being removed from the stock eye draw, and
the flag cleanly restored the ordinary HUD. That is direct target-population
evidence. Worn panel depth, comfort, binocular parity and coverage are still
required before enabling it in production.

## Private-range input isolation and muzzle origin

The unattended Psykhanium run exposed an ownership bug in the synthetic test
provider: controller tracking and gameplay buttons were both published through
flat loading and menu states. Its periodic Back/Menu phase therefore closed the
training-options view after the mod selected Shooting Range. Synthetic tracking
now remains continuous, while gameplay buttons are emitted only in
`stereo_world`. A clean authenticated launch then completed the scripted flow
with `DARKTIDEVR_PSYKHANIUM result=pass game_mode=shooting_range` and reached
`shared_ready=17259` with one transient pose mismatch across the whole run.

The ranged-action hook now derives the shot origin from Darktide's registered
third-person muzzle source and attachment node. It preserves the stock origin
if that live node is absent, handles alternating muzzles using the just-prepared
shot index, and retains the existing first-projectile ownership rule for
simultaneous groups. The available Psyker loadout also established the non-
`ActionShoot` routes. `ActionSpawnProjectile` now separates spawn ownership
from aim ownership: normal staff fire uses the tracked left-hand origin and
right-hand aim, while charged/ADS fire uses the live staff-tip attachment and
right-hand aim. Smite/chain-lightning targeting, damage and smart-target
queries use a scoped right-controller read proxy; Darktide's read-only
`first_person` component is never mutated. Clean live Psykhanium runs logged
`left_origin_right_aim`, `staff_tip_right_aim`, and four advancing lightning
right-aim updates while stereo reached `shared_ready=9487`. The harness's
charged-fire phase holds secondary across a phase boundary before pressing
primary, and its C++ contract test covers that overlap. Firearm worn alignment,
binocular reticle policy and optional laser presentation remain open.

## Billboard acceptance correction

The exact particle shader ownership and substitution plumbing remain useful
evidence, but the identified native particles are **not** accepted as
cylindrically billboarded. The user's latest recollection is that those
particles remained spherical. Treat prior acceptance wording as stale and
re-run the worn/native particle gate only when billboard work is reached in the
explicit priority order.

## Exact per-eye visual-parity diagnosis

The XR harness now supports an on-demand, synchronized readback of the two
completed shared-eye resources. Creating
`%TEMP%\darktidevr-shared-eye-readback.request` writes left and right PPMs only
after the pair-copy command list and its fence complete. This avoids the
producer race and desktop-mirror ambiguity of earlier screenshots. Shared-eye
submission also now fails closed while `shared_ready` is zero; this fixes a
live startup crash in which newly opened but unpublished resources supplied an
uninitialized pose to quaternion processing.

`set-coincident-eye-probe.ps1` provides an exact gameplay comparison mode. It
coincides both eye positions and both optical/frustum rotations; coinciding
position alone was insufficient because the runtime supplies asymmetric
per-eye optical rotations. At 2496x2688, the production prepared-second-eye
path measured 8.0127% changed pixels above an RGB threshold of 2, MAE 0.8554,
PSNR 34.5915 dB and affine edge correlation 0.97714. Repeating the capture with
the complete second `ScriptWorld.render` wrapper measured 8.0049%, MAE 0.8597,
PSNR 34.5431 dB and edge correlation 0.97594. The signed channel errors were
also effectively identical. Amplified differences cluster around bright and
specular lighting, fine edges, particles and local illumination. The optimized
Lua preparation boundary is therefore falsified as the cause of the remaining
binocular mismatch.

Resetting DLSS before each eye made the result worse (8.6221% changed pixels,
MAE 0.8973, edge correlation 0.96963) and reduced fresh-pair throughput from
roughly 52-56 to 43-46 pairs/s, so that experiment was rejected and reverted.
A proper no-DLSS run reached exact stereo rendering but the native completed-
output discovery never promoted the negotiated full-eye surfaces without its
format-28 intermediate. That is a diagnostic boundary failure, not evidence
about no-upscaler parity. Repair that discovery before attempting the no-DLSS
A/B again.

Runtime flags and the user graphics configuration were restored after the
tests: coincident eyes and the full second wrapper are disabled, per-eye DLSS
reset is false, and the backed-up DLSS/frame-generation/upscaling settings are
active. Captures and amplified diffs are retained under
`artifacts/unattended/visual-parity-coincident-2026-08-31/` (ignored by Git).

That native attribution boundary is now complete. Focused draw records carry a
command-list recording generation, and queue submission emits the render-arm
identity for every list in the batch. Joining on `(frame, command list,
generation)` avoids both reused D3D12 command-list pointers and the misleading
alternating `AMD FSR Replacement BackBuffer` resource identity. In the normal
order, the completed right eye contained stable opaque/depth families that the
left eye omitted by roughly 54, 20, 10, 8 and 5 draws per eye frame. Reversing
submission order left those populations attached to the right viewport/camera
identity, so "the second render gets richer" is falsified. Inheriting the
primary viewport's layer, shading callback, or both also left the asymmetry
intact.

Source inspection then found the structural difference. Darktide creates the
primary viewport through `CameraManager.create_viewport` with a dedicated
shadow-cull camera, updates that camera before the late VR hook replaces the
render camera pose, and registers the viewport with camera-manager observers.
The duplicate eye was created directly without a shadow-cull camera. An initial
probe that moved the primary's dedicated shadow camera was invalid because it
lives on the same camera unit and visibly changed the render camera. The
corrected probe instead assigns the already tracked primary render camera as
the shadow-cull camera for both viewports and never manipulates the dedicated
camera.

The corrected exact-pose result is decisive. Across 42 frames it attributed
21,454 left and 21,449 right draws; the largest remaining signature delta was
only 0.048 draws/frame and the former stable opaque/depth families disappeared.
At 2496x2688, pixels above threshold 2 fell from about 8.01% to **0.0948%**,
MAE from about 0.855 to **0.0308**, PSNR rose to **48.72 dB**, and affine edge
correlation rose to **0.99830**. The amplified remainder is confined mainly to
small dynamic HUD markers. Shared tracked-camera culling is therefore the
production default; `darktidevr_shared_shadow_cull.flag=disabled` remains only
as a diagnostic regression control. Corrected evidence is retained under
`artifacts/unattended/visual-parity-shared-render-cull-corrected-2026-08-31/`.

The production-normal follow-up disabled coincident eyes, reverse order and
metadata inheritance, synchronized the corrected Lua/DLL, and entered the hub
through the authenticated launcher. The fresh log reported
`shadow_cull shared=true`, normal `half_ipd=0.032`, and advancing stereo through
`shared_ready=4264`. The 30-second hub soak had zero reused frames and zero pose
mismatches; exit was clean. The Lua source gate passed at 198/198 locals, the
Release native DLL built with warnings-as-errors, all 30 CTest cases passed,
the diagnostic PowerShell tools parsed, Python attribution tooling compiled,
and `git diff --check` passed.

## Matched shared-cull performance control

Performance profiling is now a fresh-process opt-in rather than a permanently
active diagnostic cost. `set-performance-profile.ps1` writes the startup flag,
and `start-darktide-vr.ps1 -DiagnosticRenderHooks` preserves the native GPU
timestamp hooks through its own deployment sync. Newly added command-list
generation and output-attribution bookkeeping also bypasses its atomic,
hash-map and logging work unless a focused trace is actually armed.

A matched pair of stationary authenticated hub runs compared the corrected
shared tracked-camera cull with the old independent/stale-cull regression. The
last twelve warmed 240-frame windows measured 33.773 ms versus 30.942 ms summed
eye GPU average, 33.491 versus 30.544 ms summed independent-eye p50s, and
40.699 versus 37.312 ms summed independent-eye p95s. Lua pair-wrapper CPU was
only 0.324/0.582 ms average/p95 with shared culling and 0.367/0.603 ms in the
control. The roughly 2.8 ms GPU increase is expected work restored by the
visual-parity fix, not cull sharing: both eyes now render the geometry, shadows
and lighting that the stale primary cull omitted. The next optimization seam is
therefore reuse of completed visibility/draw preparation (and eventually
multiview-like submission), not weakening the shared-cull correctness fix or
micro-optimizing the already small Lua wrapper. Full logs are retained in the
ignored `artifacts/unattended/performance-shared-cull-*-2026-08-31/` folders.
Production flags were restored afterward: shared culling enabled, performance
profiling disabled, and diagnostic render hooks removed.

## Generation-aware GPU batch attribution

The focused profiler now brackets each intercepted direct-queue engine
submission with timestamp marker command lists and retains the submitted
command-list pointer plus recording generation. This replaced an invalid
output-target timestamp attempt: command lists are recorded out of GPU
execution order, so timestamps inserted at target-bind time were
non-monotonic and that prototype was discarded after a device-removal failure.

The accepted stationary-hub trace completed without truncation or device loss.
One claimed profiler sample crossed two completed-output boundaries, which is
useful rather than an eye-label failure once segmented by terminal list
identity. Batches 0-4 ended at render eye 1 and contained 5.499 ms of timed
direct-queue work; batches 5-26 ended at render eye 0 and contained 6.955 ms.
Generation-aware PSO attribution found 251 and 259 unique PSOs respectively,
with 239 shared out of 271 total (0.882 Jaccard). Bind-count multiset Jaccard
was 0.703. The dominant terminal batches cost 4.167 and 3.537 ms, while the
largest preceding batches cost 1.101 and 1.333 ms. This establishes substantial
shared pipeline-family structure but also real eye-specific command-count
differences.

`set-performance-pass-trace.ps1` owns the fresh-process diagnostic flag and
implies ordinary GPU profiling. `analyze-gpu-batch-trace.py` emits the render
segments, expensive batches, command-list/PSO joins and overlap metrics.
Evidence is retained under the ignored
`artifacts/unattended/performance-gpu-batches-2026-08-31/` directory. The next
renderer task is to identify the CPU/engine owner of common visibility and draw
preparation before eye-dependent recording. Production was restored after the
trace: performance flags disabled, shared tracked-camera culling enabled and
diagnostic render hooks removed.

## Semantic XR input across shop landing views

The ordinary hub shop landing pages now share one concrete semantic XR-input
owner. Hooks on `ContractsBackgroundView`, `CreditsVendorBackgroundView`,
`CosmeticsVendorBackgroundView` and `BarberVendorBackgroundView` transform the
published landscape panel pointer into each retained portrait eye scenegraph,
clear stale forced hover/press state on every draw, null the competing native
input service while XR owns the ray, and arm only the matching `_button_widgets`
hotspot. The menu-input diagnostic flag now polls every 15 UI updates even
after a missed synthetic point, allowing coordinate correction without a game
restart.

Two clean authenticated hub sessions produced the following source-coordinate
evidence at `1280x720`:

- Contracts `(300,380)` activated `option_button_1` and opened
  `contracts_view`;
- Contracts `(300,405)` activated `option_button_2` and opened
  `marks_vendor_view`;
- Armoury `(300,380)` activated `option_button_1` and opened
  `credits_vendor_view`;
- Cosmetics `(300,380)` activated `option_button_1` and opened
  `cosmetics_vendor_view`;
- Barber `(300,405)` activated `option_button_2` and opened
  `character_appearance_view`.

Shared eye-resource readiness continued advancing and no script error or GPU
failure followed any accepted path. The first test session ended at its
configured ten-minute harness duration, not from a crash. The Contracts Events
child is a separate blocker: an earlier `option_button_4` activation opened
`live_events_view` and was followed by a GPU hang. Do not generalize that child
failure to the landing owner, and do not mark Events accepted until it survives
an isolated lifecycle run.

Next shop gates are worn corner alignment, scrolling, Back and representative
nested actions in each accepted child. Premium Store retains its separate
mode-6 private-grid path. The brief post-shop mono flash remains deferred
transition polish.

## Unattended Psykhanium launch contract

A clean ranged-input diagnostic exposed two orchestration gaps rather than a
weapon-aim failure. `-EnterPsykhanium` armed an in-game state machine which
correctly waits for an authenticated hub, but the launcher stopped at operative
select unless `-AutoEnterHub` was also supplied. Psykhanium entry now implies
that guarded splash/operative advance. `-SyntheticGameplayInput` also now owns
its test-only Lua adapter flag for the lifetime of the run and restores the
prior value in `finally`; previously it could publish synthetic buttons that
Lua intentionally ignored. A subsequent clean launch used only
`-EnterPsykhanium -SyntheticControllerPath -SyntheticGameplayInput`, reached
`DARKTIDEVR_PSYKHANIUM result=pass`, advanced nonzero `shared_ready`, and
delivered every synthetic gameplay action without missing bindings. It ended
cleanly with `shared_ready=10938`, no reused shared frames and one transient
pose mismatch. After selecting the available force staff, charged fire logged
`staff_tip_right_aim`; earlier clean range evidence still covers normal
`left_origin_right_aim` and lightning. The runner restored the gameplay flag
automatically, and the controller-aim flag was restored disabled afterward.

## Right-hand spatial reticle diagnostic

The OpenXR compositor now has an opt-in gameplay reticle path behind
`-EnableGameplayReticle`. It samples an always-available opaque cyan texel from
the existing flat-capture swapchain, so the prototype adds no swapchain or
per-frame capture allocation. In `stereo_world` it places a 6 cm binocular quad
8 m along the tracked right-controller aim ray. Submission is restricted to a
fresh synchronized eye pair, valid position/orientation tracking and a
controller origin within 1.5 m of the head. It is never submitted over loading
or menu panels.

A clean authenticated hub run with a synthetic controller path submitted 1,653
reticle frames, received 4,840 fresh shared pairs, reused zero shared frames and
reported zero pair-pose mismatches. The run ended with `result=pass`; the source
gate, Release build and all 30 CTest tests also passed. This is deliberately a
diagnostic switch rather than the production policy. Worn acceptance must check
right-hand alignment, angular size, perceived depth and off-axis skew. The
current quad is parallel to the head and always compositor-visible; a later
depth-aware world hit and controller-aim enablement policy remain separate
decisions.

## Contracts Events lifecycle isolation

The earlier Events GPU hang is now reproduced and causally bounded. An isolated
accepted Contracts landing activated `option_button_4`, opened
`live_events_view` through the generic world-preserved mode-4 route, and hit a
D3D12 page fault eight seconds later (`DXGI_ERROR_DEVICE_HUNG`). The view's
shipping declaration sets `disable_game_world=true`; the generic preserve-world
hook registered it as a mode-4 world menu before the normal fullscreen path
could choose a captured client.

`live_events_view` is now an explicit member of the Contracts mode-5 shop
family. The same isolated activation then remained stable for the rest of a
four-minute run: `shared_ready=5774`, zero capture failures, zero reused frames,
zero pose mismatches and `result=pass`. A second run added the same guarded
child-before-parent close sequencing used by nested shop families. The harness
returned to presentation mode 1, stereo readiness continued to 5,441, and the
220-second run passed with zero capture failures, reuse or pose mismatches.
Worn content/input alignment within Events remains to be checked; the renderer
lifecycle and stereo restoration are no longer blocked by the prior device
hang.

## Escape Options semantic-coordinate ownership

SystemView and OptionsView do not share one semantic coordinate space even
though they appear in the same landscape Escape panel. The System row probe is
authored against the landscape client, while the nested Options grids remain
in Darktide's 2496x2688 portrait eye canvas. Applying the source-to-eye
transform only in BaseView proved insufficient: BaseView first consumed
OptionsView's broad `grid_interaction` catcher, and after that catcher was
excluded the private `OptionsView._draw_grid` still tested the raw source
pointer.

OptionsView now owns its complete semantic transform. Its row, dropdown,
slider, scroll-catcher and slider-drag tests all use an eye-layout hit pointer,
while the published cursor/laser and consumed input sequence remain in the
original 1280x720 panel space. BaseView no longer claims OptionsView's three
dynamic grid overlays. A clean source probe first activated SystemView's real
Options row at `(290,421)/1280x720`, then a nested `(180,144)/1280x720` probe
logged `options_source_activate widget=grid_content_pivot_widget_3`; no
`base_source_activate ... grid_interaction` occurred. The resulting category
populated the stock settings grid and emitted transformed slider geometry.

The ten-minute authenticated run ended with `result=pass`, `shared_ready=6628`,
zero capture failures, zero reused frames and zero pose mismatches. One backend
sign-in error was dismissed and retried through the already authenticated
launcher flow before this validation; it was not an XR or mod-load failure.
Worn laser/cursor alignment and representative dropdown, slider and toggle
actions remain the human acceptance gate.

The first nested probe also exposed a diagnostic-only counter handoff defect.
Its synthetic primary sequence advanced beyond the native transport counter;
after consumption, native sequence zero therefore appeared permanently newer
than consumed sequence two and retriggered geometry diagnostics every UI pass.
Synthetic consumption now rejoins the underlying native counter. A clean
relaunch activated Video exactly once with no following slider flood. A second
source probe at `(995,105)/1280x720` then opened the stock Resolution dropdown
(`widget_setting_82`) and published correct modal option geometry, without
changing the selected resolution. Selection, toggle and drag remain worn/live
acceptance work rather than assumptions from an open-only probe.
