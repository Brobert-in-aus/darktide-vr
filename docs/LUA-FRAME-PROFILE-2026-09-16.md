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

## Step 2: read less (`hub-haptics2`)

Same conditions. Means across all 18 windows of each run:

| | mod ms/frame | haptics µs/frame | haptics max µs, median | worst |
| --- | ---: | ---: | ---: | ---: |
| baseline | 0.1473 | 58.7 | 190 | 515 |
| step 1, no closures | 0.1411 | 54.5 | 176 | 280 |
| step 2, fewer reads | 0.1407 | 54.1 | 145 | 247 |

Step 2 moved the mean by 0.4 µs, which is noise. The spikes kept falling,
which is worth having, but the nine reads it removed were cheap Lua table
lookups, so the "engine reads at one to two microseconds each" model was
wrong as well. Two models wrong in a row is the signal to stop modelling and
measure inside `sample`: the profiler nests, so the next run carries
sub-sections for the body read, the gauges, the melee and interaction reads,
each of the five event comparisons, and the ammo step.

## Step 3: pcall only where a read can throw (`hub-haptics3`, `hub-haptics4`)

The stock read proxy's `__index` does `config[field].type`, so an undeclared
field throws, while `read_component` returns nil for an unknown name. Of the
fields the sample reads only the two weapon-slot ones are outside the static
config, so only those keep an index guard (the lock now has a slot proxy that
throws on them). The other seventeen pcalls went. Measured with nesting on:
60.5 to 59.6 us. About one microsecond. The third wrong model in a row.

But the nested run (`hub-haptics4`, report cut raised so nothing falls off)
finally says where the time is:

| sub-section | us/frame |
| --- | ---: |
| haptics.read_body | 14.0 |
| haptics.read_melee | 3.3 |
| haptics.body_events | 2.7 |
| haptics.gauge_events | 2.5 |
| haptics.read_interaction | 1.9 |
| haptics.melee_events | 1.3 |
| haptics.interaction_events | 1.0 |
| haptics.read_gauges | 0.9 |
| sum | 27.4 |
| input.haptics | 59.6 |

Three things follow. `read_gauges` wraps a single `read_component` and costs
0.9 us with the section overhead, so a component read is about 0.4 us, and
DMF's `mod:get` is two table lookups: neither is the cost. `read_body` at 14 us
is therefore mostly its five stock extension method calls (`current_health`,
`max_health`, `current_toughness_percent`, `remaining_ability_charges` twice),
about two microseconds each: real work in stock code, not plumbing. And about
20 us sit outside every sub-section, in code that does almost nothing, while
the spike profile fell every time an allocation went. That is the shape of
the incremental garbage collector being charged to whoever allocates: `sample`
still builds six tables a frame (body, gauges, the melee reading, the
interaction, and four event lists that are almost always empty). Step 4 is to
stop allocating them: double-buffer the four readings against their
`previous`, and return a shared empty list when there are no events.

## Step 4: no allocation per frame (`hub-haptics5`)

Same conditions, nested: 59.6 to 56.1 us. The sub-sections sum barely moved
(27.4 to 26.2) and, this time, **the spikes did not fall** (median 197 to
203, worst 313 to 338). About 30 us still sit outside every sub-section, in
code that should cost a few microseconds. Four models in a row have been off
by the same shape, which is itself the evidence: work that should be cheap
costing five to ten times more is what an interpreted function looks like.
LuaJIT compiles a function only if a trace through it completes; anything in
it the JIT does not implement aborts the trace, and after enough aborts the
function is blacklisted and runs interpreted for good. Nothing so far has
asked the JIT what it did with `sample`. It can be asked: `jit.attach` reports
every trace start and abort with the reason and the source line. That is the
next measurement, and it may apply to every per-frame function in the mod,
not just this one.

## The answer: the game runs with the JIT off

`scripts/boot_init.lua`, line 4, in the stock game: `jit.off()`. Every Lua
function in Darktide, the mod's included, runs in the LuaJIT interpreter. That
is why four models in a row were wrong by the same factor: a body of a few
hundred bytecodes that would compile to a few microseconds costs thirty
interpreted, and closures, pcalls, read counts and tables were never the lever
because none of them is the interpreter's per-bytecode cost.

What follows for every Lua path in this mod:

- **Cost is bytecodes executed per frame.** The only real reductions are doing
  less per frame: sampling things that change slowly at a lower rate, early
  exits before any work, and hoisting anything invariant out of the per-frame
  path. Micro-structure (allocation, pcall, table shape) is second order, as
  the four steps above showed: about 8 us of 59 between them, though the
  spike reduction from removing allocation was real.
- **`jit.on(func)` re-enables compilation for one function even when the JIT
  is globally off.** If the mod can reach the `jit` table, its own hot
  per-frame functions could be compiled while the game's stay interpreted,
  which would be a large multiple on every measured section. That is not a
  change to make quietly: Fatshark turned the JIT off deliberately, and the
  reason (stability, determinism, or a specific fault) decides whether opting
  our functions back in is safe. Build it behind a flag, measure it in the
  Hub, and put the numbers and the risk to the user.

### The mod can reach the JIT (`hub-jitprobe1`)

`jit global=true mods_lua=false require=true status=false version=LuaJIT
2.1.1771479498`: the global `jit` table is visible to the mod, `require("jit")`
works, and `jit.status()` is false, so the compiler is off in the mod's
environment as in the game's. One implementation detail decides the shape of
any experiment: with the JIT globally off LuaJIT installs no hot-counting in
its dispatch table at all, so `jit.on(func)` for one function has no effect;
the only switch that compiles anything is `jit.on()` for the whole state,
which compiles the game's Lua as well. That is exactly what Fatshark avoided,
for a reason `boot_init.lua` does not state. So: a flag, an unattended Hub
run with the profiler, the numbers and the error count, and the decision is
the user's. Never on by default.

## The heavy paths, measured (`hub-wide1`)

With the post-animation body pass, the HUD panel draw, the marker-world
widget replay, the input-manager hook and the stereo UI sync wrapped as well,
the mod's Lua in the Hub is **0.30 ms per input frame**, about 2.7 % of the
90 Hz budget (the earlier 0.15 was the samplers only). The order of cost:

| Section | µs/frame | note |
| --- | ---: | --- |
| input.manager_update | 63.7 | the `InputManager.update` hook: input-service scan and the menu input probe, every gameplay frame |
| input.haptics | 59.9 | on in the saved settings |
| render.marker_widget | 41.2 | the HUD widget replay onto the stereo panel, once a frame here |
| render.hud_panel | 17.2 | |
| input.two_hand | 13.2 | |
| input.communication | 11.2 | |
| draw.ammo_readout | 8.2 | |
| post.body_ik | 2.5 | the body pass is cheap in tracked-hands mode |
| everything else | < 7 each | |

`render.ui_stereo_sync` did not run in this context. About 7 us of the total
is the profiler's own per-section overhead at 33 sections.

The next target is the input-manager hook: a menu input scan during gameplay,
every frame, is work that could run far less often or not at all while no
menu is up, and it is the one place a reduction of tens of microseconds is
available without touching what the player feels.

## The first real win: a failed file open per frame (`hub-wide2`)

`presentation.scan_input_services`, in the `InputManager.update` hook, tried
to open `darktidevr_input_inventory.flag` on every update; the flag arms a dev
diagnostic, and with no file present, which is every player, that was a
failed `CreateFile` on the main thread each frame. The menu input probe did
the same every 15 updates. Both poll every 300 updates now; nothing in the
tools or tests waits on them faster.

| | before | after |
| --- | ---: | ---: |
| input.manager_update, µs/frame | 63.7 | 3.8 |
| mod Lua, ms/frame | 0.299 | 0.183 |

Sixty microseconds a frame for every player, from a diagnostic nobody had
enabled, and it is gone without touching anything the player feels. The
haptics rewrites, by comparison, bought eight. This is the lesson of the day
in one row: under an interpreter, look for work that should not be happening
at all before making work that should be happening cheaper.

The same pattern, milder, is in eleven modules that poll a test flag every
120 calls: a failed open every two seconds each, which is the shape of their
spikes. Raised to 300 as well.

## The sampler gates (`hub-gates2`)

Three exact reductions: `physical_hold` returns before walking the controls
when no button is held; two-hand's `live()` looks up fixed keys instead of
concatenating three strings a frame; and its `snapshot` asks whether a gun is
wielded before the tracking, online-rule and state-machine gates, which are
pure, so the order does not change the answer.

| section, µs/frame | wide2 | gates2 |
| --- | ---: | ---: |
| input.two_hand | 11.8 | 7.6 |
| input.communication | 10.0 | 8.9 |
| mod total, ms/frame | 0.183 | 0.245 |

The total went up, and the table says why if read whole: `render.marker_widget`
was absent in wide2 and is 41 µs a frame in gates2, because an interaction
marker was in view this time; take it out and the runs are 0.183 against
0.204, and the rest of that gap is the whole run being about a tenth slower
(275 frames a report against 286; every untouched section is 10 to 20 per
cent dearer). The gates' five microseconds is real and inside that noise;
they stay because they are exact. The lesson for reading these tables: the
run-to-run noise is about a tenth, so only changes larger than that, or
sections that appear and vanish, mean anything without a same-run control.

The marker replay, 27 µs per widget per frame whenever a marker is in view,
which in the Hub is most of the time, is the largest situational cost now
and the next target.

## The marker replay (`hub-marker1`): a wrong guess, two findings, one bug

The guess: the atlas replayed every recorded material value of a marker, a
pcall into Material.set_* each, on every primitive of every frame, so a
revision-keyed skip should take a good part of the widget's 27 us. Measured,
the replay is one microsecond and stops after three reports (the skip works
and there was nothing worth skipping). It stays because it is exact and
tested, but it bought nothing.

The findings, from sectioning inside the module rather than around it:

| per marker, us/frame | marker1 |
| --- | ---: |
| render.marker_widget (the routed draw) | 39 |
| of which marker.atlas_call (the stock draw itself, on the atlas) | 24 |
| render.marker_scope (the scope builder, never timed before) | 21 |

So a marker in view costs about 60 us a frame, more than half of it the
stock widget drawing itself into the atlas, which is the game's cost to
draw a marker at all; and hub-marker1 had two in view for most of its run
(552 widget draws per 276 frames against gates2's mix of one and two),
which is why it looked dearer than gates2 before reading the calls column.
The rest of the scope builder's 21 was the head's centre, axes and pixel
tangent recomputed for every marker, and a closure built per call; those
are now computed once per frame and phase and shared, and named.

The bug: the report's total summed every section, nested ones included, so
a sub-section counted twice. Every total with the haptics sub-sections in
it was inflated by about 26 us, and marker1's 0.355 by the marker
sub-sections too. Sections carry a depth now; nested ones keep their rows
and leave the total. Totals from hub-marker2 on are comparable with each
other; earlier ones are comparable with each other only after subtracting
their nested rows.

What would actually shrink a marker's cost is drawing its content into the
atlas every other frame (the quad tracks the head every frame regardless;
the atlas already tolerates cells 100 ms old). That halves the 60, but a
fill or a count would update at half the frame rate, which a player can in
principle see, so it is a change for the user to choose, not one to make
unattended.

## `hub-marker2`: the first comparable total

No marker was in view after the warm-up report, so the shared head frame is
unmeasured in the field (exact by construction; the plane maths is covered
by the suite). What the run gives instead is the first total with the
nesting fixed: 0.156 to 0.166 ms a frame with no marker in view, no errors,
which agrees with wide2's 0.183 less its 26 us of double-counted haptics
sub-sections. That is the baseline to compare against from here: about
0.16 ms of interpreted Lua a frame, 1.5 per cent of an 11 ms frame, with
haptics 58 us of it and the rest spread thin. The three levers left are all
the user's to pull: the JIT switch (the patch), the marker draw cadence, and
a lower body-read rate for haptics.

## Where the Hub's frame actually goes (`hub-noviewer1`)

The user asked for rendering performance, into the engine if need be. The
first measurement answers a question none of the Lua work could: with the
viewer, the capture consumer and Virtual Desktop's encoder out of the way
(`-NoViewer`; the mod still renders both eyes into the same 2112x2304
targets), the Hub's game loop runs at about **118 Hz** (590 frames a
5-second report) against **55 Hz** with them (276). And the mod's own Lua
per frame halves as well, 0.16 to 0.067 ms, the same code: that is the
signature of the game's threads getting half the CPU they get alone.

| Hub, 1280x768 window, 2112x2304 per eye | with viewer | no viewer |
| --- | ---: | ---: |
| game loop, Hz | 55 | 118 |
| mod Lua, ms/frame | 0.16 | 0.067 |

So the engine renders the Hub in stereo at 118 Hz on this machine; the
pipeline after it (the viewer process at 120 Hz with reprojection, the
d3d12 capture handoff, the Virtual Desktop streamer's encoder, all on the
same eight cores and one GPU) is where the other half of the frame goes.
Which of the three, and whether it is CPU contention or GPU contention, is
the next measurement: the same run with the CPU render timing and the
native GPU eye profile armed, with and without the viewer.

## The frame is GPU time under contention (`hub-render1`)

The same Hub run with the CPU render timing, the native GPU eye profile and
the frame profiler all armed, through the viewer:

| Hub, viewer running | per pair |
| --- | ---: |
| main-thread render calls (left + right + wrapper) | 0.19 ms |
| GPU, left eye | 11.9 ms avg (p50 8.9, p95 18.9) |
| GPU, right eye | 11.7 ms avg (p50 13.9, p95 17.0) |
| GPU, both eyes | 23.5 ms |
| game loop | 54 Hz |
| fresh pairs at the viewer | 27.5/s |

Nothing on the CPU side of the engine blocks: the render calls are two
tenths of a millisecond. The GPU spends 23.5 ms on the two eyes, which is
the 54 Hz loop; and the same targets ran at 118 Hz with no viewer, so the
eye's GPU time at least triples when the viewer's reprojection at 111
submissions a second and Virtual Desktop's encoder share the GPU. Hardware
GPU scheduling is off on this machine, so the engines are time-sliced by
the OS scheduler and priority. That is where the Hub's frame goes: not the
engine's second eye, not the mod's Lua, but the pipeline's GPU work
interleaved with the game's.

`Application.get_frame_times` is nil in retail; the engine offers no frame
time of its own to Lua.

The control (`hub-render-noviewer1`, the same flags, no viewer): the loop
runs at 130 to 145 Hz, 700 frames a report, so both eyes together take at
most about 7 ms of GPU. The per-eye timestamps need the capture path, which
is idle without a viewer, so the loop rate is the measurement there. With
the viewer, 23.5 ms: the contention triples the game's GPU time.

The lever this suggests, and the one nothing in the repository has tried:
the OS schedules GPU work by queue priority when hardware scheduling is
off, and every queue the game creates is at normal priority, the same as
the runtime's compositing and the streamer's encoder. Asking for the game's
queues at high priority is one hook on the device's `CreateCommandQueue`
in the proxy, flag-gated (`darktidevr_queue_priority.flag`), and its effect
is read off the same eye spans.

## Queue priority: no effect (`hub-queue1`)

Built, deployed and measured: with `darktidevr_queue_priority.flag` the
proxy asked for every game queue at high priority (six raised, none
refused, no errors) and the eye spans did not move.

| Hub, viewer running | normal priority (render1) | high (queue1) |
| --- | ---: | ---: |
| GPU left / right, ms | 11.9 / 11.7 | 11.5 / 12.1 |
| GPU per pair, ms | 23.5 | 23.6 |
| game loop, Hz | 54 | 56 |

So D3D12 queue priority is not what arbitrates between the game and the
other processes on this machine with hardware GPU scheduling off; the
lever is closed. The flag stays, default off and harmless, for a retry if
hardware scheduling is ever turned on (which changes the arbitration, and
which the 11 September handoff believed frame generation required, though
today's engine log reports it off and frame generation delivering).

What is left is the pipeline's own work: the runtime's per-vsync
compositing of what the viewer submits and the streamer's encoder, both
proportional to submissions per second and pixels per submission. The
viewer's submission shape is already lean: in gameplay it hands the runtime
two layers, the projection and the reticle quad (the pointer quads are
menus only, the vignette ADS only), so there is nothing to strip there
worth a build. The levers are the user's settings, in order of expected
return: the headset refresh (120 to 90 Hz takes a quarter off both the
compositing and the encoder, and the game delivers 32 fresh pairs a second
either way), the resolution one step down (already measured on 11
September at 15 to 23 per cent shorter spans), the codec (H.264+ about 10
per cent), and hardware GPU scheduling on, which changes how the three GPU
clients are arbitrated and is the one arm nobody has run. The engine side
of the frame is measured and is not the problem.

## Frame generation under contention: not a lever either

The NGX timing log of `hub-queue1` (viewer running, 90 reports): the
frame-generation evaluation is **1.39 ms left, 1.31 ms right** per pair,
2.7 ms of the 23.5, and not stretched by the contention (the simulator
measured 1.8; the 11 September handoff saw the same). It returns about
fifty generated frames a second for that. Turning it off would give back
under twelve per cent of the pair and lose half the displayed frames, so
it stays; the runtime toggle the mod has for it goes through the user
settings and was not used.

## Experiments for the user, with the same instruments

Every arm below changes a setting the brief keeps out of unattended hands,
so they are yours; the instruments are the day's and give one comparable
table. Each arm is one Hub launch with the headset streaming:

```
tools/unattended/run-darktide-session.ps1 -Scene Hub -HoldSeconds 100 -End Quit -SyntheticControllerPath -RequestFiles @{'darktidevr_frame_profile.flag'='enabled'; 'darktidevr_cpu_render_timing.flag'='enabled'; 'darktidevr_performance_profile.flag'='enabled'} -OutputDirectory artifacts/unattended/profile-<date>/<arm>
```

Read three numbers from `console.log`: the last `DARKTIDEVR_GPU_PERF`
line's `left_avg_ms`/`right_avg_ms` (the contended eye spans; 11.9/11.7
today), the `frames=` of the `DARKTIDEVR_FRAME_PROFILE report=` lines
divided by five (the loop rate; 54 today), and `fresh_pair_fps` at the end
of `viewer.log` (32 today). The contention stretches the game's GPU work
about 3.3 times (7 to 23.5 ms), so a millisecond saved in the engine is
worth three on the headset, and an arm that shortens the pipeline's own
work shows in all three numbers at once.

1. Headset refresh 90 Hz in Virtual Desktop (the compositing and the
   encoder both run per vsync; the game makes 32 fresh pairs a second at
   either rate).
2. Hardware GPU scheduling on (Windows graphics settings, reboot). Today's
   engine log reports it off. It changes how the three GPU clients are
   arbitrated, and it is the one arm nobody has run; with it on,
   `darktidevr_queue_priority.flag` is worth one more launch.
3. The VR render-settings profile, `tools/stereo/set-vr-render-settings.ps1`
   (ambient occlusion, GI, SSR, sun and local shadows, decals, volumetrics
   off; texture quality low; LOD and scatter reduced). It cuts the engine's
   own GPU work, which the stretch multiplies; it has never been measured
   before and after, and it is a visual-quality decision.
4. Resolution one step down and H.264+, both measured on 11 September
   (15 to 23 per cent and about 10 per cent), as the reference arms.

## Where the day ended

| the mod's Lua, per frame | 0.30 ms morning, 0.16 ms now |
| --- | --- |
| the engine's two eyes, alone | at most 7 ms of GPU, 118 to 145 Hz |
| the same two eyes with the headset pipeline | 23.5 ms of GPU, 54 Hz |
| queue priority | tried, no effect |

The mod's own cost was never the Hub's problem, and the day's Lua work was
worth doing anyway for the sixty microseconds that should not have been
there. The Hub's frame is the headset pipeline sharing the GPU with the
game. That is measured now, three ways, and the levers that remain are the
user's to pull.

## Method notes

- A section returns up to four values and allocates nothing; off, it is one
  branch and a tail call, so the wrapper itself is not in the numbers.
- Each report is a fresh five-second window, so a change shows in the next
  window rather than being averaged away.
- `mod_ms_per_frame` divides by *input* frames; the draw and render sections
  run once per rendered frame, which in these runs is the same rate.
