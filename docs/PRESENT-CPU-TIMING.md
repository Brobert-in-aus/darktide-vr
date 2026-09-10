# Presentation-thread CPU timing

The 144 Hz comparison identified a thread using about 98% of one logical core
in both FG modes. That thread appears in the same process's presentation
records. Lua render calls were typically below 0.15 ms, so the next diagnostic
separates time inside the presentation hook from time between hook entries.

`PresentCpuProfile` is enabled only by an explicit `[probe] enabled=1` file
beside the native DLL. After 600 calls in one nonzero gameplay generation it
records at most 240 samples across all threads. A generation change restarts
warm-up. QPC supplies wall time; `GetThreadTimes` supplies current-thread CPU
time. The latter's 100 ns units do not guarantee per-frame measurement
precision, so compare aggregate windows rather than treating a single CPU
sample as exact. No GPU timestamp submissions or waits are introduced.

Each record includes the begin-to-begin frame interval and the current hook's
entry-to-exit interval, both in wall and CPU time. Comparing their means is an
approximate inside/outside split: the intervals differ by one presentation at
the window boundaries. The scope includes the full outer hook, including
native calls it makes. It does not identify individual engine functions.

The runner's `-PresentCpuProfile` flag backs up/restores the diagnostic flag,
copies only the launched process's log and requires 240 records. The profiler
preserves the caller's Windows error state. Tests cover disabled behavior,
generation resets, concurrent admission, unique samples and error-state
preservation. Both tests pass; Release compilation passes. The focused cherry
pick required resolving only the include-list context from the newer checkout.

The focused candidate is `7c316ed`, DLL SHA-256
`e87b739108c1e4a24de23d3a142eca506c5abaf8e12d25150c706bab30a8727b`.
The first diagnostic uses the stationary Malice mission workload, 120 Hz,
FG off and Unlimited. Its frame rate is diagnostic output rather than a new
uninstrumented control.

The 240-record mission capture completed on one thread and generation. Mean
frame interval was 13.343 ms wall / 12.891 ms CPU; mean full presentation hook
was 0.479 ms wall / 0.260 ms CPU. Frame wall p95 was 14.985 ms and presentation
wall p95 0.804 ms. CPU records were visibly quantized in 15.625 ms steps,
confirming that per-frame CPU percentiles are not useful here. Aggregate data
places most CPU time between presentation entries, not inside the hook.

The diagnostic delivered 75.13 native pairs/s over 20.76 analyzed seconds,
with no generated frames or pose mismatches. All 240 records were preserved,
shutdown was clean and exact restoration passed. Further profiling must
distinguish game update, render preparation and driver command recording;
this measurement does not assign the remaining time to any one of them.
