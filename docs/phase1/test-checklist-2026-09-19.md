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

Nothing is deployed. The sync script refuses while Darktide is running, and it
was running for this whole session, so everything above is committed and built
but not installed. It needs the game closed and a deploy with
`-FullBodyExperimental -BodyTrace -ArmCensus -ViewerLog`.

The viewer binary changed for item 3, so this is a deploy of the harness as well
as the Lua.
