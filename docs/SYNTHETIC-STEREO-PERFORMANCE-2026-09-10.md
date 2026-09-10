# Synthetic stereo performance capture, 10 September 2026

The existing offline dual-view benchmark works while physical Quest tracking is
unavailable. It renders the production sequential left/right viewports with a
synthetic head publisher and a deterministic 20-second hub camera revolution.
There is no OpenXR consumer. This provides an engine workload, not XR readiness,
headset presentation latency or worn visual acceptance.

The publisher supplies the fixed VirtualDesktopXR Medium frusta, a 64 mm IPD
and a 2112 by 2304 eye target. At the retained DLSS Quality setting, the trace
contains 1408 by 1536 internal targets. This differs from the recent physical
headset capture's 2496 by 2688 output and 1664 by 1792 internal targets; those
runs are not a resolution-matched performance comparison.

## Reproduction

With Darktide closed, retain the accepted installation:

```powershell
$env:DTVR_XR_PRECISE_PAIR_WAIT = '1'
tools/stereo/start-darktide-vr.ps1 -OfflineDualViewBenchmark -SyntheticRuntimeFrusta -SkipDeploymentSync -DurationSeconds 120 -GameStartTimeoutSeconds 300
```

Restore the prior process environment value afterwards. Add
`-EnablePerformancePassTrace` for the existing bounded native trace. That also
enables performance profiling and broad diagnostic hooks; recording overhead is
part of this configuration. The launcher restores its flags and stops its owned
game and publisher. Both the checkout and installed Lua source gates run before
launch. No gameplay verification or Psykhanium entry is involved.

The accepted native DLL remained SHA-256
`FCCDD0DE699F9D50D2BD316792829D4EE5700843D925D194BE4DF1F3EEB02369`.
No candidate DLL or Lua source was deployed. The first, uninstrumented run
completed successfully. WPR recording failed because Windows could not enable
the profiling policy (`0xc5585011`); see [CPU sampling](ENGINE-CPU-SAMPLING.md).

## Bounded trace

The instrumented run entered sequential stereo, started the trace about five
seconds later, and completed it with 34,198 records. The GPU batch capture
reported complete, untruncated records for both eyes:

| Recorded work | Left | Right |
| --- | ---: | ---: |
| Direct-queue batch time | 2.905 ms | 3.025 ms |
| Timed batches | 6 | 3 |
| Draw calls, indexed plus non-indexed | 244 | 304 |
| Dispatch calls | 39 | 72 |
| Indirect calls | 606 | 769 |
| Copy calls | 33 | 25 |
| Barrier calls | 394 | 372 |
| PSO binds with matched generation records | 488 | 638 |

The two terminal batches account for 2.042 and 2.315 ms respectively. Unique
PSO overlap is 122 of 147. Only 7 of 18 left command lists and 7 of 13 right
lists have matching PSO records; work-counter availability does not establish
complete shader attribution. The existing identity file appends across runs
and omits compute shader hashes, so it must not be treated as a fresh complete
shader map based only on pointer matches.

The full 120-second traced run completed, stopped its owned game and publisher,
and restored both profiling flags to disabled.

These timings cover recorded direct-queue work, not whole-frame GPU time. The
single early capture and asymmetric command counts do not prove redundant
second-eye work. Persistent GPU interval telemetry includes longer intervals;
do not subtract these batch totals from interval averages to invent a missing
pass cost. Profiling overhead, queue boundaries and sample selection differ.

In the native implementation, an interval starts when Lua arms an eye and ends
when a completed output is recognised, before the shared-eye copy. Both eye
intervals can be active together. They can include time waiting for subsequent
queue submissions, and adding them is not a whole-frame duration. The
`pre_full`/`post_full` split marks an internal-sized to output-sized resource
transition; it is not an identified DLSS or post-processing pass boundary.

Local receipts: `artifacts/unattended/synthetic-engine-{baseline-launch,profile-launch,focused,gpu}-20260910.*`.
Raw game logs and extracted shader data remain outside Git.

## Timing-only follow-up

A third 120-second run used `-EnablePerformanceProfile` without pass tracing.
It completed and restored its owned processes and flags. The broad shader
identity file did not grow. For report windows ending 20–100 seconds after the
hub-spin start, sample-weighted means were:

| Metric | Pass-trace configuration | Timing only |
| --- | ---: | ---: |
| CPU pair submission interval | 0.201 ms | 0.224 ms |
| Left GPU interval | 7.500 ms | 6.829 ms |
| Right GPU interval | 11.353 ms | 9.464 ms |

These are sequential diagnostic runs, not randomized repeated trials. They show
why the broad trace configuration cannot serve as an unqualified performance
baseline; the difference is not an established game optimisation or an exact
measurement of hook overhead. Window averages were weighted by their own
sample counts, with 18 and 20 windows respectively. No combined percentile was
derived from window percentiles.

A separate 30.101-second process sample consumed 96.797 CPU seconds, equivalent
to 3.216 cores on average. Aggregate process use cannot establish whether the
main thread is saturated. Receipts use `synthetic-engine-timing-only-*` and
`synthetic-engine-profile-comparison-20260910.json` in the same artifact directory.

The launcher now describes its offline readiness wait correctly instead of
announcing an XR launch. This message-only change passed PowerShell parsing;
it does not change launch or cleanup behaviour.
