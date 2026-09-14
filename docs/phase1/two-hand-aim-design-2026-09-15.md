# Two-handed aim and the virtual stock: design (15 September 2026)

Status: design. Nothing here is implemented yet, except the offline
measurement in "Why the right hand feels off". Todo item 7 in
[todo-2026-09-15.md](todo-2026-09-15.md). The full-body design (item 8) shares
its shoulder estimate; see
[full-body-ik-design-2026-09-15.md](full-body-ik-design-2026-09-15.md).

Research notes, with sources and [S]/[I] tags:
- [two-handing and virtual stocks](research/two-handing-and-virtual-stocks-2026-09-15.md)
- [full-body IK](research/full-body-ik-2026-09-15.md)

## The worn report

From the 14 September evening test:
- Moving the **left** hand while two-handing feels good.
- Moving the **right** (dominant) hand "feels off".

## How two-handed aim works today

`darktidevr_two_hand_pose.lua` and `darktidevr_two_hand_support.lua` compute
the aim in five steps.

1. **Dominant aim.** The controller's aim rotation, passed through the
   adaptive angular damping in `darktidevr_weapon_stabilization.lua`, then
   pitched by `vr_gun_pitch` (`gun_aim.base_aim`). This is `q`.
2. **Hands line.** The support hand's position relative to the dominant grip,
   taken into `q`'s frame. `Pose.correction` returns the **smallest rotation**
   that turns the weapon's support socket (the authored left-hand grip, about
   0.33 m ahead on the galvanic rifle) onto that line. Twist about the barrel
   is left alone, so roll comes from the right wrist.
3. **Filter.** `Pose.new().update` slerps the stored correction toward that
   target with a time constant of `smoothing` = 0.07 s. The correction is a
   rotation **in the controller's local frame**.
4. **Result.** The aim is `q × correction`, used for both the gun and the
   reticle (`gun_aim.aim`). The gun's origin stays at the dominant grip.
5. **Stock.** An optional anchor (`Pose.stock_correction`, `new_stock_anchor`)
   exists but never engages. No stock profile ships, and `body_visual_yaw` is
   nil in the default hands-only body mode, so `snapshot` never gives the
   stock its body inputs.

Steps 1-2 match what VRExpansionPlugin `GS_GunTools`, FRIK and Unity XRI do
(origin at the dominant grip, dominant rotation as the base, minimal swing
toward the support hand). The research notes' first guess, that the mod
discards the dominant hand's rotation, was based on the todo's wording and is
wrong.

## Why the right hand feels off

The difference is step 3.
- **Where the others filter.** VRE filters the support-hand *point* in world
  space before computing the swing.
- **Where the mod filters.** The mod filters the *correction* after computing
  it, in controller-local space. A local-space correction rides along with
  the wrist.

So when the dominant wrist rotates, the whole gun turns with it immediately.
The support socket leaves the left hand, and the filter then pulls the barrel
back onto the hands line over about 0.2 s. A left-hand move never does this:
it only changes the target, which the barrel follows with a short lag.

**Offline measurement** (current `darktidevr_two_hand_pose.lua`, 90 Hz,
smoothing 0.07 s, both hands still, socket 0.33 m ahead; scratch script, not
committed).

A 10° right-wrist yaw with both hands still. Angle between the barrel and the
hands line:

| frame after the turn | 1 | 2 | 3 | 5 | 10 | 15 | 20 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| barrel off the line (deg) | 8.53 | 7.28 | 6.21 | 4.52 | 2.04 | 0.92 | 0.42 |

The right hand moved 2 cm sideways with the wrist still (target swing
3.47°). How far the barrel lags behind that target:

| frame after the move | 1 | 2 | 3 | 5 | 10 | 15 |
| --- | --- | --- | --- | --- | --- | --- |
| lag behind the target (deg) | 2.96 | 2.52 | 2.15 | 1.57 | 0.71 | 0.32 |

A real right-hand move always carries some wrist rotation, so it gets both
effects:
- the barrel first follows the wrist off the left hand and swims back;
- it then lags behind the new hands line.

On top of that, the dominant rotation has already been damped once in step 1.

A second, geometric effect makes the right hand more sensitive whatever the
filter does. The gun pivots at the right grip, so lateral right-hand noise is
amplified by the short baseline. At 0.33 m, 1 cm of drift turns the aim 1.7°.
A real rifle has a third contact point, the shoulder, which is what a virtual
stock supplies.

## Design

### 1. Filter the hands line, not the correction

The per-frame aim becomes:

```
q      = dominant aim (as today: stabilised, pitched)
line_t = support - primary, in tracking space (inverse scene-basis rotation)
line_f = filter(line_t)                -- direction filter, tracking space
target = Pose.correction(q, primary, primary + scene(line_f), socket)
aim    = q × target                    -- recomputed every frame from q
```

- **The correction is recomputed from the current `q` every frame.** A wrist
  rotation therefore never swings the socket off the support hand. Wrist roll
  still twists the gun about the barrel, and wrist pitch or yaw does nothing
  while two-handed (the hands line decides direction), as in VRE and FRIK.
- **The filter runs on the hands-line direction in tracking space** (the
  controllers' own space, before the scene basis). Stick turning, walking and
  root motion move both hands together through the scene basis, so they are
  never delayed. Only the physical hand motion is smoothed.
- **The filter is a One Euro filter** on the unit direction (component-wise,
  renormalised), with a speed-dependent cutoff:
  - slow micro-adjustments are smoothed, fast swings pass through;
  - starting values from Casiez's tuning procedure: `min_cutoff` 1.5 Hz,
    `beta` 0.5 (per metre per second of the normalised line's derivative),
    `d_cutoff` 1 Hz;
  - tuned by an offline trace and a worn check.
- **Grip, release and gates stay as they are**: the zone snap, the
  hold/toggle mode, `retain=true`, and the guards for hands too close (8 cm)
  or crossed (dot < -0.95).
- **Dominant-rotation damping** (`weapon_stabilization`) still applies to
  roll. While two-handing it no longer adds lag to direction, because
  direction comes from the hands line.

Optional, later: a **support weight** `w` that fades the swing when the
support hand strays far from the socket. VRE fades from 50 cm to 100 cm. With
`retain=true` and any hand spacing, a hand pulled away 60 cm still steers,
which is what the user asked for (13 September), so `w` stays 1 unless a worn
test asks otherwise.

### 2. The shared shoulder (body frame)

The stock needs a shoulder, and full-body IK needs the same shoulder. One
pure module owns it: **`darktidevr_body_frame.lua`**. It has no engine calls
and is tested offline. It is updated once per frame in the locomotion
`post_update` seam, before two-hand `prepare` and before any body IK, in
**every** body mode (hands-only included).

Inputs (all already available):
- head pose in tracking space and the recenter generation;
- both grip poses with tracking flags;
- the scene basis (`body_anchor_q*`);
- the avatar root position;
- calibration: `floor_eye_height`, `hand_span`, standing or seated;
- the dominant side;
- crouch input and character state.

Outputs, in tracking space and world space:

| Output | Computation (starting values) | Source |
| --- | --- | --- |
| `yaw` | Head yaw, pitch-safe past ±50° (blend forward toward up/down by pitch/90). Biased 0.7 toward the mean head-to-hand direction when both hands are tracked and in front. Clamped to ±60° of head yaw. Low-passed (0.15 s) outside a 20° dead zone. | Quake VR, FRIK, VRIK `maxRootAngle` |
| `neck` | eye + head rotation × (0, −0.07, −0.08) × s: 7 cm behind and 8 cm below the eye, turning with the head | VHVR head offset (−0.165 down, −0.09 back), VRArmIK |
| `crouch` | clamp(1 − eye height / standing eye height, 0, 1) | Quake VR |
| `pitch` | forward lean = 105° × crouch + 0.1 × head pitch, ≤ 45° | FRIK, VRArmIK |
| `shoulder_left`, `shoulder_right` | neck + (yaw, then lean) × (±0.17 × s, 0, −0.08 × s). Eye to shoulder totals about 16 cm down and 7 cm back. s = floor eye height / 1.62 m; the lateral term also uses `hand_span` when calibrated | Daydream (±0.17, −0.20), VRArmIK |
| `chest` | midpoint of the shoulders, 0.10 × s down | [I] |
| `valid` | head tracked and eye height plausible (0.8-2.4 m) | existing guards |

- **Frames.** Offsets are in a body basis of x right, y forward, z up. The
  holster zones already use eye-relative coordinates in that basis.
- **Owner.** The body frame module owns the shoulder. Two-handing reads it,
  and so does full-body IK once it exists. The rig adapts to the estimate,
  never the other way round: the proxy's clavicles are rotated toward it (see
  the full-body design). A body solve never feeds back into the shoulder, so
  the stock behaves the same with the body on or off.
- **Head yaw and lean.** Glancing sideways barely moves the shoulder: the
  hands bias the yaw and the dead zone holds it. A real torso lean or crouch
  moves the neck, because the neck hangs from the eye, so the shoulder follows
  the lean.
- **Existing field.** `body_visual_yaw` keeps its meaning for the 3P body
  heading. The stock stops depending on it.

### 3. Virtual stock

Built on the existing `Pose.stock_correction` (primary grip never moves; aim
slerps toward shoulder-to-support):

- **Anchor.** The dominant `shoulder` from the body frame, plus a
  user-adjustable pocket offset (default 0.03 m inward, 0.02 m forward) and a
  side flip for cross-eye-dominant players.
- **Rear contact** (`profile.stock.offset`). The butt relative to the primary
  grip in the aim frame.
  - Measured once per weapon template from the 3P weapon unit, the same way
    authored grips are: the rearmost node or mesh bound behind the grip.
  - Fallback default (0, −0.24, 0.03) for guns without a stock node.
  - Pistols and stockless guns (autopistol, revolver, laspistol, plasma gun,
    flamers) get no stock.
- **Engage.** The butt comes within 0.12 m of the anchor while both hands
  grip. The weight ramps as proximity² (existing), with strength 1 inside
  0.05 m.
  - VRE measures the *dominant hand* within 35 cm, blended over 20 cm. The mod
    measures the butt instead, which is tighter and more physical.
  - Worn tuning picks between the two.
- **Aim while engaged.** Direction is the shoulder anchor to the filtered
  support point. The baseline roughly doubles (about 0.6 m). Lateral
  right-hand noise stops steering, and right-wrist roll still cants the gun.
- **Release.** The weight falls with distance; there is no latch beyond the
  existing contact-yaw latch. It is released at once on grip release or any
  guard.
- **Options** (default off, per the brief). A new option `vr_virtual_stock`
  with values off, auto (distance) and while ADS. Sub-options: pocket offset
  (lateral, vertical) and side.

### 4. Sights and the eye (links todo item 4)

- **Stock height.** Once stocked, the sight line should pass through the
  dominant eye. The butt-to-sight height of each weapon (rear sight or optic
  node above the butt line) sets how high the anchor sits relative to the eye.
  A wrong value shows up as having to hold the head low or high.
- **Crosshair.** The crosshair misalignment reported with the galvanic rifle
  is measured separately (item 4). If it is a fixed sight-over-bore height,
  that is parallax, not a fault. The stock design relies on the same
  sight-line measurement.

## Rollout and tests

1. **Filter change behind an option.** `vr_two_hand_steadying`: *classic*
   (today, the default) or *hands line*.
   - Pure tests in `test-two-hand-pose.lua`: a wrist yaw with still hands
     keeps the barrel on the hands line (≤ 0.1° off on every frame); stick
     turning with both hands moving together is not delayed; fast swings pass
     within 2 frames; roll follows the wrist; the too-close and crossed guards
     still hold.
   - Unattended: the synthetic once path's two-hand hold shows steering in
     `DARKTIDEVR_TWO_HAND released ... max_steer_degrees`.
   - Worn A/B, right hand moving: classic against hands line.
2. **Body frame module.** Pure tests: yaw stays within 20° while the head
   glances 40° with hands forward; crouch lowers the shoulders; recenter
   resets; seated mode. A debug marker at each shoulder behind a flag file,
   checked with an eye readback.
3. **Virtual stock** on the body frame, with per-template butt offsets. Worn
   A/B: hands line against hands line plus stock.
4. **Full-body IK** reads the same shoulder (see its design).

## Open questions for the user

- After the A/B, should *hands line* become the default for two-handing?
- Should the stock engage by distance (auto) or only while ADS is held?
- Is a "breath hold" (extra smoothing while a button is held, as in Into the
  Radius) wanted on a gripping-layer binding?
