# D3D12 dispatch job layout

The thread-residency experiment identifies the wait after parallel command
dispatch as the dominant observed active-wait site. Further read-only inspection
uses the same exact engine SHA-256 as the residency report.

Worker initialization at primary RVA `27e750` reads `max_worker_threads`, caps
it by a CPU-derived budget and clamps it to 0–12. The configured value is not
the effective worker count. The similarly named `cpu_dispatcher_threads` is
read from PhysX configuration at `2840e0`; it is not the D3D12 dispatcher control.

At `7aa1c0`, the dispatcher derives a nominal chunk count from its pool count
plus the assisting caller and a minimum batch size of 64. A weighted path is
gated by more than 4,000 commands and an enabled field. That path accumulates
per-category estimated costs toward a budget based on historical totals.
This is evidence that weighted splitting already exists, not a missing feature
to add blindly. State transfer and command-list ordering still impose dependencies.

## Live layout observation

`capture-thread-residency.ps1 -ObserveDispatchLayout` reads a small set of
existing fields only when the sampled instruction and two return slots identify
the verified nested wait after dispatcher call `7ac4a5`. The wrapper requires
the known engine hash. The frame/register relationships were checked against
the exact function prologs and call site; no engine memory is written.

The 1,000-sample mission capture produced 90 valid observations at that location:

| Field | Observation |
| --- | --- |
| Pool worker count | 6 in all 90 observations |
| Commands in current batch | 4,673–5,716 |
| Weighted-input command count | Same range as current batch |
| Weighted splitting enabled | 1 in all 90 observations |
| Historical command count | 10,128–11,282 |
| Historical aggregate cost, raw engine units | 19.333–34.1147 |

These use a configured worker value of 13, accepted Lua, the focused Present
CPU DLL, DLSS Quality, FG off and the 120 Hz simulator. The observed command
counts exceed the weighted-path threshold. The earlier 8-versus-13 setting
comparison cannot be assumed to have changed the effective pool; a value below
six is the next meaningful control. No new default is selected from residency.

Mean debugger pause was 50.79 microseconds and maximum 295.5 microseconds.
The capture is diagnostic, not uninstrumented throughput evidence. Native build,
self-test, wrapper parsing and reader checks pass. Exact restoration passed.
Evidence: `synthetic-solo-dispatch-layout-a-20260910` in ignored artifacts.
