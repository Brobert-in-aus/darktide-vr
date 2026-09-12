# Two-handed guns, virtual stock and ADS

Status: offline calibrated two-hand candidate implemented 8 September 2026;
no live two-hand behavior is deployed. The user accepted the final controller-based gun
pitch, hand placement and draw/reload checks on `ab9e9db`.

## Optional stock anchor candidate: 8 September follow-up

The coordinator now supports an explicit `profile.stock` with `shoulder` and
`offset` numeric XYZ arrays, `radius` and `strength`. `shoulder` is measured
relative to the player's root in the avatar-heading basis; `offset` is the
weapon's rear contact point relative to the primary grip in the gun basis.
No stock profile or shoulder/stock dimensions are supplied by default. The
support calibration command does not invent these additional measurements.

At contact, the anchor latches avatar yaw relative to the scene's pre-head-
tracking basis. During contact it follows root translation and artificial scene
turns, holding that relative yaw through delayed avatar catch-up during head-only
glances. Leaving the contact radius or releasing grip clears the latch. Invalid
or missing owned body data falls back to ordinary two-hand aiming. Stock
configuration changes retire gesture ownership and require neutral input.
`stock_active` reports whether the optional contribution is currently engaged.

This is an estimated shoulder reference, not tracked torso orientation. Real
torso turns, crouching, roomscale collider repayment, high/low aim and shouldering
comfort still require worn checks. Root-relative shoulder height does not
automatically solve crouch posture; leaving contact removes stock influence.
The measured main grip remains fixed and the same resolved aim drives gun and
reticle. No candidate code or stock profile has been deployed.

Four affected offline checks pass in 0.10 seconds: `gun_aim`, `two_hand_pose`,
`two_hand_support`, and `gameplay_ui_ownership`. The installed-adapter fixture
holds a changed body heading for 120 samples without steering the mounted gun;
geometry tests cover artificial turns, translation, contact loss and invalidity.
All 45 Lua chunks compile. Earlier notes below describe the staged implementation
before this optional anchor connection.

The subsequent full Windows x64 Release CTest run passes **128/128 in 26.36
seconds**, headset tests OFF. Evidence:
`artifacts/unattended/virtual-stock-integrated-128-20260908.log`.

## Requested interaction

Move the left hand to the gun's support grip and press grip to two-hand it.
That contextual press overrides the currently bound grip action. A press outside
the grip region retains its binding. Use logical support/dominant roles internally
so future handedness does not require duplicating this behavior.

Claim the whole press/hold/release gesture before normal action dispatch. Do not
start grabbing merely by moving a previously held grip into range. Release,
weapon switch, menus, death or tracking loss must end ownership cleanly and
require neutral input before restoring the displaced action. A held button must
never suddenly trigger its old action when the hand leaves the grip region.

## Research and proposed implementation

VR Expansion Plugin treats a secondary grip as a modifier on an existing primary
grip and calculates the secondary socket relative to the held object. That is
a useful reference for preserving the gun's main grip while the support hand
steers it. [Author documentation](https://vreue4.com/basic-gripping#secondary-grip-types).

Its gun implementation derives a stock anchor from an offset and headset yaw,
uses proximity to blend stock influence, clears mounting when the secondary
grip ends, and resets a smoothing filter on engagement. These are reference
mechanisms, not Darktide integration code.
[Author source](https://github.com/mordentral/VRExpansionPlugin/blob/Master/VRExpansionPlugin/Source/VRExpansionPlugin/Private/GripScripts/GS_GunTools.cpp).

Our proposed solver and acceptance work:

- Author or resolve support sockets per weapon; use a small acquisition volume
  and a larger release tolerance. Begin with the owned lasgun. Pistols need a
  support-hand cup near the dominant grip; stocks and foregrips are not universal.
- Keep the main grip position as the primary constraint. Derive orientation from
  the main/support grip line with the authored gun basis, retaining sensible
  wrist roll. Blend acquisition/release to avoid a barrel jump. Handle coincident
  hands and extreme angles explicitly; never scale the gun to controller distance.
- Add an optional adjustable shoulder anchor and stock-length contact test.
  Blend toward shoulder-supported aiming only near the shoulder. Use a stable
  body-heading estimate, avoiding an immediate gun swivel when the user turns
  their head independently. Headset yaw alone cannot measure torso yaw.
- Offer stock strength/offset and modest time-based smoothing; reset on recenter
  or tracking discontinuity. Keep high/low aiming, hip fire and eye alignment
  usable. Do not rigidly lock the weapon to the face or delay fast deliberate aim.
- Feed the same resolved gun basis to visual weapon, simulation aim and reticle.
  Preserve stock recoil/spread once. Keep the main hand seated; a constrained
  support-hand visual may differ slightly from raw tracking at the socket.
- Test grip-action suppression, release without an accidental old action,
  weapon/context changes, tracking loss, recenter, close hands, head-only turns,
  high/low aim, one/two-hand transitions, and worn sights/reticle/impact agreement.

All solver details above are a proposed adaptation and require worn tuning.

## ADS coupling

The 8 September stock-parser follow-up executes 108 toggle entry/exit routes
across the 54 admitted templates. Both directions require a press in toggle
mode; grip release alone matches neither. The extracted stock buffering method
also preserves an unconsumed lasgun zoom request until its buffer deadline and
refreshes that deadline during sprint. Therefore a fixed timeout or an exit
pulse based only on the current `alternate_fire.is_active` value is insufficient:
an earlier entry may still be pending. These checks extend
`tests/tooling/test-two-hand-stock-contract.lua`; they isolate input evaluation
and buffering, with hierarchy-jump/clear callbacks substituted, rather than
executing the full action lifecycle. Toggle coupling remains disabled pending
ownership-aware integration that preserves independent manual inputs.

The user's suggested first candidate is: two-hand hold requests the weapon's
normal ADS/braced input; release requests its ordinary exit. Physical sight
alignment remains something the user performs with the held weapon. A later
option can require shouldering/sight proximity if users want supported hip fire.

The inspected local `lasgun_p3_m2.lua` has `action_zoom` (`kind = "aim"`),
`action_unzoom`, and `action_shoot_zoomed`. Its `alternate_fire_settings` select
different recoil/spread/sway templates and a movement-speed modifier curve.
Therefore ordinary ADS input is a plausible route to the intended movement and
accuracy tradeoff. Exact recoil/spread differences must be checked per weapon;
two hands by themselves must not be claimed to grant a universal bonus.

Audit input arbitration with an already held aim binding, interruptions, and
weapon-specific secondary modes (ADS, bracing, charging, special attacks).
Do not map staff grip to a charged cast indiscriminately. Preserve normal action
gates, stamina/ammo/timing and server-authoritative combat rules. Suppress flat
camera zoom/repositioning in VR through presentation handling, while retaining
gameplay ADS state; scopes need their own readable stereo treatment.

True firing origins remain the stock body/face-based origins. Two-handed aiming
and cosmetic muzzle effects do not enable gun-only blind fire around cover.

## Located integration boundaries

`darktidevr_controller_bindings.lua` treats native channels as physical inputs:
left grip is channel 512 (default blitz), and alternate action maps to the stock
`action_two_pressed/hold/release` names. The main input reader calls its `sample`
before dispatching ephemeral actions; fixed updates use the mapper's held state.
Insert contextual ownership at that mapping boundary, before semantic actions
are aggregated. Masking the grenade action afterward would break remaps and
could suppress an independent control bound to the same action.

Keep each control's contribution separate until aggregation, including a
two-hand ADS contribution. Releasing the support grip must not release ADS if
the normal aim control is still held. Preserve existing remap/context/publisher
neutral guards and keyboard/mouse coexistence; do not mutate saved bindings.
This requires explicit handling of the user's hold/toggle ADS preference rather
than assuming every `action_two` gesture has the same lifecycle.

Stock `ActionAim.start` calls `AlternateFire.start`, which selects the weapon's
alternate spread/recoil/sway templates, starts animation and immediate
spread/sway changes, and triggers relevant buffs/stats. `ActionUnaim` uses the
matching stop route. `AlternateFire.movement_speed_modifier` applies the active
weapon curve. Request ordinary inputs so these transitions remain intact;
setting only `alternate_fire.is_active` or directly replacing accuracy templates
would skip stock behavior.

## Initial weapon-specific findings

These are raw local source values, before item stats, buffs and the active
movement/firing state; they are not measured final weapon performance.

| Template | Relevant stock behavior | Consequence for the candidate |
| --- | --- | --- |
| `lasgun_p3_m2` | Uses `hip_lasgun_p3_m1` and `default_lasgun_killshot` spread templates. Their still-state minimum pitch/yaw spread is 1.8–1.5 versus 0; maximum is 6.25–6 versus 2.5. | Stock ADS provides a concrete spread advantage to test through two-hand hold. |
| Same lasgun | Hip and ADS recoil templates have matching listed rise magnitudes, but camera recoil fraction changes from 0.15 to 0.01 and rise duration from 0.075 to 0.01. | Do not describe this simply as uniformly less total recoil. Preserve the complete template and verify visible/actual shot agreement. |
| `autogun_p2_m1` | Uses `kind = "aim"` with a `to_braced` first-person animation, alternate recoil/spread and a movement-speed curve. | An aim action can mean bracing rather than looking through sights; generic ADS naming is insufficient. |
| `stubrevolver_p1_m1` | Uses ironsight recoil/spread/sway and camera settings, but its alternate settings contain `action_movement_curve`, not the lasgun's `movement_speed_modifier` field. | Audit the actual action/movement consumers before promising the same slowdown for pistols. |

Files inspected: `scripts/settings/equipment/weapon_templates/lasguns/lasgun_p3_m2.lua`,
its `settings_templates/lasgun_spread_templates.lua` and `lasgun_recoil_templates.lua`,
`autoguns/autogun_p2_m1.lua`, and `stub_pistols/stubrevolver_p1_m1.lua` under the
ignored local Darktide source checkout. Per-weapon scope, physical stock and
grip-socket configuration remain implementation work.

## 8 September implementation checkpoint

The controller mapper accepts an optional support request as its last sample
argument: `{control, owner, acquire, retain, action}`. Control is a physical
left/right grip; owner is a stable weapon/tracking identity; action is `alternate`
or `unbound`. No request preserves normal mapping. It owns a fresh press before
semantic aggregation, suppresses the displaced gesture, and exposes support
pressed/held/released/cancelled state. Weapon changes, disappearance, retention
loss, publisher changes, menus and remaps cancel/rearm without leaking a held
control into its old binding. Independent aliases retain their own contribution.

`darktidevr_two_hand_pose.lua` supplies geometry and smoothing with explicit
numeric inputs in a common space. It steers the authored primary-to-support
socket ray, preserves controller wrist roll through a shortest-arc correction,
does not scale the weapon, and smooths only the correction in controller-local
space. Release decays to one-hand aim. Owner changes, cancellation, long/invalid
frame intervals and invalid or nearly coincident hand poses discard stale state.
Sockets shorter than 8 cm and nearly reversed directions are rejected for now;
close pistol support needs a separate policy rather than pretending it provides
a stable two-point direction. Radius-based acquisition supports a larger release
volume; no weapon socket measurements or tuning are inferred from these tests.

Focused Windows x64 CTests pass 9/9 in 1.13 seconds, including controller aliases,
lifecycle cancellation, 120 off-axis socket geometry cases, translation/rotation
covariance, wrist roll, 30/60/90/120 Hz smoothing, gun regression, all 44 compiled
Lua chunks and source invariants. Configured count is 127. These modules still
need verified per-weapon sockets, stock ADS arbitration,
support-hand visuals and virtual-stock handling before live acceptance.

Stock `toggle_ads` is carried in input-handler settings. The inspected lasgun
uses `action_two_hold=true/false` for ordinary enter/exit, but substitutes
`action_two_pressed=true` for both transitions when toggle ADS is selected.
Consequently the mapper's alternate contribution alone must not be enabled as
hold-to-two-hand ADS in toggle mode. Keep saved preferences intact and use a
state-aware coordinator (including an independently active aim owner) before
enabling that route. Raw grip release is not a toggle-mode ADS exit.

The live controller observation has distinct `*_grip_tracking_live` fields;
`*_grip_usable` can retain an old wrist pose intentionally. Two-hand acquisition
and retention must require live tracking, not the presentation fallback pose.

The subsequent production coordinator is connected before semantic mapping in
pre-update, and its result passes through the shared gun-aim reader after the
accepted pitch adjustment. A separate base-aim reader prevents solver feedback.
Fixed-update stock-input cancellation clears support state before aim/history
updates. The coordinator checks current weapon identity, role, recenter,
publisher, real grip tracking and character/action eligibility; reload/draw,
death, retired owners and unsupported weapon modes cancel support. Current
weapon/action identity is checked again when aim is read, covering switches
between input samples.

The coordinator defaults disabled and its profile registry is empty. Register a
verified `profiles[template_name]` with numeric socket, acquisition/release radii,
smoothing and an optional ADS request before enabling the candidate. Socket
coordinates are measured from the primary grip in the pitch-corrected gun basis,
in the same world units as the tracked grip targets. In-place profile edits
retire the current gesture. Toggle ADS or an unknown preference permits support
aim only; it does not request alternate fire. No socket is guessed for a staff,
another gun or a replacement loadout. No automatic enable or live deployment.

Coordinator/production-seam validation: ten focused CTests passed in 1.11 seconds;
after adding fixed-update cancellation and actual shared-aim ordering checks,
seven affected checks passed in 1.16 seconds. All 45 Lua chunks compile. The
configured suite contains 128 checks; full integrated rerun is not claimed.

## Session-only support calibration candidate

8 September follow-up: measured profiles now retain the physical support side
alongside equipped-item identity. A role change cannot reuse the opposite
hand's socket/orientation; neutral input and returning to the measured side
allow normal reacquisition. A role change during the countdown cancels capture.
Explicit generic profiles without a side remain supported by the pure geometry
coordinator; the runtime measurement command always binds its physical side.
The new regression failed before the fix. Six focused CTests pass, including
support, pose, bindings, gun alignment, anatomical calibration and 48-chunk Lua
compilation. This candidate remains undeployed and disabled by default.

The candidate now registers local DMF commands. `/dtvr_two_hand_calibrate`
disables support aim, waits for chat to close, then captures the tracked
primary-to-support offset after three seconds. The user must physically place
the support controller at the desired visible grip during that countdown.
Weapon/character replacement, recentering, publisher changes, tracking loss,
reload/firing, reopening menus or the 30-second request deadline cancel capture.
Degenerate or implausibly distant geometry is rejected. The result remains in
memory under that weapon template and is bound to the calibrated equipped-item
object; another item with the same template does not inherit it. It is not
persisted or committed as a profile.

`/dtvr_two_hand_on` enables registered sockets; `/dtvr_two_hand_off` cancels
pending capture and returns to one-hand aiming. Capture never auto-enables the
feature. Initial acquisition/release/smoothing values are candidate tuning,
not worn acceptance. Hold-mode ADS is requested for the captured profile;
toggle/unknown ADS preference retains support aim without an alternate request.

Calibration/geometry/compiler/invariant checks passed 4/4 in 0.97 seconds.
No commands have been invoked in the live session and the candidate is not
deployed. Next worn request: place the support hand naturally under the same
lasgun, calibrate, then observe grab/release continuity and barrel/reticle/hits.

Optional virtual-stock geometry is now tested in the pose module. It blends a
shoulder-to-support ray into two-hand aim only when the authored rear stock
point is close to an explicit shoulder anchor, with tunable strength and smooth
proximity falloff. It changes orientation only, clears on release and ignores
invalid/out-of-range anchors. Four focused checks pass in 0.96 seconds. It is
not wired to the production coordinator: a stable body/shoulder anchor and worn
tuning remain required. The existing avatar heading follows head yaw with a
dead zone and delayed convergence; using it directly would still eventually
swivel a shouldered gun during a sustained head-only glance.

Support-hand presentation is now connected to the calibrated profile. Capture
also records the support grip's rotation relative to the pitch-corrected gun.
While held, the visible local support hand uses that socket position and grip
rotation through the existing anatomical hand-placement helper. It does not
write the gameplay skeleton; release stops constraining the visual hand. Grip
rotation/profile/role changes retire ownership, and calibration cancels on
long frame discontinuities. Worn pose and release comfort remain unverified.

Full Windows x64 offline CTest suite passes **128/128 in 21.88 seconds** with
headset tests OFF, including all 45 Lua chunks. Evidence:
`artifacts/unattended/two-hand-offline-128-20260908.log`. Native code is unchanged;
the running accepted Psykhanium session remains separate from these source
changes. Review is PR #3, based on the aggregate development branch in PR #2.

The production ADS gate now requires a canonical `aim`/`unaim` pair backed by
single `action_two_hold=true/false` sequences and normal alternate-fire settings.
Only absent or recognized toggle-ADS overrides are admitted. A charge action,
compound gesture or unknown input-setting override keeps support aiming without
requesting secondary fire. Four affected checks pass in 0.98 seconds after this
gate and exact-item calibration ownership were added.

The optional stock-source fixture passes against cached source
`0f0cb45991e9305ef4a7b925370792d7d6035f95`: 62 ranged templates inspected, 54 with
canonical ADS input routes and eight excluded. All four staff and both plasma
templates are explicitly checked as excluded. The fixture executes the actual
literal input tables and stock parser with contextual mapper output, verifying
entry/release admission and no exit while an independent aim alias remains held.
Action kind/start-input metadata is extracted without executing asset setup.
This does not execute the complete action hierarchy or establish live firing,
accuracy, server behavior or worn acceptance. Run:

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-two-hand-stock-contract.lua _downloads/Darktide-Source-Code mods/darktidevr/scripts/mods/darktidevr/darktidevr_two_hand_support.lua mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_bindings.lua artifacts/unattended/ranged-template-paths-20260907.txt
```
