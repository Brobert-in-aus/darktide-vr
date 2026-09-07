# Two-handed guns, virtual stock and ADS

Status: offline input/pose foundations implemented 8 September 2026; no live
two-hand behavior is deployed. The user accepted the final controller-based gun
pitch, hand placement and draw/reload checks on `ab9e9db`.

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
