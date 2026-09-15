# Arm length from the height and arm calibration: design (16 September 2026)

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
  offset and the rig's own shoulder width; split it 56/44 upper arm to
  forearm; aim about 3 % short.
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
- S = the rig's shoulder joint distance in world space, after the body's
  uniform scale; not the body frame's 17 cm estimate.
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

## Open questions for the user

- Recalibrate with the new T-pose guidance once it is built. The current span
  looks short, and every derived length follows it.
- Whether the overlay's scale-to-neck should be reduced in favour of true arm
  lengths. The copy is enlarged 17-24 % to bring its neck to the camera, which
  also lengthens its arms and hands.
