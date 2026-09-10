# Render API CPU timing

The optional Present CPU flag also enables a bounded observation of selected
existing D3D12 hooks on the first Present caller's thread. After 600 calls in a
stable nonzero generation, 240 intervals between Present calls are collected
in memory and written once to a PID-specific log. Generation changes discard
partial windows. Other threads and work inside Present are excluded.

Categories are draw/indirect, dispatch, barriers, pipeline selection, selected
root bindings and queue execution. A nested selected call is attributed only to
the outermost category, preventing double counting. Durations include the
original graphics API and driver, plus hook work and timer overhead. They are
wall-clock intervals, not isolated CPU execution or mod overhead.

The diagnostic does not install additional hooks or enable the general render
trace. Consequently, zero counts may mean an inactive hook and must not be read
as no draws, dispatches or bindings. Unobserved API paths, worker-thread work and
engine work remain outside coverage. The first Present caller owns the log;
compare its header thread with the corresponding Present CPU log.

The runner's `-RenderApiCpuProfile` enables the existing Present CPU flag,
preserves both PID logs and requires all 1,440 category rows (240 frames times
six categories). Exact installation/settings restoration remains mandatory.

Windows x64 Release main and focused builds pass. Tests `render_api_cpu_off`
and `render_api_cpu_on` pass 2/2 in both builds, checking disabled behavior,
generation-reset warm-up, bounded completion, nested accounting, foreign-thread
exclusion and preservation of the caller's Windows error state. The runner
parses successfully. No GPU timestamps or waits are added.

## Mission evidence

The clean repeat used the focused DLL, DLSS Quality, FG off, unlimited cap,
13 workers and the 120 Hz simulator at SoloPlay `cm_archives` mission start.
All 240 frames were recorded on the matching Present thread:

| Observed category | Mean calls/frame | Mean wall ms/frame |
| --- | ---: | ---: |
| Draw/indirect | 17.32 | 0.006 |
| Barriers | 48.55 | 0.120 |
| Pipeline selection | 390.11 | 0.150 |
| Queue execution | 21.02 | 0.475 |
| Total observed outermost scopes | | 0.751 |

Dispatch and binding counts were zero; those hooks are conditional in this
production configuration, so these categories provide no coverage evidence.
Present CPU samples averaged 13.643 ms frame wall time, 13.411 ms thread CPU,
and 0.502 ms Present wall time. CPU values are quantized by Windows accounting.
These averages are diagnostic windows, not a partition of the full benchmark.

The first capture measured 0.730 ms in the same categories; a build occurred
during that launch, so the clean repeat is the preferred receipt. The repeat
benchmark delivered 75.62 native pairs/s over 20.63 analyzed seconds, with
fresh readiness, clean exit and exact restoration. Neither short diagnostic
establishes instrumentation overhead or an optimization gain. Evidence lives
under `synthetic-solo-render-api-cpu-b-20260910` in ignored unattended artifacts.
