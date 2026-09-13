# Whole-body IK for the third-person body: design (14 September 2026)

Status: design only. Nothing here is implemented or worn-tested. It replaces
the approach of layering tracked arms and torso onto Darktide's own
third-person animation, at the user's direction (13 September): that
layering clashes too often to finish. Todo item: "Custom whole-body IK for the
third-person body" in [todo-2026-09-14.md](todo-2026-09-14.md).

## What exists today (the parts this reuses)

Mapped from the code on 14 September; line numbers are approximate.

- **Proxy rig.** `darktidevr_body_proxy.lua` spawns a presentation-only unit
  with `UIProfileSpawner` from the player's own profile, so the rig follows
  the breed. It keeps only the body, torso and upper-body gear slots, and its
  actors have collision and scene queries off.
  - Once ready, the spawner is no longer updated.
  - Each frame the proxy root copies the gameplay avatar's root.
  - `inherit_authoritative_pose` copies 16 spine, neck, head and arm joints
    from the avatar's animated pose. The proxy's own idle animation had moved
    `j_hips` by 23-25 cm per frame (26 August plan).
- **Hands-only mode (the default).** Two rigid glove units, placed so
  `j_lefthand` and `j_righthand` sit on the tracked grips. The glove item is
  hard-coded human, including on Ogryn.
- **IK path.** `apply_body_ik` runs in the `PlayerUnitLocomotionExtension`
  `post_update` hook, after the stock animation. Its full-body branch (behind
  `darktidevr_full_body_experimental.flag`, off) runs these steps in order:
  1. calibrated height (root scale);
  2. body heading (30° dead zone);
  3. crouch (writes `j_hips`, solves the legs back to their ankles);
  4. neck pivot, torso and shoulder alignment;
  5. calibrated arm length;
  6. shoulder reach (spine rotations and clavicle protraction);
  7. both arms;
  8. equipment hands.
- **Native solver.** `dtvr_solve_two_bone_ik`: 17 floats in, 14 out, with
  flags for clamping and pole fallback. It is in `src/core/two_bone_ik.cpp`
  and tested in `tests/two_bone_ik`.
- **Inputs.**
  - Head pose and floor eye height come from the shared head pose.
  - Controller grip and aim poses come in a Z-up body basis relative to the
    recentered head.
  - The body anchor pose comes from the viewer.
  - Calibration (schema 4) provides T-pose and sides poses, `floor_eye_height`
    and hand span. `calibrated_character_scale` gives the Ogryn scale and the
    human visual scale.
- **Measured rig facts (human).** The live 3P rig has 246 nodes. Upper arm
  and forearm are about 0.275 m authored and 0.261 m animated. Earlier
  shoulder-solver tuning:
  - participation starts at 90 % reach, capped at 12 % of arm length;
  - girdle yaw up to 20°, spread 15/30/55 % over `j_spine`, `j_spine1` and
    `j_spine2` with 3/6/11° limits.
- **Missing: recorded traces.** There are no recorded headset or controller
  traces, only deterministic synthetic paths (reach, head pitch, crouch,
  roomscale, and the holster reach added today).

## Shape of the replacement

A proxy rig with no animation state machine and no inherited stock pose. The
mod poses every mapped joint each frame from the headset, both controllers,
the gameplay root and its velocity. The gameplay avatar, collision, hit
detection, networking and what other players see stay stock.

The work splits in two:

1. **A pure solver** (`darktidevr_body_solver.lua`). Plain tables in, joint
   world transforms out, no engine calls. Tested offline.
2. **A thin adapter.** It reads the inputs, converts world and local
   transforms, writes them to the proxy, and blends with stock states.

### Joint map

Human rig (names as spelled in the rig; `scan_body_rig` lists them live):

| Group | Joints written | Driven by |
| --- | --- | --- |
| Root | proxy root | gameplay root position, pelvis yaw |
| Pelvis | `j_hips` | pelvis solve |
| Spine | `j_spine`, `j_spine1`, `j_spine2` (`j_spine3` if present) | spine distribution |
| Neck, head | `j_neck`, `j_head` | head pose |
| Clavicles | `j_leftshoulder`, `j_rightshoulder` | shoulder reach |
| Arms | `j_leftarm`, `j_leftforearm`, `j_lefthand` (and right) | two-bone arm IK |
| Twist | `j_leftforearmroll1`, `j_leftforearmroll2` (and right), upper-arm roll nodes | twist distribution, ±100° |
| Fingers | finger chains | stock grip pose copied from the avatar's hands, as today |
| Legs | `j_leftupleg`, `j_leftleg`, `j_leftfoot` (and right) | procedural gait, two-bone knees |
| IK handles | `j_left_hand_ik_handle`, `j_right_hand_ik_handle`, `j_left_foot_ik_handle`, `j_right_foot_ik_handle`, orient handles, `j_hips_handle` | left alone; checked that nothing downstream reads them |

Ogryn: the rig is expected to use the same `j_` naming at a larger scale, but
this is not verified. The user's characters are a Psyker, a Veteran and a
Skitarius, with no Ogryn. First step: run the existing rig scan on an Ogryn
profile through the proxy spawner in the Psykhanium, which needs no Ogryn
character, and record the parent chain and bind lengths.

Rest pose: capture each mapped joint's local transform once from the
spawner's first posed frame, before any update. It is then used only for bone
lengths and neutral joint orientations, never re-read. Open question: whether
the spawner's first frame is the authored bind pose or already animated. The
scan prints both frames to decide.

### Solve order each frame

1. **Pelvis.**
   - *Height:* standing pelvis height = 0.53 x stature, where stature =
     calibrated floor eye height / 0.936.
   - *Crouch:* when the head drops by d below the standing eye height, the
     pelvis drops by 0.8 d until the knees reach their limit (thigh-shin angle
     of 35°). Further drop goes to spine flexion. Blend with the game's crouch
     state when `crouching` is held, so the character crouches when the player
     presses crouch without lowering their head.
   - *Horizontal:* the pelvis sits under the neck base, offset backwards by
     head pitch times the neck-to-pelvis length times 0.35 (hip hinge). Lean
     is limited to 25°.
   - *Yaw:* follows head yaw with the existing 30° dead zone. It is biased
     towards the mean forward direction of both tracked hands when both are in
     front of the chest (a two-handed gun), and snaps to the root velocity
     direction while moving faster than 1.5 m/s.
2. **Spine.**
   - Target the neck base: head position minus the head-local neck offset
     (the existing `(0, 0.0805, 0.075)` arc, scaled).
   - Distribute the bend from pelvis to neck base over `j_spine`, `j_spine1`
     and `j_spine2` at 20/30/50 %.
   - Total limits: flexion 45° forward, 20° back, 25° lateral, 40° twist
     (twist spread 15/30/55 %).
   - Remaining distance to the neck base is absorbed by neck translation up to
     3 cm, then the head is allowed to leave the neck. Presentation only; the
     camera is never moved.
3. **Neck and head.** `j_neck` takes 40 % and `j_head` 60 % of the head's
   rotation relative to the chest, limited to 70° yaw, 60° pitch and 40° roll.
4. **Clavicles.** The existing shoulder reach (90 % participation start, 12 %
   cap), unchanged.
5. **Arms.**
   - Native two-bone solve from the shoulder to the calibrated wrist target.
   - *Elbow pole:* outward 0.8, down 0.5, back 0.2 in chest space. It is
     rotated by 50 % of the hand's roll around the forearm axis, so a rolled
     wrist lifts the elbow, and clamped so the elbow never passes above
     shoulder height or across the chest midline.
   - *Twist:* hand roll relative to the forearm is split 35/65 % over the two
     roll joints, within ±100°.
6. **Legs (procedural gait).**
   - *Support:* each foot has a planted world position. Stepping starts when
     the pelvis's ground projection leaves a 0.18 m (x scale) radius around
     the midpoint of the feet, when pelvis yaw has turned more than 40° from
     the feet's mean yaw, or on a movement start.
   - *Step:* one foot at a time, the one farther from its ideal position
     (hip-width either side of the pelvis, pushed along root velocity by
     0.25 s). Swing duration 0.35 s minus 0.03 s per m/s of speed, clamped to
     0.18-0.4 s. Swing arc 0.08 m; ease in and out.
   - *Ground:* raycast down from above each target foot, from hip height to
     0.6 m below the root, on the static physics world. On no hit the foot
     stays at root height.
   - *Knees:* native two-bone from the hip to the ankle, pole along the foot's
     forward plus the pelvis forward.
   - *Gait classes by root velocity in pelvis space:* walk, sprint (longer
     stride, earlier step), crouch-walk (lower pelvis, shorter stride),
     backwards and strafe (feet keep their yaw within 60° of the pelvis). Idle
     turning steps in place past the yaw threshold.
7. **Hands and equipment.** Fingers come from the stock grip, as today. The
   held weapon follows the hand socket through the existing
   `sync_equipment_hands_to_proxy`.

### States the stock animation keeps

The proxy blends to the stock animated pose over 0.2 s when entering a state
and back when leaving, weight per joint group:

| State (character state machine) | Owner | Notes |
| --- | --- | --- |
| walking, sprinting, sliding, jumping, falling, dodging | solver | legs procedural; jump and fall tuck feet by vertical velocity |
| ledge_hanging, ledge_hanging_pull_up, climbing, vaulting | stock | hands on the ledge are the game's, not the controllers' |
| knocked_down, netted, pounced, grabbed, consumed, mutant_charged, catapulted | stock | the player has no control |
| hogtied (carried), dead, captured | stock | |
| stunned, staggered | stock arms 50 %, solver legs | keeps the hit reaction readable |
| interacting with a device or emote | stock | emotes are animation content |
| cutscenes | stock (proxy hidden) | as today |
| minigame (decode, auspex) | solver arms to the device, stock legs | |

Any state not in the table defaults to stock, and the log names it the first
time it appears.

## Adapter

- **Where:** the same locomotion `post_update` hook, replacing
  `inherit_authoritative_pose` and the layered steps when the new option is
  on. The hands-only default stays as it is.
- **Writes:** local transforms, computed from the solver's world transforms
  and the rig's parents. The existing parent-chain check fails closed.
- **World inputs:** root position, root velocity from the locomotion
  component, character state name, crouch input, and a ground raycast
  (`PhysicsWorld.raycast`, statics only).
- **Visibility:** full proxy visible, source body slots hidden
  (`hides_source_slot` already handles this in full-body mode). First-person
  camera: the head and neck meshes are hidden, or scaled to zero, for the
  local view.
- **Cost budget:** under 0.3 ms per frame in Lua for the solver and adapter
  on the current machine. One proxy only (the local player).

## Offline testing

- **Recorder (implemented, `a506d9e`).** A request-file-enabled recorder (`darktidevr_pose_trace.flag`)
  appends a CSV (`mods/darktidevr/darktidevr_pose_trace.csv`, moved into`nartifacts after recording) at 30 Hz; columns are documented in`n`darktidevr_pose_trace.lua`. Each row: time,
  head pose, both grip poses and tracking flags, root position and velocity,
  character state, crouch input, floor eye height, calibration id. Players
  never have the flag.
- **Traces.** Record them in the evening's worn session: standing look
  around, crouch and stand, lean over a rail, reach up and down, two-handed
  gun, melee swings, walk, strafe, turn in place, sprint, slide. Until then,
  the synthetic head and controller publishers (neck pivot, crouch,
  roomscale, reach, holster) give deterministic inputs.
- **Solver invariants per trace:**
  - bone lengths constant within 1 mm;
  - no elbow or knee flip, meaning the bend direction's dot product with the
    previous frame's stays above 0;
  - joint limits respected;
  - planted feet slide less than 1 cm per step;
  - pelvis and chest continuous through turns and crouches, with no jump over
    3 cm or 10° between frames at 30 Hz;
  - hands reach their targets within 1 mm when in reach;
  - every state transition blends.
- **Screenshots without a headset:** the viewer's eye readback
  (`%TEMP%\darktidevr-shared-eye-readback.request`) shows the rig in the real
  render, for example with the hub third-person camera or a mirror position.

## Milestones

1. Rig scan (human and Ogryn joint map, rest pose decision) and the trace
   recorder. No visible change.
2. Pure upper-body solver (pelvis, spine, neck, arms) with tests on synthetic
   and recorded traces.
3. Procedural legs and foot planting with tests.
4. Default-off option "Full body (experimental)", hub and Psykhanium only,
   replacing the current full-body flag path. Stock-state blends.
5. Worn tuning passes: comfort, the look in a mirror or third person, and the
   first-person view down.
6. Missions, remote servers (presentation only), then the networked pose as
   the separate [feasibility study](networked-vr-ik-feasibility.md).

## Risks and open questions

- The spawner's first frame may already be animated; the rest pose must come
  from somewhere stable (milestone 1 decides).
- Ogryn rig naming and proportions are unverified.
- Weapon animation (reload, inspect) moves the hands in the stock animation;
  with tracked hands those animations are not visible on the body. This is
  accepted today in hands-only mode.
- Procedural feet on stairs and slopes depend on the raycasts; ladders and
  vaults stay stock.
- Looking down in first person at a procedural body is the comfort-critical
  case and can only be judged worn.
