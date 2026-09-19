# Two bodies on loading into the Psykhanium, 19 September 2026

Not worn acceptance. This is a fault read out of the last worn session's log,
fixed at the point the log names, with a test that fails on the fault and on
the fix's own reversal. The worn test is item 1 of
[test-checklist-2026-09-19.md](test-checklist-2026-09-19.md).

## What was reported

Two bodies on the player when loading into the Psykhanium, with the
"Full body (experimental)" option on. The 19 September checklist's item 1 had
already hidden the stock third-person model wholesale while the copy draws,
and the log confirms that part worked:

```
DARKTIDEVR_BODY one_body copy_draws_body=true
    hidden_slots=slot_gear_upperbody,slot_gear_head,slot_gear_extra_cosmetic,
                 slot_body_legs,slot_body_arms,slot_body_face,slot_grenade_ability,
                 slot_unarmed,slot_secondary,slot_gear_lowerbody
    visible_3p_units=2
```

So the second body was not the stock model.

## What the log names

`console-2026-09-18-23.10.40-e7a28687-….log`, the session that ran the
deployed `c99d9aa` Lua. The whole handover takes sixteen milliseconds:

```
23:13:07.453  DARKTIDEVR_IK visual_proxy=active   mode=upper_body
23:13:07.933  DARKTIDEVR_BODY_MIRROR spawn mode=overlay kept_slots=26 ignored_slots=28
23:13:07.948  DARKTIDEVR_IK hand_rig=body
23:13:07.957  DARKTIDEVR_IK visual_proxy=inactive mode=upper_body
23:13:07.964  DARKTIDEVR_IK visual_proxy=active   mode=upper_body
```

and the arm census, at the next weapon swap, lists the two spawned bodies at
the same wrist:

```
DARKTIDEVR_ARM_CENSUS wielded=slot_primary source=proxy_body  arms=4 meshes=1 wrist=0.077,5.855,2.020
DARKTIDEVR_ARM_CENSUS wielded=slot_primary source=mirror_copy arms=4 meshes=1 wrist=0.077,5.855,2.020
```

`proxy_body` is `darktidevr_body_proxy`'s own unit -- the profile named
`DarktideVRUpperBody`, spawned with `slot_body_arms`, `slot_body_torso`,
`slot_gear_upperbody` and `slot_gear_extra_cosmetic` retained. `mirror_copy` is
the body overlay's full-profile copy. The same two lines, with the same
sequence of `visual_proxy` flips, are in the 22:27 log from the session before.

## Why

Three body systems are layered in this build, and the layering is the fault:

| system | turned on by | what it spawns |
|--------|--------------|----------------|
| gloves (default) | nothing | two rigid glove units |
| headless third person | dev flag `darktidevr_full_body_experimental` | the proxy's upper-body profile, solved by the full-body IK path in the main file |
| body overlay | option `vr_full_body_experimental` | a full-profile copy, which takes the hand rig |

The deploy for the checklist writes the dev flag `enabled` ("item 1 lives
behind it"), so the proxy is in upper-body mode (`hands_only=false`) while the
overlay runs. `BodyProxy.update` had two branches that knew about the hand rig
and both were gated on `hands_only`:

```lua
if hands_only and hand_rig and not Unit.alive(hand_rig) then ... end
if hands_only and hand_rig then  -- pose only, no units
```

When the copy called `set_hand_rig`, the proxy's `safe_destroy` cleared
`state.world`. The upper-body branch, which never looked at `hand_rig`, then
read `state.world ~= world` as "nothing spawned yet" and spawned the
torso-and-arms profile again on the next frame. The copy's hands were the
hands (the source avatar's arms were hidden on the rig's account, the 18
September fix) and a second torso-and-arms body stood inside the copy.

## The fix

**`darktidevr_body_proxy.lua`.** The rig is checked before the caller's mode,
which is the same rule `hides_source_slot` was given on 18 September: a body
that owns the rig is the body, in either mode, and the proxy spawns nothing of
its own while it lives. When the rig's unit dies the proxy falls back to
whatever the mode asks for -- gloves, or the upper body under the flag. A new
`BodyProxy.hand_rig_active()` says whether a rig owns the hands.

**`darktidevr.lua`, `apply_body_ik`.** With no proxy body the proxy hands back
the gameplay avatar as the unit to solve, and the full-body path would then
have run on the avatar itself: `apply_calibrated_body_height` scales the root
of the unit it is given. Under a rig the IK takes the tracked-hands path, flag
or no flag. That path is what records the wrist poses the copy solves its own
arms to, so nothing the copy needs is lost. The `visual_proxy=` log line says
`body_rig` in this state; before, it said `upper_body` whether or not the
proxy had a body, which is why the two spawns read as one.

**`darktidevr_body_mirror.lua`.** A copy whose scene graph does not match the
avatar's is hidden and never posed. It no longer takes the hand rig on the way
to being hidden: had it done so, the gloves would have been destroyed, the
source arms hidden on the rig's account, and the player left with a floating
weapon and no hands. This is the same ownership rule from the copy's side; it
is not tested by a harness (the module's `install` path has none) and is
flagged here for that reason.

Not changed: the hub, where the overlay never runs and the flag's headless
presentation stands as before; the stock model's wholesale hiding from item 1;
the weapon staying on the stock unit.

## Validation

```
build/dependencies/luajit/src/luajit.exe tests/tooling/test-body-hand-rig.lua \
    mods/darktidevr/scripts/mods/darktidevr/darktidevr_body_proxy.lua \
    mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua
build/dependencies/luajit/src/luajit.exe tests/tooling/test-rigid-hand-readiness.lua ... (same two)
build/dependencies/luajit/src/luajit.exe tests/tooling/test-body-mirror.lua \
    mods/darktidevr/scripts/mods/darktidevr/darktidevr_body_mirror.lua
ctest --test-dir build/windows-vs2022 -C Release
```

`test-body-hand-rig.lua` now runs the proxy in upper-body mode under a rig and
asserts no spawn, then slices the real `apply_body_ik` out of the main file
and asserts the tracked-hands path with the flag on and off, then kills the
rig and asserts the upper-body fallback spawns and the full-body path comes
back. Both guards were mutated before being believed:

| mutation | caught by |
|----------|-----------|
| the proxy's two branches gated on `hands_only` again (lines 607 and 627) | `test-body-hand-rig.lua:214: upper-body mode under a rig did not hand back the source unit` |
| the IK gate without `or body_rig` | `test-body-hand-rig.lua:241: the full-body path ran under a rig` |
| control, unmutated | passes |

A first cut of the first mutation also rewrote an unrelated `if hand_rig then`
at line 478 and tripped an earlier assertion; the harness above is the
line-limited one.

The full tooling suite: 281 of 282 passed. The one failure, `online_reticle`,
is not this change's: another session was editing the reticle's zoom
correction and its test in the same working tree while this was written
(`zoom_corrected_aim_point` calling a `zoom_aim_correction_enabled` that does
not exist yet), and the same test passes against `c99d9aa`'s main file. This
commit carries none of that work: the main file's index entry was built from
`c99d9aa` plus the two hunks named above.

## Worn, 09:40, and the second pass

Head `fada8a4`. The report: *"Only one body. It flickers constantly when I
move (almost certainly the same root cause as all the previous
flicker-when-moving issues). Weapons are invisible."* The log agrees on the
first part: one `spawn`, `visual_proxy=active mode=body_rig` after the copy
took the rig, and no second `visual_proxy=active` -- the proxy stayed
pose-only. Item 1 is closed on the spawn count.

### The weapons

The first cut of item 1 hid the stock root with its children in one call and
then showed the wielded slot back by its own handle. The weapon unit is
linked under the root's hand joint. `visible_3p_units=2` in the log says the
show call was made; the headset says it did nothing. Fatshark's own code
never shows a child back under a hidden parent: `update_item_visibility`
shows the root *with children* and then hides slots one by one, which is the
only order that works if a linked unit reads as hidden while anything above
it is. The gloves mode has hidden the stock model that way since the start
and the root's own mesh has never shown as a stray there. The copy branch
now does the same: root shown with children, every slot hidden by name, the
wielded slot and the companion's gear shown. The stock body is still not
drawn; only the mechanism changed.

### The flicker: measured, not guessed

Every flicker-while-moving this mod has had was one shape: a thing drawn
from a value that advanced in fixed steps while the view advanced every
frame, so it flicked between two places at the frame rate. The forearm
miniatures read last frame's eye in the locomotion post-update
(animation-audit-2026-09-16.md); the mirror copy was placed from the
avatar's root (17 September, "glitches around when I move"). The overlay
copy stands on four positions: the avatar's root (which the game
interpolates every frame in `post_update`, before this mod's hook runs), the
body frame's neck target (from `eye_pose`, which is stored against the body
anchor -- `first_person_component.position`, fixed-step -- and read back
from it), the tracked eye itself, and the copy's own root after the neck
follow. Reading the source has not said which of them steps, and the trace
that would have shown it was written `disabled` by the deployment this run
used.

So the module now measures it. `DARKTIDEVR_BODY_MOTION`, under the body
trace flag, prints every frame while the avatar moves more than a
millimetre: the step each of those four took since the previous frame. The
one that alternates -- `0.000, 0.032, 0.000, 0.032` against a view stepping
`0.016, 0.016` -- is the one to re-derive from the interpolated timeline.
Every frame rather than every third, because a two-state alternation
sampled every third frame aliases into a smooth line. It shares the trace's
25,000-line budget, so move early in the session.

The body trace flag is written `enabled` in the installed mod for the next
run, by hand, because the sync deployment turns it off unless asked
(`-BodyTrace`).

## The animation, and the separation rule

The third report of the morning: *"The body still appears to use the base
game animations (idle animation, shifting position when I ADS etc), which
it was explicitly instructed not to do."* Then, on the 15 September design's
legs-from-the-avatar step: *"keeping the leg animation was a made-up
instruction, I said to create the new custom-IK wholesale."* And the rule
in full: *"The base model needs to exist (but hidden, and completely
disconnected from the custom-ik model except what's absolutely required for
weapon function) due to things like hit detection, but otherwise there
should be no relationship between the two."*

The copy was posed every frame by copying every joint's local pose from
the animated avatar and solving on top of it. That is where the idle sway
and the stance shift in the sights came from, and it is also where item
2's "turn leak" came from: the avatar's counter-rotation arriving through
the copied spine. The mirror key's copy fell back to the avatar's animated
hand when no wrist pose was recorded. The root's rotation and scale were
the avatar's, and the rig was compared with the avatar's by index.

Now the spawn pose is boxed once as the rest pose. Each frame every joint
below the root goes back to it, and only the solves move joints: the root
yaw from the body frame, the neck follow and scale, the clavicles, the arms
to the recorded wrist poses. The legs hold the rest pose until a procedural
gait exists; the design's step 2 is withdrawn in the design doc. The
turn-leak block is gone, since nothing copied can leak. The arm's fallback
is rest, not the animated hand. The root's heading is the body frame's and
its scale its own. The rig check is on the copy's own named joints. The
diagnostics that compared the copy's hand and torso with the avatar's are
gone. The one read of the avatar left is its root position: where the
player stands.

`test-body-mirror.lua` now scans the module's source and refuses any read
of an avatar joint beyond the root, by pattern and line. Mutated before
being believed: against the previous module it fails on
`Unit.local_pose(avatar` at its line 1077; against the new module with that
one line put back it fails at 1133; the control passes. A first cut was
tripped by a missing constant before the scan ran, which is the wrong check
catching the mutation, so the scan runs first.

What this changes in the headset: no sway when standing, no stance change
in the sights, and the legs stand still while you walk. The last is the
cost of the rule until a gait is written, and it is the user's call, made
in those words.

## Worn, 10:51: too large, turned right, no leg movement -- and the rule for scale

The report on `a8d474a`: *"body is way too large, doesn't sit square
(neutral position is slightly turned to the right), no run animation/leg
movement."* The log has all three:

```
DARKTIDEVR_BODY_MIRROR gait=ready left=-0.156,0.182,0.103 right=0.141,-0.192,0.100
DARKTIDEVR_BODY_MIRROR neck_follow ... scale_ratio=1.300
DARKTIDEVR_BODY_MIRROR gait speed_mps=4.824 ...
```

The rest ankle offsets say the frozen spawn frame was a staggered combat
stance, left foot 18 cm forward and right foot 19 cm back: the turned
neutral. Its neck sat low, so the scale-to-neck ran to its 1.3 cap to reach
the head: the size. And the gait ran, at up to 4.8 m/s, but one foot at a
time with a 0.8 m reach cap cannot keep up with a run: at 4 m/s a foot
stepping every other swing has to cover nearly two metres, so the legs
trailed at full stretch: no leg movement.

**The rule, from the user, applied in full.** Scale should be as close to 1
as possible and come from the calibration, not from anything measured in
game; the calibration sets the character's height, which is a player-facing
setting, so no further scaling is ever needed; the neck is correct relative
to the head when the calibration is, so it never needs to lift; height
beyond the settable range is stretched or compressed vertically into the
bones that carry it, and arm length is stretched or compressed into the arm
bones only.

So, at ready (`prepare_rest`):

1. The legs are measured as spawned: bone lengths, the ankle's height off
   the floor and its distance to the side.
2. The copy's scale is the game's own character height for the profile,
   from `PlayerHeight.player_character_third_person_scale`, the number the
   avatar and every UI character get. Fixed for the session. The
   scale-to-neck is gone; `Mirror.scale_ratio` remains only for its test.
3. The height beyond the settable range, if any: the calibrated standing
   eye height against the character's eye height at that scale. The
   difference, past a centimetre, becomes one factor on the floor-to-neck
   chain (`Mirror.height_stretch`, clamped 0.80-1.25) and is applied along
   the bones of the spine, neck and legs: each bone's local offset scaled,
   which lengthens it in its own direction. Never a uniform scale.
4. The torso is turned square to the root and stood upright, by one
   rotation of the hips that takes the shoulder line to the root's right
   and the hips-to-neck axis to vertical.
5. The hips are put at standing height for these legs
   (`Mirror.standing_hips_height`: ankle height plus the stretched legs with
   the knee softened by 8 degrees).
6. Every joint moved is boxed back as the rest pose; the feet's ideal
   places are made symmetric, hip-width either side, neither forward.

The arms: `arm_length` is on in every live mode with a loose clamp
(0.6-1.6), so `solve_arm` sets the upper-arm and forearm bones to the
calibrated lengths from the arm-length calibration, on those bones only.

The gait's run cadence is in gait-2026-09-19.md.

## Worn, 11:14: far too small, wrists into forearms, and the flicker named

On `1361146`: *"model is far too small now. Also, with my hands close to
me the wrist moves down into the forearm, and when I reach out the hands
disconnect from the forearm and float away from it."* Then: *"The t-pose
calibration was 100% done correctly"*, and *"the body is flickering, and
the hands, which are part of the body, not the weapon though."*

```
DARKTIDEVR_BODY_MIRROR rest scale=1.0691 character_eye_m=1.896 calibrated_eye_m=1.723
    chain_m=1.411 stretch=0.8856 torso_yaw_fix_deg=-13.8 hips_z_m=0.872->0.897
DARKTIDEVR_BODY_MIRROR arm_length source=span span_m=1.559 reach_m=0.518 upper_m=0.290 lower_m=0.228
DARKTIDEVR_BODY_MIRROR arm side=right world_upper_m=0.2899 world_lower_m=0.2277
```

**Too small.** The residual was taken between the player's real standing
eye height (1.723 m) and the avatar's in-world eye height (1.896 m), and
the copy was compressed by 11 % toward a head the camera was not at: this
mod anchors the tracked eye to the avatar's eye, so the camera stands at
the avatar's height, and at the game's scale alone the copy already
matches it (the squared rest pose's chain, 1.411 m at scale 1, puts the
neck where the avatar's is). The residual is now between the camera's
height above the floor and the game's eye height for the profile; they
agree, so it is 1, and it appears only if the camera is ever put elsewhere.
The dead zone is 3 cm.

**Wrists and floating hands.** The T-pose was right and the arm lengths
were applied exactly (the world bone lengths in the log are the calibrated
ones). What was wrong is how a changed bone length reached the skin: the
child joint was moved along the bone and the mesh, skinned to the joint it
hangs from, kept its authored length. A forearm bone shortened to 0.228 m
under a 0.294 m forearm mesh overhangs the wrist when the arm is bent; the
reach stretch moved the hand joint past the mesh's end. Bone lengths now
change through the joints' scales, uniformly, with the inverse on the
child: the upper arm carries its factor, the forearm the ratio of the two,
the hand the inverse of the forearm's, so each mesh stretches with its bone
and the hand is its own size. The height residual, when it is ever
non-zero, is applied the same way: the spine root carries it and the head
and clavicles the inverse; each hip joint carries it and the foot the
inverse.

**The flicker.** *"It's not a judder. The body is alternating between two
positions each frame."* The weapon rides the hidden avatar and is steady;
the copy and its hands ride the body frame. The body frame's smoothing
state -- its yaw and its "turning" -- was advanced by three callers on
three clocks: the copy in the post-update with the frame's t, the two-hand
stock at input time (`input.two_hand`) with the previous frame's t, the
holsters at draw time. "Sampled at most once per game time" only
de-duplicated an equal t; a different one re-ran the smoothing with that
gap as dt, and a negative or oversized gap snaps the yaw to its target. So
the copy's root was set from a snapped heading one frame and a smoothed
one the next: two placements, alternating, hands included, weapon not.
`api.sample` now advances once per rendered frame on the game's main clock
and hands every other sample in that frame the same frame back, whatever
time it passes: one writer.

The motion probe no longer depends on the trace flag, which three
deployments in an hour each wrote `disabled`; it runs with its own budget
of 3,000 lines.

## Worn, 11:36: the probe named it

On `565f8e7`: *"arm length is good, no change to flicker, I've also
noticed there are no hand animations and they're not quite correctly
aligned with weapons."* And, on the write-up's hedge: *"the weapon does
NOT flicker with the body. Stop second guessing me."* The one-writer body
frame was not it. The probe, running without the flag for the first time,
had 2,767 samples:

```
dt=0.0071 d_avatar_m=0.0152 d_neck_target_m=0.0484 d_eye_m=0.0484 d_unit_m=0.0484
dt=0.0070 d_avatar_m=0.0142 d_neck_target_m=0.0000 d_eye_m=0.0001 d_unit_m=0.0002
dt=0.0071 d_avatar_m=0.0144 d_neck_target_m=0.0392 d_eye_m=0.0392 d_unit_m=0.0392
dt=0.0079 d_avatar_m=0.0125 d_neck_target_m=0.0001 d_eye_m=0.0001 d_unit_m=0.0001
dt=0.0067 d_avatar_m=0.0106 d_neck_target_m=0.0001 d_eye_m=0.0001 d_unit_m=0.0001
dt=0.0079 d_avatar_m=0.0109 d_neck_target_m=0.0303 d_eye_m=0.0303 d_unit_m=0.0303
                       smoothness (mean min/max of consecutive steps):
                       avatar 0.866   neck_target 0.121   eye 0.100   unit 0.115
```

The avatar's root, which the game interpolates every frame, moves about
1.5 cm every frame. The eye the copy is placed from stands still for two or
three frames and jumps 3 to 5 cm, and the neck target and the copy's root
do exactly the same: a 60 Hz fixed-step position read at 140 frames a
second. The eye is re-based each frame on the body anchor, and the anchor
is `first_person_component.position`, which the game writes in its fixed
update. The user's "alternating between two positions each frame" is that
pattern seen against a view that moves every frame.

**The smooth timeline.** The game's first-person unit carries the same
point on the interpolated timeline (the interpolated root plus the height,
set in `update_unit_position` from the root the post-update just wrote).
The difference between the unit's position and the component's is the
anchor's lag this frame, and the copy adds it to the neck target and the
shoulder targets (`smooth_offset`, `shifted`). It is a read of the
avatar's camera point, not of its animation; the separation scan still
passes. The probe now prints `anchor_lag_m` so the next log shows the lag
being taken up.

**Fingers.** The gloves took their curl from the gameplay rig's grip,
captured once per weapon and held (the animation exception the user
allowed for fingers), and nothing did the same for the rig, so the copy's
hands stood open at the rest pose. `BodyProxy.pose_rig_fingers` runs the
same function on the copy's own hand joints after the arm solve.

**Weapon alignment.** The copy's hand joint is put on the recorded wrist
pose and its rotation set to the pose's; `hand_angle_deg` in the arm log
now says how far the drawn hand's rotation is from that pose after the
write. The weapon is placed from the same pose, so a hand that matches it
here and still sits wrong on the gun puts the difference in the equipment
sync's authored basis, which is the next thing to measure.

**Two-handing.** *"I can no longer two-hand ranged weapons by grabbing
them with my off-hand."* Not code: the sessions at 11:16, 11:31 and 11:36
have two-hand release lines and every session after the 11:40 crash has
none, and the restored settings file has `vr_two_hand_support = false`.
The restore source, `user_settings.vr.config`, dated 14 September, has no
entry for the key at all. Set back to true in the live file with the game
closed, and the backup refreshed from it with the old copy kept beside.

## Worn, 12:07: the root is smooth and the flicker stays; feet a little high

On `d447f61`: *"Flicker persists, hands are aligned and curl now. Body is
a little too high, feet are floating off the ground slightly."* The probe,
13,293 samples with `anchor_lag_m`:

```
cols:   avatar  neck_target  eye    unit   lag
smooth: 0.914   0.912        0.278  0.904  0.548
```

The copy's root now moves as smoothly as the avatar's, the raw eye still
steps and the lag alternates as it should, so the root is no longer what
alternates. The trace's yaw columns are flat (steps of a hundredth of a
degree). Whatever alternates does so after the point where the probe reads
the copy, or in a joint the probe does not watch. So the copy now records
its root and right hand at the end of its update and reads them again in
the `ScriptWorld.render` hook, the last Lua boundary before the frame is
drawn and after the engine's own world update
(`api.check_before_render`). A drift there is a writer this module cannot
see, and it is logged with the frame it happened on, plus a summary every
600 checks so a clean result is written down too.

**The feet.** Over the session the avatar root, the copy root and the
raycast floor share the same median height within six millimetres, so the
ground is right. The ankle height was the spawn frame's ankle above the
root, 0.101 m, with the feet wherever the idle had them; the sole sits
below the ankle by an amount the rig knows through its toe joint
(`j_*toebase`, the ball of the foot). The ankle's height is now ankle
minus toe plus 1.5 cm, and the hips' standing height, built on the same
number, comes down with it.

**Industry practice, as asked.** VRIK calibrates height by having the
player stand straight and comparing the head target's height with the
avatar's head bone, and offers scaling the mesh to the player or the
player to the mesh, with arm-length calibration beside it; this mod does
the former through the game's own character-height setting and the
latter through the arm bones. For the feet VRIK anchors the toes to the
footsteps rather than the ankle, so the avatar can rise on its toes and
the headset has more room before a side-step is forced; this pass moves
the anchor's height to the toe's measure and leaves toe anchoring proper
for the gait. For locomotion VRIK calls its procedural stepping legacy,
"not responsive enough" and inclined "to fall behind the camera when
moving fast", and uses an eight-direction walk and run blend tree whose
foot placements a full-body solve then adapts to the terrain. Those cycles
are authored animation, which the separation rule keeps off this body
unless they are the mod's own; the procedural gait here is the legacy
approach with the run overlap added to keep it from falling behind.

## Worn, 12:22: the check never ran; the legs get the game's own clips

On `ed3cfe7`: *"flicker still exists in the latest run."* And the
pre-render check's answer was silence: zero summaries, zero drifts. It sat
inside the render hook's native-capture branch, which this configuration
never takes, so it never ran. It is at the top of the hook now, for every
world, and the module answers only for its own. The rest line confirms the
toe measure took (`ankle_z_m=0.089 spawn_ankle_z_m=0.101 toe_z_m=0.027`).
The next log has the check's summaries, and either names a writer or
clears this path for good.

### Animated legs, behind the mode flag

*"Surely the animations are stored somewhere and we can hook into them
rather than grabbing them from the loaded 3p model?"* They are: the walk,
run and idle cycles live in a third-person animation state machine that the
game picks per wielded weapon (`WeaponTemplate.state_machines`) and puts on
the avatar with one engine call, and the game drives it through per-unit
events from the animation extension and a move-speed variable the
locomotion writes every frame. The copy is a character of the same rig, so
it runs that machine itself, fed the same inputs:

- **The wield.** `inventory_slot_wielded` on the local player's animation
  extension is hooked; the template is kept and, on a live copy, the same
  machine is set the way the game sets it (blend base layer, then the
  template's initialization variables, evaluated for the copy).
- **The events.** The four third-person `anim_event*` methods are hooked
  for the local player and re-issued on the copy with their variables.
- **The move speed.** Each frame the three cached third-person variables
  (`anim_move_speed`, `aim`, `climb_time`) are read off the avatar with
  the engine's own `animation_get_variable` and set on the copy.

The machine writes every joint of the copy after the Lua update, so the
solve for the root, the hips and everything above them is boxed at the end
of the copy's update and put back over the machine's output at the render
boundary, in the same call as the drift check, which then measures what is
left. The legs, found by index under the two upper legs
(`Mirror.leg_indices`), are the machine's. The gait stands down while the
machine is live and is the fallback for any frame it is not: no weapon yet,
a machine the template does not have, an engine call that fails, each
logged once.

Dev flag mode `overlayanimated`: write it into
`darktidevr_body_mirror.flag` in the installed mod. The default overlay is
unchanged. Not worn.

**Known limits of this first cut.** The legs strafe relative to the copy's
heading (the body frame) rather than the avatar's (the aim), a difference
inside the body frame's dead zone most of the time; no raycast correction
of the animated feet yet, which the Psykhanium's flat floor does not need;
and the machine's idle stance is the character's, staggered, under a square
torso. The base model contributes nothing of its pose; the guard's rule on
its joints stands, and the one new read of it is its animation variables.

## Worn, 12:52: the module threw at ready, and the session looked at the fallback

*"body is too short & too crouched by default, and hand animations are
gone again, but the flickering is fixed."* Right on all three, and all
three describe the stock avatar's headless fallback with the upper-body
proxy, not the copy:

```
DARKTIDEVR_BODY_MIRROR failed=[string "..."]:855: attempt to call global 'log_once' (a nil value)
```

Inside `install` the api functions and the helpers are locals of one
scope in source order. The animated-legs block was placed above the
`local function log_once` line, so its call resolved to a nil global and
threw on the copy's first ready frame; the module's failure path shut it
down for the session and destroyed the copy. The same ordering silenced
`check_before_render`, which calls `array` from the same position. Nothing
of the animated legs, the moved check or the toe height was exercised, and
the steadiness observed is the stock avatar's, consistent with every
measurement so far. The "flicker fixed" finding is void.

Fixed with forward declarations of `log_once`, `array` and `vector` at the
top of `install`, the later definitions turned into assignments. The
mirror test now walks twelve helper names and refuses any whose first
call precedes its declaration; on the module that shipped at 12:52 it
fails at `log_once is called at line 833 before its declaration at line
952`, and on a mutation that removes the forward declaration at 841
before 960. An unattended check would have caught this before the sitting:
the copy's ready frame is reachable without a headset.

## Worn, 13:02: the machine refused the copy; the gait with locked knees

*"Flicker is back, body is definitely floating, no run animation, legs
just stay straight and swing forwards together in the direction of
travel."* The copy was drawn this time, and:

```
DARKTIDEVR_BODY_MIRROR animated_legs=failed error=...: Unit `#ID[...]` has no animation state machine
```

`Unit.set_animation_state_machine_blend_base_layer`, the game's call,
blends a new machine onto a unit that has one; the copy's machine had
been disabled at ready, and the engine refused. `assign_machine` now uses
`Unit.set_animation_state_machine`, the UI spawner's own call, which sets
a machine outright. The gait ran the whole session (46 gait lines, no
`live`). Its standing hips height softened the knee by eight degrees,
which is one per cent of slack: with the feet on the floor the legs
locked straight, and with the run overlap both feet swung at once, which
is "legs just stay straight and swing forwards together". The rest bend is
twenty degrees now, about six per cent, a visible standing bend and room
for the arc. The headset screenshot the user asked me to read shows the
reflection standing with straight legs and both feet at the symmetric
ideal places: the gait at rest, exactly. The toe constant is zero, since
the feet still floated with 1.5 cm on this rig.

The render check wrote nothing for a second time, and this time the reason
was mine: it compared the snapshot's frame number with `state.frames`,
which increments at the END of the update, after the snapshot, so the
equality never held. It consumes a stamp taken at the snapshot now, counts
every call, keeps a reason for every early return, and writes a summary
every 600 calls whatever it did. Two silent runs are two too many.

## Worn, 13:10: no change, and what the data excludes

*"no change to anything."* Then: *"For the rest of this session, guessing
is forbidden. All attempts to solve the problem must be data driven."*

```
animated_legs=failed error=...: AnimationStateMachine `#ID[178cfbef0b6a177a]` does not exist
prerender calls=108600 checks=9196 drifted=0 skipped=no_copy=28407,other_world=70996
```

**The machine.** `Unit.set_animation_state_machine` refused too, on a
unit whose machine instance `disable_animation_state_machine` had taken
away at ready. The copy's default is the archetype's portrait machine
(`portrait_state_machine`, a menu idle with no locomotion), which is why
the gameplay machine has to replace it. This build enables the machine
again first, tries both engine calls, and keeps both errors in the log
line, so the next refusal, if there is one, is named exactly.

**The check ran.** 9,196 checks, no drift: between the copy's update and
the frame, nothing moves its root or its hand. Together with the probe's
smooth root (0.90 against the avatar's 0.91) and the trace's flat yaws,
every quantity Lua can measure on the copy is steady, and the drawn body
alternates. The stage Lua cannot measure is the skinning: the engine
refreshes skin matrices with the animation update, this copy's animation
has been disabled since ready, the weapon is a rigid unit, and the stock
avatar animates every frame. That is what the data leaves, not a
conclusion.

**The experiment, labelled.** When the machine cannot be set, the
spawner's portrait idle stays running and the copy's whole solved pose is
put back over it at the render boundary (`state.restore_all`): the only
way from Lua to give the copy an animation update every frame. Its
observable is a headset video recording of the reflection while walking,
pulled over adb and measured frame by frame; the viewer's eye readback
takes one frame per request at 250 ms and cannot show an alternation. The
recording also answers whether a render-boundary write is skinned in the
same frame or a frame late, which no log line can.

**The legs and the float** in this report are the gait's again, with the
twenty-degree knee and the zero toe constant in: "no change" is a report
on the gait as it now stands, and the recording covers it too.

## Worn, 13:20: the body stood in the idle, and that named the stage

The run on 88269cc, with the recording asked for in item 1l. The user:
"My character model was broken this run - no hand tracking and was
completely still, but the mirror model still moved." Then: "hands do
flicker, it's only weapons that don't", and "the hands flicker even though
the gloves in hand-only mode didn't flicker (though they did when first
implemented)".

The log:

```
animated_legs=failed error=...had_machine=true set:AnimationStateMachine `#ID[178cfbef0b6a177a]` does not exist blend:AnimationStateMachine `#ID[178cfbef0b6a177a]` does not exist
animated_legs=ready machine=nil restore_all=true leg_joints=24
prerender calls=183600 checks=17369 drifted=0 skipped=no_copy=27379,other_world=138851
```

Both engine calls refused the gameplay machine on a unit that had one
(`had_machine=true`), so the fallback ran: the spawner's portrait idle
left running on the copy, and the whole solved pose written back over it
at the render boundary. The render check read the solve at that boundary
17,369 times with no drift. And the user saw the idle: a still body with
no hand tracking. **The scene graph held the solve and the skin showed the
machine.** That is a measurement of the one stage Lua could not read:
joint poses written after the world update, in post_update and again at
the render boundary, do not reach the drawn skin of a unit whose machine
is running.

The reflection (the second copy, the mirror toggled at 03:20:11 UTC),
which has no animated-legs mode and so no running machine, moved.

### The frame, from the game's source

`state_game.lua`: `StateGame.update` runs the gameplay state machine
(`self._sm:update`) and then `Managers.world:update`; `StateGame.post_update`
runs `self._sm:post_update`, which is where `GameplayStateRun.post_update`
calls `Managers.state.extension:post_update()`; then `StateGame.render`.
`world_manager.lua`: `WorldManager.update` calls `ScriptWorld.update` on
every world, which is `World.update_animations` and then
`World.update_scene` (`script_world.lua`). So the order each frame is:
gameplay update, animation update, scene update, extension post_update,
render.

The hands, the weapon and this copy were all placed in
`PlayerUnitLocomotionExtension.post_update`: after the animation and
scene update. The weapon is a rigid unit; the gloves of the hands-only
mode move only their unit's root (`place_rigid_hand` in the body proxy
sets the root's position and rotation so the hand joint lands on the
target); both are steady. The copy has its joints written every frame,
and only the copy alternates. The game's own procedural joint writes on an
animated unit (`scripted_flying_animation_extension.lua`,
`Unit.set_local_rotation` on a named node) are made in the extension's
`update`, before the world update, never in `post_update`.

### The change: posed before the world update

`darktidevr.lua`: the locomotion post_update hook now records the frame's
inputs (`body_mirror.schedule(world, avatar, dt, t)`), and a hook on
`WorldManager.update` runs the pose (`body_mirror.run_scheduled(dt, t)`)
before `World.update_animations` and `World.update_scene`. The copy's
joints therefore travel to the skin the same way every animated unit's
do. The inputs are the previous post_update's: the avatar's root and the
recorded wrist poses, one frame old. The camera's own anchor is the
avatar's root as it stands in the gameplay update, so the copy and the
view share that timeline; the wrist poses are one tracking sample behind
the weapon's, which at a metre a second is about 9 mm.

The machine experiment is withdrawn: `assign_machine` disables the machine
again when the engine refuses it, nothing is restored at the render
boundary, and the render check is a read-only compare of what the world
update did to the copy since it was posed. The animated-legs design as
written (gameplay clips on the legs, the solve restored over the rest at
the render boundary) cannot work: the restore is not drawn. If the legs
are to have the game's clips, the upper body has to be written between
the animation update and the scene update, which is what
`World.update_animations_with_callback` exists for; the game does not use
it, and its semantics are not known from source.

### The recording, measured

Two headset recordings (13:20:40 and 13:21:00 local, 30 fps, 1920×1080).
The reflection's horizontal position was tracked frame to frame against
the background by phase correlation of column sums, on a crop centred on
the red mask of its coat:

| segment | reflection minus background, residual vs 5-frame median |
|---|---|
| walking toward it, frames 15–80 | mean 0.09 px, p90 0.17 px, max 1.8 px |
| standing, frames 150–240 | mean 0.32 px, p90 0.86 px |
| second recording, frames 40–120 | mean 0.39 px, p90 0.88 px |

A one-frame lag alternating at 113 Hz while walking at 2 m/s is 17 mm; at
the reflection's distance in those frames that is about 3 px of 960. The
residual is a tenth of that. But the walking in both recordings is toward
the reflection, which moves it vertically and in scale, not sideways, so
this measurement is not sensitive to the alternation and decides nothing
about it. The reflection keeps its distance from the player, so a
sideways pass is not possible; a strafe while facing it is the recording
that would show it, with the floor plates sliding behind a reflection
that stays put.

### What the probe's eye column is

`d_eye_m` alternates between 0 and about 39 mm on moving frames (5,203 of
9,432 moving frames under 2 mm, 4,172 over 20 mm, 46% of consecutive
pairs a 0/step pair). It is `presentation.eye_pose`, the tracked eye as
last stored, anchored to the body anchor; the store happens at the
tracking sample rate, not per frame. The rendered camera's position is
`body_camera_anchor`, which is the avatar's root plus a fixed local eye
offset, and the avatar's root is interpolated by the game every frame
(`d_avatar_m` smooth). The column measures the sample cadence, not the
camera, and is not the flicker.

## Worn, 13:47: the pre-world pose changed nothing; the children

On 571524d. The user, strafing while facing the reflection: the flicker
"extremely obvious", visible in the recording, "between exactly two
locations, one of which looks like the correct location". Also: the
character too short and floating, a hand rested on the real shoulder
5-10 cm above the drawn one, the eyeline above the reflection's.

The log: `Hooking 'update' from [WorldManager]` at start, `posed
mode=overlayanimated frames=14400`, `prerender checks=14917 drifted=0`,
`animated_legs=ready machine=nil leg_joints=24`. The copy was posed before
the world update every frame, its own joints never moved between that and
the render, and the drawn body still alternated. The write timing is not
the mechanism.

The recording (13:47:24 local, 30 fps, 1920×1080), the reflection's eye
lenses tracked as a blue mask and the yellow crate behind it as a yellow
mask, both centroids per frame:

| | residual vs 5-frame median |
|---|---|
| crate x | mean 4.1 px, p90 11 px |
| lens x | mean 12.0 px, p90 39 px, max 82 px |
| lens x minus crate x, while the crate moves | mean 16.6 px, p90 48 px |

An earlier pass that correlated column sums read the floor as still while
the user strafed: the sums were dominated by the HUD, which is fixed in
the frame. That measurement was wrong; the report was right.

### The children

The copy's drawn surfaces are all child units: the profile spawner links
each gear unit to the copy's skeleton (`World.link_unit(world, unit, 1,
parent, node, map_mode)` in `visual_loadout_customization.lua`). The
render check, the probe and the drift compare have only ever read the
copy's own joints. The module now collects, at ready, every linked unit
that carries one of j_head, j_righthand, j_lefthand, j_hips, j_neck, and
measures the distance between the child's joint and the copy's same joint
three times a frame: after the solve's last `World.update_unit` on the
copy alone (`child_before_m`), after `World.update_unit_and_children`
(`child_after_m`; this call is what the rigid gloves have always used and
is the labelled experiment), and at the render boundary
(`child_render_*` in the heartbeat). The reflection's own root move flushes
its children the same way.

### Height and float, instrumented

At ready, `height camera_eye_root_z=... copy_eye_root_z=... eye_gap_m=...
neck_root_z=... shoulder_root_z=.../...`: the copy's eyes are the face
unit's j_lefteye/j_righteye (the face is hidden in the overlay but its
joints follow the skeleton), all in the root's frame against the camera's
eye in that frame. The gait line gains `toe_above_ground_m` per side,
the drawn toe joint against the ground the gait put the foot on.

## Worn, 14:05: the children stand on the skeleton; the skulls flicker too

On 2e17761. The user: torso top right relative to the camera, comfortable
to look down, shoulders out of the view; the legs float and the body
should extend downward with the torso top kept; flicker unchanged; the
servo-skulls flicker as well.

```
children linked=13 joints=slot_body_arms:j_lefthand,slot_body_arms:j_righthand,slot_gear_head:j_head,...
height camera_eye_root_z=1.773 copy_eye_root_z=1.660 eye_gap_m=0.113 neck_root_z=1.515 shoulder_root_z=1.511/1.526
gait ... toe_above_ground_m=0.045/0.052      (at rest; ankle_error_m=0.002/0.010)
prerender calls=225600 checks=19523 drifted=86 child_render_over_1mm=0 child_render_max_m=0.0000 child_update_over_1mm=5830 child_update_max_m=1.1906
animated_legs=live machine=content/characters/player/human/third_person/animations/unarmed_hub template=unarmed_hub_human   (04:05:36, the hub)
```

`child_before_m` was non-zero on 4,338 of 4,340 moving probe lines (the
head gear 2-5 cm, the reflection's hips 2.5 m: `World.update_unit` on the
copy alone leaves the linked units where the last flush put them);
`child_after_m` and the render-boundary read were zero throughout. The
children are on the skeleton at the render boundary and the drawn body
alternates. The 86 drifts are the hub instance with the unarmed machine
live: the hand 0.6-1.2 m from the solve, the machine writing over it.

### What flickers

The copy and its hands; the servo-skulls (`darktidevr_skull_throw.lua`
moves the flying companion's root children in its post_update and
flushes with `World.update_unit_and_children`; the companion is a game
unit with its own animation). Steady: the weapon; the rigid gloves of the
hands-only mode (`place_rigid_hand`: the glove unit's root moved so the
hand joint lands on the target, the fingers copied, flushed with the
children call). The gloves are spawned by the same profile spawner as the
copy, with the same `optional_ignore_state_machine`.

### This build

- `machines` at ready: `Unit.has_animation_state_machine` for the copy,
  each gear unit and the avatar's weapon units.
- The marker: a glove spawned as the hands-only mode spawns one (a profile
  carrying only the glove item, no machine asked for, the machine
  disabled once spawned), its root set 35 cm above the copy's head joint
  every frame with the copy's rotation, flushed with the children call.
  Overlay modes only. The observable is the user's eye: the glove steady
  over a flickering body, or flickering with it.
- `check_after_render`: the original render call is wrapped once at the
  top of the `ScriptWorld.render` hook, and the copy's root and hand are
  read after it; `after_render=moved/checks max_m` in the heartbeat. And
  `between_frames=moved/checks max_m`: the copy as the last render left it
  against the next frame's start, read in `run_scheduled` before the pose.
- The feet: the ankle target height is the spawn pose's ankle height above
  the root (0.101 m at scale 1; the spawn pose stands on the root's
  plane), not the toe-derived 0.074; and after the leg solve the foot's
  pitch on the ankle-to-toe line is measured and put back to the rest
  pose's. `foot_pitch_deg=solved/solved rest_pitch_deg=rest/rest` on the
  gait line. Not worn.

## Worn, 14:20: the marker flickers; the copy's numbers alternate

On 9a6e40f. The user: "There's no glove", then "I found the glove, it was
above and behind me for some reason, and it flickers."

```
machines avatar_slot_primary=false avatar_slot_secondary=false copy=false slot_body_arms=true slot_body_face=false slot_body_legs=false slot_gear_extra_cosmetic=true slot_gear_head=true slot_gear_lowerbody=false slot_gear_upperbody=false
marker=ready machine=false
prerender calls=80400 checks=5630 drifted=0 child_render_over_1mm=0 ... after_render=0/5630 max_m=0.0000 between_frames=0/5629 max_m=0.0000
gait ... toe_above_ground_m=0.125/0.132 foot_pitch_deg=4.7/4.6 rest_pitch_deg=-28.0/-27.2
```

The glove was placed by the marker body's root at the copy's head, so
the glove item, hanging from that body's rest-pose hand, sat above and
behind. It flickers. It is a unit with no animation state machine, moved
by its root only, from the copy's head joint; the rigid gloves of the
hands-only mode are moved by their roots from the controller and are
steady, as is the weapon. Therefore the numbers the module computes for
the copy alternate frame to frame. The root does not (the probe's
`d_unit_m` has been 1.8 cm a frame, the avatar's own step, all day), so
the alternation is in the solve above the root: the head after the neck
follow, the torso, the arms. Every within-frame check is closed: the
children on the skeleton, nothing moved after the render or between
frames.

The machine census: the copy has none (the disable at ready removes it;
`had_machine=true` earlier was read after an enable), nor do the
weapons; the arms, head and extra-cosmetic gear units carry one. With
the marker result that is not the lead it looked like.

### This build

The probe gains, per moving frame, the step since the previous frame of
the copy's head joint (`d_head_m`), its right hand joint (`d_hand_m`),
the recorded wrist target (`d_hand_target_m`) and the marker's root
(`d_marker_m`), and prints the head and hand positions. An A-B-A-B
alternation is a large step of the same size every frame. The marker is
placed by its own hand joint half a metre ahead of the copy's head at
head height.

The feet: after the pitch correction the solved pitch still read +4.7
deg against a rest of -28, and the toe joint stood 12 cm above the
ground point (the ankle target rose 2.9 cm with the spawn height and the
foot is still pitched up). The gait line now says whether the toe joint
is a child of the ankle in this rig's scene graph; if it is not, rotating
the ankle cannot move it and the correction was applied to the wrong
joint's frame. Not worn.

## Worn, 14:26: the probe named the flicker

On e85810f. The user: flicker unchanged, the glove in front and
flickering too; "the flicker only occurs when moving, not when looking
around or waving the hands, just moving the whole character"; toes
pointed up worse.

Ten consecutive moving probe lines (2,294 in the run):

| d_avatar_m | d_eye_m | d_neck_target_m | d_unit_m | d_head_m | d_marker_m | d_hand_target_m |
|---|---|---|---|---|---|---|
| 0.0210 | 0.0000 | 0.0342 | 0.0342 | 0.0342 | 0.0343 | 0.0002 |
| 0.0230 | 0.0551 | 0.0781 | 0.0781 | 0.0781 | 0.0779 | 0.0552 |
| 0.0276 | 0.0001 | 0.0303 | 0.0304 | 0.0303 | 0.0305 | 0.0000 |
| 0.0261 | 0.0579 | 0.0841 | 0.0840 | 0.0840 | 0.0839 | 0.0580 |
| 0.0259 | 0.0002 | 0.0260 | 0.0260 | 0.0260 | 0.0258 | 0.0001 |
| 0.0232 | 0.0000 | 0.0366 | 0.0366 | 0.0366 | 0.0367 | 0.0003 |
| 0.0240 | 0.0596 | 0.0839 | 0.0838 | 0.0838 | 0.0837 | 0.0596 |

The copy's root against the avatar's, from the printed positions,
alternates between about (+0.027, -0.021) and (+0.050, +0.030): two
places 5 cm apart along the direction of travel, every other frame.

The eye (`presentation.eye_pose`, the tracked eye stored against the
body anchor) advances every other frame by two frames' worth: the
fixed-step anchor. The recorded wrist targets advance on exactly those
frames by the same amount: the same anchor. The camera's position is
built on that anchor. Everything the mod draws from the anchor steps
together with the view and holds still against it: the weapon, the
rigid gloves. The copy's neck target was the eye plus the smooth-lag
shift from the morning (first-person unit minus component position),
which does not cancel the eye's step on the same frame, and stepped 3
then 8 cm; the root is moved by `neck_offset` so the neck lands on the
target, so the root stepped 3 then 8; the head and the marker copied the
root. Against a view stepping 0 then 6, that is two places. It happens
only while moving because the anchor only steps while moving.

Earlier in the day the copy's root stood on the avatar's interpolated
root (smooth) with the targets on the anchor, and flickered; the shift
put the targets onto the avatar's timeline while the view stayed on the
anchor's, and it flickered the other way. The one timeline the view is
on is the anchor's.

### The change

The shift is removed: neck and shoulder targets are the frame's, and the
root lands where the neck follow puts it, on the anchor's timeline. The
`shifted` helper is gone; `smooth_offset` stays for the probe's
`anchor_lag_m`. The probe gains `d_unit_rel_eye_m`, the root's step
against the eye: what the view sees.

### The toes

`left_pitch_stages_deg=aim:.. rebase:.. aimed:..` on the gait line: the
foot's pitch as the knee's aim left it, after the rest rotation is
re-based to the foot's heading, and after the foot is aimed. The 14:26
log read +4.7 deg after the re-base against a rest of -28, and the
axis-angle correction turned the toes further up (the sign: about the
side axis from up x forward, a negative angle raises the toe). The foot
is now aimed with `aim_joint`, the knees' own path, at the point a flat
foot's toe occupies: the rest pitch below the ankle along the foot's
heading. Not worn.

## Worn, 14:36: one timeline in Lua, and the phase

On c0161e8. The user: no change to the flicker; one of the two locations
is definitely the right one, the other lags behind.

| d_avatar_m | d_eye_m | d_neck_target_m | d_unit_m | d_marker_m | d_hand_target_m | d_unit_rel_eye_m |
|---|---|---|---|---|---|---|
| 0.0323 | 0.0744 | 0.0753 | 0.0752 | 0.0752 | 0.0731 | 0.0010 |
| 0.0326 | 0.0006 | 0.0003 | 0.0003 | 0.0003 | 0.0024 | 0.0006 |
| 0.0338 | 0.0732 | 0.0747 | 0.0747 | 0.0746 | 0.0735 | 0.0015 |
| 0.0351 | 0.0008 | 0.0002 | 0.0001 | 0.0002 | 0.0005 | 0.0007 |

Over 4,537 moving lines the root's step against the eye is 0.6 mm mean,
2.4 cm max, three lines over 2 cm. The copy, the eye and the wrist
targets step together. The feet: `toe_above_ground_m=0.030/0.040
foot_pitch_deg=-28.0/-27.2 rest_pitch_deg=-28.0/-27.2
left_pitch_stages_deg=aim:-16.1 rebase:-11.6 aimed:-28.0`.

What remains is one frame of lag on the frames the anchor advances,
which is the pre-world pose: `run_scheduled` posed the copy from the
previous post_update's eye and wrist poses, and the anchor those are
built on had already moved on for this frame. The rigid gloves and the
weapon are placed after the refresh in the same post_update and hold
still; the marker, placed pre-world, flickered.

### The change

The pose returns to the locomotion post_update, after `post.body_ik`;
the WorldManager hook, `schedule` and `run_scheduled` are removed; the
between-frames read moves to the top of `api.update`. The copy has no
state machine (census, 14:20), so joints written there are drawn. The
render check reads `presentation.eye_pose` at the render boundary
against the eye the pose was built on (`state.posed_eye`):
`render_eye_lag=over/checks max_m` in the heartbeat, over 5 mm counted.
Under the pre-world pose this would have read an anchor step on
alternate frames; on the frame's own inputs it reads zero. The
source-scan test now asserts the post_update pose after the body IK and
the absence of the pre-world hook. Not worn.

The 13:20 fact stands and is narrower than it was read: a running
machine owns the skin. It was not a rule about the phase.

## Worn, 14:44: the flicker is gone

On 3391c66. The user: "flicker is gone, however physics objects (cloth
etc) is still flickering/wobbling and skulls are still flickering. Now
we've got this working, try re-enabling the original 3p model legs and
attaching them to the torso, since the custom-ik run animation is really
bad."

```
prerender checks=22498 drifted=0 after_render=0/22498 between_frames=0/22497 render_eye_lag=44/22498 max_m=0.0169
moving lines 7539: d_unit_rel_eye_m mean 0.0006 max 0.0299
gait ... toe_above_ground_m=0.028/0.030 foot_pitch_deg=-28.0/-27.2   (37 of 40 lines)
```

The whole day's flicker, in one line: the copy was on a different
timeline from the view. First on the avatar's interpolated root while
the view stepped on the fixed-step anchor; then, after the morning's
shift, on a mix of the two; then, posed before the world update, on the
anchor but a frame behind it. The view, the hands and the weapon are
built on the anchor refreshed in the locomotion post_update; the copy
posed there, after the refresh, from the frame's own eye, holds still
against them. `render_eye_lag` reads the eye at the render boundary
against the eye the pose was built on and is the number that says so.

### The stock legs

The user's instruction at 14:44 amends the separation rule for the legs.
In the animated-legs mode the copy's leg joints (under the two upper
legs, `Mirror.leg_indices`) take `Unit.local_pose(avatar, index)` every
frame; the gait stands down. The layout is checked by name at ready
(`Mirror.same_layout` on the hips, upper legs, lower legs, feet and toes
of both units); a mismatch keeps the gait. The test's separation scan
cuts the two marked blocks out before scanning, so every other avatar
read still fails it. `stock_legs hips_copy_above_floor_m=..
hips_avatar_above_floor_m=.. toe_above_floor_m=../.. stretch=..` every
900 frames: whether the legs need lowering or grounding is read off
that, not guessed. The height stretch scales the hips and feet when the
calibrated height is outside the settable range; copied local poses
would overwrite the feet's scale, and the line prints the stretch so a
run with one is recognisable. Not worn.

### Cloth and the skulls

Cloth is simulated against a body that steps 0 then 7.4 cm every other
frame: the anchor's cadence, which the camera, the hands and the weapon
share. It wobbles for that reason; the stock avatar's cloth rides the
game's interpolated root. Smoothing it is a change to the anchor itself,
for everything at once. The skulls: their offset is applied in the
flying companion's post_update, registered after the locomotion system
(`extension_system_configuration.lua`), so it runs after the anchor
refresh; which timeline the companion's own root and the offset are on
is for a probe to say.

## Worn, 14:57: the skulls named; the reflection becomes a mirror

On 8636182. The user: "legs working, physics objects still jiggling,
skulls still flicker. Also, the mirror model's legs are still the old
way, and its head should follow my headset position (tracked the same
way the hands are). Also, its hand animations should match mine, and it
should have the same weapon/item equipped that I do. Also, it should be
a true mirror, rather than me but rotated 180 deg."

```
SKULL_MOTION (40 lines): d_skull_root_m mean 0.0828 (0 of 40 under 2 mm)  d_eye_m mean 0.0105 (23 of 40 under 2 mm)  d_skull_rel_eye_m mean 0.1757
stock_legs hips_copy_above_floor_m=1.044 hips_avatar_above_floor_m=0.774 / 0.851 / 0.864 toe_above_floor_m=0.440/0.354, 0.281/0.194, 0.238/0.559
```

### The skulls

The companion's root moves every frame on the game's interpolated
timeline; the view steps on the fixed-step anchor. While following, the
module used to place nothing (the stock update was fed the lazy heading
and left to move the skull). Now, while following, the drawn skull is
placed at the real root minus the anchor's lag (first-person unit
position minus the fixed-step component position, `anchor_lag`), with
the same `place` the bridge and the throw use, so it steps with the
view. The real root is untouched and the bridge still starts from it.
`d_skull_rel_eye_m` is the number.

### The stock legs

The copy's hips stand at 1.044 m; the stock animation carries the
avatar's at 0.77-0.86, and the copied legs hang the difference above the
floor (toes 24-56 cm up). The user called the legs working; nothing is
changed. Grounding them is a decision with three shapes, each with a
cost the numbers now give: the leg solve pushing the animated feet to
the floor (straighter legs, the run's knee lift reduced), the leg bones
lengthened by about a third, or the hips lowered to the animation's
height with the spine stretched to keep the neck at the headset.

### The reflection

- Stock legs: `animated_legs = true` on the reflection mode; the same
  copy of the avatar's leg-subtree local poses. Not mirrored: the
  reflection's left leg is the player's left leg.
- Head: `follow_head`. The head joint's world rotation is the headset's
  rotation (reflected for the mirror) times a constant captured once
  when the player first looks within 20 degrees of the body's heading:
  the head's rest frame relative to a yaw-only eye frame.
- Fingers: the parent instance hands the reflection an accessor to its
  own copy (`reflection.overlay`); each frame the reflection copies the
  finger joints' local rotations from the overlay's hands, each side
  from the other side.
- Weapon: `Mirror.keeps_slot(slot, settings, with_weapons)` keeps the
  weapon slots for the reflection's spawner; the avatar's inventory
  component's `wielded_slot` is wielded on the spawner when it changes
  (`wield_slot`), after `set_visibility(true)`. The spawner attaches it
  to the right hand as the game does.
- A true mirror: `Mirror.mirror_plane(pivot, heading, distance)` is the
  vertical plane half the mirror distance ahead of the neck across the
  heading; `reflect_point`, `reflect_dir`, `reflect_yaw` reflect across
  it. The root is the reflected avatar root, the heading the reflected
  frame yaw, the neck target from the reflected neck point on the
  reflected head yaw, each shoulder from the other side's reflected
  shoulder, each arm from the other hand's recorded pose with the
  position reflected and the rotation rebuilt from its reflected forward
  and up (a proper rotation; the reflected right hand is a left hand),
  the head from the reflected headset rotation. The old turn-and-stand
  block is gone. Tests on the pure helpers: the plane point is its own
  image, twice is the identity, 1.25 m before lands 1.25 m beyond, the
  heading reflects to face back, a 30-degree turn to 150.

Not worn.

## Worn, 15:10: the anchor goes smooth

On 3a4407b. The user: skulls fixed; physics objects still move as if
flickering; legs tilted forward about 15 degrees; the mirror's head
below the player's and squished; the mirror's hands upside-down; the
mirrored weapons present.

- **The anchor.** `presentation.anchor_head_position(first_person_extension)`
  returns the first-person unit's world position (the game's
  interpolated timeline, `update_unit_position` every frame) when it is
  alive and within 0.5 m of the component's position, else the
  component's. `body_camera_anchor`, its alignment diagnostic and the
  camera's fallback read it. Every consumer of the anchor moves every
  frame: camera, hands, weapon, copy, skulls. The skull module's
  `anchor_lag` becomes zero by construction and subtracts nothing. The
  cloth was jittering against a body stepping 0 then 7.4 cm on alternate
  frames; the observable is `d_eye_m` on the probe (one smooth step a
  frame) and the cloth itself. Not worn.
- **The legs.** The upper legs take
  `inverse(yaw(avatar root)) * world_rotation(avatar, upleg)` re-based
  on the copy's root yaw, after the local-pose copy; the joints below
  keep their copied locals. `stock_legs` logs `hips_pitch_deg` and
  `upleg_pitch_deg` for both units, the pitch of the joint's forward
  axis.
- **The mirror's head.** The head constant was
  `inv(yaw(eye)) * inv(yaw(head)) * head`; it is `inv(yaw(eye)) * head`.
- **The mirror's hands.** `Quaternion.look(reflected forward, -reflected up)`.

## Limits

- The smooth timeline is measured cause and reasoned fix: the probe shows
  the copy on the fixed-step timeline and the avatar's root on the frame
  timeline, and the correction is their difference. Not yet worn; the
  probe's `anchor_lag_m` and `d_unit_m` columns say whether it took.
- The one-writer body frame stays: it was a real second writer of the
  frame's yaw, it just was not the one the body was flickering from.
- The rest pose is now the spawner's first frame made neutral by rule:
  square, upright, hips at standing height. The spine's own curve from that
  frame is kept. Whether it reads as a good standing pose is a worn
  question; `DARKTIDEVR_BODY_MIRROR rest ...` logs every number it used.
- A player outside the settable height range gets the stretch, which is
  correct in height and untested in proportion.
- The torso squaring uses the shoulder line; a rest frame with one
  shoulder shrugged would be squared to the shrug.
- The flicker is not fixed. It is instrumented; the next worn log names the
  stepping quantity, and the fix follows the 16 and 17 September pattern for
  whichever it is.
- The weapon fix rests on one worn observation and Fatshark's own usage of
  the call; the engine's rule for a visible unit under a hidden parent is
  not documented anywhere this mod can read.
- Read out of a log and reproduced in a harness with stand-in units; not worn.
- The mirror-side change (no rig on a layout mismatch) has no harness.
- Whether the copy needs the dev flag at all is a separate question. With the
  flag off the tracked-arms visibility branch already hides every stock slot
  but the arms (hidden under a rig) and the weapon, so the overlay may stand
  alone on the option; that has not been run.
