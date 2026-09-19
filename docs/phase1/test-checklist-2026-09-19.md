# The worn checklist, 19 September 2026

Numbering restarts at 1. Headings rather than a numbered list, because your
viewer renumbers ordered lists.

Four items: three fixes and one new option. The reticle turned out to be
findable after all -- your note that it is correct outside the sights is what
named it.

---

## 1. One body

You said it plainly: *"There's no reason to ever show that 3p model. All we
ever show is the new custom-IK model."*

The log agreed with you before I changed anything:

```
DARKTIDEVR_BODY headless_3p applied hidden_slots=slot_gear_head,slot_body_face
                visible_3p_units=7 hidden_3p_units=5
```

Only the head and face were ever hidden. Seven slot units stayed visible. The
hiding worked off two allow-lists and neither contains `slot_body_legs` or
`slot_gear_lowerbody`, so the stock legs have been drawn inside the copy's legs
on every frame this mode has ever run — which is why there was no flicker and
no change when the arms fix landed. The arms and torso were on the other list,
hidden only once the copy took the hand rig, which is a race you can see.

It is inverted now. While the copy is drawing your body the stock model is
hidden **wholesale** — root plus children in one call — and only named
exceptions are shown back. A slot Fatshark adds in a future patch is hidden
rather than drawn as a second body. The switch is forced the moment the copy
becomes ready rather than waiting out the sixty-frame heartbeat, so you should
not see both even briefly.

**Test**: load in and look down, then at your legs, then toggle the mirror with
F8 and look at yourself and at the reflection.

**Report**: how many bodies you can see on yourself, and how many in total with
the mirror on. The answer I am expecting is one and two.

### 1a. The second body was a second *spawn*, and it was not the stock model

Written after the above, from your report of two bodies on loading into the
Psykhanium. The stock model was hidden as promised; the arm census in the
same log named the other body, and it was one this mod spawns itself:

```
DARKTIDEVR_IK hand_rig=body                              23:13:07.948
DARKTIDEVR_IK visual_proxy=inactive mode=upper_body      23:13:07.957
DARKTIDEVR_IK visual_proxy=active   mode=upper_body      23:13:07.964
DARKTIDEVR_ARM_CENSUS ... source=proxy_body  arms=4 wrist=0.077,5.855,2.020
DARKTIDEVR_ARM_CENSUS ... source=mirror_copy arms=4 wrist=0.077,5.855,2.020
```

Under the full-body dev flag the body proxy runs in its older upper-body
mode and spawns a torso-and-arms profile of its own. The copy took the hands,
the proxy destroyed its units, and sixteen milliseconds later the upper-body
branch read its own cleared state as "nothing spawned yet" and spawned them
again. Only the hands-only branch ever knew about the rig. Two spawned bodies
on you, at the same wrist, with the stock model correctly hidden underneath
both.

Fixed in the proxy itself: a body that owns the rig is the body, in either
mode, and the proxy spawns nothing while it lives. The IK in the main file
takes the tracked-hands path under a rig too, flag or no flag, because the
full-body path solves on whatever unit it is handed and under a rig that
would be your gameplay avatar. Written up in
[two-bodies-2026-09-19.md](two-bodies-2026-09-19.md).

**Test**: the same as item 1. **Report**: the same count. The log line to
quote if it is still wrong is `DARKTIDEVR_IK visual_proxy=... mode=...`,
which now says `body_rig` while the copy owns the hands.

### 1b. Worn at 09:40: one body, weapons invisible, flicker when moving

Your report: *"Only one body. It flickers constantly when I move (almost
certainly the same root cause as all the previous flicker-when-moving
issues). Weapons are invisible."* The log agrees on the count: one spawn,
and the proxy stayed pose-only (`mode=body_rig`). Closed on the spawn.

**Weapons.** The first cut hid the stock root *with its children* in one
call and showed the weapon back by its own handle; the weapon is linked
under the root's hand joint and stayed hidden. Fatshark's code never shows
a child back under a hidden parent, and the gloves mode has always hidden
the body the other way round: root shown, slots hidden one by one. The copy
branch now does exactly that.

**Test**: load in with a gun wielded, then swap to melee and back.
**Report**: whether the weapon is drawn, and whether the stock body has come
back with it (it should not: the same slots are hidden, only the root is
left visible, as in the gloves mode).

**Flicker.** Not fixed; measured. You are right about the shape -- every
flicker-while-moving so far was something drawn from a value that advanced
in fixed steps while the view advanced every frame -- but the copy stands on
four such values (the avatar's root, the neck target, the tracked eye, its
own root) and reading the source has not said which one steps. The trace
that would have shown it was written `disabled` by this morning's second
deployment. It is on again, and a new line, `DARKTIDEVR_BODY_MOTION`,
prints every frame while you move: the step each of the four took since the
last frame. The one that alternates against a view that does not is the
one to fix, and the fix is the 16 and 17 September pattern.

**Test**: walk and strafe for ten seconds early in the session (the trace
budget is 25,000 lines and this spends about ninety a second while you
move), then stand still. **Report**: nothing beyond what you already said;
the log carries the answer.

### 1c. No base animation on the body, and none on the legs either

Your rule, applied in full: the copy holds its spawn pose and only the
mod's solves move it -- the heading from the body frame, the neck, the
clavicles, the arms to your controllers. Nothing is read from the hidden
model's joints any more; its root position is the one thing taken from it,
because that is where you are standing. The legs-from-the-avatar step in the
15 September design was never your instruction and is withdrawn: the legs
hold the rest pose until a gait is written. A test now refuses the next
line of code that would read an avatar joint.

This also removes item 2's mechanism. The torso turned faster than your
head because the avatar's counter-rotation came through the copied spine;
with nothing copied, there is nothing to leak, and the torso faces the body
frame's heading because the root does.

**Test**: stand still and look down (no sway), enter the sights (no stance
shift), stick-turn slowly and quickly (item 2's test still applies), then
walk and look at your legs.

**Report**: whether the body is now still when you are, whether the sights
move it, whether the torso still leads or drifts on a turn, and whether the
standing rest pose reads as a reasonable stance -- it is the spawner's first
frame, and if it is a bad one that is the next thing to fix.

### 1d. The legs walk

A procedural gait ([gait-2026-09-19.md](gait-2026-09-19.md)). Each foot
stays planted where it is until the body has moved 8 cm from it, or turned
40°, and then steps -- one foot at a time, the farther first, landing where
the body will be a quarter of a second on. A small movement is a small, low
step; a walk is a stride that shortens and quickens with speed. The feet
come down flat and turned to your heading. Room-scale movement drives the
feet the same way the stick does, because both move the same root.

**Test**: stand still and lean or shift your weight (a small step or none),
take one real step across the room and back (a step each way), then walk
and sprint with the stick, then turn on the spot, then crouch.

**Report**: whether the feet stay planted when you are still, whether a
small movement gets a small step rather than a stride or a slide, whether
walking reads as walking, whether the feet turn with you, and whether the
knees bend the right way when you crouch. The feet are put down on the
floor a raycast finds under them, so walk up the Psykhanium's steps and
along its ramps and say whether each foot lands on the step it is over and
whether a foot ever floats or sinks.

### 1e. Worn at 10:51: too large, turned right, no leg movement

All three were in the log. The frozen spawn frame was a staggered combat
stance (left foot 18 cm forward, torso turned right): the turned neutral.
Its neck sat low, so the scale-to-neck ran to its 1.3 cap to reach your
head: the size. And the gait ran, at up to 4.8 m/s, but one foot at a time
could not keep up with a run, so the legs trailed at full stretch.

Your rule, applied: the copy's scale is the game's own character height for
your profile, which the calibration sets, fixed for the session, and
nothing in game scales it again. Height beyond the settable range goes into
the leg, spine and neck bones as a stretch along the bone; the arm bones
take the calibrated arm lengths. The rest pose is made neutral at ready:
torso squared to the root and stood upright, hips at standing height for
the legs' own lengths, feet symmetric. The gait has a run now: above
1.5 m/s the next foot leaves once the first is halfway, swings re-time
themselves as you accelerate, and the reach cap is a metre.

**Test**: stand and look down and at the mirror (size and squareness),
then look at your hands at full reach (arm length), then walk, then sprint.

**Report**: whether the body is your size, whether it stands square with
you when you are neutral, whether your arms reach where your hands are,
and whether the legs run when you run. If the size is still off, the line
`DARKTIDEVR_BODY_MIRROR rest scale=... character_eye_m=... calibrated_eye_m=...
stretch=...` has every number that decided it.

### 1f. Worn at 11:14: far too small, wrists into forearms, and the flicker

**Size.** My residual compared your real eye height with the avatar's and
shrank the copy 11 % toward a head the camera is not at: the camera stands
at the avatar's eye height in this mod, and at the game's scale alone the
copy matches it. The residual is now camera against the game's own eye
height, which agree, so the stretch is 1.

**Wrists.** Your T-pose was right and the lengths were applied exactly.
The fault was that a shortened bone moved the joint and left the skin
behind: the forearm mesh overhung the wrist when bent, and the reach
stretch pushed the hand past the mesh. Bones now change length through the
joints' scales, so the skin follows and the hand keeps its own size.

**Flicker.** Two writers, as you said. The weapon is steady because it
rides the hidden avatar; the copy and its hands ride the body frame, whose
smoothing was advanced by three callers on three clocks (the copy each
frame, the two-hand stock at input time with the previous frame's time,
the holsters at draw time), and a sample with a different time re-ran the
smoothing and snapped the heading. Snapped one frame, smoothed the next.
It advances once per frame on one clock now, and everyone gets the same
frame.

**Test**: stand and look down and in the mirror (size), bend your arms in
close and reach out fully (wrists), walk and strafe (flicker), sprint.

**Report**: size, whether the wrist stays joined at both extremes, and
whether the flicker is gone. The motion probe runs without the trace flag
now, so the log will show the per-frame steps either way.

### 1g. Worn at 11:36: the probe named the flicker; fingers; two-handing

**Flicker.** The probe ran, and it says: your avatar's root moves 1.5 cm
every frame, while the eye the copy is placed from stands still for two or
three frames and then jumps 3 to 5 cm, and the copy does exactly what the
eye does. That eye is re-based on the body anchor, which is the
first-person component's position, and the game writes that in its fixed
update at 60 Hz while you render at 140. The copy now adds the difference
between the game's smooth first-person unit and that fixed-step position
to everything it places, so it stands on the same timeline your view does.

**Fingers.** The gloves had a grip curl captured per weapon; the copy's
hands never got it. They do now, on their own hand joints.

**Weapon alignment.** Not changed yet. The arm log now carries the angle
between the drawn hand and the recorded wrist pose; if that is near zero
and the gun still sits wrong, the difference is in the weapon's authored
basis, which is the next thing to measure.

**Two-handing.** The restore after the crash brought back a settings file
from 14 September with two-hand support off; every session after it had no
two-hand lines and the three before it did. It is on again in your
settings, and the backup the restore uses is refreshed from the corrected
file, so the next restore keeps it.

**Test**: walk and strafe (flicker), wield a gun and look at your fingers,
then grab the gun with your off-hand.

**Report**: whether the body now moves with you every frame, whether the
fingers curl on the grip, and whether two-handing works. The probe's
`anchor_lag_m` column shows the lag being taken up either way.

### 1h. Worn at 12:07: the root is smooth, the flicker stays, feet a little high

**Flicker.** The probe says the copy's root now moves as smoothly as your
avatar's, so the root is no longer what alternates. Whatever does, does it
after the copy is posed or in a joint the probe does not watch. The copy
now reads its own root and right hand again at the last point before the
frame is drawn and logs any drift since its update, with a summary line
every 600 frames so a clean result is on record too.

**Feet and height.** The floor is right: the avatar's root, the copy's
root and the raycast floor agree within six millimetres over the session.
The ankle height came from the spawn frame's foot, and the sole sits below
the ankle by more than that; the height is now taken from the rig's toe
joint, and the hips' standing height comes down with it.

**Industry practice.** VRIK's height calibration is the head target
against the head bone standing straight, scaling one to the other, which
is what the game's own character-height setting does here. For the feet
it anchors the toes rather than the ankles; the toe measure above is the
first half of that. For locomotion it calls procedural stepping legacy and
uses authored walk and run cycles adapted to the terrain by the solve;
those are animation, which your rule keeps off this body unless they are
ours. The gait here is the legacy approach with the run overlap.

**Test**: walk and strafe as before; stand and look at your feet.

**Report**: whether the flicker is unchanged, and whether the feet now sit
on the floor. The log's `prerender_drift` and `prerender checks=` lines
carry the answer to the first either way.

### 1i. Worn at 12:22: the check never ran; the legs can run the game's clips

**The check.** It sat inside a branch of the render hook this build never
takes, so its silence meant nothing. It is at the top of the hook now and
runs every frame; the next log carries its summaries.

**Animated legs, behind the flag.** The copy runs the game's own
third-person state machine for your wielded weapon on its own skeleton,
fed the same inputs the game feeds the avatar: the wield picks the machine,
every third-person animation event is re-issued on the copy, and the move
speed is mirrored each frame. The solve for everything but the legs is put
back over the machine's output at the render boundary. The gait stands
down while the machine is live and is the fallback whenever it is not. The
base model contributes nothing of its pose.

**Set up for you**: `mods\darktidevr\darktidevr_body_mirror.flag` in the
installed mod now holds `overlayanimated`, so launching the game as usual
runs the animated legs in the Psykhanium (the flag is gated out of the hub
like the option). Delete the file to return to the option's overlay with
the gait. The sync deployment does not write this file, so it survives a
redeploy; it is listed here so it is not left behind by mistake.

**Test**: with the flag, wield a gun, stand still, walk, sprint, strafe,
then swap to melee and back.

**Report**: whether the legs walk and run from the game's cycles, whether
the upper body still follows you exactly, whether the legs turn with the
body when you strafe, and whether a weapon swap keeps them going. The log
line `animated_legs=live machine=...` says the machine took; any
`animated_legs=failed` or `=waiting` line says why the gait is running
instead.

### 1j. The 12:52 session tested nothing of this: my code threw at ready

Your report: *"body is too short & too crouched by default, and hand
animations are gone again, but the flickering is fixed."* All three are
right, and all three describe the hidden model's headless fallback with
the old upper-body proxy, not the copy. The log:

```
DARKTIDEVR_BODY_MIRROR failed=...:855: attempt to call global 'log_once' (a nil value)
```

The machine-assignment code I placed above the helper it calls resolved
that helper to a nil global, threw on the copy's first ready frame, and
the module shut itself down for the session and destroyed the copy. What
you were looking at was the stock avatar at its own scale in its combat
stance, with no finger capture, and it does not flicker, which is
consistent with everything measured so far. The animated legs, the render
check and the toe height were never exercised.

Fixed by declaring the helpers before the functions that use them, and a
guard in the mirror test now fails on any helper called above its
declaration; it fails on the module that shipped at 12:52 by name and
line. The flag is still set, so the same launch as before tests item 1i
for real. Sorry for the wasted sitting.

### 1k. Worn at 13:02: the machine refused the copy, so you saw the gait with locked knees

Your report: *"Flicker is back, body is definitely floating, no run
animation, legs just stay straight and swing forwards together in the
direction of travel."* The log:

```
DARKTIDEVR_BODY_MIRROR animated_legs=failed error=...: Unit `#ID[...]` has no animation state machine
```

The call the game uses blends a new machine onto a unit that already has
one, and the copy's machine had been disabled at ready, so it refused.
The gait ran the whole session. Its standing hips left the knee eight
degrees of bend, one per cent of slack, so with the feet on the floor the
legs locked straight, and every step, both feet in the air at a run, read
as a stiff swing. That is the straight legs, and the standing pose in your
screenshot is the gait at rest. The flicker is the copy's again, since the
copy was drawn this time; the render check still wrote nothing, because it
compared the snapshot's frame with a counter that increments after the
snapshot, so it never ran.

Fixed: the machine is set with the call the UI spawner itself uses; the
rest bend is twenty degrees; the toe constant is zero, since the feet
still floated with it; and the check counts every call and writes a
summary every 600 whatever it did, with the reason for each early return,
so it cannot be silent again.

**Test**: the same launch. **Report**: whether `animated_legs=live` is in
the log and the legs walk from the game's cycles; whether the feet sit on
the floor; and the flicker as before. The line `prerender calls=...` is
the check's heartbeat this time.

### 1l. Worn at 13:10: no change, and what the data now excludes

The log, this time complete:

```
animated_legs=failed error=...: AnimationStateMachine `#ID[...]` does not exist
prerender calls=108600 checks=9196 drifted=0 skipped=no_copy=28407,other_world=70996
```

The machine failed on the second call too, this time on a unit whose
machine instance the disable at ready had taken away, so the gait ran
again; the knee and toe changes were in, so "no change" on the legs and
the float is a report on the gait as it stands. The render check ran
9,196 times and found no drift: between the copy's update and the frame,
nothing moves its root or its hand. With the probe's smooth root, the flat
yaws and this, every quantity that can be measured from Lua is steady,
and you see the body alternate. The one stage between the scene graph and
the pixels that Lua cannot measure is the skinning, which the engine
refreshes with the animation update, and this copy's animation has been
disabled since it was ready, while the weapon is a rigid unit and the
stock avatar animates every frame.

**Two things in this build, both labelled for what they are.** The machine
is enabled again before it is set, and both engine calls are tried with
both errors kept, so the log names the refusal exactly. And when the
machine still cannot be set, the spawner's own idle stays running and the
copy's whole solved pose is put back over it at the render boundary. That
second part is an experiment, not a fix: it is the only way from Lua to
give the copy an animation update every frame, and whether that is what
the flicker needs is decided by the observable below, not by me.

**Please record, rather than report, the flicker this time.** In the
headset, with the mirror up (F8), walk toward and past the reflection for
five seconds while looking at it, and record it with the headset's own
video capture. The reflection is a target in the world frame, so a
recording shows frame by frame whether it moves against the floor plates
the way your view does or in two steps. I will pull the recording over
adb from the headset's VideoShots folder and measure it. The viewer's
eye readback takes one frame per request, a quarter of a second apart,
so it cannot show an alternation.

**Report** as well: `animated_legs=ready machine=... restore_all=...` and
any `animated_legs=failed` line from the log, which say which of the two
paths ran; whether the legs walk from the game's cycles if the machine
took; and the float.

### 1m. Worn at 13:20: the still body named the stage; the copy is now posed before the world update

Your report: the character model was still with no hand tracking while
the reflection moved; the hands flicker and only the weapons do not; the
gloves of the hands-only mode do not flicker now though they did at first.

The log for that run: both engine calls refused the gameplay machine
(`had_machine=true ... does not exist`), so the experiment ran: the
spawner's idle left running on the copy and the whole solved pose written
back at the render boundary. The render check read the solve there 17,369
times with no drift, and you saw the idle. The scene graph held the solve
and the skin showed the machine. That is the measurement that was
missing: joint poses written after the world update do not reach the
drawn skin.

The frame, from the game's source: gameplay update, then the world update
(animations, then scene), then the extensions' post_update, then render.
The hands, the weapon and the copy were all placed in post_update. The
weapon is rigid and the gloves move only their unit's root; the copy has
its joints written, and the copy is the one that alternates. The game
writes its own procedural joints before the world update, never after.

**The change.** The copy is posed before the world update now: post_update
records the frame's inputs and a hook on the world manager's update poses
the copy from them ahead of the animation and scene update, so its joints
reach the skin the way every animated unit's do. The inputs are one frame
old (the avatar's root, the recorded wrist poses), which the camera's own
anchor shares; the copy's hands trail the weapon by one tracking sample,
about 9 mm at a metre a second. The machine experiment is withdrawn: the
machine is disabled again when the engine refuses it, nothing is restored
at the render boundary.

**What decides it.** Your report of the body while walking, and the log:
`animated_legs=ready machine=nil leg_joints=24` (the gait), the
`prerender calls=... checks=... drifted=...` line (now a read-only check
of what the world update did to the copy after it was posed; drift there
would be new information), and the probe as before. If you record again,
face the reflection and **strafe** with the stick for a few seconds (the
reflection keeps its distance from you, so there is no walking past it).
The floor plates then slide sideways behind a reflection that stays put,
and a frame-old alternation shows as the reflection jittering against
them. Both recordings so far walked toward it, and forward motion moves
it in scale, not across the plates, so they could not show an
alternation either way.

### 1n. Worn at 13:47: the flicker survived the pre-world pose; the children are measured and flushed

Your report: strafing, the flicker extremely obvious and visible in the
recording, between exactly two locations, one of which looks correct; the
character too short and floating; a hand rested on your real shoulder
sits 5-10 cm above the drawn one; your eyeline is above the reflection's.

The log for that run: the copy was posed before the world update (the
WorldManager hook was installed, `posed frames=14400` against 14,917
render checks), no drift, and the flicker stayed. So the timing of the
joint writes was not it. The recording, measured on the reflection's eye
lenses against the crate behind it at 1920 wide: the lenses jump 12 px on
average and up to 82 px frame to frame while the crate moves 4 px. That is
tens of centimetres, not a one-frame lag.

**What has never been read.** Everything drawn of the copy is a child
unit linked to its skeleton by the profile spawner: the gear, the hands,
the head with its lenses. Every check so far read the copy's own joints,
which were always where the solve put them. This build reads the
children: for each linked unit carrying a named joint (head, hands, hips,
neck), the distance between its joint and the copy's same joint, three
times a frame: as the update left them, after a flush with the call the
rigid gloves have always used (`World.update_unit_and_children`, the
labelled experiment), and at the render boundary.

```
DARKTIDEVR_BODY_MIRROR children linked=N joints=...
DARKTIDEVR_BODY_MOTION ... child_before_m=... child_after_m=... child=slot:joint
DARKTIDEVR_BODY_MIRROR prerender ... child_render_over_1mm=N child_render_max_m=... child_update_over_1mm=N ...
```

A `child_before_m` in the centimetres with `child_after_m` at zero says
the linked units were being left where the previous flush put them, and
the flush is the fix. Zero everywhere says the drawn skin is not the
scene graph and the next measurement has to be of the renderer.

**Height and float, measured this run.** A `height` line at ready gives
the copy's own eyes (the face unit's eye joints), neck and shoulder
joints against the camera's eye, all in the root's frame, and the gait
line gains `toe_above_ground_m` per side. Those numbers, not a guess,
decide the height and the float.

### 1o. Worn at 14:05: the children were fine, the servo-skulls flicker too, a glove marker at your head, and the feet

Your report: the top of the torso is right relative to the camera and
comfortable; the legs float and the body should extend further down with
the torso top kept; flicker unchanged; the servo-skulls floating around
you flicker as well.

The log for that run: 13 linked child units measured three times a
frame. As the update left them, before the flush: off on 4,338 of 4,340
moving frames (2-5 cm at the head gear, the reflection's hips by its whole
2.5 m). After the flush and at the render boundary: zero on every one of
19,523 checks. So the children stand exactly on the skeleton when the
frame is rendered, and the body still alternates. Also new: the hub's
unarmed machine did set on the copy once at 04:05:36 (`animated_legs=live
... unarmed_hub`), and with it running the render check saw the hand
drift 0.6-1.2 m on 86 frames, the machine writing over the solve.

**What flickers and what does not.** Flickers: the copy, its hands, the
servo-skulls (game units with their own animation, whose nodes the mod
moves). Steady: the weapon, the rigid gloves of the hands-only mode. The
gloves are the one thing the mod draws by moving a unit's root only.

**Two things in this build, both labelled.** A `machines` line at ready
lists which units carry an animation state machine: the copy, each of
its gear units, and the weapon units. And a marker: one glove, spawned
the way the hands-only mode spawns them, stood 35 cm above the copy's
head joint every frame by its root, with the copy's own numbers. Look
up: if the glove holds still while the body under it flickers, the pose
the module computes is steady and the fault is in how the linked,
machine-bearing units are drawn; if the glove flickers with the body,
the pose itself alternates and the Lua checks have been reading it at
the wrong moments. Two more counters in the heartbeat close the frame:
`after_render=moved/checks` (the copy read again after the engine's
render call) and `between_frames=moved/checks` (as the last render left
it against the next frame's start).

**The feet, from the numbers.** The gait line gave
`toe_above_ground_m=0.045/0.052` at rest and the leg's ankle error under
a centimetre: the legs reach the ground point, and the toe joint sits
4.5-5.7 cm above it where the spawn pose has it 2.7 cm up. The foot was
pitched toes-up after the leg solve, and the ankle target was the
toe-derived 7.4 cm rather than the 10.1 cm the spawn pose stands at.
This build restores the foot's rest pitch after the solve and uses the
spawn ankle height; the gait line now carries `foot_pitch_deg` against
`rest_pitch_deg` per side, and `toe_above_ground_m` should read about
0.029. The height itself is unchanged: `height` gave the copy's eyes 11
cm below the camera's with the neck at 1.515 and the shoulders at 1.51-
1.53 in the root's frame, which is the torso you called right. If the
feet still float after this, the lever is the leg bones, stretched the
way the arms are, and the numbers above are what it would be set from.

### 1p. Worn at 14:20: the glove marker flickers, so the copy's numbers alternate; the solved joints go in the probe

Your report: the glove was above and behind you, and it flickers.

That is the bisect answered. The glove is a unit with no animation
(`marker=ready machine=false`), placed by its root only, from the copy's
head joint. The rigid gloves of the hands-only mode are placed the same
way from the controller and are steady; the weapon is steady. So the
numbers the module computes alternate frame to frame, and the root, the
one joint the probe has read all day, is not where: it stepped 1.8 cm a
frame like the avatar. The log also closed every other door: the
children on the skeleton (0 of 5,630 checks), nothing moved after the
render (0 of 5,630) or between frames (0 of 5,629), and the machine
census read the copy and the weapons without a machine and the arms,
head and cosmetic gear units with one.

**This build measures the solved joints.** Every probe line while you
move now carries `d_head_m`, `d_hand_m` (the copy's head and right hand
after the solve), `d_hand_target_m` (the recorded wrist target) and
`d_marker_m` (the glove's root), each stepped against the previous
frame. A two-location alternation is a large step every frame, the same
size, where the root's is 1.8 cm. Whichever column shows it names the
stage. The glove now hangs half a metre in front of your head at head
height, placed by its own hand joint the way the gloves are.

**The feet.** The gait line read `rest_pitch_deg=-28 foot_pitch_deg=4.7`
after a correction that should have made them equal, and the toe joint
12 cm above the ground point. The line now says whether the toe joint is
under the ankle in the rig's graph at all (`toe_under_ankle`), which
decides whether rotating the ankle can move it.

### 1q. Worn at 14:26: the probe named it; the copy steps with the camera now; the foot is aimed

Your report: flicker unchanged, the glove in front of you flickering
too; the toes pointed up worse; and the rule that the flicker only
happens when moving, not when looking around or waving the hands.

The log, ten consecutive moving frames:

```
d_neck_target_m=0.0342 d_eye_m=0.0000 d_unit_m=0.0342
d_neck_target_m=0.0781 d_eye_m=0.0551 d_unit_m=0.0781
d_neck_target_m=0.0303 d_eye_m=0.0001 d_unit_m=0.0304
d_neck_target_m=0.0841 d_eye_m=0.0579 d_unit_m=0.0840
...
d_hand_target_m: 0.0000 / 0.0552 / 0.0000 / 0.0580 ...     d_avatar_m: a steady 0.021-0.033
```

While you move, the eye steps 0 then 6 cm a frame: it is stored against
the fixed-step body anchor. The recorded wrist targets step 0 then 6 cm
on the same frames: same anchor. The camera is on that anchor too. That
is why the weapon and the rigid gloves hold still against the view: they
step with it. The copy's neck target, the eye plus the "smooth" shift I
put in this morning, stepped 3 then 8 cm, because the shift no longer
cancels the eye's step frame by frame; the root is moved so the neck
lands on that target, so the root stepped 3 then 8 cm too; the head and
the marker glove copied the root exactly. Against a view stepping 0 then
6, that is a body alternating between two places, only while moving.
The avatar's own root steps a smooth 2.5 cm and had nothing to do with
it.

**The change.** The shift is off. The neck and shoulder targets are the
frame's, on the anchor's timeline, and the root lands where the neck
follow puts it, on that timeline. The probe gains `d_unit_rel_eye_m`,
the root's step against the eye, which is what the view sees: it should
read near zero on every moving frame, where `d_unit_m` will now read 0
then 6 like the eye.

**The toes.** The pitch stages will show it, but the log already says
the rest-rebased rotation leaves the foot at +4.7 deg against a rest of
-28, and the axis-angle correction turned it further up, which is what
you saw. The foot is now aimed with the same helper that aims the knees:
the toe is pointed at where a flat foot's toe sits, the rest pitch
below the ankle along the foot's heading. The gait line carries
`left_pitch_stages_deg=aim:.. rebase:.. aimed:..`; the last should equal
the rest pitch and `toe_above_ground_m` should read about 0.03.

### 1r. Worn at 14:36: one timeline in Lua, still two places drawn; the pose goes back to post_update

Your report: no change to the flicker; one of the two locations is
definitely the right one, the other lags behind.

The log: the copy's root now steps exactly with the eye, 0 then 7.4 cm
on alternate moving frames, the wrist targets with them, and the root's
step against the eye is 0.6 mm on average over 4,537 moving frames
(three over 2 cm). The feet: toe 3 cm above the ground point, foot
pitch -28 against a rest of -28, the aim stage doing what the re-base
did not.

So in Lua the copy, the eye and the hands are on one timeline, and what
you see is the copy a step behind the view on alternate frames. That is
the phase: since 13:38 the copy has been posed from a hook before the
world update, on the previous post_update's inputs. The body anchor
that the camera, the hands and the weapon are built on is refreshed in
the locomotion post_update, and it advances every other frame; on the
frames it advanced, the copy still stood on the old one. The rigid
gloves and the weapon are placed in post_update from the frame's own
anchor and hold still; the marker glove, placed pre-world, flickered.

**The change.** The copy is posed in the locomotion post_update again,
after the body IK has refreshed the anchor and placed the hands, and
the pre-world hook is gone. The copy carries no state machine (the
census), so its joints written there are drawn; the still body at 13:20
was a machine left running, a different thing. The render check now
reads the eye at the render boundary against the eye the copy was
posed from: `render_eye_lag=over/checks max_m` in the heartbeat. It
would have read an anchor step on alternate frames under the pre-world
pose; it should read zero now. That is the number that decides this,
beside your eyes.

The servo-skulls are placed in the flying companion's post_update; if
that runs before the player's locomotion post_update they have the same
one-frame lag, which is the next thing to check for them.

### 1s. Worn at 14:44: the flicker is gone; the stock legs on the copy; cloth and skulls

Your report: flicker gone; physics objects (cloth) still wobbling; the
skulls still flickering; and, with the body working, re-enable the
original third-person model's legs and attach them to the torso, since
the custom-IK run animation is bad.

The log: `render_eye_lag=44/22498 max_m=0.0169` (44 frames over 5 mm in
22,498, the largest 1.7 cm, against an anchor step of 7.4 cm every other
frame under the pre-world pose), the root within a millimetre of the eye
on 7,539 moving lines, no drift, nothing moved after the render or
between frames, feet flat at 3 cm.

**The legs.** In the animated-legs mode (the flag you are running), the
copy's leg joints, everything under the two upper legs, take their local
poses from the avatar's animation every frame, so they hang from the
copy's own hips wherever the solve has put them and run with the game's
clips; the gait stands down. Nothing above the hips is read; the guard
in the test cuts the two marked blocks out before it scans for avatar
reads, so anything else would still fail it. The joints share indices
because the copy is spawned from the same profile; that is checked by
name at ready (`animated_legs=ready legs=stock`), and a mismatch keeps
the gait (`legs=gait`). A `stock_legs` line every 900 frames gives the
copy's hips and the avatar's hips above the floor and the copy's toes
above it: those numbers say whether the legs need lowering or the feet
grounding, and I will not guess at either before they are read.

**Cloth.** The body now steps with the anchor, 0 then 7.4 cm on alternate
frames while you move, as the camera does. Cloth is simulated against
that stepping body, so it wobbles where the stock avatar's, on the
game's interpolated root, does not. That is a property of the anchor's
cadence, not of the copy; making it smooth means moving the camera, the
hands and the weapon onto an interpolated anchor together, which is a
separate piece of work and would take the wobble with it.

**Skulls.** The skull module moves the companion's root children by an
offset in the flying companion's post_update, which runs after the
player's locomotion post_update (the systems are registered in that
order), so it is not the phase the body had. What timeline the offset
and the companion's own root are on is not known from the code, so this
build adds a probe: `DARKTIDEVR_SKULL_MOTION` lines while you move, with
the step of the owner's root, the eye, the skull's own root, the drawn
offset, and the skull against the eye. The eye steps 0 then 7 cm; the
column that steps every frame instead is the one on the other timeline.

### 1t. Worn at 14:57: legs working; the skulls named; the reflection made a true mirror with legs, head, fingers and weapon

Your report: legs working; physics objects still jiggling; skulls still
flickering. And for the reflection: stock legs, the head following the
headset, the hand animations matching, the same weapon equipped, and a
true mirror rather than you rotated 180 degrees.

**The skulls, from the probe.** 40 lines while you moved: the
companion's own root steps 8.3 cm every frame (never under 2 mm), the
eye 0 then 3.9 cm on alternate frames (23 of 40 under 2 mm), the skull
against the eye 17.6 cm a frame. The skull rides the game's
interpolated root and the view rides the fixed-step anchor: the body's
fault of the morning, on the skulls. This build pulls the drawn skull
back by the anchor's lag each frame while it follows you, with the same
placement the bridge and the throw use, so it steps with the view as the
hands and the weapon do. The probe stays: `d_skull_rel_eye_m` should
fall from 17 cm to near zero.

**The stock legs, from the numbers.** `hips_copy_above_floor_m=1.044
hips_avatar_above_floor_m=0.774..0.864 toe_above_floor_m=0.24..0.56`:
the stock animation carries its pelvis 18 to 27 cm lower than the copy's
standing hips, so the copied legs hang that much above the floor. You
said the legs are working, so nothing is changed there this build; the
numbers say what grounding them would cost, and that is a separate
decision (the feet pushed to the floor by the leg solve, or the leg
bones lengthened, or the hips lowered with the spine stretched).

**The reflection.** In the reflection mode the copy's leg joints take
the stock animation the same way the overlay's do (`legs=stock` on its
ready line). Its head takes the headset's rotation, times a constant
captured the first time you look within 20 degrees of your body's
heading; look around and it should look around. Its fingers are copied
joint for joint from the overlay's hands each frame. Its spawner keeps
the weapon slots, and the slot you wield is wielded on it whenever it
changes (`reflection_wield slot=...`). And it is a true mirror: the
mirror plane stands half the mirror distance ahead of your neck across
your heading, and every input it is posed from is reflected across
that plane, with each side taking the other side's hand and shoulder.
Two known departures, both to look for: the legs are not mirrored (the
reflection's left leg is your left leg, which a mirror would show on
the other side), and the spawner puts the wielded weapon in the right
hand as the game does, where a mirror would show it in the left.

**Cloth.** Unchanged, and why is in 1s.

### 1u. Worn at 15:10: skulls fixed; the anchor goes smooth for the cloth; legs untilted; the mirror's head and hands

Your report: skulls no longer flicker; physics objects still move as if
there were a flicker; the legs tilt forward about 15 degrees with the
feet out in front; the mirror works, its head is below yours and a
little squished into the torso, its hands are upside-down rather than
mirrored; the mirrored weapons are present.

**Cloth: the anchor itself.** Everything the mod draws now steps 0 then
7 cm with the view on alternate frames, because the body anchor is the
first-person component's position, written in the game's fixed update.
Cloth simulated against a stepping body jitters, where the stock
avatar's cloth rides the game's interpolated root. The game's
first-person unit carries the same point on the interpolated timeline;
the anchor is that now, in the three places the component's position
was read (the camera anchor, its diagnostic, and the camera's fallback).
The camera, the hands, the weapon, the body and the skulls move every
frame together, and so does the world against you. Two observables: the
probe's `d_eye_m`, 0 then 0.074 all day, should read one smooth step a
frame, with `d_unit_rel_eye_m` still near zero; and your eyes on the
cloth and on the world while you walk. This is the largest change of
the day to how the view moves, and it is the change the cloth needs.

**Legs.** The copied leg poses were local to the pelvis, which the copy
holds upright while the animation tilts the avatar's; the difference
tilted the legs. Each upper leg now takes the animation's upper-leg
world rotation relative to the avatar's heading, re-based on the copy's
heading, so the legs stand as the animation stands them whatever the
pelvis does. The `stock_legs` line adds `hips_pitch_deg` and
`upleg_pitch_deg` for both units.

**The mirror's head.** A stray factor in the captured head constant
pitched the head down into the torso, which read as low and squished.
Fixed; the `height` line now runs for the reflection too, so its eye
height against yours is in the log.

**The mirror's hands.** A reflected frame is left-handed and one axis
has to flip to make the other hand's rotation. I flipped the right axis
and you saw hands upside-down; the rig's other hand is the mirror turned
about its forward axis, so it is the up that flips. Changed; look for
palms that match.

### 1v. Worn at 15:26: the anchor is smooth; the skulls were left on the old one; the rig names the hand flip

Your report: skulls flickering again, less than before; the mirror's
hands still not mirrored, facing the wrong way now instead of
upside-down.

The log: the eye moves every frame now (`d_eye_m` mean 2.4 cm, one
frame in 1,917 under 2 mm, where it was 0 then 7 cm), the copy stays
within 2 mm of it on 1,928 of 2,146 moving frames, and the skull's own
root moves every frame too. But the skull against the eye still moved
2.7 cm a frame: the skull module was still subtracting the difference
between the interpolated unit and the fixed-step component, which put
the skulls back on the timeline the view had just left. It subtracts
the difference to the view's actual anchor now, which is zero, and the
probe's `d_skull_rel_eye_m` should read near zero.

**The mirror's hands.** A reflected frame is left-handed and one axis
must flip to make the other hand's rotation. Flipping the right gave
upside-down, flipping the up gave the wrong way; that leaves the
forward, but rather than take the third guess the rig is asked: in its
rest pose the two hands are mirror images across the body's midline,
so the right hand's rest axes are reflected across it and compared with
the left hand's, and the axis that comes out reversed is the one the
rig flips. `hand_mirror flip=x|y|z dots=... trusted=...` at ready says
what it found; the same flip is applied to the finger rotations carried
across. If the rest pose is not symmetric enough to trust (any dot
under 0.8), the frame keeps its forward and up and the line says so.

**The mirror's height, in the log.** The reflection's `height` line
read the camera 1.903 above its root against 1.773 for the overlay:
the reflection's root stands 13 cm lower. Both instances now print
which they are, the root's world height, the avatar's, and the neck
follow's vertical offset, so the next log says where the 13 cm come
from rather than me guessing.

### 1w. Worn at 15:50: skulls fixed; the rig flips all three hand axes; the head levelled; the weapon moved to the other hand

Your report: skulls fixed; the weapon still in the wrong hand; the
mirror's hands upside-down; the mirror's head present but looking down.

The log: `hand_mirror flip=nil dots=x:-0.94 y:-0.77 z:-0.72 trusted=false`.
The rig's other hand reverses all three reflected axes, not one, and my
rule only accepted a single flip, so the mirror fell back to the
look default and you saw upside-down hands again. Three flips are as
proper a mapping as one (any odd number is), so the signs are now
taken per axis, trusted when each dot is at least 0.5 in size and an
odd number are negative, and applied to the hands' rotations, to the
finger rotations carried across (with all three flipped they carry
unchanged) and to the weapon's offset. The line reads `hand_mirror
signs=x:-1 y:-1 z:-1` now.

**The head.** The captured constant carried the rest head's own pitch,
which is the spawner's idle looking down; the reflection looked down
with it. At capture the rest head is turned level about its right axis
first, and `head_follow captured rest_head_pitch_deg=... eye_pitch_deg=...`
says how far down it was.

**The weapon.** The wield event is answered by the weapon's own flow,
which links it to the right hand. Two frames after a wield, the
reflection measures the weapon's pose relative to its right hand
joint, unlinks it, links it to the left hand joint, and sets the pose
carried across by the rig's sign map. `reflection_weapon
moved_to=j_lefthand ...` logs it; a failure logs once and leaves the
weapon where the flow put it. The engine's link calls are not used
anywhere else in the mod yet, so this is the first run of them here.

The skull-against-eye number was 3.0 cm a frame on this run's log,
with the old lag still in the build you ran; the fix for it is in.

### 1x. Worn at 16:05: the head from the model's own axes; the weapon's grip measured once

Your report: no fix to the head; the mirrored weapons alternate between
hands as you quick-switch and drift further from the character each
time. And the rule: the 3p model's default pose has the head
approximately neutral and facing forward, which says which of its axes
are which; the headset is what is tracked live.

**The head.** No capture and no levelling any more. The rest pose the
copy was spawned with has the head near neutral; which of the head
joint's axes point forward and up is read off it once, each snapped to
the nearest body axis so a slight rest tilt is not carried, and every
frame the head is the headset's rotation, reflected for the mirror, on
that exact axis mapping. `head_axes forward=.. up=..` logs the mapping.

**The weapon.** The log: the first move measured a grip of 5 cm from
the right hand, the later ones 40 cm and growing. The weapon's own flow
links it to the right hand on its first wield and only sets its pose
afterwards, so a weapon I had moved to the left hand stayed there and
each later measurement added the move. Now the grip is measured once
per weapon, on its first wield, and reused; and before each wield the
weapon I moved goes back on the right hand with its grip, so the flows
find what they expect. `reflection_weapon moved_to=j_lefthand grip_m=..`
should read the same grip on every switch.

### 1y. Worn at 16:25: the head at eye level; the weapon's half turn

Your report: weapons in the correct hand but upside down; the head
following yours but below your eye level.

The log: `head_axes forward=0,-1,0 up=1,0,0` (the mapping the head
tracks on), the grip the same on every switch (`grip_m=-0.053,0.045,0.010`
for the primary, `-0.056,0.045,0.009` for the secondary, four switches),
and the reflection's `height` line: camera eye 1.773 above the root,
copy eyes 1.698, neck 1.542.

**The head's height, from those numbers.** The neck target is put 19.2
cm under the eye (8 cm in the frame plus 10 cm extra, at scale 1.069)
and the rig's eyes stand only 15.6 cm above its neck joint; and the
neck follow never lifts the root, so the neck also sits 3.9 cm under
its target. Together, 7.5 cm. You judged the torso height right, so
the torso stays where it is; for the mirror the head joint is lifted
by the measured gap between the camera's eye and the copy's eyes each
frame. The reflection's height line should read an eye gap near zero.

**The weapon.** With all three hand axes reversed the grip rotation
carries unchanged, which leaves the weapon rolled half a turn about its
barrel in the other hand. It gets that half turn about the unit's
forward axis. If it now comes out backwards rather than upside-down,
the barrel is another axis of the weapon unit and the next log will
say which by elimination.

**The torso, from your 16:30 note** (the mirror's shoulders level with
your 3p model's, its head squished into the torso; the 3p model's
shoulders below your real ones; bring the 3p torso up a bit and the
mirror's head up a bit beyond that). The neck follow may now lift the
root to reach its target: that is the 3.9 cm the rest neck sat under
it, on both copies, so the 3p model's shoulders come up by that. The
mirror's head lift then covers what remains, the rig's own 3.6 cm
between its eyes and its neck, so its eyes land on yours. The stock
legs hang from the hips, so the feet rise with the torso; the
`stock_legs` line's `toe_above_floor_m` says by how much.

### 1z. Worn at 16:40: the head's lift read a stale joint; the barrel is the unit's right axis

Your report: weapon backwards; head freaking out.

**The head.** The lift was measured on the face unit's eye joints, and
that unit's positions refresh only at the end-of-frame children flush,
so each frame read the previous frame's lift and the lift alternated.
The rig's eyes-above-head distance is now read once
(`eyes_above_head_m=..` in the log) and the gap each frame is taken from
the copy's own head joint, which is current within the frame.

**The weapon.** No turn gave upside-down; a half turn about the unit's
forward gave backwards. Upside-down needs a half turn about the barrel,
and a half turn about the forward turned it end for end instead, so the
barrel is the unit's right axis. The half turn goes about that now, by
elimination rather than by guess.

### 1aa. Worn at 16:50: floating; the neck follow's lift was not 4 cm; the stretch to the floor

Your report: floating above the ground; stretch the torso and legs a
bit so the feet reach the ground with slightly bent legs; the model
height may not be calculated right, since standing your in-game floor
is level with the real one and your height is calibrated. You are 178
cm tall with eyes near 1.73 m.

The log, on the build that let the neck follow lift the root: the
offset read +0.204 up at ready and -0.487 down later, with 449 of
8,675 traced frames at the 0.5 m cap; the body stood 20 cm in the air
and later 49 cm sunk. The previous run's neck distance averaged 5 cm,
this one's 21 cm. The rig's shortfall is 3.9 cm, so a 20 cm lift is a
fault that the clamp had been hiding, and I do not know its cause yet.
Your eye height matches the camera: it read 1.74 m above the avatar's
root. The model's height is the other side of it: the copy is scaled
1.069 by the game's height setting, its rest neck stands 1.542 above
the root, and which of those the 20 cm comes from is what this build
measures.

**This build.** The neck follow's vertical part is held to 12 cm either
way while the numbers that decide it go on the height line: the
camera's height, the frame's neck, the target, the rest neck, and the
frame's scale, all in world metres, with a count of clamped frames.
And the stretch you asked for: the copy's hips above the floor against
the avatar's, whose animated feet stand on it, is the floor gap; the
chain from neck to ankle is stretched by k = 1 + gap / chain, spine and
upper legs by k, head, clavicles and ankles by 1/k, eased over a
second, never below 1 nor above 1.25. `stretch_k` and `floor_gap_m` are
on the height line; `toe_above_floor_m` on the stock-legs line should
read near zero when it has settled.

### 1ab. Worn at 16:50, your question: the model is not short, its rest torso was folded

Your question: why is the model too short in the first place, when it is
calibrated to your height, and the calibration should factor in its
posture.

It does, and the log agrees. The camera in this mod is anchored to the
avatar model's own eye joints, so the camera's 1.74 m above the root is
the calibrated model's eye height in its normal gameplay pose, and it
is your eye height. The copy did not stand like the model. The avatar's
hips stand 0.85 to 0.89 m above the floor with its eyes at 1.74, hips
to eyes 0.85 to 0.89. The copy's rest pose had its hips at 1.01 and its
eyes at 1.69, hips to eyes 0.67: the same rig at the same scale, 18 to
22 cm shorter through the torso, because its rest pose was the
spawner's crouched idle, pelvis pitched 20.7 degrees against the
avatar's 0 to 3, spine curve kept, and my squaring only fixed its yaw
and pushed the hips up to a straight-leg height. Long legs under a
folded torso: the feet float and the shoulders sit low.

**This build.** In the stock-legs mode the copy's rest torso is the
model's normal pose: once, at ready, the local poses of every joint
from the head down to the hips, the hips' own height included, are
taken from the avatar as the game stands it (`torso_rest=stock
joints=N`), and the standing-hips rule stands down. A static capture
of a pose, not the animation, in a marked block like the legs. The
neck follow should then need no lift, the stock legs' feet should land
on the floor, and the stretch factor should sit near one. A `torso`
line beside the height line gives hips-to-eyes for the copy and
hips-to-camera for the avatar; they should match.

### 1ac. Worn at 17:15: the stretch off, the eye stack on one line, the weapon as the mirror image of yours

Your report: the melee weapon turned 180 degrees about the vertical, the
gun pitched down 45 degrees; the torso and legs stretched and messed
up; the feet into the ground.

The log: `torso_rest=stock joints=6` took, and the hips stayed at the
model's height (`hips_z_m=0.872->0.872`). But the neck target sat 33 cm
above the rest neck, the lift clamped at 12 cm on every frame, the
floor gap read 0.2 to 0.5 m from that, and the stretch ran to its 1.25
cap on it and pushed the feet 6 cm into the floor. The target is the
fault: `frame_scale=0.753`, the tracked eye 2.0 m above the avatar's
root against your 1.73, the first-person unit at 1.896, the game's
camera height times the character scale. Those do not add up, and the
neck target is built from constants times that scale on that eye.

**This build.** The stretch is held at one (the gap still logs). An
`eye_stack` line beside the height line puts every height from the
floor to the tracked eye in world metres on one line, with the two
inputs the frame's scale is made of, so the next log says which number
is wrong rather than me tuning around it. And the reflection's weapon
no longer takes a grip constant: two frames after a wield it is
unlinked, and from then on every frame it stands at your own wielded
weapon's pose reflected across the mirror plane, position reflected,
rotation rebuilt from the reflected forward and up. That is correct
for any weapon; the one thing a mirror cannot give a chiral object is
its handedness.

### 1ad. Worn at 17:25 to 17:35: the mirror fixed in the world; the camera at the calibrated eye height

Your reports: place the mirror in world space at spawn so it does not
fly about as you move; the body is right now but the mirror's head is
about 10 cm low, and against the hub's model it is well low; a seated
start then standing, and a recenter should reset the height to the
calibrated one; every load into the Psykhanium you are too far up; you
think the default camera position on spawn is too high.

**The camera, from the log.** `camera_origin=first_person_fallback` in
every log today: the model eye anchor never captured, so the camera
sat at the game's first-person point, its camera height times the
character scale (1.896 m), plus two 5 cm fallback offsets: 2.0 m above
the floor. Your calibrated eye height is 1.72. Every body number today
was built on a camera 27 cm too high, and that is why the model read
short and why you are too far up on load. The camera's height above the
avatar's root is the calibrated standing eye height now, whatever the
anchor source (the source still gives the horizontal position), and the
hands' anchor takes the same height so they agree. A recenter keeps
that height because it is not derived from the headset. The body
frame's scale is made from the calibrated height too, not the live
headset height (a seated start had it at 0.75 all session). The eye
stack line now says why the model eye anchor fails.

**The mirror in world space.** The mirror plane is set once, on the
first frame the reflection has a frame to set it from, and kept for
the life of that copy (`mirror_plane fixed at=.. normal=..`). Toggling
off and on spawns a new plane where you then stand.

**The mirror's head.** The eyes-above-head distance had been read from
the face unit on the first frame, before that unit was flushed to the
copy, and read minus 25.5 cm; the lift then never landed. It is read
once at the end of a frame after the flush, in the root's frame, and
the lift is applied against the tracked eye in that frame.

### 1ae. Worn at 17:40: camera right, all good; the skull grab made a grab

Your report: the camera height is right and it all works; next, grabbing
the flamer skull should be an actual grab: the hand against the side of
the skull, the skull turning with the hand, not just translating.

The log for the run: the camera 1.723 m above the avatar's root, the
calibrated height; the mirror plane fixed; the eyes-above-head constant
6 cm, sane.

**The grab.** While the off hand holds the skull it is rigid to the
hand. On the frame the hold begins, the vector from the hand to the
skull's drawn centre is taken in the hand's frame and set to the
skull's radius (10 to 16 cm), so the palm sits on its side from
whichever direction it was grabbed, and the hand's rotation is taken
as the zero. Every held frame after, the centre is the hand plus the
hand's rotation on that vector, and the skull turns by the hand's
rotation since the zero, about its centre. The stock movement is still
fed the hold so the real root follows; the drawn parts are what the
hand holds. Released, the grab drops and the throw or the bridge takes
over as before. `grabbed offset_m=..` logs the vector on each grab.

### The weapon, and why it is still on the stock model

You asked why the weapon needs to be there. It does not, and it already is not
in any sense you can see: `sync_equipment_hand_to_proxy` writes the weapon
unit's own `j_righthand` node directly from the tracked wrist, so the stock
animation contributes nothing to where the weapon appears. It is parented there
and nothing more.

I have kept that one unit and shown it back through a named exception rather
than spawning a second weapon on the copy, for a reason I can point at: the
game addresses muzzle flash, shell ejection and weapon audio to the *equipped*
unit through its `fx_sources._muzzle`. A duplicate would be identical geometry
in an identical place with the effects still playing on the hidden original.

**Assumption recorded, not agreed**: that this is close enough to "functionally
nonexistent" for now. If you want the real separation, say so and I will cost
it properly rather than sneak it in.

---

## 2. The torso turning faster than your head

This one is arithmetic rather than a theory, which is a change from the last
four attempts at it.

The copy's joints are copied as **local** poses, and a local pose is relative to
the **avatar's** root. `body_yaw` then replaces the copy's root yaw with your
body heading, and never takes the avatar's root yaw out — so it leaks into
everything above the hips. With the wrong sign, because what the animation puts
into the spine during a stick turn is the *counter-rotation* that holds the
torso still in the world while the legs turn underneath. The copy inherited the
compensation without inheriting the turn it was compensating for.

The predictor is `d(torso) = d(copy root) + d(avatar torso) − d(avatar root)`,
and it reproduces your own trace, in degrees per sample:

| d_unit | d_av_torso | d_avatar | predicted | measured |
|--------|-----------|----------|-----------|----------|
| −0.04  | −0.73     | −10.53   | 9.76      | 10.11    |
| 1.96   | 4.77      | 0.00     | 6.73      | 6.60     |
| 1.55   | 2.32      | −7.18    | 11.05     | 10.25    |
| 4.55   | 2.03      | 1.16     | 5.42      | 4.91     |

Your head moved about a degree in each of those.

So it was never a rate to damp. It is an uncancelled term — which is also why
the body **drifts out of alignment** rather than merely lagging, and why "don't
second guess my reports" was the right correction when I kept measuring roots.
It is cancelled at the hips now, and those four samples are the test.

**Test**: stick-turn in both directions, slowly and quickly, then walk and turn
together. Then stand still and look at whether the copy stays square to you.

**Report**: whether the torso still leads your view, and whether it still ends
up misaligned after a few turns rather than only during them.

---

## 3. The reticle — found, and it was ADS-only all along

Two things you said cracked this. The error is **proportional to the distance
aimed**, and **the reticle is at the correct depth when you are not in the
sights**. Together they rule out the entire transport and point at one line.

`zoomed_frustum` renders the world through a narrowed frustum while the viewer
submits the field of view unchanged — the code says so itself: *"submitted
field of view is unchanged, which is what makes it a zoom."* Every angle from
the view axis is multiplied by the magnification, and so is the disparity
between your two eyes. A point at range D has disparity proportional to IPD/D;
multiplied by m it reads as IPD/(D/m). **The world in the sights appears at
D/m.**

The reticle does not. It is an OpenXR quad layer at a true world pose, which
the runtime composites through the *submitted* field of view — the unnarrowed
one. So the world comes forward and the reticle stays put, and it reads m times
further than the thing it marks. Proportional, ADS-only, gone outside the
sights.

And this is why six candidates inside the reticle path were each ruled out by
measurement without finding it. `magnified_target` — the existing correction —
renormalises the point to its original length. It **preserves the range by
construction**, so it could never have corrected a depth however it was tuned.
It is the angular half of the correction. The radial half was missing.

At your current 3% setting: **9 cm at three metres** — under the ground when
you are looking down at it — and **97 cm at thirty**. Which is "inside the
ground" and "further away than it should be", in the two places you saw them.

Five mutations of the new guard, all caught.

**Test**: aim at the ground two or three metres away and enter the sights, then
at a wall across the room and enter the sights again.

**Report**: whether the reticle now sits *on* the surface in the sights. If it
is better but not right, raise `vr_ads_zoom` — the residue should scale with
it, which would say the mechanism is right and a factor is off. Both ends also
log it now (`anchor_distance_m` from the game, `head_distance_m` and
`resolved=` from the viewer), so the numbers are there either way.

---

## 4. Melee animations, off (new option, default on)

The Nexus request: turn the melee swings off and keep the hands and weapon
tracking the controllers, leaving hit markers and slash effects alone.

The machinery was already there. `uses_stock_melee_animation` decides, per
action, whether the authored swing takes the hands from the tracking; the new
**Melee animations** checkbox gates it. Hit markers, impacts and slash effects
are played by the weapon's effect and damage systems, which never consult that
gate, so they are untouched — and keyboard and mouse reads the same flag, so it
turns the animations off there too, as you asked.

**Push and block keep their animations**, on your call. Both are read by other
people as well as by you: a shove that staggers, and a guard that says you are
blocking. Everything else — `sweep`, `windup`, `melee_explosive` — hands back
to the controllers.

Default is **on**, so nobody's melee changes until they choose it.

**Test**: with it off, swing a melee weapon and watch your hands and the weapon.
Then push, then hold block.

**Report**: whether the swing follows your controller all the way through,
whether the hit markers and slash effects still look right, and whether push
and block still read properly.

---

## Deployment

**Deployed and ready to launch.** Commit `c99d9aa`, pushed to both remotes,
282/282 tests passing, deployed as
`deployment-d593a6291d4a42e4a46db3f43279e5fc` (134 files, `deployment=committed`).
Verified after the fact rather than assumed: every installed Lua file matches
the repo byte for byte, and the installed viewer is the new build with the new
`head_distance_m` diagnostic in it.

Diagnostics on for this run, and nothing else — the deploy writes every other
flag as `disabled`, so no leftover from an earlier session is running:

| flag | why |
|------|-----|
| `darktidevr_full_body_experimental` | item 1 lives behind it |
| `darktidevr_body_trace` | the torso yaw chain for item 2 |
| `darktidevr_arm_census` | names the units on you if item 1 is still wrong |
| `darktidevr_xr_log` | `head_distance_m` and `resolved=` for item 3 |

The previous session's viewer logs are archived to
`artifacts/worn/2026-09-19-pre-deploy/` and cleared, so whatever is in
`mods/darktidevr/bin/darktidevr-xr-viewer.log` afterwards is from this run
alone.

### One setting to check before you start

**Melee animations** (item 4) is a new checkbox and it defaults to **on**, which
is the behaviour you already had. Turn it off in the mod options to test it.
Everything else is where you left it.

### What the trace budget will and will not cover

The body trace spends 25,000 lines and the last worn session used its whole
budget inside about five minutes of standing around. If item 2 matters most,
do the stick turns early rather than late.
