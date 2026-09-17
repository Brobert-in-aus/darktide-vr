# Worn checklist: 16 and 17 September 2026

Branch `codex/alpha-4-2026-09-14`, after the 0.2.0-alpha.1 release
(`d6d0e90`, tag `v0.2.0-alpha.1`). Session state and evidence:
[handover](../handoffs/2026-09-16-session.md). Each deployment adds an item
here when it is installed.

Rewritten on the evening of 17 September to what is still to try worn. The
results of the two worn rounds and the fixes they led to:
[16 September](../handoffs/2026-09-16-session.md) ("The evening: the worn
session") and [17 September](worn-results-2026-09-17.md).

Items are headings, not a numbered list: a Markdown viewer renumbers a list
that starts at 6 as 6, 7, 8, which is how the 17 September results came back
against different numbers. The numbers are the ones the handover, the results
and the changelog cite.

## Start state

- The installed Lua and viewer match the branch head (`9741baa`), checked file
  by file against the previously deployed commit before copying, 17 September
  evening. The capture DLL and proxy are the 16 September build. The viewer
  before the board fix is kept as
  `artifacts/unattended/board-projection-20260917/darktidevr-xr-harness.before-board-projection.exe`.
- **Check the flags before putting the headset on.** Several features read a
  `*.flag` file in the installed mod folder and turn themselves on when one
  is there, whatever the option says. Anything other than
  `darktidevr_crosshair_scale.flag` should be deleted first. (Checked at the
  17 September deployment: only that one.)
- None of items 39 to 46 has had an unattended run: you were at the headset
  all evening, and no launch is made while you are. Their pure parts are unit
  tested (274 pass) and a review read the engine side; what that cannot
  show is said in each item.

## Passed worn, 17 September (nothing to do)

6 viewer survives a zero field of view; 9 eye anchor; 15 and 16 hand roles;
22 to 28 the "still works" family (profiler wrapping, haptics, flag polls,
sampler gates, marker values, marker head frame, native rebuild); 30 boards
re-seat on a recenter; 34 and 38 the boards ("board fix worked": the viewer
draws them itself, right with the FOV tangent at 90 per cent).

## Still open from before

### 8. Calibration T-pose guidance

Restart; open the VR calibration. The T-pose instruction asks for arms
straight out at shoulder height, fully extended, controllers pointing
outward. After saving, the result shows the arm span with the span expected
for your height, and names any problem with the T-pose. 17 September: "see
later note"; waiting for the note. (From the full-body report: height 178 cm,
eye height measured about 172 cm, span captured with arms in the right
position.)

### 13. Tag what your off hand points at

Withdrawn. 17 September: "left hand tag pointing doesn't seem to work (also
disable it for now)". See 46.

### 14. The body overlay (dev flag)

Superseded by 44: the option now turns the overlay on.

## New on 17 September

### 39. No sliver beside the ammo count

Restart; no option. The sliver was the left ends of the wrist display's
three bars. They are laid out 243 px left of their overlay cell's centre:
inside the 528 px cell of a 2112-wide eye target, 4 px outside the 477 px
cell that Virtual Desktop's 90 per cent FOV tangent gives, and so inside the
ammo count's cell next door. (It went away whenever a bar was not drawn to
its full width or the cells were claimed in another order.) The wrist
panel's scale now fits its layout to the cell, and every overlay rectangle
is clipped to its own cell. Check: nothing beside the ammo count or the
charge count at any health, toughness or stamina; the wrist display looks
the same (at the 90 per cent tangent it is drawn about 6 per cent coarser,
the same size in the world).

### 40. Charge display left of the weapon

Restart; Experimental features, "Weapon charge display". The melee count and
the charge bars sit ahead of the weapon hand's grip and toward your midline
as you look at it, level with the hand, where the ammo count sits beside a
gun. Above the grip they landed on the forearm holster's count (your
screenshot: "1/8" over "8 / 49"). Check: count and bars each sit left of a
right-hand melee weapon, clear of the holstered gun's count; say if it wants
to be nearer or further (6 cm to the side, 8 cm ahead; the bars' centre a
further 5 cm out so their near end clears the hand).

### 41. Talk zone a third smaller

Restart; "Push to talk with the off hand at the mouth". The zone is 13.5 cm
around the mouth to start talking and 19 cm to keep talking (were 20 and
28). Check: it still opens with the hand cupped at the mouth, and no longer
with the hand merely near the face.

### 42. Item radial with a gun out

Restart; Experimental features, "Item radial". With a ranged weapon wielded
the radial closed a moment after opening, and a flick then went to the
stick's own binding (the weapon switch): two-hand support offers its claim
every frame a gun is out, wherever the off hand is, and the radial gave way
to any offer. It now gives way only when that hand is at or approaching the
foregrip, or a grip is already held. Check: with a gun out, hold the
carried-items control: the radial stays while held; flick to an empty
sector: nothing happens, and no weapon switch; flick to a filled one: it
wields. By design it will not open while your off hand is on or near the
foregrip, or while a toggled two-hand grip is latched.

### 43. Servo skulls: sides, following, leading

Restart; Experimental features, "Grab and throw the servo skull". Neither
change showed on 17 September because the first-person body reports third
person to the game's equipment code, so the skulls read their third-person
rest table (flamethrower 55 cm to the right, medical to the left) and only
the first-person one was mirrored; and the stock skull is placed from your
head's look direction, so a drawn skull chasing it 0.2 s behind still read
as head-locked. Now: both tables are mirrored (for a right-handed player;
left-handed, stock already has the throwable skull at the off hand); every
skull of yours keeps its place relative to a heading that follows your head
only beyond 20 degrees, tracks your head's position exactly as the HUD does,
and leans up to 30 cm ahead along your run. The drawn skull is now the
skull's own root, so the grab zone is where you see it. Check: flamethrower
skull at your left, 30 cm forward, medical and regular on the right; glance
left and right: they stay put; turn: they swing round after you; run: they
move ahead of you; grab the flamethrower skull with the off hand where you
see it; send it and let it return. Not proven unattended; the log's
`DARKTIDEVR_SKULL_THROW follow=root` line gives the node counts that say
whether the throw's child-node placement can ever have shown.

### 44. Full body (experimental) is the body overlay

Restart (for the new files; after that the option takes effect within a
couple of seconds); Experimental features, "Full body (experimental)"; not
in the hub. The option used to turn on the older headless body, which keeps
the character's own height, hence the head floating above it. It now turns
on the overlay: a copy of your character scaled until its neck meets your
head, arms solved to your controllers, clavicle swing, protraction and soft
stretch (the `both4` result). A few seconds to appear. Check, as item 14
asked: looking down, are the arms, gloves and gun readable, one pair of
hands; reach across, up and out: do the arms stay on the controllers; strafe
and turn: does the body follow your head rather than the run animation; is
the neck placed behind your eye; and whether enlarging the copy 17 to 24 per
cent is worth it against arms of their calibrated length.

### 45. Body mirror on F8, in the Psykhanium

Restart (a new key binding); "Body mirror shortcut", default F8. A copy of
your character stands 2.5 m ahead facing you; press again to remove it.
While it is up it replaces the overlay of 44 (one copy at a time), and it
shows the game's own animated pose, not the solved arms. It turns itself
off when you leave the Psykhanium.

### 46. Tag by pointing out of the menu

Restart. The option is gone and a saved value is ignored; tagging follows
the weapon.

## Suggested order

1. At launch: 39 (look beside the ammo count), 46 (the option is gone).
2. In the Psykhanium as Robobert: 43 (skulls), 40 (charge display), 42 (the
   radial with the gun out), 41 (talk zone), then 44 (turn Full body on) and
   45 (F8).
3. When the note arrives: 8.
