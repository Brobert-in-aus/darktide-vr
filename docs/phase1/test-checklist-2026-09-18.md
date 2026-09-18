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

### 4. The torso coming back round

Glancing still does not turn your body — the dead zone is unchanged. What is
new: if you *hold* the glance, the torso now drifts round to follow, over a
couple of seconds. Before, it stopped dead and stayed askew until a real turn
moved it.

Look 20-30 degrees off to one side and hold it. Then turn properly and stop.

**Report**: whether the drift feels right, too fast, or too slow — and
especially whether it fights you when you are trying to hold a position, for
example peeking round cover while your body stays behind it.

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

## Not fixed, and why — please do not go hunting for these

### 9. The ADS reticle being different in each eye (was 62)

**Unchanged.** I did not find it, and I am not going to guess at it after
getting the shooting diagnosis wrong the same day.

What I checked and ruled out: the per-eye draw uses each eye's own pose and
field of view correctly; the zoom correction is computed about the head, and
the resulting per-eye disagreement is about one millimetre at your settings —
far too small to be what you saw.

If you want to help it along: tell me whether the two eyes' reticles differ by
a *constant* amount or by more when the target is closer. Constant points at
the draw; distance-dependent points at it being ordinary stereo parallax
between a reticle at the target's distance and ironsights 50 cm from your face,
which would mean the reticle is right and the comparison is not.

### 10. The ADS vignette (was 56)

**Unchanged, and I now know more about why I could not fix it.** It is being
submitted — the viewer logs it — it is sized so the darkening peaks at 52
degrees rather than the old 61, and at 45 degrees off centre it should now
reach 89 of 255 rather than 9. It is not being dropped by a layer limit
either: the runtime allows 16 and we submit far fewer.

So the geometry is right and it still is not visible, which means the sprite is
not reaching the surface the quad samples, or the quad is not being composited.
Neither can be settled by reading the code — it needs the projected-eye
readback with the sights forced up, which is a desk job, not a worn one.

### 11. The body jitter and the flicker while running (was 52)

**Unchanged.** You said this feels like the same issue fixed several times
before, and you are right about the class: both previous fixes were "update the
scene graph after posing" or "follow the drawn thing, not the source". I found
the previous fix and the shape of it, but not the specific place it is missing
this time, and I would rather leave it than change something at random in the
body path and have you test a guess.

### 12. Stick turn rotating the body faster than your view (was 52)

**Unchanged.** Same reason. The body's yaw follows the head through a lag, so
it should trail rather than lead, which means something else is turning it too
— and finding which needs the body telemetry read against a stick turn rather
than more reading.

### 13. Nested submenus (was 61)

**Answered, not fixable.** DMF has no submenus. Its `group` type is a heading
row with an indentation level inside one flat scrolling list — there is no
sub-page to open. The mod already uses seven of those headings across 48
settings, which is exactly what you saw: sections, but all on one scroll.

The one lever DMF does give is that an option nested under a switch disappears
when the switch is off. So the list can be made shorter for anyone who has
features turned off, but it cannot be made into pages.

**Report**: whether shortening it that way is worth doing, or whether you would
rather it stayed flat and predictable.
