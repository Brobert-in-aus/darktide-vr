# Frame-production investigation, 11 September 2026

The user resumed continuous development and the existing 20-minute heartbeat.
Earlier stop instructions and the paused state in yesterday's handover are
historical. Current performance target remains 120 distinct FPS at 2496x2688
per eye; 144 Hz remains secondary. No basic gameplay verification is requested.

## Initial matched controls

All use cm_archives difficulty 3 mission start, Quality DLSS, 120 Hz simulator,
13 configured workers, Reflex On, accepted world-space HUD and menu input on,
preview off, clean optional diagnostics, graphics validation off. Same FB244186
native, 216E3F76 viewer, CB8B5202 simulator, accepted Lua. Each lasts 60 seconds;
analysis excludes ten seconds of warm-up. Native-only uses Unlimited; FG uses
cap 120. These controls do not modify the accepted installed build.

| Trial | Original FPS | Generated FPS | Distinct FPS | GPU utilisation samples | Board power samples |
|---|---:|---:|---:|---:|---:|
| FG A | 48.69 | 48.71 | 97.41 | 94.8% | 315.1 W |
| Native A | 51.89 | 0 | 51.89 | 92.2% | 331.4 W |
| FG B | 48.67 | 48.67 | 97.34 | 94.4% | 314.7 W |

All foreground samples in their 10-60 second windows belong to Darktide (50,
49 and 49 respectively). All exit cleanly, restore files, and have zero pose
mismatches. GPU means use ten five-second samples each, not continuous traces;
clocks average 2715 MHz and temperature 54-56 C. No thermal throttling conclusion
is drawn solely from these samples. Native-only is also below the older 70.85
FPS high-resolution control, so the change is not confined to generated frames.

## Background streaming control in progress

A per-process Windows GPU Engine snapshot during FG B identifies Virtual Desktop
Streamer using approximately 6.3% on the 3D engine and 43% on each of two video
encode engines. Engine percentages must not be added to the board utilisation
or treated as equivalent costs. This proves concurrent work, not its causal cost.

After all run-owned game/viewer processes exited, normal Quest proximity behaviour
was restored and an explicit sleep request issued. Power reports Asleep, with no
display suspend blocker. The following GPU sample contained no Streamer engine
above 0.1%. The simulator-only control uses the same explicit saved eye resolution;
physical headset readiness is not claimed while it sleeps. VDXR registry remains
unchanged. Compare FG with the same 60-second method before further conclusions.

## Measurement maintenance

The launcher has four legitimate authenticated-process messages: normal launch,
launcher transition, Play activation and Play retry. The native/GPU evidence
collector and thread-profiler tools now recognize all four; executable and process
identity gates remain in place. The GPU summary tests cover all four messages and
pass (four tests). This prevents a valid launch from silently losing its native
logs or being rejected by the focused profiler.

Ignored evidence: `artifacts/unattended/morning-production-*20260911`,
`morning-production-focus.csv`, `morning-production-gpu.csv`, and
`morning-gpu-process-snapshot.json`. No device identifiers are included here.

## Sleeping-headset result

The otherwise matched FG control with the headset asleep delivered **115.79 distinct
FPS** (57.89 original + 57.89 generated), 120.00 submissions/sec and 4.21 repeats/sec.
All 50 foreground samples were Darktide; zero pose mismatches, clean exit and exact
restoration passed. The Streamer had no sampled engine above 0.1% during the run.
Ten GPU samples averaged 98.3%, 342.3 W and 2715 MHz. This is +19.0% relative to
FG B with desktop streaming active, and recovers/exceeds the historical 112.68
result. It is a strong background-workload lead, not yet a completed A/B/A proof.
The headset was then explicitly woken and a fresh Ready preflight passed. The next
trial must verify actual encoding activity rather than assuming awake implies an
active desktop stream.

## Awake without desktop encoding

Waking the headset and passing Ready did **not** restore desktop encoding. The
snapshot during the next mission still contained no Streamer engine above 0.1%.
That run delivered **116.00 distinct FPS**, with 49/49 foreground samples in the
game, zero pose mismatches and exact restoration. Thus wakefulness itself does
not reproduce the loss. Treat this as a second idle-encoding control, not the
missing streaming-on reversal. Do not claim a completed A/B/A experiment.

The next native controls use 120 seconds and exclude 30 seconds of warm-up.
The first, HUD off with idle desktop streaming, delivered 76.88 FPS with 90/90
sampled foreground observations in Darktide. GPU samples averaged 79.1% and
332.2 W; zero pose mismatches and exact restoration passed. This differs in HUD
and analysis duration from Native A above, so wait for the matching HUD-on control
before assigning the entire native recovery to background streaming.


## Completed longer native controls

All three used idle desktop encoding, 120-second runs and 30-second warm-up.

| DLSS | HUD | Native FPS | Mean sampled GPU utilisation | Mean sampled board power |
|---|---|---:|---:|---:|
| Quality | Off | 76.88 | 79.1% | 332.2 W |
| Quality | On | 77.00 | 82.6% | 329.0 W |
| Performance | On | 75.82 | 69.8% | 274.7 W |

All 90/89/89 foreground observations respectively belong to Darktide. Every run
closed cleanly, restored files and reported zero pose mismatches. GPU means use
17/17/18 samples respectively. Performance reduces GPU work and power without a
native throughput gain here; Quality remains the accepted default. The matched
HUD pair shows no material cost. No exact CPU function cost is established by
this comparison, but the existing render-dispatch CPU investigation remains
relevant after eliminating the background streaming confounder.

The initial active-encoding native run used a shorter analysis window, so its
51.89-to-77 difference is not a fully matched effect estimate. The FG active/idle
controls do use matched windows and show approximately 97.4 versus 115.9 distinct
FPS. Active desktop encoding was not successfully reinstated; therefore call it
a strong measured association after the sleep intervention, not a completed
reversal or proof of the specific driver/encoder mechanism. This is benchmark
hygiene, not a mod optimisation or a promise of 116 FPS on the physical headset.

All synthetic sessions are now closed; installed native hashes and simulator
runtime were restored, and normal Quest proximity automation was re-enabled.
Subsequent development: the [descriptor/ring candidate](NATIVE-ORIGINAL-RING.md)
delivered repeated 89.57/89.34 native FPS against a fresh accepted 76.47 FPS
control, about 17% faster. Its DLSS Performance control reached 95.80 FPS.
Matched FG controls reached about 119–120 distinct FPS at both 120/144 Hz;
144 Hz added repeats. The physical on-demand viewer comparison still awaits
resumed VD streaming. See the [current handover](handoffs/2026-09-11.md).
