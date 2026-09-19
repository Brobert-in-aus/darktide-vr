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
