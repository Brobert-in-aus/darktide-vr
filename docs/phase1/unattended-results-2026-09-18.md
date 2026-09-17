# Unattended results: 18 September 2026

One Psykhanium launch as Robobert (`artifacts/unattended/prove-20260918`),
200 s hold, flags for the skull throw, the item radial, the wrist display,
the ammo readout, the weapon charge display, the new aim-down-sights test
flag, and `darktidevr_body_mirror.flag` = `overlay`. Scene reached in 114 s,
no crash, clean quit, **zero mod warnings or errors**. The run's job was to
put the 17 September work in front of the game for the first time and to
answer five open questions in one launch.

## What it settled

### 1. The vignette could never have been seen — and now reaches the runtime

`openxr.ads_vignette blend=0.218 half_extent_m=1.285 peak_deg=52.1 images=3
sprite=1801,1008`, with `openxr.ads aiming=1` from the new test flag.

- **`images=3`.** The runtime cycles three flat swapchain images. The sprite
  used to be painted only when its strength changed, which wrote one image,
  so at best one frame in three could have shown anything — and the others
  held whatever the capture last put there. That is the fault the user could
  not name ("I suspect it's never worked").
- **`peak_deg=52.1`.** The darkening now reaches its full strength at the
  edge of what Virtual Desktop actually shows. It was a fixed 3.6 m quad
  whose peak sat at 61 degrees, outside the view: at 45 degrees off centre
  the vignette reached 9 of 255.

### 2. World markers do not depend on the desktop window, and the UI scale is exact

`DARKTIDEVR_MARKER pixel_spaces back_buffer=1908x2076 lookup=1908x2076
scale=0.99375 eye_target=1908x2076`.

Two of the FOV-tangent audit's open questions close together. The marker head
frame divides by `Application.back_buffer_size()`'s height while marker sizes
are authored at `RESOLUTION_LOOKUP`: those are **the same** in the headset, so
there is no window-size dependence and no 10 per cent error. And
`RESOLUTION_LOOKUP.scale` is exactly 1908/1920 = 0.99375, not quantised, so
the published menu extents cannot drift from the viewer's flat swapchain.

### 3. The pickup sliver is not content drawn outside its cell

`DARKTIDEVR_MARKER extents max_dx=71.7 max_dy=8.9 half_cell=512.0,256.0`.

The worst offset any routed marker draw asked for was 72 px from its cell's
centre, against a half cell of 512. So the hand displays' cause (a layout
wider than its cell) is **not** the pickup markers' cause, and the
17 September guess that it was sampling reaching past the cell edge is the
one still standing. The 8-texel gutter deployed last night is the fix for
that reading; whether it worked is now a question for the user's eyes, and
a screenshot if it has not.

### 4. The servo skulls' feed runs for every skull, with no error

`DARKTIDEVR_SKULL_THROW feed thrower=true mirror=true tables=2
root_children=9`, plus two `thrower=false` lines for the medical and regular
skulls. Both rest tables are swapped for every skull, the nine parts under
the root are what the throw must move, and no `feed_error` appeared in
200 seconds. The wrapped stock update is sound; what it looks like worn is
still checklist item 53.

### 5. The body overlay is still reaching for a neck it cannot get to

`neck_follow offset_m=-0.078,0.120,0.000 distance_m=0.143 scale_ratio=1.300`,
then `1.205`. The z offset is 0.000 and the scale sits at its 1.3 cap: even
with the target lowered 10 cm last night, the copy's neck is still *below*
where it is asked to be, so the move that would fix it is upward and the code
correctly refuses to lift the root. That is the uniform-scale problem the
arm-length design exists to replace, not a fault in last night's change.
**This is now the strongest argument for doing the arm-length work**: the
copy is enlarged to the cap and its arms with it.

### 6. Near-eye mesh hiding has never hidden a mesh — confirmed again

`near_eye eye=0.070,0.238,1.562 ... meshes=32 hidden=0`. The scan estimates
the eye from the copy's head joint in the spawn pose, about 0.24 m forward of
where this module's own `live_eye_root_local` line says the camera is, and it
runs before the scale settles. Fixed the same day (the scan now takes the
first-person camera and waits for the scale); unproven until the next run.

## What it did not answer

The eye readbacks were requested and consumed but wrote nothing: the
**projected**-eye readback is only copied on a frame that draws the tracked
cuffs or a board, so an ordinary gameplay frame serves the request and writes
no file. The runner now asks for the **shared**-eye readback as well, which is
the game's own rendered pair and is what shows the zoom.

## The second run (`prove-20260918-b`), after the day's review fixes

Same scene and character, 120 s, with the aim-down-sights test flag and the
body overlay. Scene reached, no crash, no mod errors.

- **The eye readbacks work now.** Four PPMs at the full 1908x2076, at 60 s
  and 100 s. The runner asks for both readback kinds because the
  **projected**-eye one is only copied on a frame that draws the tracked
  cuffs or a board, so the first run consumed its request and wrote nothing;
  the **shared**-eye readback is the game's own rendered pair and is written
  in ordinary gameplay.
- **The zoom does not break the render.** The readback with the zoom active
  shows the Psykhanium correctly projected, the HUD in place, no black
  frame, no distortion: the one real risk in changing the rendered frustum
  is cleared. The magnification itself is proven by
  `DARKTIDEVR_AIM zoom=on` and by the pure test; the readback cannot show it
  on its own without a matching unzoomed frame to compare.
- **The near-eye scan now takes the real camera**:
  `near_eye eye=0.097,0.020,1.364 source=camera head=0.107,0.032,1.315`.
  The old estimate put the eye 0.24 m forward and 0.20 m above where the
  camera actually is. **It still hides nothing** (`meshes=32 hidden=0`), so
  the eye was not the only reason: with the correct eye, no mesh's box comes
  within the 0.25 m radius. Either the criterion wants the mesh's surface
  rather than its box centre, or the hiding is simply unnecessary now that
  the head slots are hidden outright. Not worth guessing further without the
  user looking down at the body.

## Still open after both runs

- The pickup sliver: measured *not* to be content overflow, so last night's
  gutter is the standing explanation. The user's eyes decide.
- The body overlay's uniform scale: capped at 1.3, and the arms with it. In
  the first run the solve wanted a target 0.759 m from the shoulder against a
  0.709 m reach, so the soft stretch ran on **every** frame
  (`unreachable_frames=25200` of 25200, `max_stretch_ratio` 1.13 to 1.19).
  That is the case for the arm-length work, in numbers.

## The streaming rate: 120 Hz against 100 Hz in the Hub (the user's question)

`hub-100hz-1`, a Hub arm with the frame-profile, cpu-render-timing and
performance-profile flags, against the two arms of 16 September
(`profile-20260916/hub-fov90-1`, `-2`). Same zone, same character, same
90 per cent FOV tangent (`recommended_size=1908x2076` in all three), same
flags; the only difference is Virtual Desktop's streaming rate, which the
viewer records as `last_display_period_ms` (8 ms = 120 Hz, 10 ms = 100 Hz).

| arm | rate | GPU per pair | game pairs a second |
|---|---|---|---|
| hub-fov90-1 (16 Sept) | 120 Hz | 21.2 ms | 59.2 |
| hub-fov90-2 (16 Sept) | 120 Hz | 20.7 ms | 58.5 |
| hub-100hz-1 (18 Sept) | 100 Hz | **19.6 ms** | **72.3** |

**Lowering the streaming rate by a sixth raised the game's own frame rate by
about 22 per cent**, and took 7 per cent off the GPU each pair costs. That is
larger than every mod-side lever measured on 16 September put together (queue
priority, process class, padding, frame generation: none moved it) and larger
than the FOV tangent's own 10 per cent.

Why, most likely: the compositor and the encoder take a share of the GPU for
every frame they are handed, so handing them fewer leaves more for the game.
The viewer's own submission rate supports that reading — at 120 Hz it
submitted about 117 frames a second (repeating pairs to fill the cadence),
at 100 Hz it submitted 72.9, exactly the rate fresh pairs arrived, and
Virtual Desktop's own reprojection filled the rest.

**What this does not say**: whether 90, 80 or 72 Hz is better still, and
whether the smoothness of the headset's own reprojection at a lower rate is
worth the extra rendered frames. Those need the rate changed in the
headset's Virtual Desktop menu, which nothing on the PC can do: the rate is
not in the streamer's registry or `%APPDATA%\Virtual Desktop`, and the Quest
exposes no `debug.oculus.refreshRate` property to set (checked, empty).
So the sweep below 100 Hz is either a worn task or needs the Virtual Desktop
app driven over adb.

**Tooling note**: `summarize-hub-arms.py` reads `viewer.log`, but a run with
the game-started viewer writes `game-viewer.log`, so its pair and submission
columns read zero for such a run. The numbers above come from the viewer log
directly.

## Arm lengths from the calibration, measured against the uniform scale

`body-armlength-20260918` runs the `overlayarmlength` mode, which applies the
calibrated upper-arm and forearm lengths after the uniform scale, against the
first run's plain `overlay`. Both in the Psykhanium as Robobert, neither with
tracked controllers, so the hand targets come from the character's own
animation in both: the arm *lengths* below are calibration-driven and
comparable, the shoulder-to-target distances are not the worn case.

| | `overlay` | `overlayarmlength` |
|---|---|---|
| world upper arm | 0.355 m | 0.290 m |
| world forearm | 0.354 m | 0.248 m |
| **reach (upper + forearm)** | **0.709 m** | **0.538 m** |
| length ratios applied | none | 0.815 and **0.700** (at the clamp floor) |
| soft stretch, worst | 0.00 m (ratio 1.13-1.19) | **0.42 m** |

**Corrected after checking the arithmetic against the saved calibration.**
The first reading of this table was that the calibration is too short to use.
It is not. The saved result is a standing one (`seated = false`,
`floor_eye_height = 1.723`, `hand_span = 1.559` against a predicted 1.630,
so 7.1 cm or **1.6 standard deviations** short — inside the 2.5 SD the
derivation accepts, which is why its source reads `span`). From that span the
derivation gives a shoulder-to-wrist reach of 0.518 m, and 0.29 m + 0.23 m
segments, for a 1.78 m player. Those are **plausible human arm lengths**; the
log's `shoulder_width_m=0.491` is the rig's own width, printed for
information, while the derivation correctly used the player's 0.362 m.

The conflict is the other side of the equation. The rig's own arm is 0.550 m
unscaled, and the copy is scaled by 1.21 to 1.30 to reach the neck, which
puts its arm at 0.665 to 0.715 m **and its shoulders that much further from
the body's centre** — while the hand targets stay where the unscaled avatar's
hands are. The solve is then asked for 0.82 to 0.87 m from a shoulder that
has been moved outward and upward. Giving it true 0.518 m arms makes that
gap worse, not better: the stretch goes from 0.05 m to 0.42 m.

So the lesson is not about the capture at all:

- **Calibrated arm lengths cannot be used while the copy is uniformly
  scaled.** The two are in direct conflict, and the design says as much —
  the uniform scale is a stand-in until the body is the player's height by
  construction (the spine and legs milestones), not by enlargement.
- **The order of work is therefore**: stop scaling the whole copy (bend the
  spine, or scale only the legs, so the neck reaches the head without the
  shoulders moving), and only then apply the calibrated arms.
- The span capture is still worth improving (the design asks for the 90th
  percentile of grip-to-grip over the hold, and the code averages 45 frames
  inside a 15 mm stillness gate, so it cannot correct a player who does not
  fully extend). But at 1.6 SD it is **not** what is blocking the arms, and
  today's A/B is not evidence against it.

## The body at the player's own proportions (`overlaytrue`, `body-true-20260918`)

Acting on the correction above: a dev-flag mode that drops the uniform scale
entirely, bends the spine to bring the neck up (the existing `spine_bend`
step) and applies the calibrated arm lengths. Same scene, character and
conditions as the two arms above.

| | `overlay` (shipping) | `overlayarmlength` | **`overlaytrue`** |
|---|---|---|---|
| uniform scale | 1.30 (at the cap) | 1.21 | **none** |
| world arm (upper + forearm) | 0.709 m | 0.538 m | 0.518 m |
| shoulder to target | 0.75-0.80 m | 0.82-0.87 m | **0.57-0.60 m** |
| worst soft stretch | 0.00 m (ratio 1.13-1.19) | 0.42 m | **0.0006 m left, 0.031 m right** |
| length ratios | none | 0.815 / 0.700 (floor) | 0.985 / 0.776 (free) |

**The arm solve stops fighting the body.** With the shoulders left where the
player's are, the calibrated 0.518 m arm reaches its target with under 3 cm
of stretch on the worse side and essentially none on the better, against
0.42 m when the same arms were fitted to a copy scaled up to reach the neck.
The forearm ratio also comes off its clamp floor (0.776 against 0.700), which
means the derivation is being applied as it was designed rather than being
truncated.

**What is not solved**: `spine neck_gap_m=0.254->0.181`. Bending the spine
closes the gap between the copy's neck and the player's head from 25 cm to
18 cm, so 18 cm remain — the head still sits above the body, which is the
user's original complaint (worn item 52). The uniform scale was hiding that
by enlarging everything. So the honest position is:

- scaling the whole copy makes the neck meet the head and ruins the arms;
- bending the spine fixes the arms and leaves the head 18 cm high;
- neither is finished. The remaining 18 cm is what the legs milestone (or a
  larger spine range, or scaling only below the neck) is for.

This is measurement, not a recommendation to change the default: `overlay`
still ships and `overlaytrue` is a flag. The worn question for the user is
which of the two looks less wrong, and that needs a head.

## The projection anything drawn into the eye images has to use

Preparing the reticle work turned up a plain arithmetic mismatch that nobody
had checked. The theatre eye images are submitted to the runtime with a
**recentered symmetric** projection (`main.cpp`,
`recentered_symmetric_projection`), and the game renders the pair with the
same one (`darktidevr_projection_math.lua: Projection.recentered_eye`). The
tracked cuffs were drawn into those images with the runtime's own **off-axis**
frustum and the un-composed pose. Those are not interchangeable.

At the field of view Virtual Desktop reported in `hub-100hz-1`
(`openxr.runtime_fov.eye0=-0.893445,0.648593,0.71549,-0.909609`, aspect
1908/2076), a point on the eye's own optical axis lands at:

| convention | NDC | off the rendered centre |
|---|---|---|
| recentered symmetric (what the image is) | 0.000, 0.000 | 0 |
| raw runtime frustum (what the cuffs used) | **+0.120, +0.102** | **6.2 deg, 5.9 deg** |

The optical centre is 7.0 degrees of yaw and 5.6 of pitch off the eye's
forward, and the yaw has the opposite sign in each eye, so the horizontal
error reverses between them: the two images disagree by about 12 degrees of
disparity, which is a stereo cue claiming a depth the cuff is not at. The
cuff overlay is a `--tracked-cuff-overlay` development switch and is off in
play, which is why this has never been worn.

Fixed by computing the submitted projection once, before the theatre command
list, and having the cuffs, the new reticle draw and the layer all read that
one answer. `core_math` pins both numbers above, so the two conventions
cannot be quietly swapped again.

## The reticle out of the quad layer (`DTVR_XR_RETICLE_IN_EYES`, default off)

Built as the detailed list planned it: the panel renderer draws the reticle
quad into the eye images beside the cuffs, from the same pose, size and texel
rectangle the quad layer would have used, so it is the same sprite in the
same place -- but placed by the projection the world is placed by, instead of
by Virtual Desktop's compositor guessing at a cropped display.

Four things it needed, and where each landed:

1. **A texture to sample.** The sprite is painted into the flat swapchain
   image, which is the runtime's, not ours. The same `CopyTextureRegion` now
   also puts it in `PanelRenderer`'s board texture, in the command list that
   paints it.
2. **The right projection.** The hoisted arrays above.
3. **The eye's own rectangle.** Both layouts handled: separate swapchains, or
   the halves of one.
4. **Resource states.** The draw sits inside the cuffs' existing
   COPY_DEST -> RENDER_TARGET window.

`openxr.gameplay_reticle layer=quad|eyes` says which path a run took, and the
projected-eye readback now fires on a reticle-only frame, so an unattended run
can finally **see** the reticle and check where it is -- which it never could
while the reticle lived in a layer the runtime composites after us.

Not yet run in the game. Default off until it has been worn.

## What the reviews caught before anything ran

Three of the day's reviews found faults in work written the same hour. None
of these reached the game, and two would have been hard to diagnose from a
worn session.

1. **All three of solo play's bots on one panel anchor.** The teammate key
   asked for the account id, then the peer id. A bot is added with no account
   id at all and carries the host's peer id, so every bot resolved to the same
   key: the second and third overwrote the first's position and claimed extra
   cells against it, which is two panels over one bot's head and none over the
   others, every frame. `unique_id` (peer, local player and a counter) is
   asked first now.
2. **A clock that goes backwards wedged the new anchor sweep permanently**,
   and the marker atlas had the same shape with a worse symptom -- a negative
   age reads as "drawn this instant", so the cells last claimed would keep
   showing and the resources would never be released, which is the crash on
   mission unload that release exists to avoid.
3. **The reticle would have vanished past 100 metres.** The panel renderer's
   projection has always had a 100 m far plane, invisible while it drew only
   boards two metres out. The mod publishes the aim distance up to 200 m, so
   aiming down a long hall clipped the quad away -- and because a draw had
   been *issued*, the quad layer stood down, leaving nothing at all. Far plane
   now 1000 m, and "drawn" means the centre is inside the frustum.
4. **The aim state was read too early for the path that ships.** Hoisting the
   derivation above the theatre command list is necessary for drawing into the
   eye images and costs everything else the samples published during the pair
   wait and the GPU work. It is one lambda now, called early only when the
   draw needs it.

## The aim zoom was moving the world and not the reticle

Following the last of those: the zoom renders a narrower cone across the same
angle while the viewer submits the runtime's field of view unchanged. Anything
placed by that submitted field of view is therefore placed for an image that
was not rendered -- off the view's centre the world has moved out by the
magnification and the reticle has not. At the default twelve per cent a
reticle four degrees off centre sits about half a degree inside its target,
and further as you look further out.

The mod publishes the point now with the magnification applied across the
view, which cancels it exactly and corrects the shipped quad layer as well as
the drawn one. The head's axis rather than each eye's leaves the two eyes
disagreeing by (m - 1) times half the IPD: under 4 mm at a tenth
magnification, a fiftieth of a degree at ten metres.

**Not run at the time this was written.** The reticle work was built,
reviewed and committed, and the proof prepared -- Psykhanium, synthetic
controller path, `darktidevr_reticle_in_eyes.flag`, eye readbacks, and
`openxr.gameplay_reticle_clip` to check the picture against arithmetic -- but
held back, because I had widened the launch rule to "stop as soon as any
message arrives" and the user had sent two feature requests from work.

**That was my invention and the user removed it**: *"only hold off on
launches if I state I'm home and testing"*. They message during the day
without being near the headset. The rule is a statement of being home or
testing, or a genuinely worn observation -- not contact. The run follows
below.

## The options menu, and a test that was not doing its job

The user asked in the afternoon whether DMF supports nested submenus and for
the segments to be reorganised either way. It does: `sub_widgets` unfold
recursively with no depth limit, and the mod was already two deep in two
places. So the menu is eight sections instead of forty-three settings in a
column, with a setting nested under the one it depends on. No `setting_id`
changed, so every saved value carries over.

The review of that found the thing worth writing down: **DMF hides a
checkbox's children while it is off** -- `is_visible = get(parent) == true`,
not an indent and not a collapse. So nothing may be nested under a setting it
can work without. The body mirror's key had been nested under Full body, and
F8 toggles the mirror whether Full body is on or not: the default
configuration was a working key with no row anywhere that named it, and the
user guide sends you there by name.

And the test written to guard the tree was checking none of DMF's own
required-field rules. Six mutations of the real file -- a typo'd `type`, a
default outside its options, a button with no text, a keybind with no
trigger, a one-option dropdown, a duplicate option value -- all passed the
test, and all six stop the mod loading. Its census of saved keys listed 43 of
106, so a module could have dropped any of the other 63 and been waved
through. Both are fixed, and a mutation script now drives all seven failures
through it.

**The lesson for the rest of the tooling**: a test that walks a structure and
checks what the author happened to think of is worth much less than one
checked against the consumer's own validator. The consumer here is thirty
lines of `validate_*_data` sitting on disk.

## The reticle, drawn into the eye images and measured there

`artifacts/unattended/reticle-eyes-20260918`, Psykhanium, 150 s hold, scene
reached in 72 s, no crash, clean quit. Flags:
`darktidevr_reticle_in_eyes.flag` (the gate) and
`darktidevr_reticle_test.flag` (the published world target standing in for a
tracked hand). The first attempt did nothing at all -- `openxr.system=
hmd-unavailable` -- because the headset was asleep and the Virtual Desktop
client was not running; the Ready preflight woke it, the client was started
over adb, and the second attempt streamed.

```
openxr.reticle_in_eyes=1
openxr.reticle_test=1
openxr.gameplay_reticle layer=eyes texels=37 size_m=0.530634
openxr.gameplay_reticle_clip eye=0 ndc=0.123198,-0.359852 pixel=1071.53,1411.53 w=20.2968
openxr.gameplay_reticle_clip eye=1 ndc=-0.123088,-0.359846 pixel=836.574,1411.52 w=20.297
openxr.gameplay_reticle_frames=11295
```

**11295 frames with a reticle, against 0 in every previous run.** That is the
test flag: nothing unattended has a controller within 1.5 m of the head, which
is what the reticle required.

### Where it landed, checked rather than admired

The projected-eye readback is the eye image as submitted; the shared-eye
readback is the game's own pair before the viewer draws. Everything that
differs between them is the viewer's work. Differencing them at both
readbacks:

| | pixels changed | box | centroid | predicted | error |
|---|---|---|---|---|---|
| 55 s left | 106 | 23x21 | 1071.0, 1411.0 | 1071.5, 1411.5 | **0.7 px** |
| 55 s right | 109 | 23x21 | 836.0, 1410.9 | 836.6, 1411.5 | **0.8 px** |
| 105 s left | 106 | 23x21 | 1071.0, 1411.0 | 1071.5, 1411.5 | **0.6 px** |
| 105 s right | 106 | 23x21 | 836.0, 1411.0 | 836.6, 1411.5 | **0.8 px** |

One compact blob in each image, nothing else changed anywhere in 1908x2076,
and its centre is within a pixel of what the clip arithmetic predicted. The
reticle is drawn into the eye images, in both eyes, exactly where the
projection says it belongs.

The two eyes' horizontal positions are equal and opposite (+0.1232, -0.1231
NDC). That is not a disparity error: it is each eye's own optical centre,
7.0 degrees of yaw in opposite directions, which is precisely what a world
point on the head's forward looks like through the recentered projection the
images are submitted with. A point 20 m away with a 63 mm interpupillary
distance has a true disparity of about 0.2 degrees, far below this.

**What is still not proved**: that it looks right to a person. The gate stays
off by default and checklist item 60 asks for the worn look -- whether it
stays on target through a head turn, which is the fault it was built to
remove and which no readback can show.

## A check that passes the defects it exists for is worse than no check

The hook-arity invariant was written to stop `mod:hook` handlers naming the
stock signature, which silently drops whatever the engine adds beyond it --
the fault that cost the item radial's stick claim a day on 17 September. A
review mutation-tested it and **it passed six real dropped arguments**.

It matched one spelling and one shape of everything:

- `pcall(func,self,...)` was invisible. The opener was written with a space
  and the compact modules have none; worse, `func(` is not a substring of
  `pcall(func,` at all, because that call passes `func` as a value. Eleven
  forward sites unchecked.
- Anything spanning two lines was skipped on a silent `continue`.
- The handler regex required the second parameter to be `self`, so a hook on
  a free function was not a handler.
- `function(func, self)` and `func(self)` were exempt twice over -- the arity
  regex needed a parameter after `self`, and the forward check guarded on a
  non-empty argument list, which is the total-drop case.

Rewritten to normalise spacing, balance brackets across lines, accept any
function whose first parameter is `func`, and read `pcall(func,` as the
forward it is. It immediately found **nine more handlers**, including
`create_viewport` with twelve parameters forwarded three times.

**The other half of the lesson**: it then had to be taught what *not* to
flag. `func(location, false)` in the visual settings deliberately overrides
the value it was handed, and forwarding a tail after it would pass the value
being overridden. A forward is flagged only when it copies the handler's own
parameter list, allowing one substituted name but not a literal. A guard that
blocks a legitimate change is a worse guard than none, and the first cut of
this rule flagged three.

Both harnesses live in `tools/lua/`: `mutate-hook-arity.py` and
`mutate-options-data.py`. Each puts the real failures through the real check
and every one must read CAUGHT. Neither is in ctest, because both anchor on
exact source text and would break the build on an ordinary edit rather than
on the thing being tested.

**The general lesson, twice in one day**: a test that walks a structure and
checks what its author happened to think of is worth much less than one
checked against the consumer's own rules, and worth nothing at all until its
failures have been made to fail. Both of today's new checks passed their own
subject matter until they were mutated.
