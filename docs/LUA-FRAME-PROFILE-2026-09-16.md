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

## Method notes

- A section returns up to four values and allocates nothing; off, it is one
  branch and a tail call, so the wrapper itself is not in the numbers.
- Each report is a fresh five-second window, so a change shows in the next
  window rather than being averaged away.
- `mod_ms_per_frame` divides by *input* frames; the draw and render sections
  run once per rendered frame, which in these runs is the same rate.
