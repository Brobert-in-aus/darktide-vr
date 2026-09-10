# CPU render timing without GPU timestamp submissions

The native-only mission-start trial averaged 72.85 FPS with 61% GPU busy time.
The existing performance flag also enables GPU timestamp command submissions,
so it changes the workload when only CPU render-call timing is needed.

The optional `darktidevr_cpu_render_timing.flag` enables the existing QPC-based
Lua timings without enabling that GPU profiler. It retains the existing
240-sample batches, means, medians, p95 and maxima. These are wall-clock CPU
call durations: they can include waits and are not isolated CPU execution time
or GPU duration. The flag is read once, bounded to 32 bytes and disabled by
default. Existing full profiling retains its behavior.

The simulator runner accepts `-CpuRenderTimingSourcePath` with an exact installed
Lua hash, deploys the focused main chunk and its census module dependency,
disables the census flag, compiles the installed package with pinned LuaJIT and
restores all files and flags exactly. The selected console must report CPU
timing on, GPU profiling off, and at least one complete timing batch. GPU timing
records cause the CPU-only evidence check to fail.

Main and focused LuaJIT gates pass (70 and 50 chunks respectively); the trial
package gate passes with 51 installed chunks. The focused source is `c0b64ba`
on the startup-census baseline. The 30-second diagnostic uses the original
native benchmark DLL `B052535...` to isolate the profiling change. Its FPS is
diagnostic output, not a new uninstrumented control.

The completed mission diagnostic produced six 240-sample gameplay batches.
Left means ranged 0.034–0.097 ms, right means were 0.003 ms, and pair means
0.044–0.144 ms. Pair p95 ranged 0.054–0.129 ms; one maximum reached 13.628 ms.
The timings bracket the Lua render calls and work between them, ending before
the post-right-eye capture handling. They do not encompass the whole engine
frame, render-worker work or GPU execution. Lua native-sync waits are disabled
in this source. These small typical durations do not locate the engine's
remaining bottleneck.

The diagnostic delivered 72.73 native pairs/s over 21.45 analyzed seconds.
CPU timing was enabled with GPU profiling disabled, fresh stereo initialization
and shared readiness were present, and clean shutdown and exact restoration
passed. The uninstrumented mission control was 72.85 pairs/s; a single short
comparison is not sufficient to quantify instrumentation overhead.
