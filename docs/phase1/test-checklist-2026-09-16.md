# Worn checklist: 16 and 17 September 2026

Branch `codex/alpha-4-2026-09-14`, after the 0.2.0-alpha.1 release
(`d6d0e90`, tag `v0.2.0-alpha.1`). Each deployment adds an item here when it
is installed. Only what is still to try worn is listed; the results of the
worn rounds and the fixes they led to are in the
[16 September handover](../handoffs/2026-09-16-session.md) ("The evening: the
worn session") and [worn-results-2026-09-17.md](worn-results-2026-09-17.md)
(both of that evening's rounds).

Items are headings, not a numbered list, so a Markdown viewer cannot renumber
them: the number you see is the number the results, the handover and the
changelog cite.

## Start state

- The installed Lua matches the branch head (`2559f28`), each file checked
  against the previously deployed commit before copying, 17 September late
  evening. The viewer is the board-fix build of the same evening; the
  capture DLL and proxy are the 16 September build.
- **Check the flags before putting the headset on.** Anything in the
  installed mod folder named `*.flag` other than
  `darktidevr_crosshair_scale.flag` should be deleted first.
- Nothing below has had an unattended run (you were at the headset, and no
  launch is made while you are). The pure parts are unit tested (274 pass)
  and a second reader reviewed the engine side of each batch; what that
  cannot show is said in each item.

## Closed on 17 September

Passed: 6, 8 (calibration), 9, 15, 16, 22 to 28, 30, 34 and 38 (the boards),
39 (no sliver beside the ammo count), 41 (talk zone). Withdrawn or nothing
to test: 13, 14, 46. Replaced by an item below: 40, 42, 43, 44, 45.

## To try

### 47. Item radial: a flick no longer also switches weapon

Restart; Experimental features, "Item radial". The cause was not in the
radial: the frame profiler's timing wrapper (16 September) passed on eight
arguments and the bindings take nine, the ninth being "the stick is owned by
a radial or the communication wheel". It was dropped for a day, so every
flick inside the radial also fired the stick's own binding. Your log shows
`quick_wield` delivered on the frame of each pick, one frame before the item
wield; when the weapon switch won, you saw a weapon switch. Check: hold the
carried-items control, flick up: the item comes out, every time; flick to an
empty sector: nothing happens. The same fault applied to the communication
wheel: flicking in the wheel should no longer also trigger the stick's
binding.

### 48. Ammo count and charge display 2 cm further from the weapon

Restart. Both the ammo count beside a gun (6 cm from it, was 4) and the
melee count and bars (8 cm, were 6).

### 49. No sliver beside distant pickups' markers

Restart. My reading, without a picture of it: a marker far away is drawn
many times smaller than its cell of the marker atlas, and a minified sample
reaches well past the half-texel guard into the neighbouring cell. Every
cell is now shown without its outer 8 texels, the quad shrunk to match so
nothing changes size. Check the stims and medipacks in the Psykhanium from
across the room. **If a sliver is still there, a headset screenshot of it
would settle what it is** (the last one on the headset was of the mirror).

### 50. Hand display text fitted to its cell

Restart. Text on the hand displays cannot be clipped the way rectangles
are, so it is now measured and its font scaled down to the room it has. The
one that needed it: an item's name on the forearm holsters when you hover
(54 px tall, about 730 px for a long name, in a 477 px cell), which spilled
into the cells either side. Check: hover a holstered item with a long name:
the whole name shows, smaller; nothing appears beside other displays.

### 51. Item radial labels sharper and brighter

Restart. The panel is drawn at 1.6 times the resolution (as fine as one
overlay cell allows), the letters a little larger (1.5 cm), unpicked labels
near white, the picked one amber.

### 52. Full body: lower, further back, turning smoothly

Restart; Experimental features, "Full body (experimental)". The copy's
`j_neck` is the base of the neck; it was being put on a point 8 cm below the
eye (the skull's pivot), which stood the body about 10 cm too high and
enlarged it 1.2 to 1.3 times to get there (your log). Its target is now
10 cm lower and 5 cm further back, and the shoulders' targets move with it.
Its heading now eases after your body over about a third of a second
instead of stepping; a stick snap turn is still taken at once. Check: the
eye sits about where your own does, above and ahead of the collar; on a
reset view it no longer grows up to your head; turning on the spot, the body
follows without a snap; at the mouth for push to talk, your hand is outside
the head (see it in the mirror, 54). Say which way it is still off, in
centimetres: the two numbers are constants.

### 53. Servo skulls: no flicker, held in the hand, thrown from the hand

Restart; Experimental features, "Grab and throw the servo skull". The
flicker of the skull's physics parts came from two writers (the game placed
the skull, then the mod moved it). Now there is one: the game's own update
is given the mod's heading, rest offsets and lead for its duration, and the
mod writes nothing while a skull follows. While your off hand holds the
grab, the offset it is given is your hand, so the skull should sit just
above the hand during targeting; on release, on a local server (the
Psykhanium, solo play), the ordered skull really leaves from there. The
throw's own arc never showed because the skull's parts are nine siblings
under its root and only the first was being moved; all nine move now (that
matters on a remote server, where the real skull leaves from the server's
side). Check: run and strafe with the skulls in view: nothing on them
flickers; sides, lazy turning and the 30 cm lead as before; grab the
flamethrower skull: it comes to your hand and stays there as you aim;
release: it flies out from the hand.

### 54. Body mirror: a true copy of your body

Restart; F8 in the Psykhanium. The mirror is now a second copy posed by the
same pipeline as the full-body overlay (neck, scale, shoulders, arms solved
to your wrists), head shown, then turned about you and stood 2.5 m ahead. It
is placed from your tracked head, not from the character's root, which is
what made it jump about while moving. It runs beside the overlay instead of
replacing it, and works with the overlay off too. Check: it stands still
relative to you while you walk and strafe; its arms, shoulders and hands
match yours; raise a hand to your mouth and see where it is against the
head (this is the check for 52's numbers). It faces you as another person
would (your right hand is on your left as you look at it), not as a glass
mirror.

## Suggested order

1. At launch, anywhere: 48 (the counts), 51 and 47 (the radial).
2. In the Psykhanium as Robobert: 53 (skulls), 49 (pickup markers across the
   room), 50 (hover a holstered item).
3. Then turn Full body on: 52, with F8 for 54.
