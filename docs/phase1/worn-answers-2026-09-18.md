# Worn session answers, 18 September 2026

The user's replies, recorded verbatim in substance, with what each one means
and what it turns into. Answers first; conclusions after.

## The session-stopping one: shooting died and never came back

> "A short while into the session, shooting broke. Regardless of being ADS or
> no, bullets no longer fire from my gun. Melee still works."

**Traced to the second, from the console log.** Fire is `action_one`, which is
`analog_button(right.trigger)` (`core/gameplay_input.cpp:59`). It worked
normally until **07:55:46.897** -- rapid `delivered=action_one_pressed` /
`action_one_release` pairs, `missing=none` -- and then never appeared again in
a session that ran to 08:02:49.

The left trigger kept working throughout (`action_two` edges at 07:55:49,
07:55:50, 07:55:51, and ADS toggling on and off cleanly afterwards). So this
is **right-hand specific**, not a latch in the shared input path and not ADS
holding something down.

The cause is in the viewer: `read_float` returns **0.0 when the action is not
active** (`src/xr/main.cpp:5940`), and an OpenXR action goes inactive when its
device stops being reported. The controller telemetry agrees -- the right
controller drops to `right_live=false right_flags=0` repeatedly through the
session and is still out at the last sample (08:02:39), while the left is
`left_flags=15`.

So the right controller stopped being reported by the runtime -- asleep, flat,
or its link dropped -- and from that moment the trigger read a hard zero.
Nothing in the mod or the game was broken; the button simply stopped existing.

**What this earns**: losing a controller costs the player their gun with no
indication whatsoever. Seven minutes of a worn session went into a mystery
that the viewer already knew the answer to. A "controller not reporting"
signal belongs in the log and in front of the player.

## Answers

### 61. The options menu, reorganised

> "It's not in nested submenus, it's still all on the one page and you have to
> scroll the whole lot."

Not done, then. The work grouped options into eight sections and nested a few
under the switch that owns them, but DMF renders that as one scrolling list
either way. The original request was for real submenus **if DMF supports
them** -- this is the answer that it does not, at least not as used. Reopen as
a question about what DMF can actually do, not as a tweak.

### 63. The wrist display from straight above

> "Wrist display seems fine in every position."

Closed. The roll fallback holds.

### 55. Aim zoom

> "ADS is good, set the default zoom to 5% and remove the delay in ending ads
> when moving your hand out of the zone."

Two changes, both small and specific: default magnification to 5 per cent (the
log shows it ran at `percent=3`), and no hysteresis or timer on leaving ADS --
out of the zone should end it immediately.

### 56. The ADS vignette

> "No vignette."

**Still invisible.** It was rebuilt on 18 September against the real field of
view after being proved never to have worked, and it is still not visible.
The rebuild was verified by a readback, not by an eye, so something between
"painted correctly" and "reaches the player" is still wrong.

### 62. The aim zoom landing where it points

> "Reticle is misaligned in ADS -- it's no longer in the same location per eye,
> offset from the ironsights in each eye too. Left eye reticle does appear to
> be where shots go though."

**A regression, and a precise one.** The reticle now differs BETWEEN the eyes,
which it did not before, and neither eye lines up with the ironsights. The
left eye is where the shots actually land.

That the left eye is correct and the right is not points straight at the
per-eye path: something is applying a left-eye quantity to both eyes, or the
zoom correction is being computed once and submitted twice. This is the first
thing to look at tomorrow and it is squarely in today's ADS zoom work.

### 57. The item radial

> "Flick is good, as is text."

Closed -- and this closes the "infrequently it'll pull out the item" report
that has been open since the claim-slot work.

### 65, 66, 64. The three "did anything break" looks

> "No change" to all three.

Closed. The markers still reach the plane, the two re-armed displays behave,
and the wide hook-arity change broke nothing visible.

### 49. The pickup sliver

> "No sliver."

Closed. The gutter work holds.

### 52. Full body

> "Turning with stick turns the body faster than my view. Also, the body is
> quite jittery under me and my head still needs to come up a little more. The
> torso also doesn't slowly recenter if I'm still for a bit. My hands and body
> flicker as I run around."

Five separate faults:

- **Stick turn rotates the body faster than the view.** A gain mismatch
  between the body yaw and the camera yaw.
- **The body is jittery underneath.**
- **The head needs to come up a little more** -- the standing height is still
  short. No centimetre figure this time, so it stays qualitative.
- **The torso never recentres when still.** There is meant to be a slow return
  to forward; there is not.
- **Hands and body flicker while running.**

### 54. Body mirror

> "This copy mirrors me properly."

Closed, and it settles which of the two body versions reads better.

### 47, 48, 50, 51, 53. The rest of 16 September

> "All good except the servo skulls."

Four closed. The skulls:

> "The flamethrower skull needs to come forward, right and down 30cm each.
> Also, I can grab it now but throwing it has no physics, it just floats where
> released for a moment then moves to its destination."

- **The flamethrower skull's hold pose is out by 30 cm on three axes** --
  forward, right and down. A concrete offset, which is the easiest kind of fix
  to make and to verify.
- **Throwing has no physics.** It is grabbable now, but a released skull hangs
  in the air briefly and then translates to its destination rather than being
  thrown. The grab works; the release does not hand it a velocity.

## What this turns into

Ranked by what it costs the player:

1. **A lost controller must say so.** Nothing about the failure was visible in
   the headset. (New.)
2. **The ADS reticle differs between the eyes** and neither matches the
   ironsights. A regression from today. (62)
3. **The ADS vignette is still invisible** after being rebuilt. (56)
4. **Servo skull throwing has no physics**, and the flamethrower skull's hold
   pose is out by 30 cm on three axes. (53)
5. **Five body faults**: stick-turn gain, jitter, height, no recentre, flicker
   while running. (52)
6. **Two ADS settings**: default zoom to 5 per cent, and no delay leaving ADS.
   (55)
7. **DMF submenus are not a thing**; the options are still one long scroll.
   (61)
