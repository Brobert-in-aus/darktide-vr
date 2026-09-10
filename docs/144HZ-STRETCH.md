# 144 Hz simulator stretch comparison

120 FPS remains the core performance target. At the user's request, this
comparison follows the 120 Hz mission trials and the diagnostic fixes. It uses
a process-local 144 Hz simulator clock; it does not establish that a physical
Quest or its current runtime exposes that experimental mode.

The runtime extension preserves the 90 Hz default and 120 Hz option. Its
144-frame smoke test rendered every frame in 994.218 ms, with a clean session
exit and pass result. The benchmark also checks the reported display period
against 6.944 ms before launching the game. DLL identity is `3C3F41C...`.

The mission comparison uses cm_archives, difficulty 3, a stationary starting
position, 2112x2304 eyes, DLSS Quality and focused native `FB244186...`.
Both FG on and off use Unlimited; verified stock cap choices stop at 120.
Selecting the existing cap 72 with FG would target about 36 originals/s and
would not implement 72 native plus FG. No unsupported cap mapping is invented.

Original, generated, distinct and repeated delivery are counted separately.
GPU telemetry covers the workload interval after ten seconds of warm-up.
An additional read-only, 50-second per-thread CPU observation is recorded
during the FG trial to guide subsequent engine investigation. It is not a CPU
stack trace and cannot identify a function or assign a thread's engine role.
All installed trial files and settings are restored after each run.

The 120-second FG-on trial delivered 141.85 distinct pairs/s over 109.21
analyzed seconds, with 2.097 cached repeats/s. It published 73.70 originals
and 73.70 generated pairs/s, selecting about 70.92 of each. Board telemetry
averaged 92.92% busy time and 331.67 W over 110 seconds with complete coverage.
There were no pose mismatches; clean shutdown and exact restoration passed.
This approaches 144 FPS but has more repeats and less headroom than cap-120 FG.

The 49.63-second CPU observation measured about 4.84 logical-core equivalents
across the process. One thread consumed 98.38% of one core; the same thread ID
appears in this process's `PRESENT_BEGIN` and `NATIVE_PRESENT_BEGIN` records.
That ties the busy thread to presentation calls, not to a specific expensive
function. OS thread descriptions were unavailable. A stack attribution or
in-process timing measurement is still needed before changing engine behavior.

The matching FG-off trial delivered 74.00 original pairs/s over 110.27 analyzed
seconds, with no generated frames, repeats or pose mismatches. Its 110-second
board window averaged 62.15% GPU busy time and 269.25 W, with complete coverage.
Clean shutdown and exact restoration passed. Its 49.70-second CPU observation
measured 4.49 logical-core equivalents, with the presentation-record thread at
98.18% of one core. These are single trials in the mission starting area.

The stretch comparison is complete. Retain 120 FPS as the main target and
continue investigating the presentation thread's CPU work. Physical 144 Hz
availability, combat performance and worn visual acceptance remain untested.
