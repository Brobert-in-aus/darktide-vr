# Sustained submission slowdown: runtime trace

9 September offline tooling follow-up: `summarize-vdxr-trace.py` now refuses to
write its report over the source XML, including another hardlink to that file.
The CLI regression failed before the fix. Together with the equivalent viewer
log guard, twelve Python cases pass in two analysis CTests (0.69 seconds).
This preserves evidence; it does not alter the runtime or diagnose the slowdown.

8 September 2026, timing-only viewer with accepted native capture, focused
melee preview and SoloPlay rules. The same game/viewer process ran uninterrupted
from 14:48 Brisbane. No graphics, refresh-rate, runtime, input or shader setting
changed during the decline. This extends [viewer stage timing](XR-FRAME-STAGE-TIMING.md).

## Observed boundary

Fresh gameplay delivered about 53 original + 53 generated pairs/s. After roughly
45 minutes it began declining; by 15:49 it was about 37.7 + 37.7, and at 15:54
about 36.3 + 36.3. Source-wait time fell from roughly 5.8 ms per loop to below
0.2 ms, while `xrEndFrame` rose from about 0.12 ms to over 9 ms. GPU-fence wait
remained roughly 3–3.6 ms. The producer continued publishing faster than the
viewer submitted. No interval fallback or pose mismatch in the cited samples.

Two bounded ETW captures of the installed runtime expose its internal activity
spans. These are CPU-observed wall durations and include blocking; nested and
concurrent spans must not be summed.

| Runtime activity | Around 15:37 mean / p95 | Around 15:49 mean / p95 |
| --- | ---: | ---: |
| Async thread `OVR_BeginFrame` | 8.877 / 13.863 ms | 13.031 / 17.197 ms |
| Main thread submission-idle wait, running-start off | 3.876 / 9.861 ms | 8.450 / 13.643 ms |
| Main thread submission-idle wait, running-start on | 1.445 / 5.996 ms | 0.546 / 5.010 ms |
| Async thread `OVR_EndFrame` | 0.111 / 0.163 ms | 0.123 / 0.181 ms |

The first row has 1,867 and 377 complete samples respectively. The runtime's
[public frame implementation](https://github.com/mbucchia/VirtualDesktop-OpenXR/blob/main/virtualdesktop-openxr/frame.cpp)
waits for its previous asynchronous submission during `xrEndFrame`, and uses a
running-start wait from `xrWaitFrame`. Its background submission loop calls the
OVR frame functions before accepting another layer batch. The matching activity
names/flags in the installed trace locate the delay at that boundary. The public
source revision is not proven byte-identical to the installed binary; this does
not identify the deeper cause inside Virtual Desktop's backend, prove a network
or decoder fault, or establish that either viewer pacing candidate fixes it.

Installed VDXR is 1.0.10.0, SHA-256
`559E06095A52800FDA947163E42B292B888D3541C863AAF1815BB0CD729346EF`;
Streamer is 1.34.22.0. No update or runtime configuration change was made.
The ordinary runtime log was empty; ETW can be enabled dynamically without
restarting. Both owned trace sessions stopped normally after their bounds.

## Supporting observations and limits

A ten-second thread sample around 15:44 shows about 3.43% of one core for the
main viewer thread and 2.18% for its runtime submission thread. This supports
blocking rather than those threads exhausting a CPU core in that interval.
A Wi-Fi status snapshot reports -20 dBm and 1,200 Mbps negotiated transmit/receive
rates; it does not measure packet delay or delivered video throughput. Headset
captures report thermal status zero and DVFS field zero in the sampled windows,
with app/runtime FPS declining alongside PC submissions. These fields do not
exclude every possible device-side limit. No network or thermal control changed.

The separate [precise-wait candidate](XR-PRECISE-PAIR-WAIT.md) and
[producer cadence correction](PRODUCER-FRAME-CADENCE.md) remain undeployed.
At the observed slow point, source waiting is already a small part of the loop.
A fresh precise-wait comparison can test whether earlier polling behavior affects
the development of runtime delay; its initial FPS alone cannot establish a fix.
Keep the cadence correction out of that first comparison to isolate the wait.

## Repeatable trace analysis

The provider GUID is `{cbf3adcd-42b1-4c38-930b-91980af201f6}`. Its source comment
contains a different byte; the actual provider definition and captured provider
agree on `930b`. Manifestless provider-name enumeration returned no entry, but
starting the explicit provider GUID succeeded in the current non-elevated shell.
Do not infer that kernel/GPU tracing has the same access requirements.

Use a unique owned session name, a bounded capture and `finally` cleanup. The
five-second capture fits this workload's 64 MiB circular file. The first
30-second capture overwrote its prefix: only 19.308 seconds remain, despite zero
reported lost events. The later capture retains 5.038 seconds without indicated
overwrite. Incomplete activities at the boundaries are excluded explicitly.

```powershell
# After the owned trace has stopped:
tracerpt capture.etl -rts -o capture.xml -of XML -y
python tools/stereo/summarize-vdxr-trace.py capture.xml --process-id VIEWER_PID --output report.json
```

**Use `-rts`.** The local Windows `tracerpt` emits mixed `+09:59` and `+10:00`
offsets in formatted SystemTime within a single Brisbane capture. Normalizing
those strings manufactured minute-long durations. The committed analyzer
rejects formatted timestamps and requires raw QPC ticks plus the trace header's
positive frequency and QPC clock type. The corrected raw results above agree
with the viewer's independent steady-clock measurements. Earlier formatted-time
summary files were replaced by the raw-time analysis; do not reuse the discarded
time-zone-normalized result.

The parser streams XML, filters the requested process/provider, preserves
thread/mode groups, pairs activity identities, and reports unmatched, duplicate,
negative or invalid spans. Three fixtures cover 100 ns precision, process and
running-start separation, nested/cross-thread spans, circular overwrite and
incomplete/invalid activity handling. Both trace and viewer-stage analysis CTests
pass in 0.44 seconds. No game files changed for this diagnostic.

Evidence under `artifacts/unattended/`:

- `vdxr-{onset,later}-20260908.etl`, matching `*-rawtime-20260908.xml`, and
  `vdxr-{onset,later}-validated-20260908.json/.log`.
- `soloplay-stage-trend-20260908.json`, full live viewer/producer logs,
  `vdxr-onset-thread-cpu-20260908.json`, and local Wi-Fi snapshot.
- `quest-runtime-health-20260908/` and `quest-runtime-health-onset-20260908/`.

Raw traces/device reports and generated outputs stay out of Git. Worn smoothness
and in-mission gameplay acceptance remain pending the user's return.

## Duplicate activity identity exclusion, 9 September

A regression fixture exposed that a second start with the same activity/name
previously replaced the first timestamp, allowing the following stop to produce
an artificially shorter duration. The analyzer now discards the pending span
and quarantines that identity for the remainder of the trace. It counts the
duplicate start and subsequent ambiguous activity events separately; independent
activity identities remain measurable. It does not guess which start owns a stop.

Four trace fixtures pass, including the previously failing duplicate/reuse case.
Both trace and viewer-stage analyzer CTests pass in 0.23 seconds. Reanalysis of
the saved onset and later raw-QPC XML traces produces reports identical to their
previous validated reports: neither contains duplicate starts. Local results are
`artifacts/unattended/vdxr-{onset,later}-ambiguity-20260909.json`. Thus this fixes
future ambiguous evidence without changing the earlier slowdown findings. No
new tracing, runtime operation or performance fix is claimed.
