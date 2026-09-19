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
