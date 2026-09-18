# Worn session answers, 18 September 2026

The user's replies, recorded verbatim in substance, with what each one means
and what it turns into. Answers first; conclusions after.

## The session-stopping one: shooting died and never came back

> "A short while into the session, shooting broke. Regardless of being ADS or
> no, bullets no longer fire from my gun. Melee still works."

### The first diagnosis was wrong, and the user corrected it

It was recorded here as a lost right controller: no `action_one` edges after
**07:55:46.897**, and `right_live=false right_flags=0` in the controller
telemetry. Both observations were real and the conclusion drawn from them was
not:

> "I was pulling the trigger, it was tracking correctly, the gun was playing
> the firing sound and animation, it just generated no bullets. It's also
> impossible for melee to keep working if the controller was off, since it's
> bound to right trigger too."

Both halves land. Sound and animation mean the input reached the game, and
melee on the same physical trigger means the controller was reporting. Two
mistakes made in reading the log:

- **`right_live=false` is not a lost controller.** The LEFT controller does
  exactly the same thing, over and over, all session -- `left_live=false
  left_flags=0` at 08:00:19, 08:01:17, 08:02:05, 08:02:28, 08:03:10 and on.
  These are tracking transitions, which is what the line is named. Reading one
  hand's transitions as a device failure while the other hand's sat three
  columns away in the same lines is not a subtle error.
- **"Never appeared again" was simply false.** `pressed=1` occurs thirteen
  more times, at 08:04:14 through 08:04:20, every one of them
  `delivered=action_one_pressed missing=none`. A truncated grep was read as an
  absence.

### What the log does establish

- The gun (`slot_secondary`) was wielded from 08:04:06, ADS entered at
  08:04:09.99, and thirteen trigger presses were delivered cleanly between
  08:04:14.710 and 08:04:20.182. That burst is the reported fault happening,
  with the input path healthy end to end.
- **No Lua errors anywhere in the session**, mod or engine.
- Every shot the log did record starts its sweep inside the player's own
  hitbox: `collision=1 distance=0 self=true zone=afro`, because the shoot
  origin is the first-person position rather than the muzzle. Stock skips self
  and the shots landed, so this is not yet a fault -- but it means every shot
  depends on that self-skip continuing to apply.

### What the log cannot establish, which is the whole question

Whether `_shoot` was dispatched at all during that burst. `RANGED_EVIDENCE`
and `HIT_EVIDENCE` cap at four dispatches per weapon route (`row.calls>4`), and
the fourth was written at **07:51:52** -- twelve minutes before the fault. From
then on, silence in the log means "capped", not "no shot". The single question
that separates "the trigger never reached the weapon action" from "the weapon
action ran and produced nothing" had no answer in a 13,357 line log.

**That is the defect worth fixing first, and it has been.** Past the detail
cap the module now writes a compact `dispatches=N since_last=N` line, throttled
to one per five seconds per route, so a burst of fire always leaves a mark and
"the trigger was pulled here and nothing dispatched" becomes a readable fact
rather than an inference. The next occurrence answers itself.

**Still open**: the cause. The honest position is that the wrong answer was
given confidently once already, so the next one waits for the instrument.

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
- **The head needs to come up a little more.** Sized on a second look
  (user, 18 September): "eyes only need to come up ~5cm, they also need to
  come forward ~5cm too". Both done -- `presentation.EYE_ANCHOR_FORWARD_M`
  and `EYE_ANCHOR_UP_M`, applied to the captured anchor on every read rather
  than folded into the capture, which would compound. The measurement itself
  is left alone: the avatar's eye node is where it is, and this is a
  correction on top of it.
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

1. **Why the gun fires and no bullet appears.** Reopened: the first answer
   was wrong. The instrument that would have settled it is in (the shot log no
   longer goes quiet after four dispatches); the cause is not yet known.
2. **The ADS reticle differs between the eyes** and neither matches the
   ironsights. A regression from today. (62)
3. **The ADS vignette is still invisible** after being rebuilt. (56)
4. **Servo skull throwing has no physics**, and the flamethrower skull's hold
   pose is out by 30 cm on three axes. (53)
5. **Four body faults**: stick-turn gain, jitter, no recentre, flicker while
   running. Height is done. (52)
6. **Two ADS settings**: default zoom to 5 per cent, and no delay leaving ADS.
   (55)
7. **DMF submenus are not a thing**; the options are still one long scroll.
   (61)
