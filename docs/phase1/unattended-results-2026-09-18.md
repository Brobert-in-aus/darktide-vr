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

**Applying the calibration as it stands makes the arms markedly worse**, and
the reason is in the same log line: `arm_length source=span span_m=1.559
reach_m=0.518 upper_m=0.290 lower_m=0.228`. A 1.56 m span for a 1.78 m player
is short — the 16 September capture was 150.6 cm against 163 expected, and
this one is no better — so the derived forearm hits the mode's 0.70 clamp
floor and the arm ends up a fifth shorter than the rig's own.

So the next step for the body is **not** to switch the overlay to calibrated
lengths. It is to fix the capture first: the design's step 1 asks for the
90th percentile of grip-to-grip over the hold, and the code still averages 45
frames (`darktidevr_calibration_view.lua:231-252`), which is exactly the
under-extension the design predicted. Until the span is trustworthy, the
uniform scale — capped, and stretching by 13 to 19 per cent — is the better
of the two.
