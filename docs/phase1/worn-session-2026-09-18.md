# The worn session: what to test, in order

Prepared at the end of 18 September 2026. Everything below is deployed and
running in the installed mod; nothing here needs a launch from the tools.

**Nothing in this session is dangerous to get wrong.** If something looks odd,
say what you saw rather than trying to diagnose it — where it was, which hand,
whether it moved with your head. Half the items are "does anything look
different that should not", and "no, all normal" is a real answer that closes
them.

Two items (61 and 63) need no headset at all and take about two minutes
between them, so they are first if you want to start at the desk.

## Record your answers here

Write under each heading as you go. Numbered lists renumber themselves in your
viewer, which is why these are headings.

---

## At the desk, before the headset

### 61. The options menu, reorganised

The mod's options are in eight sections now rather than one long list, and
some options are nested under the switch that turns their feature on — a
nested one disappears when its parent is off, which is DMF's behaviour, not a
bug.

Open the mod options and look for anything that reads wrong: a section that
does not match what is in it, an option you cannot find any more, a nested
option whose parent does not obviously own it, or a label that says nothing.

**Report**: anything you had to hunt for, and anything you would move.

### 63. The wrist display looked at from straight above

Hold your left wrist up and look straight down at it, then roll your wrist
slowly.

The panel's roll is ill-conditioned in that exact pose, and a fallback was
added. What should NOT happen is the panel spinning, flipping, or snapping to
a new angle as you pass through straight-down.

**Report**: whether it stays put, or where it jumps.

---

## In the headset, ranged weapon, Psykhanium

These are quickest together because they share a setup: a ranged weapon and
somewhere safe to aim.

### 55. Aim zoom

Aim down sights. The view should magnify slightly and steadily.

**Report**: whether the strength feels right — too much, too little, or about
right — because that number has never been judged by eye.

### 56. The aim-down-sights vignette

While aiming, the edges of your view should darken.

This was built on 12 September and proved never to have worked until it was
measured on 18 September: it was painted for a wider field than Virtual
Desktop shows, so at 45 degrees off centre its darkening reached 9 of 255 —
invisible. It is sized from the real field of view now.

**Report**: whether you can see it at all, and whether it is too strong.

### 62. The aim zoom, now that it lands where it points

The zoom correction was being computed in the wrong frame, which displaced a
dead-centre target by about 1.2 degrees at 10 degrees of pitch.

Aim at something small and distant, then pitch your head up and down while
staying on it. The aim point should stay on the target.

**Report**: whether it drifts as you pitch, and which way.

### 57. The item radial

Open the item radial and use it. Then, separately, flick the stick hard
without opening it.

A flick used to sometimes also switch weapon ("infrequently it'll pull out the
item"). It should not now.

**Report**: any weapon switch you did not ask for.

---

## Anywhere: the ones that are "did anything break"

### 65. The markers still reach the plane

Nothing was meant to change on screen. World markers, interaction prompts and
the tag prompt should sit in the world at the right distance — not flat
against your view, and not swimming with your head.

Look at: an objective or teammate marker, an interaction prompt (a door, ammo,
plasteel), and tag something and look at the tag prompt.

**Report**: only if one of the three looks different from yesterday.

### 66. Two displays that used to stay gone

The teammate nameplates and the forearm weapon previews used to switch
themselves off permanently after a single error and stay off until the game
was restarted. They now stop only after three errors in a row and a level load
gives them another chance.

**Report**: only if either vanishes mid-mission and does NOT come back after
the next load, or if either flickers within one mission.

### 64. Nothing changed, in the places most likely to have

Every `mod:hook` handler changed shape: each now passes along any argument the
engine gives it beyond the ones it names. No behaviour was meant to change
anywhere, which makes "looks exactly as it did" the whole answer.

An unattended run already reached the Psykhanium with no mod or Lua errors and
every changed hook family running, so this is a look rather than a hunt:

- the options menu, inventory, crafting or vendor views — anything that fails
  to draw, draws twice, or loses its pointer;
- in a mission: the HUD, world markers, teammate nameplates, interaction
  prompts, the tag wheel, the communication wheel;
- spectating, if you get downed;
- the display and graphics settings.

**Report**: anything odd, even if it seems unrelated to VR. The change was
mechanical and wide, and that is how a quiet regression gets in.

### 58. Nothing else changed

The catch-all for today's other work. If something looks different and is not
covered above, it belongs here.

---

## If you have longer: the 16 September items never run in game

These were deployed on 16–17 September and have never been looked at. They are
lower priority than everything above, but they are the oldest unanswered
things on the list.

### 49. No sliver beside distant pickups' markers

A thin bright sliver used to appear beside the markers on distant pickups.
Look at pickups from a distance.

**Report**: whether any sliver survives, and a screenshot if it does.

### 52. Full body: lower, further back, turning smoothly

With a body shown, look down at yourself and turn on the spot.

**Report**: whether the body sits where yours does — and the head error in
centimetres if you can judge it, because that number is what the next change
is sized from.

### 54. Body mirror: a true copy of your body

**Report**: which of the two body versions reads better, if you try both.

### 47, 48, 50, 51, 53

The radial flick, the ammo and charge display distance, the hand display text
fit, the radial label sharpness, and the servo skulls. All described in
`test-checklist-2026-09-16.md` — worth a look only if the session is going
well.

---

## Not in this session

Foveated rendering is not switched on. The census that decides where it goes
ran tonight and answered — the shading is at the DLSS internal resolution, not
the eye extent — but no shading rate is being set, so nothing about the image
should have changed.

The Steam Frame bindings are written but cannot be exercised on a Quest: the
Frame profile reports `extension-unavailable` under Virtual Desktop, which is
correct.
