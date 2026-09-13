# Virtual holsters: design (14 September 2026)

Status: core logic and wiring behind the experimental option "Virtual
holsters" (`vr_holsters`, default off). Not worn-tested. Zone placement, sizes
and accidental triggering are the evening's worn checks; nothing here claims a
good feel.

## Why

A Quest controller has two triggers, two grips, four face buttons and two
sticks. The accepted layout already spends every button and both stick
directions it can, and carried items share one button that cycles. Reaching
to where an item is carried and pressing grip frees buttons, and matches what
players expect from other VR shooters.

## Zones

Six zones in a body frame, as spheres. Centres are metres from the eyes at a
reference eye height of 1.64 m and scale with the player's eye height (both
the offsets and the radii):

| Zone | Centre (x right, y forward, z up) | Radius | Wields | Stock input |
| --- | --- | --- | --- | --- |
| Right shoulder, over and behind | 0.16, -0.14, -0.10 | 0.15 | ranged weapon (`slot_secondary`) | `wield_2` |
| Left hip | -0.20, 0.00, -0.72 | 0.14 | melee weapon (`slot_primary`) | `wield_1` |
| Right hip | 0.20, 0.00, -0.72 | 0.14 | device (auspex, `slot_device`) | `wield_5` |
| Left chest | -0.13, 0.16, -0.38 | 0.10 | stim (`slot_pocketable_small`) | `wield_4` |
| Right chest | 0.13, 0.16, -0.38 | 0.10 | carried item (ammo crate, medkit, `slot_pocketable`) | `wield_3` |
| Belt, front | 0.00, 0.14, -0.60 | 0.11 | blitz (held: press draws and aims, release throws) | `grenade_ability_pressed`/`hold`/`release` |

Both hands can use every zone. The layout keeps the chest zones small and in
front, where a gun's support hand rarely rests, and the hip zones low beside
the body, below where the dominant hand holds a weapon.

Body frame (world space): origin at the first-person eye position; forward is
the body's visual yaw (`body_visual_yaw`, the yaw the body presentation
already follows) and falls back to the head's yaw; the scale is the player's
physical standing eye height from the headset (times the character scale,
1 for humans), because tracked hands move in physical metres. So the zones
turn with the body, not with a glance, and follow crouching.

## Arming and pressing

- Entry: a hand enters the nearest zone whose radius contains it (nearest
  relative to the radius).
- Hysteresis: the hand stays in that zone until it leaves 1.25 times its
  radius, so the boundary does not flicker.
- Dwell: the zone arms after the hand has rested in it for 50 ms, so a hand
  sweeping past (a melee swing across the hip) does not arm anything.
- Press: a fresh grip press (not a grip already held when the hand arrives)
  on an armed zone claims the grip and delivers the zone's wield input as a
  press edge.
- Claim: the claim holds until the grip is released, even when the hand draws
  the item out of the zone, so the grip's own action (weapon special, combat
  ability) cannot fire on release. Menus, lost tracking and binding changes
  cancel the claim through the existing grip-claim rules.

## Precedence and pass-through

- Only the armed hand's grip is claimed; the other grip keeps its binding.
- If both hands are armed, the claim already held wins, then the right hand.
- Empty slot, or the slot already in the hand: no claim. The grip keeps its
  binding in that zone (so a melee weapon held low at the left hip still
  gets its special).
- Against two-hand support: a holster that is armed or holds a claim is used
  instead of the two-hand support request for that frame; otherwise the
  two-hand request passes through unchanged. The two-hand filter sees an
  idle grip while a holster owns it.
- The binding options are untouched: the grip requests reuse the contextual
  grip claim the controller bindings already provide for two-hand support
  (`support` request: control, owner, action, acquire, retain), extended to
  wield selectors. `melee` and `ranged` are request-only actions (`wield_1`,
  `wield_2`), with no option widget.

## Options

- "Virtual holsters" (Experimental features), default off. No per-zone
  options yet; if the worn check finds the positions right but sizes off, a
  single size scale is the next option.

## Parity and limits

- Mission servers: wield inputs are ordinary stock inputs, so holsters work
  wherever controller input does (hub, Psykhanium, SoloPlay, remote missions).
- Hub: off (nothing to wield; the hub grip opens the inventory).
- No haptic or visual cue when a zone arms (the viewer's haptics are backlog).
  A console line `DARKTIDEVR_HOLSTER armed zone=... hand=... selector=...`
  logs the first arming of each zone per session, and
  `DARKTIDEVR_HOLSTER wield hand=... selector=...` each press.
- Blitz from the belt (`4571e85`): the belt holds the stock blitz input for as long as the grip is held, so the stock draw, aim arc and throw on release apply; it is requested even while the blitz is out. The throw follows the dominant hand's aim, as with the button.
- Holster counts and the item radial are separate backlog items.
- Seated play: zones scale with the measured standing eye height but hang from
  the seated head, so the hip zones sit below the seat. Seated tuning is not
  attempted.

## Tests

`tests/tooling/test-holsters.lua`: frame (identity, rotated, scaled, invalid
input), zone entry and exit hysteresis, every zone's centre resolving to
itself, dwell and re-entry, lost tracking, requests for stim, empty and
wielded slots, claim retention outside the zone, release and cancel.
`test-controller-bindings.lua`: stim, melee and ranged grip requests hold
their masks and suppress the grip's own action; an unknown action is no
request; `wield_1` and `wield_2` are delivered.

## Worn check (evening)

Turn on Mod Options > Darktide VR > Experimental features > Virtual holsters.
In the Psykhanium: reach over the right shoulder and press grip (ranged
weapon comes out), left hip (melee), left chest (stim), right hip (auspex, if
carried). Check that holding a gun normally, swinging melee and reloading do
not trigger anything, and that the grip still does its special away from the
zones. Report positions that feel wrong as "higher / lower / further forward".
