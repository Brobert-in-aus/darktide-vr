# Foveated rendering: what it would take here

Investigation, 18 September 2026. Requested because a Steam Frame is arriving
and foveation is the largest single GPU saving available to a stereo renderer,
and because fixed foveation can be judged on the Quest 3 today without waiting
for an eye-tracked headset.

**Foveated rendering and foveated encoding are different things and only one of
them is ours.** Foveated *encoding* reduces the bitrate spent on the periphery
of an already-rendered frame; it lives in the streamer (Virtual Desktop's, or
the Frame's 6 GHz encoder) and saves bandwidth and encode latency. Nothing in
this repository can implement it or needs to. Foveated *rendering* reduces the
shading work for those pixels in the first place, and that is the frame-time
saving. This note is about rendering.

## The one measurement that was missing, and now is not

Foveation on PC means D3D12 **variable rate shading**, and image-based VRS --
tier 2 -- is the only form that can express it. Tier 1 sets one rate for a
whole draw; foveation is by definition a rate that varies across the screen,
which is a *shading rate image*: a small R8_UINT texture, one texel per tile,
fine in the centre and coarse at the edges.

The viewer now reports the adapter's answer (`--no-openxr` is enough, no
headset, no game):

```
d3d12.adapter=NVIDIA GeForce RTX 4090
d3d12.variable_shading_rate_tier=2 tile_size=16 additional_rates=yes
```

**Tier 2, 16-pixel tiles, and the additional 2x4/4x2 rates.** So the capability
is there, the shading rate image for a 1920x2160 eye is 120x135 texels, and the
non-square rates are available for a pattern that falls off faster horizontally
than vertically.

## Where it has to be applied, and why that is the hard part

The expensive pixels are not ours. The viewer composites and submits; Darktide
renders. An OpenXR foveation extension (`XR_FB_foveation` and its relatives)
applies to swapchains the *application* renders into, and this viewer only
copies an already-rendered texture into its swapchain, so those extensions
would save nothing at all. That is worth stating plainly because it is the
obvious first idea and it is a dead end.

The shading rate has to be set on **Darktide's own command lists**, which the
native producer already hooks:

- `src/producer/d3d12_bootstrap.cpp` is a d3d12 proxy that takes the game's
  `ID3D12Device` and installs for it.
- `src/producer/native_capture.cpp` MinHooks the `ID3D12GraphicsCommandList`
  vtable, including `RSSetViewports` (slot 21), `OMSetRenderTargets` (slot 46),
  `SetPipelineState` (25), `Reset` (10) and the draw entry points.
- `om_set_render_targets_hook` already resolves the bound RTV to its
  `ID3D12Resource*` and compares it against `named_camera_output_resources`,
  the two learned eye finals.

**And that gate is the wrong one, which is why the first thing built is a
census rather than the rate.** The eye final is the RESOLVED output: by the
time it is bound the shading is done, and setting a rate there would foveate a
blit. The main passes also run at the DLSS internal resolution rather than the
eye extent, so "the target whose size matches the eye" would miss them too.
Both of those are plausible enough to have been written down here as the plan.

`src/producer/foveation_census.h` counts draws and primitives per
render-target SHAPE -- grouped by shape rather than by resource, because an
engine rotates through several physical textures for one logical pass -- and
writes a line per shape, busiest first, to
`%TEMP%\darktidevr-foveation-census.log`. It binds nothing and changes no
render state, so a run with it on cannot make the game look wrong. Enabled by
`darktidevr_foveation.flag` containing `census`.

**It ran on 18 September, and the answer is `1272x1384`** -- exactly two
thirds of the 1908x2076 eye extent in each dimension, which is the DLSS Quality
internal resolution. That shape takes about 900 draws a frame. The eye extent
appears only as a resolve, at ten draws a frame. Both guesses in this note were
wrong, which is why the census was built first.

So the shading rate image is sized from the DLSS internal resolution, not the
eye extent, and it has to be rebuilt when the quality mode changes -- the
internal resolution moves with it, exactly as it moves with Virtual Desktop's
FOV tangent.

Two shapes to stay away from, both from the same run: a `2048x2048` shadow
atlas at a `1024x1024` viewport with 3.6 G vertices and no pixel shading, and a
downsample pyramid of `1272x1384` targets at viewports of 636x692, 318x346,
159x173 and 79x86. Foveating either is pointless.

With that known, the rest:

1. `QueryInterface` the hooked list for `ID3D12GraphicsCommandList5`. VRS lives
   there; a list that does not support it is skipped.
2. Create the shading rate image once per eye extent, in
   `D3D12_RESOURCE_STATE_SHADING_RATE_SOURCE`, and never transition it again --
   for fixed foveation it is static.
3. On `OMSetRenderTargets` binding an eye final:
   `RSSetShadingRateImage(image)` and
   `RSSetShadingRate(D3D12_SHADING_RATE_1X1, {PASSTHROUGH, OVERRIDE})` so the
   image wins.
4. On binding anything else, and on `Reset`: `RSSetShadingRateImage(nullptr)`
   and rate `1X1`. **This is the step that decides whether it looks acceptable
   or terrible**: a post-process, UI or shadow pass rendered at 4x4 is not a
   softened periphery, it is visibly broken.

No shader or PSO change is required. Per-primitive rates need `SV_ShadingRate`
in the shader and are not wanted here; screen-space image-based VRS needs
nothing from the shaders.

## Three things this project already knows that change the design

**Where the foveal centre goes, corrected.** This note first claimed the sharp
region had to sit off-centre, at each eye's optical centre, and that claim was
wrong. The game renders each eye with `Projection.recentered_eye`
(`darktidevr_projection_math.lua:19`): a **symmetric** frustum whose axis is
rotated onto that eye's optical axis. So in Darktide's eye render target the
optical axis is at NDC 0 by construction, in both eyes, and a fixed pattern
belongs at the middle of the image.

What the reticle readback on 18 September actually measured -- the aim point at
equal and *opposite* horizontal NDC in the two eyes -- is **stereo disparity**.
A world point at a finite distance projects to different NDC in each eye, and
the difference grows as the target gets nearer. That is a genuine per-eye
difference, and it is exactly why `reticle` mode has to build the image per eye
rather than once; it is simply not an optical offset, and fixed mode does not
need one.

The centre stays a parameter regardless. Reticle mode needs it, and a runtime
that submitted eyes some other way would be a one-line change rather than a
rewrite.

**Virtual Desktop's FOV tangent shrinks the eye target.** The real extent has
been 1908x2076, not the bootstrap 2112x2304, and it moves with the VD setting.
The shading rate image is sized from the render extent, so it has to be rebuilt
when the extent is republished, not created once at startup.

**DLSS is already in the path.** Darktide renders at an internal resolution and
upscales, so VRS applies to the pre-upscale render and the saving is taken on
the smaller image -- proportionally the same, absolutely less. More
importantly, DLSS's temporal accumulation expects a uniformly sampled input,
and a coarse periphery is not that. This combination is supported by NVIDIA but
its quality here is a question for measurement, not for reasoning, and the
first comparison should be run with frame generation off so that two
reprojection stages are not being judged at once.

## The pattern, which is written and tested (18 September)

`src/core/foveation.h` builds the shading rate image, and
`tests/core_math/foveation_tests.cpp` judges it -- both pure, because what a
wrongly aimed foveation pattern looks like through a headset is "foveation
looks bad", which is indistinguishable from "foveation is not worth it".

- `FoveationPattern` carries the foveal centre in NDC and separate horizontal
  and vertical radii for the inner and middle zones. The centre is a parameter
  rather than a constant -- for fixed foveation on this renderer it is (0, 0),
  and for reticle mode the two eyes differ by disparity.
- `paint_foveation_image` fills an R8_UINT tile image at a caller-supplied row
  pitch. The test uses a 256-aligned pitch, as a real D3D12 upload does, and
  checks the padding past each row is untouched -- a test passing the tile
  count as the pitch could not see a pitch bug at all.
- `foveation_cost` reports what the pattern costs as a fraction of an
  unfoveated frame. That is the only honest number before a measurement: it is
  what the PATTERN costs, not what the frame costs, and a frame that is not
  shading-bound will not move by it.

The nine mutations in `tools/lua/mutate-foveation.py` are the ways this can be
wrong without looking wrong: the centre ignored, the vertical centre ignored,
NDC y unflipped, the middle ring dropped, the row pitch ignored, a partial edge
tile dropped, one radius used for both axes, the cost counting every tile as
full rate, and a null image written through. All nine fail the test by name.

Three legitimate edits must NOT be flagged, and two of them caught real faults
in the test: widening the default radii, and changing the middle rate to the
non-square 2x4. The first cut of the test pinned `2x2` by value in two places,
which would have blocked exactly the tuning this exists to allow.

## What a first cut should be

Fixed foveation, off by default, behind a producer flag, with a static three-
zone radial pattern about the centre of each eye's render target: `1X1` inside
an inner ellipse, `2X2` in a ring, `4X4` outside it, with the ellipse wider
than tall because the horizontal field is where the periphery is largest.

Make the zone radii and the outer rate settable from the launcher rather than
compiled in. The whole point of a first cut is to find where the boundary
becomes visible during a head turn, and that cannot be found by rebuilding.

**Eye-tracked foveation is the same machinery with a moving centre.** The Steam
Frame has eye tracking, and if its runtime exposes a gaze pose the only change
is that the ellipse centre is updated per frame instead of fixed. Building the
fixed version first is not a detour.

**And the reticle is a gaze proxy that costs nothing to try** (user, 18
September). In an aimed shooter the player is usually looking at or near where
they are aiming, and the viewer ALREADY derives the aim point's NDC per eye --
that is `openxr.gameplay_reticle_clip`, the number the reticle work measured to
under a pixel. So a third mode:

- **off** -- no shading rate image, the current behaviour.
- **fixed** -- centred on the render target, which is where the eye's optical
  axis lands under the recentred symmetric projection.
- **reticle** -- centred on the aim point, per eye, falling back to the fixed
  centre whenever the aim point is stale, absent or off-screen.

`paint_foveation_image` needs nothing new for it: the centre is already a
parameter, and the test drives an off-centre aim point and an out-of-range one.
The out-of-range case matters more than it sounds -- an aim point behind the
player, or a stale one from before a teleport, would otherwise make the whole
eye coarse, which is the worst-looking failure this feature has.

What it does need is the number reaching the producer, which is the only new
plumbing: the viewer has it and the producer sets the rate. That is a shared
state channel like the ones already carrying controller state and eye surfaces,
and it should carry a validity flag and a timestamp so the producer can fall
back rather than aim at a stale point.

## How it gets measured

The Hub, with the existing evidence tooling, at a pinned extent -- the same
discipline as every other performance comparison here: an extent that moved
between runs makes the numbers mean nothing.

- GPU frame time from `src/producer/ngx_gpu_timing.cpp` and the
  `XR-FRAME-STAGE-TIMING` counters, not from a frame rate that the compositor
  is free to cap.
- Off, then on at each zone setting, in one session, so driver and clock state
  are shared.
- Judge the image worn, not from a readback: the failure mode is a boundary
  that swims during a head turn, which a still frame cannot show.

The honest expectation is a saving in the tens of percent of *shading* cost,
which is not the same as tens of percent of frame time -- the Hub is not
necessarily shading-bound, and if it is not, this buys little there and more in
a mission. That is a reason to measure in both, not a reason to skip it.

## What is not worth doing

- **OpenXR foveation extensions.** They apply to swapchains the application
  renders into. Ours are copy destinations.
- **Porting anything for foveated encoding.** It is a streamer setting on both
  Virtual Desktop and the Frame. Worth turning on and comparing; not worth
  writing.
- **Tier 1 VRS.** One rate per draw cannot express a foveal region.

## Sources

- D3D12 variable rate shading, tiers, shading rate images and combiners:
  <https://microsoft.github.io/DirectX-Specs/d3d/VariableRateShading.html>
- Capability figures above: this machine, `darktidevr-xr-harness --no-openxr`,
  18 September 2026.
