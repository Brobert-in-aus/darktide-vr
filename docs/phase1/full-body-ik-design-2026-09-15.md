# Full-body IK on the player's own character: design (15 September 2026)

Status: design only; nothing is implemented. Todo item 8 in
[todo-2026-09-15.md](todo-2026-09-15.md). This builds on and partly revises
the [whole-body IK design of 14 September](whole-body-ik-design-2026-09-14.md)
(revisions listed at the end). It shares its shoulder estimate with the
[two-hand aim and virtual stock design](two-hand-aim-design-2026-09-15.md).

Research notes, with sources and [S]/[I] tags:
[full-body IK](research/full-body-ik-2026-09-15.md) and
[two-handing and virtual stocks](research/two-handing-and-virtual-stocks-2026-09-15.md).

## Goal

Players see their own character in VR, with their cosmetics:
- looking down in first person;
- in the hub's third-person view.

The body is posed by the mod's IK from the headset and both controllers.
Gameplay, hit detection, networking and what other players see stay stock.

## What industry practice says (summary)

- **Show the body only where tracking supports it.** Shipped titles either
  show hands only (Half-Life: Alyx, RE4 VR in first person) or make the body
  optional (Contractors, Rec Room). Meta shows no legs in first person. Mods
  that convert flat games show full bodies anyway: FRIK (Fallout 4 VR), VHVR
  (Valheim) and Doom 3 BFG VR. Players accept this when it is optional.
- **The camera is the headset.** The body follows the camera and never moves
  it. No shipped title or working mod moves the view from the body, except
  options explicitly labelled as sickness risks.
- **Hybrid: IK for the upper body, stock animation for the legs.** VHVR, the
  closest analogue to this project, runs VRIK with locomotion weight 0 and
  lets Valheim's own animation move the legs. FRIK and Doom 3 BFG VR use
  procedural legs and report foot sliding and torso distortion.
- **Closed-form heuristics, not iterative full-body IK or learned models.**
  - Body yaw: head yaw blended toward the hands.
  - Neck: hangs from the eye.
  - Torso: pitch grows with crouch depth.
  - Arms: two-bone IK with heuristic elbow poles.
  - Sources: VRArmIK (Parger et al. 2018), FRIK, Quake VR.
- **Hide locally what sits at the eyes.** Head bones scaled to zero or head
  and headgear meshes hidden, for the local view only (VRChat, FRIK). Also
  hide anything within about 15-25 cm of the eyes.
- **One shoulder estimate for the body and the stock.** Quake VR's stock and
  VRArmIK both derive the shoulder from a body anchor on body yaw, not raw
  head yaw.

## How the body works today

Mapped from the code on 15 September. `DT` = `darktidevr.lua`,
`BP` = `darktidevr_body_proxy.lua`; line numbers are approximate.

### The four units involved

| Unit | What it is | Who animates it | What the mod does to it |
| --- | --- | --- | --- |
| **Gameplay avatar** (the 3P player unit) | The full character with every cosmetic slot. The server and other players simulate and see this unit. | Stock animation state machine, driven by the sim (velocity, crouch, actions, `aim_direction`) | In body modes: renders with a first-person camera (`_update_first_person_mode` returns 3P equipment with a 1P camera, DT:11306-11321). Hides body slots per mode. Writes `j_lefthand`/`j_righthand` so the **weapon units, which stay parented to these hands**, follow the tracked grips (`sync_equipment_hand_pose`, DT:9189-9241). Writes `j_rightweaponattach` for gun aim and restores it each update. Zeroes the look animation variables and the stock idle full-body layer. |
| **First-person unit** | Darktide's floating first-person arms rig with its own weapon units | Stock first-person animation | Hidden and never written. Read as the untouched authored pose: the two-hand authored grip, `follow_gameplay_hands` during stock melee, grenade aim. |
| **Rigid gloves** (default "hands" mode) | Two `UIProfileSpawner` units from the player's profile, with only a one-sided **human** glove item (`hmn_gloves_b_{left,right}_only`) | Nobody (spawner stopped at ready) | Root placed so `j_*hand` lands on the tracked grip. Fingers copied from the avatar. Colliders off. |
| **Upper-body proxy** (flag `darktidevr_full_body_experimental.flag`, off) | One `UIProfileSpawner` unit with arms, torso, upper-body gear and extra cosmetic; no head or legs | Spawner stopped at ready (its own timeline moved `j_hips` 21-25 cm); 16 spine, neck, head and arm joints copied from the avatar each frame | The full IK chain in `apply_body_ik` (DT:10287-10505): height, heading, crouch, neck pivot, torso, shoulders, arm length, shoulder reach, both arms. Then `sync_equipment_hands_to_proxy` moves the avatar's hands (and so the weapons) onto the proxy hands. |

### Visibility per mode

- **Hands (default).**
  - Avatar: only the wielded weapon and companion gear are visible; body,
    arms and upper-body gear are hidden (`hides_source_slot`).
  - Gloves: from the rigid glove units.
  - First-person unit: hidden.
- **Upper-body proxy.**
  - Avatar: arms, torso, upper-body gear and extra cosmetic are hidden. Head
    and face slots are hidden in first person (`headless_body_hidden_slot_lookup`:
    face, tattoo, scar, facial hair, make-up, hair, eye colour, `slot_gear_head`).
    The legs (`slot_body_legs`, `slot_gear_lowerbody`) stay on the avatar with
    stock animation.
  - Proxy: visible.
- **Hub third person** (`hub_third_person` option).
  - No proxy, no gloves, no IK: the stock avatar with the stock orbit camera.
  - Weapon, curio, pocketable and device units are hidden.
- **Cutscenes.** The avatar is hidden if the stock visibility system hides it.

### Camera

- **Stereo origin.** `body_camera_anchor(player_unit)` (DT:4911-4979) stores
  the model-eye offset once, in upright states, in the immutable scene basis
  with lateral X forced to 0. Body and shoulder writes can move only the
  avatar, never the camera.
- **Head tracking and roomscale** are added on top.
- **Result.** The camera is already independent of the body, which is the
  comfort rule the research asks for.

### Shoulder, heading and calibration

- **`body_visual_yaw`.** Written only by `apply_body_heading` (30° dead zone),
  which runs only on the full-body branch. In hands mode it stays nil, so the
  virtual stock never engages and the pose trace's `body_yaw` is empty.
- **Shoulder estimates.** Two exist, and neither is shared:
  - the full-body shoulder reach (rig joints);
  - the holster zone `shoulder_right`, a fixed eye-relative offset.
- **Calibration** `vr_calibration_v1` (schema 4): T-pose, sides,
  `floor_eye_height`, `hand_span`, seated. Humans keep world scale 1; the
  visual scale is only reported.

### What other players see

- **Stock animation of the gameplay avatar.** The only replicated VR datum is
  `aim_direction`, written server-side for the local unit. It drives the stock
  aim constraint, so remote players see the character pointing where the
  dominant hand aims.
- **Local only.** Everything else: gloves, proxy, hand and attach node writes,
  hidden slots.
- **Networked IK** between modded players is a separate study
  ([networked-vr-ik-feasibility.md](networked-vr-ik-feasibility.md)): a
  versioned side channel sending targets, not bones.

### Known problems carried into this design

- **Layering on stock animation clashes.** The hub gait rebuilt the upper
  chain before each solve, giving alternating hand poses and a sliding body.
  User decision, 13 September: layering "clashes too often to finish".
- **Cosmetic sleeves are part of the torso meshes.** Arms can't be shown
  without the torso; stretched proxy arms elongate cuffs.
- **Gloves are human-only.** The glove item is hard-coded human, including on
  Ogryn.
- **Weapons live under the avatar's hands.** Anything hanging off the
  avatar's animated nodes rather than its hands is left where the stock
  animation puts it. The stray cartridge by the right glove (todo item 5) is
  probably one of these; it disappears during reloads.

## Design

### Which unit carries the visible body

Two ways to show the stock model with the mod's IK:

| | A. Pose the gameplay avatar directly | B. A full-profile presentation proxy (**chosen**) |
| --- | --- | --- |
| Cosmetics | all, already there | all: the spawner builds every body and gear slot from the profile |
| Animation contention | overwrite after the stock animation update every frame; the upper-chain layering failure returns | none: the proxy has no state machine, and the mod writes every joint |
| Gameplay side effects | hit actors, the camera eye anchor and weapon attach nodes hang off the same bones | none: colliders off, not networked |
| Legs | stock | copied from the avatar (below) |
| Cost | none extra | one extra skinned character (the upper-body proxy already costs most of this) |

- **Choice.** B, as on 14 September, but with the *whole* profile: head,
  face, hair, legs and lower-body gear are added to `retained_slots`.
- **Avatar.** With the proxy ready, the avatar hides every body and gear slot
  locally and keeps only the wielded weapon and companion gear visible.
- **Weapons.** They stay parented to the avatar's hands and follow the proxy
  hands through `sync_equipment_hands_to_proxy`, as now.
- **Fallback.** If the proxy fails or is not ready, the mode falls back to
  gloves.

### Shared body frame (the virtual shoulder)

- **The module.** `darktidevr_body_frame.lua`, specified in the
  [two-hand design](two-hand-aim-design-2026-09-15.md#2-the-shared-shoulder-body-frame).
  One pure module, updated first each frame in every body mode, outputs:
  - `yaw`: head yaw, pitch-safe, biased 0.7 to the hands, ±60° clamp, 20°
    dead zone;
  - `neck`: 7 cm behind and 8 cm below the eye, turning with the head;
  - `crouch` and `pitch`;
  - `shoulder_left` and `shoulder_right` (±0.17 m × scale);
  - `chest`;
  - `valid`.
- **Ownership.** The body frame owns the shoulder. The virtual stock anchors
  to `shoulder_<dominant>`, and the body solver treats both shoulders as
  targets. The data flows one way, from the estimate to the rig, never back.
  So the stock behaves identically with the body off (hands mode) or on, and
  can ship first.
- **Agreement.** The rig's clavicles rotate toward the estimated shoulders
  (limit about 30° up or forward, as VRArmIK does). The arm IK starts from the
  rotated rig shoulder. The rig's shoulder width differs from the estimate by
  its proportions, usually by less than 3 cm on humans. The remaining gap
  shows as the stock butt sitting that far from the drawn shoulder, which is
  accepted. If worn tests show a visible gap, the estimate's lateral term is
  calibrated once from the proxy's bind-pose shoulder width (a one-off
  measurement, still not a per-frame feedback).
- **Replaces.** `body_visual_yaw` is re-derived from `body_frame.yaw` for the
  3P body heading, replacing `apply_body_heading`'s own head-only heading.
  Holsters can later read the same shoulders.

### Solve per frame (proxy)

Runs in the locomotion `post_update` seam after the stock avatar has
animated, as today.

1. **Root.**
   - *Position:* the avatar root, plus the roomscale offset the camera
     already uses, so the body sits under the headset.
   - *Yaw:* `body_frame.yaw`.
   - *Scale:* humans 1 (the visual scale is only reported); Ogryn keeps its
     calibrated scale.
2. **Legs: copy from the avatar (hybrid, VHVR pattern).**
   - Copy local rotations for `j_hips`' leg chains (`j_*upleg`, `j_*leg`,
     `j_*foot`, toes) from the stock avatar.
   - The avatar's leg animation already follows sim velocity, crouch, sprint,
     slide, jump and turning, and other players see it too.
   - **This does not reintroduce the clash:** only the *legs* are copied, and
     the mod never writes those joints, so there is no contention.
   - **Pelvis:** height from `body_frame.crouch` (0.8 × head drop, as on 14
     September), blended with the avatar's crouch state so a crouch button
     press also crouches. The legs are then re-solved from the copied pose to
     their copied ankle positions with the existing `solve_body_leg`, so the
     feet stay where the stock animation planted them when the pelvis drops.
   - **Fallback:** procedural gait (14 September design, section 6) only if
     worn tests show copied legs fighting the tracked torso, for example
     turning in place without root rotation.
3. **Spine.**
   - Bend from the pelvis to `body_frame.neck` over `j_spine`, `j_spine1`
     and `j_spine2` (20/30/50 %), leaning by `body_frame.pitch`. Twist toward
     `body_frame.yaw`.
   - Limits: 45° forward, 20° back, 25° lateral, 40° twist. These carry over
     from 14 September.
4. **Neck and head.**
   - `j_neck` takes 40 % and `j_head` 60 % of the head's rotation relative
     to the chest.
   - The head joint's position is left where the chain puts it; the camera
     never follows it.
5. **Clavicles.** Rotate `j_leftshoulder` and `j_rightshoulder` so the upper
   arm roots move toward `body_frame.shoulder_*`, within 30°. Then the
   existing shoulder reach adds protraction near full extension.
6. **Arms.**
   - `apply_body_arm_ik` as today: native two-bone solve, anatomical hand
     basis, swing-twist roll with the forearm roll joints, and translation of
     the residual.
   - Pole: VRArmIK's elbow-angle heuristic (135° base, dropping as the hand
     rises; soft clamp 13-175°).
   - Past 2 × arm length, or when tracking is lost, the arm blends to the
     avatar's animated arm (FRIK's give-up rule) instead of stretching.
7. **Hands and fingers.**
   - Fingers are copied from the avatar's grip, as now.
   - The support hand uses the two-hand socket blend (`place_support_hand`)
     unchanged.
8. **Equipment.** `sync_equipment_hands_to_proxy` moves the avatar's hands,
   and so the weapons, onto the proxy hands, as now.

### What the player sees in first person

- **Head.** The head, face, hair and headgear slots are hidden on the proxy
  for the stereo view, reusing `headless_body_hidden_slot_lookup`. Hiding
  is chosen over scaling the head bone to zero: hoods and collars skinned to
  the neck would collapse into the view.
- **Near-eye meshes.**
  - Once per cosmetic change, each retained mesh's bind-pose box centre is
    measured against the model eye.
  - Meshes whose box sits within 0.20 m of the eye and above the shoulder
    line (hoods, high collars, pauldron tips) are hidden in first person.
  - The list is logged (`DARKTIDEVR_BODY near_eye_hidden=`) so a worn test
    can name wrong ones.
  - `Mesh.box` gives bind-pose centres only, which is enough for a
    per-cosmetic decision.
- **Stock-owned states.** The whole proxy blends to the avatar's animated
  pose over 0.2 s:
  - ledge hanging, climbing and vaulting;
  - knocked down, netted, pounced, grabbed, consumed, catapulted;
  - carried and dead;
  - interaction animations and emotes.

  Unknown states default to stock, as in the 14 September table. In
  cutscenes the proxy hides with the avatar.
- **Stock melee.** Sweeps, pushes, blocks and windups keep today's rule:
  arms follow the first-person animation (`follow_gameplay_hands`), and the
  torso and legs are still solved.

### Seeing your character (third person)

- **Hub third person.**
  - The hub third-person view today shows the stock avatar with no IK.
  - With full body on, the orbit camera shows the IK proxy instead:
    the tracked arms and head, with legs from the stock animation.
  - Players can see their cosmetics moving with them.
- **Psykhanium and missions.** The proxy is visible when looking down, plus
  in the eye-readback test renders (a debug camera behind the player behind a
  flag file, for unattended checks).

### Options

- **Body presentation (`vr_body_presentation`).** Replaces the flag file:
  - *hands* (default, today's gloves);
  - *full body (experimental)*: proxy with IK, hub and Psykhanium first;
  - later, *arms and torso* (full body with the legs hidden) for players who
    dislike seeing legs.
- **Hub third person.** Shows the IK proxy when full body is on.

## Milestones

1. **Body frame module.** Shared with two-handing: pure tests, shoulder
   markers behind a flag. Serves the virtual stock first.
2. **Full-profile proxy, no IK.**
   - Spawn every slot. Copy *all* joints from the avatar each frame. Hide
     the avatar's body slots.
   - Check: in the eye readback and a hub third-person render, the proxy
     looks identical to the stock character: cosmetics complete, weapons in
     hand, no double body.
   - Decides the rest pose question (bind or animated first frame).
   - Scan the Ogryn rig through the spawner in the Psykhanium.
3. **Upper-body solve from the body frame with copied legs.**
   - Offline invariants on synthetic and recorded pose traces (bone lengths,
     no elbow flips, joint limits, continuity). These are the 14 September
     list.
   - Add the `calibration id` column the recorder is still missing.
4. **First-person hiding** (head slots and near-eye meshes) and stock-state
   blends.
5. **Worn tuning:** looking down, crouch, lean, two-handed gun with the stock,
   melee, hub third person.
6. **Procedural legs** only if copied legs fail milestone 5. Ogryn support.
7. **Networked pose** (separate feasibility study).

## Milestone 1 results: rig scan (15 September afternoon)

Run `artifacts/unattended/rig-scan-20260915/scan1` with the dev flag
`darktidevr_rig_scan.flag` (`darktidevr_rig_scan.lua`). It spawned two
characters with the body proxy's `UIProfileSpawner` in the Psykhanium: the
player's Skitarius (archetype `cryptic`) and the stock Ogryn bot profile
`darktide_seven_02`.

- **Same joint names and hierarchy.** The Ogryn rig (220 nodes, against 246
  for the human) has every joint in the map under the same parents. Neither
  base rig has `j_spine3`, `j_lefteye` or `j_righteye`; the eyes are on the
  face attachment, as `body_stable_eye_anchor` already assumes. One joint
  map serves both; the Ogryn needs its own lengths, not its own names.
- **Proportions (first frame, Ogryn over human):**
  - upper arm 2.8×, forearm 2.3×, legs 1.2-1.4×;
  - spine segments 1.3-3.5× (`j_spine1` 0.236 m against 0.079 m);
  - head 2.47 m against 1.49 m above the root.

  The solver must read bone lengths from the rig; ratios from the human
  are not usable.
- **The spawner's first frame is not a stable rest pose.** With the spawner
  no longer updated, joints still moved over 30 frames:
  - human: up to 3.7 cm at the right hand and 0.6 cm at the hips;
  - Ogryn: up to 5.3 cm at the left hand and 1.2 cm at the hips.

  The spawned unit keeps animating on its own.
- **Stopping the animation freezes it (`scan2`, `344945e`).** Calling
  `Unit.disable_animation_state_machine` on the first ready frame kept every
  mapped joint of both rigs exactly still (0.000 m from the first frame to 60
  frames later).
  - *Plan for milestone 2:* spawn the full profile, disable the state machine
    at once, and capture the rest pose (bone lengths, neutral local
    rotations) from that frame.
  - *Caveat:* that frame is the spawn pose, possibly an idle frame rather
    than the true bind pose. It is stable, which is what the solver needs;
    neutral rotations may want a one-off correction if the arms are not
    relaxed.
- **IK handles** (`j_*_ik_handle`, `j_hips_handle`) sit at the root with no
  mapped parent and zero length on both rigs. `j_hips` hangs from
  `j_hips_handle`.

## Milestone 2 check: body mirror (15 September afternoon)

Commit `3d3d788`, dev flag `darktidevr_body_mirror.flag` (`darktidevr_body_mirror.lua`),
run `artifacts/unattended/body-mirror-20260915/mirror1`.

- **What it does.**
  - Spawns the player's whole profile: body, gear and material slots, plus
    `slot_unarmed` for the spawner, and no weapons, gadgets or companion.
  - Disables its animation state machine on the ready frame.
  - Copies every joint's local pose from the gameplay avatar each frame,
    after the mod's hand writes.
  - Stands 2.5 m ahead facing the player.
- **Results.**
  - 26 slots spawned (28 ignored).
  - Both units have 246 nodes and the same layout, so joints map by index.
  - Right hand local error 0.000000 m over 4,500 frames; no script errors.
  - Eye renders show the complete Skitarius facing the camera (hood, lit
    eyes, armour, robe, legs), with its pose following the avatar between
    captures.
- **Next (milestone 2 proper).**
  - Put this unit where the body is, instead of 2.5 m ahead, behind the
    existing experimental full-body flag, and hide the avatar's body and
    gear slots.
  - Weapons stay on the avatar hands, synced to the proxy hands as today.
  - Hide the head and near-eye meshes locally.
  - Then replace the plain joint copy with the solver (milestone 3).

## Changes from the 14 September design

- **Legs.** Copied from the stock avatar (hybrid) instead of procedural first.
  - *Research basis:* VHVR's working hybrid, and the foot sliding and torso
    distortion reported by the procedural mods.
  - *Why it is safe:* the clash the user rejected was in the upper chain.
- **Visible body.** The proxy keeps the **whole** profile (head and legs
  included), hidden per view, instead of an upper body over stock legs.
- **Shoulder and heading.** They come from the shared body frame instead of
  the body solve's own pelvis yaw and shoulder reach, so the stock and the
  body agree.
- **Head.** Hidden by slots plus a near-eye mesh check, instead of scaling the
  head bone.

## Risks and open questions

- Copied stock legs under a tracked torso might look wrong when the player
  turns physically while the avatar root does not. Milestone 5 decides, with
  procedural legs as the fallback.
- Draw calls and memory for a second full character. Measure against the
  `DARKTIDEVR_IK_PERF` budget (under 0.3 ms Lua) and the frame time.
- Stock attachments hanging off the avatar's animated nodes (the stray
  cartridge) have to be classified. Anything not under the hands must either
  move to the proxy or be hidden.
- The Ogryn rig and glove are unverified.
- For the user: is *arms and torso* (no legs) worth offering? And should hub
  third person show the IK body by default when full body is on?
