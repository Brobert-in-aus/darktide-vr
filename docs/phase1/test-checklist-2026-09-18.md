# Worn checklist: 18 September 2026

Branch `codex/alpha-4-2026-09-14`. The items of
[17 September](test-checklist-2026-09-16.md) (47 to 54) are still waiting on
a worn round; these are the day's own, numbered on from them. Items are
headings so a Markdown viewer cannot renumber them.

## Start state

- The user was out for the day and said launches were allowed, so unlike
  yesterday's items these have been run in the game as well as unit tested;
  each item says what its unattended run actually showed.
- Everything below is in the installed mod; the only flag left in the mod
  folder is `darktidevr_crosshair_scale.flag`.

## To try

### 55. Aim zoom

Mod Options, Darktide VR, **"Aim zoom (%)"**, default **12**, range 0 to 30;
it needs "Aim focus" on. Aim down the sights with any ranged weapon: the
world comes 12 per cent closer, eased in over about a fifth of a second, and
eases out again when you lower the sights. It works by rendering a narrower
cone into the same eye image while the headset is told nothing changed, so
the whole view magnifies, including the HUD's world markers, which stay
attached to what they mark.
**Check**: does 12 per cent feel right, or would you rather 10, 15, or more?
It is a slider, so try a few. **Watch for**: anything drawn over the world
that does *not* move with it while aiming (a marker, the interaction prompt,
the crosshair), and any discomfort — a zoom moves the world faster than your
head, which some people feel.

### 56. The aim-down-sights vignette, visible at last

No option of its own (it comes with "Aim focus"). Aiming down the sights
should now dim the edges of your view, clear in the middle and darkest at
the very edge, easing in and out with the aim.
**Why it never worked**: it was painted into one of the several images the
runtime cycles through, so most frames showed whatever that image last held;
and its darkening was sized for a 61-degree half-angle while Virtual Desktop
shows about 52, so even when it was painted, at 45 degrees off centre it
reached 9 of 255. Both are fixed: it is painted for every image, and its
size comes from the field of view the runtime reports.
**Check**: is the dimming too strong, too weak, or in the wrong place? The
clear centre currently ends around 30 degrees off centre.

### 57. The item radial, the last of it

Two more faults behind "infrequently it'll pull out the item": the radial
only owned the stick from the frame *after* its button went down, so a stick
already held over could still fire its own binding as you pressed; and
reaching for an interaction was dead for as long as a gun was wielded,
because both the radial and the reach shared a rule that gave way to
two-hand support's standing offer.
**Check**: hold the carried-items control with the stick already pushed and
press — no weapon switch; flick repeatedly; and, with "Reach to interact"
on through its test flag only, this is not worn-visible.

### 58. Nothing else changed

The rest of the day's work is instrumentation and guards that should be
invisible: log lines that measure the marker cells and the two pixel spaces,
a copy of your character that hides itself rather than standing in your view
if its rig does not match, and a guard against the viewer submitting a layer
it has no image for.
**Check**: the ammo count, the wrist display, world markers and the
interaction prompt all look as they did; nothing flickers or is missing.

### 59. The body, two ways (worth a look, not a change)

Nothing here is switched on by default. Today measured the full body two
ways and neither is finished, so the useful thing is your eye on which is
less wrong:

- **What ships now** (`Full body` on): the copy is enlarged about 1.3 times
  until its neck reaches your head. Its neck therefore meets your head, but
  its shoulders move outward and upward with it, and the arm solve then
  stretches the forearm 13 to 19 per cent to reach your hands.
- **`darktidevr_body_mirror.flag` = `overlaytrue`** (write that file in the
  installed mod folder, delete it after): no enlargement at all. The spine
  bends to bring the neck up and the arms take the lengths your calibration
  implies (0.52 m shoulder to wrist). The arms then reach your hands with
  under 3 cm of stretch instead of 42 cm — but 18 cm of the neck-to-head gap
  remain, so your head still sits above the body.

**If you have five minutes**: try the flag, look down, and say which reads
better — a body that meets your head with long arms, or one with your own
arms whose head sits high. That decides whether the next body work is the
legs (to close the remaining 18 cm honestly) or something else.

### 60. The reticle, if an unattended run has proved it first

Only worth your time once the run below has shown it lands where it should;
if this session has not said so, skip it.

The reticle is a quad layer today, which means Virtual Desktop's compositor
places it, and with your FOV tangent at 90 per cent it places quad layers
with a projection that does not match the display -- the same fault that
turned the loading boards. For the reticle that is roughly a degree ten
degrees off centre, and it swims as you turn your head against your aim.
Drawn into the eye images instead it is placed by the projection the world
is placed by.

Off by default. To try it, launch with `-ReticleInEyes`.

- Aim at something ten metres off, hold the aim, and turn your head slowly
  left and right without moving the gun. **The reticle should stay on the
  thing you are aiming at.** Today it should drift off it and come back.
- Put the reticle on a small distant target near the edge of your view, not
  in the middle. Is it on the target, or beside it?
- Anything wrong with the image itself -- a smeared corner, a square of game
  window where the reticle should be -- matters more than placement. Say so
  and turn the switch off.

### 61. The options menu, reorganised (two minutes, no headset needed)

You asked for this today. Mod Options, Darktide VR is now a short list of
sections rather than forty-three settings in a column, and a setting that
only matters while another is on sits underneath it.

Nothing you have set has changed -- the ids are the saved keys and none was
renamed -- so the check is only whether it reads better:

- Are the eight sections the right eight? Is anything filed where you
  would not look for it?
- The nesting: the aim zoom under aim focus, the grip mode and virtual stock
  under two-hand support, the wrist display's size under the display, the
  haptic strength under the haptics mode (it should disappear when you set
  haptics to off). Does the indentation read clearly, or would you rather
  they were flat?
- Is anything you use every session now buried a level too deep?

The section titles are also the tab labels, and there are eight of them
now where there were three -- if the tab bar is cramped or a title is cut
off, say so.

Say which sections you would move things between and it is a five-minute
change.

### 62. The aim zoom, now that it lands where it points

This is the one item below that is a *correction to something you may already
have felt*. The zoom went in this morning at 12 per cent and the reticle was
not moving with it: the world magnifies about the centre of your view and the
reticle stayed where the unmagnified image said, so it sat inside its target,
further in the further off centre you looked. Then the first fix was made in
the wrong frame and displaced targets that had been right. Both are fixed and
the maths is pinned by a test, but it has never been in a headset.

With a ranged weapon, sights up:

- Put the reticle on something small about ten metres away, **near the edge of
  your view rather than in the middle**, and bring the sights up. Does the
  reticle stay on it?
- Now hold the aim and turn your head slowly, keeping the gun still. The
  reticle should stay on the target through the turn. (If it drifts only
  while you turn *fast*, that is a known one-tick lag, about 0.4 degrees at a
  hard turn — say so and it can be chased.)
- Then look well away from where you were facing when the view last
  recentred, and repeat. This is what the second fix was about: it should
  behave the same there as straight ahead.

### 63. The wrist display looked at from straight above (30 seconds)

Two small things changed in how the hand panels are drawn.

- Hold your wrist up and look **straight down** at it. The panel should hold
  still. It used to spin for a millimetre of head movement at that angle, and
  at dead vertical it vanished; now it holds its last roll and, if you turn
  right round while looking down at it, it will snap once when you look up.
  That snap is deliberate — say if it is worse than the spin was.
- Drop your hand out of tracking and bring it back while still looking down
  at it. The display should appear. It would not before.
- Any text on the hand panels that is cut off at the top or bottom, or missing
  where you expected it: it is now dropped rather than allowed to spill into
  the neighbouring panel, so a label that is simply absent is worth naming.

## Suggested order

1. In the Psykhanium with a ranged weapon: 55 and 56 together (aim, hold,
   release), then 57.
2. Anywhere: 58, which is really "does anything look different that
   should not".
3. 62 in the Psykhanium with the same weapon — it is the correction most
   likely to be felt, and it needs no setup.
4. 63 anywhere, in half a minute.
5. 61 at the desk, with the headset off.
6. 60 only if this session's notes say an unattended run saw the reticle in
   the right place.
