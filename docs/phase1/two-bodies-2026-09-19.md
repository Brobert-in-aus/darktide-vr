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
