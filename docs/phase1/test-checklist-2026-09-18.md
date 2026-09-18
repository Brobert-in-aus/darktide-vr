# The worn checklist, 18 September 2026 (evening)

Numbering restarts at 1 here, as asked. Headings rather than a numbered list,
because your viewer renumbers ordered lists.

Everything in the first section is deployed and changed since your last
session. The second section is what is **not** fixed, and why — read it before
you go looking for those things, so you do not spend a session confirming
something I already know is unchanged.

**Write your answers under each heading.** "No change" and "all normal" are
real answers that close an item.

---

## One thing to do first, at the desk

### 1. Set the ADS zoom to 5

You asked for the default zoom to be 5 per cent. I changed the default, but a
default only ever applies to a setting that has never been set, and yours is
saved at **12** — the log says `percent=12` all through your last session. (I
said 3 earlier; that was wrong, and it is corrected in the record.)

So: open the mod options and set the aim zoom to 5 yourself. Nothing else in
this list depends on it, but the two ADS items below will read differently at
12 than at 5.

**Report**: nothing, unless you cannot find the setting.

---

## In the headset

### 2. Where your eyes sit

Both of your numbers are in: the camera sits 5 cm further forward and 5 cm
higher relative to the body. The anchor is still measured off the avatar's own
eye node each spawn; this is a correction on top of that, so it moves with you
rather than replacing the measurement.

Look down at yourself, standing still.

**Report**: whether your head is now in the right place, and a centimetre
figure in whichever direction it is still out — that number is what the next
change is sized from. Also whether anything about the world's *scale* feels
different, which would mean I moved the wrong thing.

### 3. Your hands, after your eyes moved

This is the part you did not ask for and should look at anyway. The hand
targets are computed from the same anchor as the camera, so both hands moved
5 cm forward and 5 cm up with your eyes, while the avatar's shoulders did not.

That is probably right — if your eyes were 5 cm back, so were your hands — but
it eats into the reach the shoulder solver has before it starts compensating,
and it bites hardest in exactly the pose you use most: a rifle held out in
front.

**Report**: whether your hands still land where you put them, particularly
with a gun at full extension, and whether the drawn hands separate from where
you feel the controllers.

### 4. The torso coming back round — read this, I may have fixed the wrong thing

I made the body *frame* drift toward your head instead of freezing inside its
dead zone. A review then established that the body frame is not what turns the
torso you look down at: that is a separate solver, with its own 30 degree dead
zone and its own recentre after 0.75 seconds of stillness, which already claims
to do exactly what you asked for.

So one of two things is true, and the trace now records both so the session
tells us which:

- the drawn torso still does not recentre, and the bug is in that solver's
  "have I been still" test rather than anywhere I changed today; or
- it does recentre and what you noticed was something else — most likely the
  virtual stock's shoulder anchor, which *is* driven by the body frame.

What I did change has a side effect worth watching for: the virtual stock's
shoulder anchor now never quite stops moving, so with two-handed aiming on you
may see the reticle creep by a degree or two over a couple of seconds after a
glance. If you see that, say so — it is mine and it comes straight back out.

Look 20-30 degrees off to one side and hold it for five seconds. Then turn
properly and stop.

**Report**: whether the torso comes round at all, how long it takes, and
whether the aim creeps while you hold still.

### 5. Leaving aim-down-sights

The 0.3 second delay on dropping the sights is gone; it releases the moment
your hand leaves the zone. The distance hysteresis is still there — the gun has
to travel 3 cm further out than it came in — so this should feel immediate
without flickering at the boundary.

**Report**: whether it now lets go when you expect, and whether it ever
flickers on and off at the edge. The flicker is the thing the delay was
guarding against, so if it comes back, say so and the timer goes back in.

### 6. Where the flamethrower skull sits

Moved 30 cm forward, 30 cm right and 30 cm down, as measured. Only the
throwable skull moved; the medical and regular skulls keep their stock rest.

**Report**: whether it is now where you want it, and the remaining offset in
centimetres per axis if not.

### 7. Throwing the skull

The throw carried almost no velocity because the hand's speed was measured
across a single frame — an 8 millisecond sample taken while your hand was
decelerating to let go of the button, which reports close to nothing. That is
what "it just floats where released" was. It is measured across 150
milliseconds now, and capped so a tracking glitch cannot fling it.

Throw it properly — a real throwing motion, releasing at speed — and also
throw it gently.

**Report**: whether a hard throw now looks thrown, whether a gentle one looks
gentle, and whether the skull ever shoots off somewhere absurd. Note it still
flies *straight* rather than arcing: it is a flying skull under its own power,
so I did not give it gravity. Say if you want an arc.

### 8. If shooting breaks again

I could not find the cause, and the log could not have told me — see below. If
it happens again, the log now answers the one question that matters.

**If it happens**: note the time, keep playing for another twenty seconds or
so pulling the trigger, and tell me. Do not restart. The twenty seconds matter:
the log writes a line every five seconds per weapon while you fire, so a short
burst may fall between two of them.

---

## Still broken — but now instrumented. These need you to DO something

I could not fix these four by reading the code, and twice today that produced a
confident answer that was wrong. So each one now has an instrument that a
single session settles. They need specific actions from you, which is why they
are here rather than in a note.

**The body trace is on for this session.** It writes to the usual console log
and stops at six thousand lines, and it only writes when something is actually
moving, so standing in the hub costs almost nothing. It is off again on the
next deployment unless I ask for it.

### 9. Stick turning, deliberately, with the body visible

Stand still with the full body on, look straight ahead, and turn with the stick
— **a long slow hold in one direction**, not a flick. Then stop dead and stand
still for five seconds. Do it two or three times, both directions.

This is the one that needs care: the trace records six different yaws and the
answer is whichever one moves further per frame than your head does. A short
flick does not give it enough frames to tell them apart.

**Report**: roughly when you did it, and whether the body led or lagged.

### 10. Standing still, looking down at yourself

Immediately after the turns, just stand and look down at your body for ten
seconds or so without moving.

That gives the trace a clean stretch of "nothing should be moving", which is
what the jitter is measured against — a settling body's movement shrinks, a
jittering one's does not.

**Report**: whether it is jittering while you stand there, or only while you
run.

### 11. Running, for the flicker

Run around for twenty or thirty seconds watching your hands and body.

I checked both places the body hides things and neither runs per-frame, so the
flicker is not something switching visibility off and on — it is more likely a
pop in position. The trace's root movement will show that.

**Report**: whether it is the hands, the body, or both, and whether it happens
in step with your footfalls.

### 12. The ADS reticle, at two distances (was 62)

Aim down sights at something **far away** — 30 metres or more — and hold it for
a couple of seconds. Then aim at something **close**, a few metres, and hold
that.

Both distances matter and the item cannot be answered without both. The viewer
now logs each eye's reticle position and their disparity, with the target's
distance next to it. A disparity that stays the same at both distances is a
drawing fault I can fix. One that grows as the target gets closer is ordinary
stereo — the reticle sitting at the target's distance while the ironsights sit
50 cm from your face — which would mean the reticle is correct and the two
simply cannot line up in both eyes at once.

**Report**: whether the mismatch looked worse at one distance than the other.

### 13. The ADS vignette (was 56)

Just aim down sights a few times during the session. You do not need to look
for anything.

The counters will say whether the darkening is being submitted over an image
that still has it painted in. It is submitted, correctly sized and not being
dropped by a layer limit — so what is left is whether the sprite survives to
the frame it is shown on, and that is counted now rather than reasoned about.

**Report**: nothing, unless it suddenly appears — in which case say when.

---

## Answered, not fixable

### 14. Nested submenus (was 61)

DMF has no submenus. Its `group` type is a heading row with an indentation
level inside one flat scrolling list; there is no sub-page to open. The mod
already uses seven of those headings across 48 settings, which is exactly what
you saw: sections, all on one scroll.

The one lever DMF does give is that an option nested under a switch disappears
when the switch is off, so the list can be made shorter for anyone with
features turned off — but it cannot be made into pages.

**Report**: whether shortening it that way is worth doing, or whether you would
rather it stayed flat and predictable.
