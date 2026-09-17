# Arm length from the height and arm calibration: design (16 September 2026)

Status (18 September 2026): **open, and the next real step for the body.**
The calibration records the span and its T-pose problems and the derivation
is unit-tested, but the lengths are applied only in the dev mode
`overlayarmlength`; the shipped "Full body" still scales the whole copy
uniformly until its neck reaches the head, which enlarges it 17 to 24 per
cent and its arms with it. Step 3 of this document is what would replace
that. See the 18 September detailed list, section C.

User request, 16 September: use the height and arm calibration to set arm
length properly, following industry practice; do not re-enable the old
arms-forward reach pose unless practice recommends it. Research and sources:
[research/arm-length-calibration-2026-09-16.md](research/arm-length-calibration-2026-09-16.md).
Context: [full-body IK design](full-body-ik-design-2026-09-15.md) (milestone 3
results) and the [animation audit](animation-audit-2026-09-16.md).

## Summary

- **Keep the two-pose calibration** (standing eye height, T-pose, arms at
  sides). This matches shipped practice (VRArmIK, Meta's T-pose wrist
  retargeting, VRChat arm span). **The arms-forward reach pose stays out:**
  no product or framework surveyed captures one.
- **Tighten the T-pose capture:** guide full, level extension; take the
  largest span in a short hold instead of the mean; check the span against
  the span predicted from eye height and ask for a retake when it is far
  short.
- **Derive shoulder-to-wrist reach** from the grip span, the wrist-to-grip
  offset and the player's shoulder width (estimated from eye height; the rig's
  own shoulders remain the solve anchors); split it 56/44 upper arm to forearm;
  aim about 3 % short.
- **Apply it by moving the forearm and hand bones along their axes** (as VRIK
  and FRIK do), never by scaling bones, and after any uniform body scale,
  within a clamp.
- **At runtime:** clavicle protraction up to about 8 % of arm length near full
  reach, then a soft stretch, as FRIK and VRIK do, backed by the CHI 2024 study.
- **For this player the measured span looks under-extended** (below), and
  the overlay copy's arms are already about 10-35 % longer than the
  calibration asks for, because the copy is scaled up to reach the camera's
  neck height. Arm length therefore has to be set after that scale, and the
  reach failures seen in the milestone 3 runs are not caused by arms that are
  too short.

## What the mod has today

- **Capture** (`darktidevr_calibration_view.lua`, schema 4): 45 frames per
  pose, rejected if tracking spreads more than 15 mm.
  - Poses: T-pose, then arms at sides.
  - Positions: controller **grip** positions and the head, in recentred
    OpenXR metres.
  - Saved: `floor_eye_height`, `hand_span` (grip to grip in the T-pose), both
    poses.
  - Seated and single-arm modes exist.
- **Height:** eye height sets the official character height (backend range),
  with a client-only visual stretch for humans
  (`calibrated_character_scale`).
- **Arm length:** `apply_calibrated_arm_length` (`darktidevr.lua`):
  - reach = head-to-grip distance in the T-pose, minus half the rig's
    shoulder width;
  - scales the forearm and hand joints' local positions by desired over
    current length, clamped to 0.90-1.10;
  - runs only on the older full-body proxy path. The body mirror overlay
    (milestone 3) does not use it.
- **Shoulder reach:** the proxy path's shoulder solver lets the clavicle
  protract up to 18 % of arm length from 86 % extension. The overlay has its
  own clavicle swing toward the body frame shoulders (capped 30 degrees).
- **The arms-forward pose** (schema 3) was removed on 12 September
  (`b2125d5`) because no presentation used it, not because it measured badly.

## This player's calibration

Saved result: eye height 1.725 m, grip span 1.506 m. T-pose grips, relative
to the head:
- left: 0.732 m out, 0.149 m forward, 0.136 m down;
- right: 0.770 m out, 0.050 m forward, 0.152 m down.

- **Predicted from eye height [ANSUR calc]:** stature ≈ 1.725 / 0.935 =
  1.845 m; grip span ≈ 1.008 × 1.725 - 0.107 = **1.632 m** (residual SD
  4.4 cm).
- **Measured span:** 12.6 cm short, about 2.9 SD. The hands were forward of
  the head (up to 15 cm on the left) and slightly above shoulder height (about
  22 cm below the eye predicted, 14-15 cm measured). Arms angled forward, not
  fully extended, is the likely reading. This is the usual T-pose error the
  research names.
- **Shoulder joint to wrist:**
  - from the measured span: (1.506 - 2 × 0.065 - 0.36) / 2 = **0.51 m**;
  - from the predicted span: **0.57 m**;
  - from height ratios (surface landmarks, which overshoot): about 0.61 m.
- **Rig, for comparison:**
  - native arms 0.275 + 0.275 m;
  - about 0.59 m at the character's visual scale (1.07);
  - **0.69 m** in the overlay copy after `scale_to_neck` (1.17-1.24), which
    enlarges the whole body until its neck reaches the body frame's neck.

## Proposal

### 1. Capture (calibration view)

- Keep the stages. For the T-pose: instructions to hold the arms straight out
  to the sides at shoulder height, palms down, controllers pointing
  outward.
- Record about 1 s and use a high percentile (90th) of the grip-to-grip
  distance rather than the mean, since under-extension is the common error.
  Keep the 15 mm spread check for the arms-at-sides pose.
- Sanity checks, each with a retake prompt that names the problem:
  - the two grips differ in height by more than 10 cm;
  - either grip is more than 15 cm below the predicted shoulder height
    (0.87 × eye height);
  - the grips are more than 15 cm forward of the head;
  - the span is more than about 11 cm (2.5 SD) short of the span predicted
    from eye height.
- Show the measured and expected spans on the result page, so a short
  capture is visible.
- Seated: the span is still measured; without a standing eye height, use
  the last standing calibration's height, or none.
- No arms-forward pose.

### 2. Derivation (pure module, tested)

- wrist = grip - grip forward × 0.065 m (the palm centroid to the wrist;
  measure once per controller model, Touch first). The existing
  `body_ik_calibrated_wrist_target` offset can serve as the per-side
  refinement.
- S = the player's shoulder joint width, estimated from eye height (0.34 m at
  1.62 m, scaled). The first design said the rig's width. `armlen3` showed a
  rig scaled to the camera is wider than the player (0.47 m) and that made the
  arms far too short. The rig's shoulders stay the anchors of the solve.
- reach = (span - 2 × 0.065 - S) / 2, times 0.97 so the drawn elbow straightens
  no later than the real one (articular limits research).
- upper arm = 0.56 × reach, forearm = 0.44 × reach, from the ANSUR split and
  Winter's ratios. VRArmIK's 48/52 is the author's own admitted rough value.
- Without a usable span (single-arm or rejected capture): reach from eye
  height with the same regression.

### 3. Application to the drawn arms

- Move `j_*forearm` and `j_*hand` local positions along their current
  direction to the derived lengths, as VRIK's `armLengthMlp` and FRIK do.
  Never scale a bone: that fattens sleeves and armour.
- Order: uniform body scale first (`scale_to_neck` in the overlay), then arm
  lengths, then the clavicle and arm solve.
- Clamp the per-segment ratio to the rig's own length. Default 0.85-1.15; the
  overlay needs about 0.74-0.83 today, so it is the scale-to-neck that should
  give way first (see Open questions).
- Generalise `apply_calibrated_arm_length` to the overlay copy, with these
  inputs instead of the head-to-grip reach. It keeps its cache and recalibration
  reset.

### 4. Runtime reach (overlay arm solve)

- **Anchor on the rig's shoulders.** Calibrate the body frame's lateral
  shoulder term once from the rig's bind-pose shoulder width, as the full-body
  design allows. The milestone 3 A/B found the remaining clavicle gap radial,
  so a larger swing cap does not close it.
- **Clavicle protraction:** move the shoulder up to 6-8 % of arm length toward
  the hand, ramped from 0.9 to 1.1 × reach (FRIK uses 8 %, from 0.5 to 1.35 ×).
  This replaces the swing toward a fixed estimate.
- **Soft stretch** past reach: up to about 20 % of reach (10-12 cm), split by
  segment length (FRIK, VRIK stretch curve; CHI 2024 mean maximum 26 cm).
- **Beyond that:** the research suggests letting the drawn hand lag the
  controller. Here the drawn hand must stay on the weapon, so the wrist keeps
  stretching the remainder, as the overlay does now.
- **Elbow:** keep the current hint and smooth the twist (FRIK: 0.25 per
  frame).

## Validation

- **Unit tests:**
  - span checks against the regression;
  - reach and split;
  - clamp;
  - application order: scale, then lengths, then solve.
- **Unattended runs** (working viewer, synthetic hand path, Psyker and
  Skitarius), compared with `follow3`:
  - unreachable updates;
  - maximum stretch;
  - shoulder gaps;
  - looking-down renders.
- **Worn:**
  - a new calibration with the guided T-pose (does the span land near
    1.63 m?);
  - arms reaching fully forward, up and across while holding a gun;
  - no stretched sleeves.

## First measurement (16 September, run `armlen3`)

`overlayarmlength` on the Psyker, working viewer, synthetic hand path, timed
renders, against `follow3` (`overlay`):

- Derivation: `source=height` (the saved span is flagged short), span 1.632 m.
  The scaled rig's shoulders are 0.471 m apart. Reach 0.50 m, giving upper arm
  0.28 m and forearm 0.22 m. Bone ratios 0.82 upper, 0.70 forearm (at the
  clamp).
- Out of reach: right arm 5,196 of 6,300 updates (`follow3`: 0), left 1,700
  (`follow3`: 1,560). Maximum stretch right 0.16 m, left 0.52 m.
- Render (`armlen3/renders/l4.png`): much like `follow3` looking down; the
  shorter sleeves are hard to judge in the dark robe.
- **Findings:**
  1. Subtracting the rig's shoulder width was wrong. The rig is scaled up
     1.18 to reach the camera's neck, so its shoulders are wider than the
     player's, and the arms came out far too short. Fixed: the reach formula
     now uses the player's shoulder width estimated from eye height (0.36 m
     here). The rig's shoulders stay the solve anchors. That gives reach 0.55
     m, upper 0.31 m, forearm 0.24 m.
  2. The synthetic hand path is not this player's body, so its hand distances
     do not follow the calibrated span. Unattended runs cannot tell whether
     calibrated lengths are right; that needs a worn check with the player's
     own hands.
  3. The rig's shoulders sit about 5 cm further out per side than the player's
     once scaled. With true arm lengths, a hand the player reaches
     comfortably can be out of reach from the wider rig shoulder. The
     scale-to-neck conflict (below) is the root of both this and the long
     arms.

## Protraction and soft stretch (16 September, run `protract4`)

`overlayprotract` (clavicle protraction toward the hand from 0.9 to 1.1 of arm
length, up to 8 %, plus both segments stretching up to 20 % past reach; no
swing toward the estimated shoulder) against `follow3` (`overlay`), 6,300
updates each, Psyker, working viewer, synthetic hand path:

| | `overlay` | `overlayprotract` |
| --- | ---: | ---: |
| left out of reach | 1,560 | 903 |
| right out of reach | 0 | 329 |
| left wrist gap (max) | 0.360 m | 0.174 m |
| right wrist gap (max) | 0 m | 0.001 m |
| shoulder moved (max) | n/a | 0.055 m left, 0.050 m right |
| segments stretched (max) | n/a | 1.200 left, 1.057 right |

- The left arm, the one the synthetic path sweeps furthest, is out of reach 42 %
  less often and its wrist gap halves. The right arm now reports a few hundred
  out-of-reach updates where the swing toward the estimated shoulder had none,
  though its wrist gap stays about zero: the stretch absorbs it.
- The looking-down render (`protract4/renders/l6.png`) shows the gun arm
  without visible sleeve distortion at these ratios.
- Assumption tested in the next run: protraction plus soft stretch replaces the
  swing toward the estimate for the arms. It does not: both together are better
  than either (below).

## Swing with protraction and stretch (16 September, run `both4`)

`overlayboth` (the clavicle swing toward the estimated shoulder **and** then
protraction with the soft stretch), same conditions, 6,300 updates:

| | `overlay` (swing) | `overlayprotract` | `overlayboth` |
| --- | ---: | ---: | ---: |
| left out of reach | 1,560 | 903 | 1,300 |
| right out of reach | 0 | 329 | **0** |
| left wrist gap (max) | 0.360 m | 0.174 m | **0.176 m** |
| right wrist gap (max) | 0 m | 0.001 m | **0 m** |
| shoulder moved (max) | n/a | 0.055 / 0.050 m | 0.055 / 0.023 m |
| segments stretched (max) | n/a | 1.200 / 1.057 | 1.200 / 1.057 |
| clavicle gap closed | 0.171 / 0.209 m | n/a | 0.140 / 0.136 m |

- **Both together win on the measure that shows.** The wrist gap is the drawn
  hand leaving the controller, and it is what a player sees; out-of-reach
  updates only say the solver had to stretch or protract, which the wrist gap
  then shows it absorbed. `overlayboth` halves the left wrist gap against the
  swing alone (0.176 m against 0.360 m, within 2 mm of protraction alone) and
  keeps the right arm always in reach, which protraction alone lost (329
  updates).
- The left arm's out-of-reach count sits between the two (1,300 against 903 and
  1,560): the swing places the shoulder where the frame estimates rather than
  straight at the hand, so full reach is hit sooner, but the protraction and
  stretch behind it close the gap anyway.
- The right arm's shoulder moves less than half as far with the swing in front
  of it (0.023 m against 0.050 m), so the clavicle is doing less work per frame.
- **Decision:** `overlay`, the dev default, now does the swing, protraction and
  the soft stretch together. The swing-only configuration stays available as
  `overlayswing` for A/B.
- Still a synthetic hand path, not this player's arms. The ordering of the three
  is settled; the calibrated lengths behind them are not (steps 3-4 need a worn
  check).

## Open questions for the user

- Recalibrate with the new T-pose guidance once it is built. The current span
  looks short, and every derived length follows it.
- Whether the overlay's scale-to-neck should be reduced in favour of true arm
  lengths. The copy is enlarged 17-24 % to bring its neck to the camera, which
  also lengthens its arms and hands.
