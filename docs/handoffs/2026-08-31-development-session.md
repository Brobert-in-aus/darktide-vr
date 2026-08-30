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
The next evidence boundary is native per-submission render identity: attribute
command lists and their shadow/light/culling resources to the completed left
or right output instead of relying on the current `eye=-1` trace records.
