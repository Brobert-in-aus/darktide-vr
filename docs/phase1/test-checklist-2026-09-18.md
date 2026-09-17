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

## Suggested order

1. In the Psykhanium with a ranged weapon: 55 and 56 together (aim, hold,
   release), then 57.
2. Anywhere: 58, which is really "does anything look different that
   should not".
