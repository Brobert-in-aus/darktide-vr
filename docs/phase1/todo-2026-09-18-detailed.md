# Detailed away-list: 18 September 2026

The user's instruction, last thing on 17 September: "first step tomorrow
will be a broad pass to create a more detailed todo list of things to work
on while I'm away." This file is that pass's output. It supersedes nothing:
[todo-2026-09-18.md](todo-2026-09-18.md) holds the day's shape and the
standing brief, [todo-2026-09-16.md](todo-2026-09-16.md) and
[todo-2026-09-15.md](todo-2026-09-15.md) still hold their own open items,
and this file says what is worth doing, in what order, and how each piece
can be proven without a person in the headset.

## How the day starts

- Branch `codex/alpha-4-2026-09-14`, head `9a4394a` at the survey, clean
  tree, pushed. 274 tests pass. The installed mod matches the working tree
  file for file and the installed viewer matches the build. The only flag in
  the mod folder is `darktidevr_crosshair_scale.flag`.
- At 09:50 the user wrote: "I'm heading out to work, you're free to
  launch/close sessions as needed." Launches are therefore allowed. (Before
  that the headset was awake and streaming, so the morning's work was
  ordered no-launch-first; that ordering still holds because it batches the
  launches, which the three PC bugchecks of 15 September make worth doing.)

## The survey

Six parallel read-only surveys ran over: the viewer and native code; the Lua
presentation layer; input, bindings and gestures; the body, IK and
calibration; tooling, tests and the unattended harness; the documents and
release readiness. Each was asked for prioritised items with, for each one,
what it needs, how it could be proven without the user, the risk of
deploying it unworn, and a size. Their findings are folded in below with
their evidence; nothing here is a guess unless it says so.

## What "proven without the user" can mean here

In rough order of strength:

1. **A pure Lua test** under `tests/tooling` (the mod's geometry, layout,
   state machines and input sequences are mostly pure; 274 tests already).
2. **A GPU or CPU test** under `tests/` (the panel renderer's geometry is
   proven this way against Virtual Desktop's own asymmetric field of view).
3. **An unattended run's own log lines** — the mod logs a line per feature
   on its first placement, and `DARKTIDEVR_INPUT gameplay_delivery` names
   every input delivered per frame, which is what diagnosed the radial
   regression.
4. **An eye readback** (`%TEMP%` request, PPM per eye): shows what the mod
   drew into the eye images. It cannot show anything the *runtime*
   composites — quad layers, so the reticle and the ADS vignette — which is
   one reason to move them into our own projection layer.
5. **A review by a second reader** before anything is deployed for a worn
   test.

## A. No launch, worth doing first

### A1. The ADS vignette: painted per image, sized from the real field of view — DONE (`9a17269`)

Two faults, both from `481727d` (12 September), neither ever seen. The
sprite sits in a corner of the shared flat texture and was painted only when
its strength changed (`src/xr/main.cpp:3203`), so one swapchain image got it
and the others kept stale pixels. And the quad was a fixed 3.6 m at 1 m,
whose ramp peaks at 61 degrees off the view's centre while Virtual Desktop
shows at most about 52: at 45 degrees the alpha reached 9 of 255. Now
painted per image and sized from `located_views[].fov`
(`core/reticle_atlas.h: vignette_half_extent`), with the geometry logged
once and a line each time aiming starts or stops.
**Proof**: the new `openxr.ads_vignette` and `openxr.ads aiming=` lines in
one launch; the ramp itself is now a pure function and testable (A6).

### A2. The ADS zoom — DONE (`9a17269`)

"Aim zoom (%)", default 12, range 0 to 30, needs Aim focus on (user: "add a
small zoom to ADS - maybe 10-15%"). The mod owns the rendered frustum, so
aiming divides its tangents by the magnification while the viewer keeps
submitting the runtime's own field of view: a narrower cone shown across the
same angle. Asymmetry and the optical centre scale with it, so both eyes
stay on one world ray; every consumer of the frusta takes the zoomed pair,
so the HUD and the markers stay in register.
**Proof**: `DARKTIDEVR_AIM zoom=on magnification=` plus an eye readback
while aiming, where the world is visibly larger. Tested pure
(`test-projection-math.lua`).

### A3. A quad can reach the runtime with no swapchain (crash)

`src/xr/main.cpp:4805` submits `gameplay_reticle_quad` on
`gameplay_reticle_pose && reticle_scale > 0`, but it is only populated at
`:4575` under `&& window_capture && flat_swapchain != XR_NULL_HANDLE`.
`tools/stereo/run-synthetic-framegen-benchmark.ps1:291` passes both
`--enable-gameplay-reticle` and `--capture-window-deferred`, so a pair
submitted before the window is acquired sends a zeroed quad to `xrEndFrame`,
`check_xr` throws, and the viewer exits.
**Needs** no launch. **Proof**: the headless simulator with those two flags.
**Risk** none. **Size** minutes.

### A4. Input: the claim slot, the same bug class as the radial regression

Four real faults, all provable by pure tests:
- **Reach to interact is dead whenever a gun is out.**
  `darktidevr_reach_interact.lua:249` yields to *any* truthy request, and
  two-hand support offers one every frame a gun frame is valid
  (`darktidevr_two_hand_support.lua:166-175`), acquiring or not. This is
  exactly what the item radial was fixed for; share `Radial.yields`.
- **The radial owns the stick one frame late.** `darktidevr.lua:6582` reads
  `item_radial.open()`, which is only written in `api.finish` after the
  bindings sample (`:6616`), so on the frame the claim is taken a stick
  already over its threshold still fires its binding. This is the residue
  behind the user's "infrequently it'll pull out the item".
- **`two_hand.finish` can index nil** (`darktidevr.lua:6622`:
  `radial_request` true with `presentation.holsters` nil) and
  `darktidevr_two_hand_support.lua:177` has no `type(grip)=='table'` guard.
- **The cancel path leaves claims standing**: `darktidevr.lua:6711` samples
  the bindings with the service gone but never calls the three `finish`
  functions, so a holster claim and the skull's held state survive a frame.
**Needs** no launch. **Proof**: a new `test-claim-arbitration.lua` replaying
the real order (two-hand, holsters, reach, radial, bindings, the three
finishes) over a scripted sequence — the single highest-value test here,
since it covers the class that has now bitten twice.
**Risk** low. **Size** a morning for the set.

### A5. The last fixed-arity forwarders

`darktidevr_haptics.lua:519` still takes `(name, fn, a..f)`; twelve
`mod:hook` wrappers in `darktidevr.lua` name the stock signature and call
`func(self, <named>)` rather than `func(self, ...)` (`:11531, 11557, 11597,
12072, 12092, 12540, 13115, 13245, 13359, 13462, 13475, 14781`). None is
broken today; all are the shape that dropped `exclusive_stick` for a day.
**Proof**: make them variadic and add a source-invariant check to
`tools/stereo/test-darktide-lua-invariants.ps1` so the shape cannot return.
**Size** an hour.

### A6. Tests that would have caught what has actually bitten

- `src/core/reticle_atlas.h` has never had a test: assert the vignette's
  alpha at the runtime's real angles (A1), and that the painted box contains
  the submitted `imageRect` at both 2112x1188 and 1908x1073.
- A parameterised layout test over {2112, 1908} for every overlay consumer
  (`item_radial`, `forearm_holsters`, `holster_counts`, `ammo_readout`,
  `hud_panel`), not just the two fixed yesterday.
- A test that every module's `RESOLUTION_LOOKUP` consumer reads the variable
  rather than a literal.
- A wrapper round-trip test (`select('#', ...)`) for A5.
**Size** an afternoon; each is small on its own.

### A7. Presentation: displays that switch themselves off for the session

Seven modules latch `failed = true` on the first error and never clear it
(`darktidevr_ammo_readout.lua:460`, `_wrist_display.lua:196`,
`_holster_counts.lua:130`, `_teammate_status.lua:134`,
`_forearm_holsters.lua:584`, `_crosshair_feedback.lua:126`,
`_melee_preview_display.lua:99`); only `weapon_charge_display` re-arms.
One transient nil at a level change kills that display for every mission
afterwards. Re-arm on `destroy()` and latch on three consecutive failures.
**Size** an hour. **Risk** low.

### A8. Presentation: smaller, all no-launch

- The crosshair flag is rewritten every frame if the write fails
  (`_crosshair_feedback.lua:123`, `:53`) — a failed main-thread `io.open`
  per frame, the exact spike the profile document names.
- Teammate panels are keyed by iteration order, not by player
  (`_teammate_status.lua:87`), so a join or a death draws one player's bars
  over another's head for a frame.
- The hand overlay's panel roll is ill-conditioned looking straight down at
  the wrist (`_hand_overlay.lua:47`).
- `canvas.text` guards width but not height, so text near a cell's top or
  bottom still reaches the neighbour.
- A full atlas is silent (`_marker_atlas.lua:200`).
- `hand_overlay.draw` and `marker_atlas.draw` are the only camera-update
  draws not inside a `frame_profile.section`, so the atlas pass has been
  invisible in every profile taken.
- Dead `gui` upvalues in `_wrist_display.lua:92` and `_holster_counts.lua:40`.

### A9. Body: two guards before anything worn

- **The reflection with a mismatched rig puts a head on the camera.**
  `darktidevr_body_mirror.lua:684` returns early after `place()` when
  `same_layout` is false; `reflection` has `distance = 0` and
  `hide_head = false`, so an Ogryn or a cosmetic that changes the node count
  leaves a whole character with its head on the player's eyes. Guard before
  the F8 test.
- **Near-eye hiding has never hidden a mesh**: every recorded run logs
  `hidden=0`, and all 348 per-mesh decisions in
  `artifacts/unattended/body-mirror-*` are `decision=far`. The eye is
  estimated from `j_head` in the spawn pose (`:472`) about 20 cm forward of
  where the live camera actually is (`live_eye_root_local`), and the scan
  runs before the scale settles. Take the eye from the first-person unit and
  re-run once the scale has settled.
**Size** small each.

### A10. Documents (no launch, and the user's reception depends on them)

- The changelog still lists two withdrawn features under "New"
  (`CHANGELOG.md:57-69`) while the same section says they are withdrawn.
- The user guide describes none of: Full body, F8, the skull throw, the
  weapon charge display, aim pitch, F7, and four other shipped options; and
  it says the charge meters sit on the HUD panel, which the option now
  contradicts (`docs/USER-GUIDE.md:281`).
- No guidance anywhere on Virtual Desktop's FOV tangent, now the single
  biggest source of visual faults.
- Four design documents say "nothing is implemented" for features that have
  shipped (`full-body-ik-design-2026-09-15.md:3`,
  `two-hand-aim-design-2026-09-15.md:3`,
  `whole-body-ik-design-2026-09-14.md:11`,
  `virtual-holsters-2026-09-14.md:3`).
- `README.md:11` sends a returning reader to the 11 September handover and
  names a focus that is seven days stale; both doc indexes are stale too.
- The Unreleased changelog wants re-shaping into release notes a player can
  read (new options; the new shortcut; fixed; withdrawn; for tinkerers).
  **Writing them is allowed; publishing is not.**
**Size** a morning for the lot.

## B. The launches, batched

Each launch is expensive (a PC bugcheck risk during level loads, and a
long round trip), so instrument first and prove many things per launch.

### B1. Instrument, then launch once: the proving run

Before launching, add the log lines that make one run answer many
questions: the marker extents against the cell
(`DARKTIDEVR_MARKER_ATLAS extents max_dx= max_dy= half_cell=`), the overlay
text fit (`fitted key= asked= used= room=`), `Application.back_buffer_size()`
beside `RESOLUTION_LOOKUP` and `RESOLUTION_LOOKUP.scale` at level start, and
a counter on the input cancel path. Then one Psykhanium launch as Robobert
with the skull, radial, wrist, ammo and charge test flags and
`darktidevr_body_mirror.flag` = `overlay`, with an eye readback requested
mid-hold, proves:
- items 47 to 54 of the checklist (deployed 17 September, never run);
- the skull feed (`DARKTIDEVR_SKULL_THROW feed thrower= mirror= tables=2
  root_children=9`, and no `feed_error=`);
- the body overlay's new neck geometry —
  `DARKTIDEVR_BODY_MIRROR neck_follow offset_m=` must now read about
  -0.10 x scale in z, where every prior run read 0.000; that is a pure
  consequence of the change and needs no head;
- the ADS vignette's geometry line and, with a held aim, `openxr.ads
  aiming=1` and the zoom's `DARKTIDEVR_AIM zoom=on magnification=`;
- the marker extents that decide whether the pickup sliver is sampling
  bleed (yesterday's blind guess) or content drawn outside its cell — the
  presentation survey's reading is that it is the latter, because marker
  positions come from `Camera.world_to_screen` in back-buffer pixels while
  sizes scale by the eye target.

### B2. A second launch only if B1 leaves something open

The reflection mode can be run without the F8 key: the flag accepts any mode
name, so `darktidevr_body_mirror.flag` = `reflection` runs the whole
pipeline and puts the copy 2.5 m ahead, where an eye readback sees it. Worth
its own arm because it must not run beside the overlay while unproven.

### B3. Virtual Desktop's streaming frame rate against performance (user, 18 September)

"test different virtual desktop streaming framerates to see how they impact
performance. Previous testing was done at 120, it's currently set to 100."

The logs bear that out and sharpen it. Every Hub arm of 16 September records
`last_display_period_ms=8` (120 Hz), including the ones that concluded the
pipeline pins near 55 game pairs a second whatever we do to it; the user's
17 September session records 10 ms (100 Hz) and 64 to 75 pairs. So dropping
the streaming rate by a sixth *raised* the game's own frame rate by about a
fifth. That is the opposite of the usual intuition and it is the single
largest performance lever found so far, larger than the FOV tangent's 10 per
cent. The likely reason: the compositor and the encoder take a fixed share
of the GPU per submitted frame, so submitting fewer leaves more for the
game. (Correcting the 17 September handover, which said the 16 September
arms ran at 90 Hz: they ran at 120.)

What to measure: one Hub arm per rate (72, 80, 90, 100, 120), each with the
frame-profile flag, reading game pairs a second, the pair's GPU time and the
loop's wait from `summarize-hub-arms.py`, and the eye target at each rate
(Virtual Desktop may change it with the rate, which would confound the
comparison -- read `openxr.recommended_size` per arm and say so).

The obstacle: the rate is chosen in the headset's Virtual Desktop app, not
on the PC. Nothing under `%APPDATA%\Virtual Desktop` or the streamer's
registry holds it. Three ways, in order of preference:
1. Try `adb shell setprop debug.oculus.refreshRate <hz>` before a run. This
   is **self-verifying**: the viewer's own `last_display_period_ms` says
   what rate actually happened, so a failed override is obvious and costs
   nothing. Try it once before planning around it.
2. Drive the Virtual Desktop app's streaming menu over adb (`input tap`)
   from a known state. Brittle, and it needs the headset awake and the app
   in the foreground; only worth it if 1 fails and the user wants the sweep
   done unattended.
3. Ask the user to set each rate; the runs themselves are unattended. Each
   change is seconds in the headset menu, so a sweep could be: they set 72,
   we run the arm, they set 80, and so on -- but that is not away-work.

### B4. Cost, when the behaviour is settled

One Hub launch with the frame-profile flag, before and after, for: the two
spawned character profiles (`draw.body_mirror`), the new atlas section, and
any reticle change. `summarize-hub-arms.py` reads the arms.

## C. Bigger pieces, worth starting only when A and B are clear

- **The reticle out of Virtual Desktop's quad layer.** The cheap route is
  not the board projection layer (which costs a second command list and a
  blocking fence every frame) but the `TrackedCuffRenderer` pattern: draw it
  straight into the eye images inside the main command list
  (`src/xr/main.cpp:3415`). That also makes the reticle visible to an eye
  readback, which it is not today.
- **Arm lengths from the calibration in the `overlay` mode** instead of the
  17 to 24 per cent uniform scale, with the design's 0.85 to 1.15 clamp
  (`arm-length-calibration-2026-09-16.md:268`).
- **The runner**: viewer-log lines into `summary.json`, a flag inventory at
  start and end (nothing sweeps `*.flag` if a run is killed), and
  `-EyeReadbackAtSeconds` so a readback is repeatable rather than
  hand-driven.
- **Stock systems that take their third-person branch in VR**: the survey
  found `holo_sight.lua:40` has no else branch, so red-dot and holo optics
  may show no reticle at all in VR. That is a user-visible bug hiding in the
  same class as the servo skulls.

## D. Needs the user

Checklist items 47 to 54 worn; the two body constants in centimetres; a
screenshot if the pickup sliver survives B1; the tag-by-pointing decision;
the body holsters; the JIT-on patch.
