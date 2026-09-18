# The worn checklist, 18 September 2026 (third pass)

Numbering restarts at 1. Headings rather than a numbered list, because your
viewer renumbers ordered lists.

Everything closed by your last round is gone from this list. What is left is
four things I have fixed and want confirmed, two I have not, and one that is
now a measurement rather than an argument.

**Closed by the last round, not repeated below**: the eye position, the ADS
release, the skull's resting place, and the vignette — which works.

---

## The one that explains two of your reports

### 1. Shooting, and how many pairs of hands you have

These were the same bug. Your shots were terminating at **distance zero, on a
copy of you**:

```
shot=1  endpoint=-4.2220,4.1679,2.3128  distance=0.0000  hit_count=14
        origin=-4.2220,4.1679,2.3128
```

The sweep ran — fourteen collisions — and stopped where it started. The
collision list had the same unit id reporting `self=true` on one actor and
`self=false` on another, which is two Unit objects sharing an id: a copy. Stock
skips *the attacker's* actors, and the copy is not the attacker.

The full-body mirror spawns a 246-node copy of you at zero distance and never
took the collision off it. It does now, before the copy is ever posed. That
copy is also your second pair of hands.

**Test**: shoot things for a good while, including after switching weapons a
few times and after a death or a level change. Then look down at your hands.

**Report**: whether shooting stays working, and whether there is still more
than one pair of hands.

---

## Three fixes that need judging by eye

### 2. The reticle's distance in aim-down-sights

You said it was in stereo now but too far away, and inside the ground when you
aimed down at the ground. That was the zoom correction: it moved the reticle
outward across your view without keeping its distance, so a point on a surface
ended up off the surface — below the ground, and further off.

It turns the ray now and puts it back to its original length. The angle it
corrects for is unchanged; only the depth stops being disturbed.

**Test**: aim at the ground close to you, at a wall, and at something 30 m
away, entering the sights each time.

**Report**: whether the reticle sits **on** what you are aiming at, at all
three distances.

### 3. Throwing the skull

It was too slow because I averaged your hand's speed across 150 milliseconds —
and a throw peaks and then slows into the release, so the average was about
half of what you actually did. Worse, my first attempt only measured spans
*ending* at the release, which drags the follow-through into every one of them.

It now takes the fastest span between any two points in the window, with a
40 ms floor so tracker noise cannot invent a speed. The cap went from 12 to
18 m/s, because the cap was quietly doing some of the averaging's work.

**Test**: throw it hard, throw it gently, and throw it while running.

**Report**: whether a hard throw now matches what your arm did — and
especially whether it now overshoots, because I have moved this a long way in
one step and too fast is as wrong as too slow.

### 4. The hands and body flickering while you run

**Possibly fixed, and I want to know rather than assume.** You had two sets of
hands occupying the same space, which is a textbook way to get flicker: two
surfaces at the same depth fight over which is in front, frame by frame. With
the duplicate gone the cause may have gone with it.

**Test**: run around for twenty or thirty seconds, watching your hands and
body.

**Report**: whether it still flickers at all. If it does, whether it is the
hands, the body, or both.

---

## Still broken, now with a number against it

### 5. The torso turning faster than your view

**Not fixed.** But it is measured, which it was not before. During your session
the character's root turned **1 to 4.2 degrees per sample** while your head
turned **0.1 to 0.5** — about ten times faster. The drawn body's own root
barely moved; what you see spinning is the avatar's animation underneath it,
which the copy inherits joint for joint.

I also found my first trace was watching the wrong stick. The flag it keyed on
is the **movement** stick, so the rows I read as "turning" were you walking.
The trace now records the actual turn, in degrees, on every line.

**Test**: this one needs deliberate input. Stand still, look at a fixed point,
and **turn with the stick in one long hold** — not a flick — then stop dead.
Do it two or three times each way. Then do it again while walking forward, so
the two sticks are separated in the log.

**Report**: roughly when you did it. The numbers will do the rest.

### 6. The body jittering underneath you

You could not judge this last time because the torso was swinging around. It is
still worth a look, but if 5 is still happening then this stays blocked and
"can't tell" remains the right answer.

**Test**: stand still and look down at yourself for ten seconds without moving.

**Report**: whether it jitters while you are genuinely still.

---

## What changed in the instrument

The trace spent its entire budget in five minutes last time and missed the
stick turns it was written for. It is every third frame now instead of every
second, with a budget four times larger — roughly half an hour of active play
rather than five minutes — and it carries the turn column it was missing.

The thresholds are deliberately still low. A head in a headset micro-moves
constantly, so almost every sample clears them; the answer to that is a bigger
budget, not a threshold high enough to hide the jitter in item 6.
