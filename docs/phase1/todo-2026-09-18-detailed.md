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

## Where this list stood at the end of 18 September

**Done and in the game** (four unattended runs, results in
[unattended-results-2026-09-18.md](unattended-results-2026-09-18.md)): A1 the
vignette, A2 the zoom, A3 the null-swapchain guard, A4 the claim slot (with a
new `claim_arbitration` test), A5's haptics wrapper, A9's two body guards,
A10 the documents, B1's instrumentation and its launch, B3 the streaming-rate
measurement, and the runner's eye readbacks.

**Left for another day**: A5's twelve `mod:hook` forwarders; A6's
parameterised layout tests; A7 the displays that latch `failed`; A8's smaller
presentation items; C's reticle-into-the-eye-images, which is the last piece
of the FOV-tangent work; and the arm-length work, which today's A/B showed is
blocked on the calibration's short span rather than on the mode itself.
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

### A5. The last fixed-arity forwarders — DONE, and it was 40 of them, not 12

`darktidevr_haptics.lua:519` still takes `(name, fn, a..f)`; twelve
`mod:hook` wrappers in `darktidevr.lua` name the stock signature and call
`func(self, <named>)` rather than `func(self, ...)` (`:11531, 11557, 11597,
12072, 12092, 12540, 13115, 13245, 13359, 13462, 13475, 14781`). None is
broken today; all are the shape that dropped `exclusive_stick` for a day.
**Proof**: make them variadic and add a source-invariant check to
`tools/stereo/test-darktide-lua-invariants.ps1` so the shape cannot return.
**Size** an hour.

### A6. Tests that would have caught what has actually bitten

- `src/core/reticle_atlas.h` has never had a test — **DONE**
  (`tests/core_math/reticle_atlas_tests.cpp`): it reproduces the run's
  `peak_deg=52.1` from first principles, pins that the painted box contains
  the submitted rectangle at both eye targets, and fails if the vignette
  returns to its fixed size.
- A parameterised layout test over {2112, 1908} for every overlay consumer —
  **mostly done** (`test-overlay-cell-fit.lua` covers the wrist display, the
  item radial, the forearm item name, the holster counts and the ammo ring at
  three tangents). `hud_panel` is not an atlas cell consumer and is left out
  deliberately.
- A test that every module's `RESOLUTION_LOOKUP` consumer reads the variable
  rather than a literal — **DONE**, as a source invariant: the eye target's
  dimensions may appear exactly twice, at their bootstrap declaration, and a
  copy anywhere else fails by name and line.
- A wrapper round-trip test (`select('#', ...)`) for A5 — the frame
  profiler's already exists (`test-frame-profile.lua`, ten arguments through
  with trailing nils kept), and A5 itself is now guarded by a source
  invariant with a mutation harness (`tools/lua/mutate-hook-arity.py`).
**Size** an afternoon; each is small on its own.

### A7. Presentation: displays that switch themselves off for the session — DONE

The list of seven was out of date by the time it was read. `ammo_readout`,
`wrist_display` and `holster_counts` already counted failures and re-armed;
`crosshair_feedback` and `weapon_charge_display` clear their latch when their
source HUD element is destroyed, and `melee_preview_display` clears it when
the option is toggled. **Two genuinely latched for the session**:

- `teammate_status` stopped on the FIRST error and had **no `destroy` at
  all**, so there was no path back short of restarting the game. It now
  counts, and the three level-load teardown sites in `darktidevr.lua` call
  its new `destroy`.
- `forearm_holsters` stopped on the first error too. It has a `destroy` that
  a level load already calls, so only the count had to be forgiven there --
  and the bad-frame path had to stop going through `destroy`, which would
  forgive the very count it is about to be judged on and latch nothing, ever.

Both follow `ammo_readout`'s shape: three consecutive failures, or twenty in
a level, and a good frame clears the run but not the total. Guarded by
`tools/lua/mutate-display-rearm.py` -- six mutations, including both original
first-error latches, all caught.

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
- Dead `gui` upvalues in `_wrist_display.lua:92` and `_holster_counts.lua:40`
  — **DONE**. Neither was ever assigned: both displays stopped owning a GUI
  when they moved to the hand overlay's atlas.

### A9. Body: two guards before anything worn — DONE (both, earlier today)

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
(`DARKTIDEVR_MARKER extents claimant= max_dx= max_dy= half_cell=`, one
line per claimant since 18 September), the overlay
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

- **The reticle out of Virtual Desktop's quad layer** — the last piece of the
  FOV-tangent work, and the only one the user could still notice. Worth a day;
  here is the plan, so it does not have to be worked out again.

  *Why*: the gameplay reticle is a world-locked quad layer
  (`gameplay_reticle_quad`, `local_space_`), and Virtual Desktop draws quad
  layers with a projection that does not match a cropped display. Estimated
  from the same fault that moved the boards: nothing dead ahead, about
  1 degree at 10 degrees off the view's centre, 2.5 at 30, and it swims as
  the head turns against the aim. It is also invisible to an eye readback,
  so nothing can check it unattended.

  *Route*: not the board projection layer. That costs a second
  `ExecuteCommandLists` and a blocking fence every frame
  (`src/xr/main.cpp`, the board pass) and it is menus-only today; making it
  per-gameplay-frame would pay that always. Use the `TrackedCuffRenderer`
  pattern instead: draw into the theatre eye images inside the **main**
  command list, where the cuffs already draw (`record(command_list, eye,
  image_indices[eye], ...)`), with render target views that already exist.

  *The four things it needs*:
  1. **The sprite in a texture we sample.** It is painted into the flat
     swapchain image inside the `update_reticle_atlas` branch; the
     `PanelRenderer`'s `board_texture()` is only filled on the flat-capture
     path. Add the same `CopyTextureRegion` of the 41x41 sprite box into
     `board_texture()` in that branch.
  2. **The pose and field of view the layer is submitted with**, not the
     runtime's raw ones: `recentered_symmetric_projection(located_views[eye]
     .fov, render_aspect_ratio)` and the pose composed with its orientation
     offset. Those are computed after the theatre command list today, so
     hoist the computation above it (it depends only on `located_views` and
     the aspect) and let the layer assembly reuse the result.
  3. **The eye's own rectangle**: `separate_shared_eye_swapchains` decides
     whether each eye is its own swapchain or a half of one, and
     `stereo_top_bottom_layout` which half.
  4. **Resource states**: the theatre images are in `COPY_DEST` after the
     pair copy; the cuff path already transitions to `RENDER_TARGET` and
     back, and the reticle draw belongs beside it, under the same barrier.

  *Gate and proof*: behind `DTVR_XR_RETICLE_IN_EYES` (default off, so the
  quad stays until the user has seen the new one), logged once as
  `openxr.gameplay_reticle layer=quad|eyes`. An eye readback then **shows**
  the reticle, which it cannot today, so its placement can be checked
  unattended against `tracked_cuff_clip_center`-style clip arithmetic. Also
  worth a Hub arm before and after: this removes one of the two quad layers
  Virtual Desktop's compositor pre-processes over the whole flat swapchain.

  *Risk*: it draws into the world image, so a mistake is visible corruption
  rather than a missing overlay. That is why it is gated and why the
  readback matters.
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

- **The options menu: nested submenus, and a reorganisation either way**
  (user, 18 September: "the mod options are getting pretty extensive - if the
  mod tools support further nested submenus (not just segments on one big
  list) then let's do that, and can we reorganise the segments either way?").

  *They do support it.* DMF unfolds `sub_widgets` recursively with no depth
  limit (`dmf/modules/core/options.lua:649-666`), `group` is in
  `allowed_parent_widget_types` alongside `header`, `checkbox` and `dropdown`,
  and each widget's `depth` becomes `indentation_level` in the options view
  (`dmf/modules/ui/options/mod_options.lua:40` and throughout). So a group
  inside a group renders as a further indented, collapsible section. What is
  not yet known is how it *reads* at depth two -- indentation alone, or
  something clearer -- which one launch with a trial tree would answer.

  *Where we are*: 43 settings under three groups (`hud_options`,
  `mode_options`, `experimental_options`), which is what the user is calling
  extensive. The reorganisation is worth doing whether or not the nesting is,
  and should come first: group by what the player is trying to change (the
  body, the hands and what they hold, the world and its markers, comfort and
  movement, performance, developer) rather than by when each setting was
  added. Then nest only where a group has more than about six entries.

  *Care*: `setting_id`s are the saved keys, so the tree can be rearranged
  freely but no id may be renamed without dropping the player's setting.
  Every entry needs its localisation pair in `darktidevr_localization.lua`.

- **Body height and arm length should not be one number: what does everyone
  else do?** (user, 18 September: "investigate industry best practices for
  scaling the body height and arm length based on calibration - surely they
  can be independent").

  This is exactly what today's A/B ran into, from the other end. The body
  copy is fitted to the player with a single uniform scale, so reaching the
  neck up to the player's head (1.30, at its cap) drags the shoulders out and
  up with it, and the arm solve then stretches 13 to 19 per cent to reach the
  hands. Dropping the scale and using the calibrated arms instead
  (`overlaytrue`) cures the arms -- worst stretch 0.42 m to 0.03 m -- and
  leaves 18 cm of neck-to-head gap. One number cannot serve both, which is
  the user's point.

  *What to read*: how the established runtimes decompose a calibration --
  eye height, arm span and shoulder width into independent limb scales rather
  than one body scale. VRChat's IK calibration (per-bone scaling from a T
  pose), Meta's Movement SDK body tracking retargeting, Unity/Unreal's
  standard humanoid retarget rigs, OpenXR's body-tracking extensions, and the
  anthropometric regressions these all lean on (stature to segment length).
  The question to answer is which segments are scaled independently, from
  which measurements, and what is done about the residual the way our 18 cm
  is a residual.

  *What we already have to work with*: `floor_eye_height` and `hand_span` from
  the calibration, the derivation in
  `docs/design/arm-length-calibration-2026-09-16.md`, and a measured A/B of
  both extremes in
  [the results](unattended-results-2026-09-18.md). What is missing is the
  middle: spine and leg scaled to the height, arms scaled to the span, torso
  width to the shoulders.

- **The marker atlas runs out of cells, and did so in an empty room.**
  Measured 18 September (`hook-arity-smoke-20260918`):
  `DARKTIDEVR_MARKER_ATLAS atlas_full cells=8 anchor=?` in the Psykhanium.
  The atlas is 2 by 4 by default (`darktidevr_marker_atlas.lua:23`) and every
  world marker on screen claims a cell, so the ninth onward are silently
  hidden. A mission with a squad and objectives will be well past eight.

  *Derived 18 September from Darktide's own constants, not from a run, and
  the answer is twelve.* The binding claimant is the interaction popup, and
  its geometry is fixed in source rather than sampled:

  - **Width is a constant.** `background_size` is 400 logical px and the
    popup never widens with its text -- a long description wraps and grows
    taller. 400 x 1.07 = 428, which is the 425.3 the run reported. So the
    width bound is exact, and it is what holds the atlas to **two columns**:
    a 512-wide cell leaves 248 px for a box that always wants 428.
  - **Height grows with the description.**
    `H = (line(20)+20) + (line(26)*lines + 40)`; two lines gives 146.4,
    which is the 147 a run reported. The mod drops the popup by
    `interaction_popup_drop` = 1/3 of H, so it reaches `H*2/3` above the
    cell centre and `H/3 + 5 + extra_h` below it, where the `+5+extra_h` is
    `extra_info_background` hanging beneath the popup -- a box nothing had
    counted. At 1.07 that is 105 px for two lines and **127 for three**.

  | cell, in the existing 2048x2048 | cells | half-cell | three-line popup (127) |
  |---|---|---|---|
  | 1024 x 512 (today) | 8 | 504 x 248 | fits, with 121 px spare |
  | **1024 x 341** | **12** | 504 x 162 | **fits, 35 px spare** |
  | 1024 x 256 | 16 | 504 x 120 | clips onto the next marker's quad |

  So **half again as many cells are available for nothing** -- no larger
  texture, no 32 MB. Sixteen would need 2048x4096 and is not worth it.

  *Not taken yet, deliberately.* The last resize came off a derivation too,
  and it was wrong. `test-marker-atlas.lua` now asserts this one and rejects
  1024x256 by name, and the extents instrument now measures per claimant, so
  the next run that carries a marker will say whether the popup really is the
  widest claimant before the grid is bet on it. If it is, the resize is four
  characters.

  *The further direction*: the popup is routed with no `admits` check unlike
  the world-marker widgets (`darktidevr.lua:13980` against `:13881`). One
  claimant sets the cell for all of them. Handle it on its own terms and the
  other markers fit a far smaller cell again.

## D. Needs the user

Checklist items 47 to 54 worn; the two body constants in centimetres; a
screenshot if the pickup sliver survives B1; the tag-by-pointing decision;
the body holsters; the JIT-on patch.
