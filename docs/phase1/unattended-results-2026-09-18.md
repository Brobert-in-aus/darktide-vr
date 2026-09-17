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
