# Lua frame profile: the mod's own per-frame cost (16 September 2026)

Every earlier performance pass in this repository is native or GPU side. The
mod's own Lua, run on the main thread every input frame and every draw, had
never been timed; the 16 September session added seven per-frame samplers to
it. `darktidevr_frame_profile.lua` (opt-in, `darktidevr_frame_profile.flag`)
times named sections with the native module's QueryPerformanceCounter and logs
the top sections every five seconds. Note the first attempt used
`Application.time_since_launch`, which is frame-quantised and reported every
section as exactly zero; the unit test could not have caught that.

The user named the Hub as the least performant zone and the real VDXR to
Virtual Desktop pipeline as the one to measure on. All runs below are the
unattended Hub session on that pipeline, synthetic controller path, 90 s hold,
QPC at 10 MHz, about 56 input frames per second.

## Baseline: the user's own settings (`hub-defaults2`)

The run carries the user's saved settings, as every unattended run does: the
day's new options are all off (they default off), and `vr_haptics_mode` is
`informative`, so haptics is on. Stable across 18 five-second windows: **0.143 to 0.155 ms per input
frame**, 21 sections. Against an 11.1 ms budget at 90 Hz that is about 1.3 %,
so these paths are not the Hub's frame-time problem. Last window:

| Section | ms/frame | mean µs | max µs |
| --- | ---: | ---: | ---: |
| input.haptics | 0.0566 | 56.6 | 114.6 |
| input.two_hand | 0.0121 | 12.1 | 25.4 |
| input.communication | 0.0113 | 11.3 | 19.4 |
| draw.ammo_readout | 0.0081 | 8.1 | 28.5 |
| input.sight_ads | 0.0068 | 6.8 | 76.4 |
| render.crosshair_feedback | 0.0068 | 6.8 | 13.7 |
| input.bindings | 0.0059 | 5.9 | 18.1 |
| input.holsters | 0.0056 | 5.6 | 95.9 |
| draw.forearm_holsters | 0.0041 | 4.1 | 8.9 |
| draw.gun_aim | 0.0040 | 4.0 | 33.5 |
| input.comms_gesture | 0.0034 | 3.4 | 31.3 |
| render.weapon_charge | 0.0030 | 3.0 | 43.4 |

Nine more sections sit below 3 µs each.

## What the baseline says

- **Haptics is 38 % of the total, and it is on** (`informative` in the saved
  settings; I first wrote "with its option off", which was an assumption and
  wrong). Its `sample` allocates, every frame, about ten closures for pcall'd
  component reads, six tables (gauges, the melee reading, the interaction, the
  ammo state, and the event lists), and an empty table for a missing keyword
  list. 57 µs is the cost of that allocation and call overhead, not of the
  reads themselves. The one clear target, and a behaviour-preserving one.
- **The maxima are spiky where the means are small**: holsters 96 µs against a
  6 µs mean, sight ADS 76 against 7, weapon charge 43 against 3, comms 31
  against 3. Several of today's modules poll their test flag by opening a file
  every 120 calls, on the main thread; at 56 Hz that is a synchronous file open
  every two seconds per module. That is the likely shape of those spikes, and
  it is cost the day added.
- **What is not measured yet.** The wrapped set is the input samplers, the hand
  displays and the two render-path draws. The post-animation body pass
  (`apply_body_ik`), the stereo and camera update, the HUD panel and the marker
  world are not wrapped, and are where the larger Lua cost is likely to be.
  Widening coverage comes before optimising the small things above.

## Step 1: haptics without per-frame closures (`hub-haptics1`)

Same Hub conditions. Across 18 windows, `input.haptics` went from
56.3-61.6 us a frame (baseline) to 51.6-57.2 (after): about 5 us, 7 % of the
section, and the whole wrapped set from about 0.147 to 0.141 ms a frame. The
spikes fell more than the mean: baseline maxima reached 390, 433 and 515 us;
after, 280 at most. That is consistent with less garbage-collector pressure,
which is what removing a dozen allocations a frame would do.

So the closures were real but never the main cost. What remains, about 54 us,
is the *number of engine reads*: each frame `sample` makes roughly 35 to 40
calls into the stock unit data (`read_component`), the extension registry
(`has_extension`, five of them, for extensions that do not change while the
unit lives), the weapon template (fetched and its keyword list scanned every
frame to learn whether it is melee), and the ammo readout. Several reads are
duplicated within the frame: `block` twice, `action_module_charge` twice,
`inventory` twice. At one to two microseconds a call that is the whole figure.

Step 2 is therefore to read less, not to allocate less: cache the extensions
per unit, read each component once a frame, and recompute the template's
melee flag only when the template changes. None of that changes what is read
or when a pulse fires, so the same lock applies.

## Method notes

- A section returns up to four values and allocates nothing; off, it is one
  branch and a tail call, so the wrapper itself is not in the numbers.
- Each report is a fresh five-second window, so a change shows in the next
  window rather than being averaged away.
- `mod_ms_per_frame` divides by *input* frames; the draw and render sections
  run once per rendered frame, which in these runs is the same rate.
