# Worn results, 17 September 2026

The user's second worn round on the 16 September build, Virtual Desktop at
100 fps with the FOV tangent at 90 per cent, frame generation off. Recorded
here in full before any of it is acted on.

**Numbering.** The user's Markdown view renumbered the trimmed checklist
(an ordered list starting at 6 counts up from 6 whatever numbers are
written), so their numbers are not the checklist's. Both are given; the
checklist's own number is the one the handover and changelog cite. The
checklist is rewritten with headings so this cannot happen again.

| User's | Checklist | Item |
|---|---|---|
| 6 | 6 | Viewer survives a zero field of view |
| 7 | 8 | Calibration T-pose guidance |
| 8 | 9 | Neutral eye anchor in the aim frame |
| 9 | 13 | Tag what the off hand points at |
| 10 | 14 | Body overlay (dev flag, mirror) |
| 11 | 15 | Hand role resolution in one place |
| 12 | 16 | The last role swaps |
| 13 | 22 | Frame profiler wrapping |
| 14 | 23 | Haptics sample without allocation |
| 15 | 24 | Dev-flag polls throttled |
| 16 | 25 | Sampler gates |
| 17 | 26 | Marker material values replayed once per change |
| 18 | 27 | Marker head frame shared per frame |
| 19 | 28 | Native module and proxy rebuilt |
| 20 | 29 | Atlas cells inset by half a texel |
| 21 | 30 | Boards re-seat on a recenter |
| 22 | 31 | Item radial picks on the flick |
| 23 | 32 | Push to talk hums while held |
| 24 | 33 | Full body in the settings menu |
| 25 | 34 | Loading and menu boards |
| 26 | 35 | Servo skulls swapped and following |
| 27 | 36 | One weapon charge display |
| 28 | 37 | Review fixes on the evening's changes |
| 29 | 38 | Boards drawn by the viewer (not deployed when tested) |

## Reported before the checklist

- **Frame rate**: "I'm firing up the game with VD set to 100fps"; then "I
  switched off framegen, looks to be around 65-70". The viewer log agrees:
  64 to 75 game pairs a second across the session, against the 55 Hz the
  pipeline pinned at on 16 September at 90 Hz.
- **Boards**: "Loading screens and menus are correctly locked in space but
  once again appear to be billboarding - could be distorting rather than
  billboarding, but something's definitely wrong". Then: "See if you can
  handle the tangent distortion - it causes no issues in game, just
  loading/menus, and many players will probably have it turned on."

## The checklist, in the user's words

Passes (nothing to do): 6 ("seems like a pass, at the least I haven't
noticed anything"), 9 eye anchor ("Nothing looks different"), 15 ("Still
works"), 16, 22, 23, 24, 25, 26, 27, 28 ("Nothing looks different" /
"Nothing visible at my end"), 30 boards re-seat ("Pass").

Open, each with the user's words and what is to be done:

1. **Checklist 8, calibration**: "see later note". Waiting for the note.
2. **Checklist 13, tag by pointing**: "left hand tag pointing doesn't seem
   to work (also disable it for now)". To do: take it out of the menu and
   ignore its saved value (test flag only), as reach and inspect were.
3. **Checklist 14, body overlay**: "see 24. also add a button (F8?) which
   toggles the mirrored player in psykh". To do: a key (F8 unless taken)
   that toggles the mirror copy in the Psykhanium.
4. **Checklist 29, atlas sliver**: "Still broken (grab latest screenshot) -
   sliver is still next to ammo count/weapon charge - it briefly disappears
   intermittently though. Melee weapon charge has incorrectly moved to the
   right side of the hand, too". The screenshot
   (`VirtualDesktop.Android-20260917-185029.jpg`) shows a one-to-two pixel
   column of the wrist display's three bars (white, cyan, yellow) right of
   the ammo count, and the melee count "1/8" drawn over the ammo count
   "8 / 49". So the half-texel inset was the wrong fix: a whole column of
   the bars is inside the ammo quad, and it goes away when a bar is not
   full (the bars' ends spill into the neighbouring cell). To do: find the
   spill and stop it at the cell; see item 8 here for the count's place.
5. **Checklist 31, item radial**: "Works on a flick - an empty slot still
   uses the original flick (e.g. flicking up with no item switches weapon,
   which is what's bound to RS Up) - also, with the ranged weapon out, the
   menu disappears after a moment even if you hold the button, it remains
   as you hold the button with a melee weapon out though". To do: a flick
   into an empty sector is swallowed while the radial is open; find why the
   radial closes with a ranged weapon out.
6. **Checklist 32, talk hum**: "hum works, make the zone ~33% smaller
   though". To do: the mouth zone's radii reduced by a third.
7. **Checklist 33, full body**: "Head is floating way above body even after
   a re-calibration. Height is measured correctly (I'm 178cm tall, eye
   height measured at ~172cm), armspan was measured with my arms in the
   correct position, so I guess it's accurate?" To do: find why the body
   sits low under the head in the option's mode (the mirror copy's neck
   reached the head unattended on 16 September).
8. **Checklist 36, weapon charge display**: "Works, it should be to the
   left of the weapon not above it, same as ammo (see my earlier comment)";
   and from 29: "Melee weapon charge has incorrectly moved to the right
   side of the hand". To do: the melee count and the bars sit where the
   ammo count sits, left of the weapon, never over the ammo count.
9. **Checklist 35 and 37, servo skulls**: "servo-skulls still on the same
   sides they were before, and still locked to my head rather than
   following. Also, they should 'predict' my movement and try to stay ~0.3m
   ahead of me as I run, more immersive and makes it easier to spot where
   the flamethrower skull is. This is as well as the flamethrower sitting
   forwards ~0.3m when stationary for ease of grabbing". 37: "all seem fine
   except servo-skull behaviour being unchanged". To do: find why neither
   the mirror nor the follower showed worn (both logged as armed
   unattended); add a lead of about 0.3 m along the player's velocity.
10. **Checklist 34 and 38, boards**: "see my earlier comment" / "see
    earlier comment". The fix (commit `85f5517`) was not deployed while the
    user tested; it is the next thing to try worn.

## What was done, the same evening

All committed, tested (274 pass), reviewed by a second reader, deployed with
the game closed, and listed for the next worn round as checklist items 39 to
46. None had an unattended run: the user was at the headset.

- Boards (10): deployed first; the user: "board fix worked".
- Tag by pointing (2): out of the menu, saved value ignored (`e135fd3`).
- Talk zone (6): 0.135 m in, 0.19 m out (`e135fd3`).
- Charge display (8): count and bars ahead of the grip and toward the
  midline as the eye sees it; above the grip they landed on the forearm
  holster's count, 13 cm up (`e135fd3`).
- Sliver (4): the wrist bars' left ends, 243 px left of their cell's centre,
  4 px outside the 477 px cell of the 1908-wide eye target the 90 per cent
  FOV tangent gives (inside the 528 px cell at 2112). The second thing that
  setting broke, after the boards. The wrist panel's scale fits the cell;
  overlay rectangles are clipped to their cell (`e135fd3`).
- Radial (5): both symptoms were one cause, two-hand support's idle claim
  offer every frame a gun is out; the radial yields only to a request that
  is acquiring, approaching, or already held (`af5d8a4`).
- Skulls (9): the first-person body reports third person, so the stock
  movement reads the third_person rest table; both are mirrored now, by
  handedness. The follower holds the skull relative to a lazy heading,
  tracks the head's position, leads the run by up to 0.3 m, covers every
  skull of the player, and writes the skull's root (the child node it moved
  before was never seen to move anything) (`0a7423a`, `9741baa`).
- Full body (7) and the mirror key (3): the option selected the older
  headless body; it now selects the body mirror module's `overlay` mode.
  F8 toggles its `mirror` mode in the Psykhanium (`6e220e8`, `9741baa`).
- Calibration (1): waiting for the user's note.

## Order of work

Deploy the board fix first (the game is closed). Then, smallest first: tag
by pointing out of the menu (2), the talk zone (6), the charge display's
place (8), the sliver (4), the radial (5), the skulls (9), the F8 mirror
toggle (3), the full body's head height (7). The calibration note (1) when
it arrives.

## Second round, the same evening (items 39 to 46, build `9741baa`)

The user's words, by the checklist's own numbers (headings this time, so
they match), recorded before acting.

- **8, calibration**: "I did this one last time, calibration seemed to
  work". Pass.
- **13, 14, 46**: "nothing to test". Closed.
- **39, sliver**: "Fixed, however item pickups still have a sliver". Open:
  the pickups' world markers.
- **40, charge display**: "good, but move both it and the ammo counter
  further to the left of the gun - maybe 2cm?" Open: both 2 cm further.
- **41, talk zone**: "pass".
- **42, radial**: "persists with a gun out, but flicks up still swap weapons
  rather than grabbing the item (but only most of the time, infrequently
  it'll pull out the item)". Open.
- **43, skulls**: "leading works, but physics objects on them flicker as I
  move (but not when I turn, I expect this is the same issue with conflict
  between our position and the base model position, same as past flickers
  when moving)". And: "Throwing works in that it triggers the targeting
  mode and releasing sends the skull, but the skull never gets visually
  grabbed and just follows its usual path when thrown." Open: one writer
  for the skull's position; the grab and throw never draw.
- **44, full body**: "snap turns as I turn rather than following smoothly,
  and eyes are a bit too low, need to come up maybe 10cm, and forward maybe
  5? Or perhaps the body needs to move down. Check where the eyes are
  supposed to be vs where they are, resetting view and sitting or standing
  doesn't seem to change it. I notice that when doing the left-hand in
  front of mouth to PTT that the mirrored model shows my hand going inside
  its head." And: "I notice that when I reset view the body scales height
  up to my head, so it's coming up too far (and I think the eyes need to be
  further forward too)". Open: the body turns in steps; it stands about
  10 cm too high and about 5 cm too far forward of the eye.
- **45, mirror**: "works, but glitches around when I move. Also, doesn't
  mirror my IK except the hands, and its own hands are invisible - it
  should match my IK identically, a true mirror." Open.
