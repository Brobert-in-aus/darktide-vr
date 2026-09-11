# Combined small optimisations

The user requested a cumulative test of the individually marginal changes.
Compare the established descriptor/native-ring baseline against that baseline
plus all three focused CPU hook improvements, enhanced-barrier lock filtering
and direct native original copying in the viewer.

The three CPU changes reserve diagnostic budget before preparing unused log
payloads, match short resource names without allocation, and copy fixed command
recording state without copying diagnostic maps. The barrier change skips a
capture bookkeeping lock for irrelevant texture layouts. The viewer change
removes one intermediate stereo copy while generated surfaces are absent.

## Exact comparison

| Component | A / A2 baseline | B combined |
| --- | --- | --- |
| Native source | `10550a4` | `2f2bed3`: `a99b8ce` plus `4354209` |
| Native DLL SHA-256 | `D4AB131A16C30143AEDFC4296CD5846E60C9CB6ED4C32BCC320C8A0578BE10AE` | `0E4718A34A553D8336BD15F6D2654818D7907F70FA509AFBA969E7556B603B0F` |
| Viewer source | `d8cafb3` | same executable |
| Direct original copy | Off | On |

Viewer SHA-256:
`972CD7A5A8108FA039A5661B96DE9C61FDB6E254F8D14D11741B7EBBDC279D5E`.
Its path is `build/focused-direct-original-viewer/tests/xr_harness/Release/darktidevr-xr-harness.exe`.
The native candidate is under `build/focused-stacked-performance` and source
branch `codex/focused-stacked-performance-2026-09-11`. No broad diagnostic
observer or on-demand desktop-capture experiment is added to this stack.

All runs use the same stationary SoloPlay `cm_archives` difficulty 3 mission,
2496x2688 per eye, Quality DLSS, FG Off, unlimited cap, 120 Hz simulator,
configured 13 workers, stereo HUD/menu enabled, preview/debug off, and accepted
Lua. The same viewer is used in both arms to avoid a binary-version confound.
Measure 90 seconds after readiness, excluding the analyzer's ten-second warm-up.
Use distinct original delivery, not the simulator's cumulative title-bar rate.

Initial physical Ready checks failed because rendering was unavailable; later
checks before A2/B2/A3 passed. All workloads remain the same explicitly selected
simulator control, not a physical-headset comparison. Every trial retains the Lua compilation gate,
temporary deployment, process ownership and restoration checks. No builds run
during measurements. Valid GPU activity records must show idle Streamer for
these to be comparable with the existing idle-encoding controls.

## Offline checks

Focused Windows x64 Release native build passes. `native_capture_hooks` and
`enhanced_barrier_interest` pass 2/2 in 0.61 seconds; `bounded_diagnostic`,
`resource_name_match` and `command_recording_snapshot` pass 3/3 in 0.57 seconds.
The viewer and its previously tested GPU copy helper are unchanged and their
hash is verified before the comparison.

```
cmake --build build/focused-stacked-performance --config Release --target darktidevr_native_capture darktidevr-native-capture-tests darktidevr-enhanced-barrier-interest-tests darktidevr-bounded-diagnostic-tests darktidevr-resource-name-match-tests darktidevr-command-recording-snapshot-tests
ctest --test-dir build/focused-stacked-performance -C Release -R '^(native_capture_hooks|enhanced_barrier_interest|bounded_diagnostic|resource_name_match|command_recording_snapshot)$' --output-on-failure
```

## Controls and environmental interruption

The first baseline A delivered 89.51046 native FPS. The first combined B
delivered 73.01264, but Streamer video encoding/3D activity appeared in 19 of
27 valid GPU observations, versus none in A. B is excluded from the performance
comparison. Its clean exit and restoration still passed. This is an observed
environmental change, not evidence that the stack caused the slowdown.

A2 returned to idle Streamer observations but delivered 85.38231 FPS despite
identical recorded settings to A. That larger baseline drift means the original
A cannot be used to confidently assign a sub-percent difference to the stack.
The repeated local sequence is therefore the useful comparison:

| Run | Stack | Distinct native FPS | Viewer GPU-completion wait, ms |
| --- | --- | ---: | ---: |
| A2 | Off | 85.38231 | 1.62912 |
| B2 | On | 86.37962 | 1.49075 |
| A3 | Off | 85.83978 | 1.65102 |
| B3 | On | 86.56145 | 1.55627 |

B2 is 0.90% above the surrounding baseline average and 0.63% above A3.
Its viewer completion wait is lower by approximately 0.15 ms. These are
CPU-observed fence waits, including GPU dependencies, not GPU timestamp
measurements of copy execution. The timing figures use the final 60 accepted
world-mode timing windows, not precisely the FPS analysis window. This agrees
with the earlier isolated direct-copy observation; it does not demonstrate that
all five changes contributed independently or that their savings add linearly.

The B3 repeat supports a small local uplift: the time-weighted A2/A3 baseline
is 85.61043 FPS and B2/B3 combined is 86.47044 FPS, a 1.00% difference. Both
combined repeats exceed both nearby baselines, but there are only two runs per
arm, and the earlier 89.51 baseline shows larger environmental drift. Treat
this as evidence for a modest benefit under these controls, not a precise
general performance guarantee or proof of additive gains from every change.
The combined candidate is retained. No large cumulative speedup was uncovered.

All six runs exit cleanly, restore temporary files and report zero pose
mismatches. A/A2/A3 each have 27 valid GPU observations and one unavailable;
B2 has 26/two and B3 has 25/three. None has observed Streamer activity in valid
samples. The excluded B has 27/one, with 19 busy Streamer samples. Missing
observations remain unknown. Direct-copy submission records are present in
combined runs and absent in baselines. All recorded configuration fields match
except the intended native DLL hash; the direct-copy process option is separately
verified in the consumer logs.

Evidence directories: `artifacts/unattended/synthetic-descriptor-demand-stacked-{a,b,a2,b2,a3,b3}-20260911`.
Each contains configuration, restoration, FPS and viewer-stage reports. The local
`stacked-performance-receipt-20260911.json` records hashes of those reports and
consumer logs. The accepted installed native module remains the restoration
target; this experiment does not promote the stack to normal launch.

## Encoding scope and follow-up

The user confirmed they were away and had not touched Virtual Desktop. Do not
attribute B's encoding activity to user interaction. Its Streamer PID was the
same as in every control. Activity was observed from 01:25:17 to 01:27:32 UTC,
after the 01:25:04 failed physical Ready check; subsequent Ready checks passed
and the simulator controls observed idle encoding again. Readiness wakes the
Quest and opens a short XR session, making automation a possible trigger. This
timing is not a demonstrated causal explanation.

GPU activity monitoring detects this confounder; it does not supply a fixed
encoding penalty that can be subtracted from FPS. These idle-encoding controls
isolate the mod/transport changes and omit the complete physical VDXR compositor,
VR encoding, streaming and headset path. Desktop encoding during a simulator run
is not identical to VR encoding. A controlled active-streaming baseline/candidate
comparison remains necessary before predicting in-headset gains or claiming the
120 FPS target with the full streaming load. Retain the native/generated/repeated
frame distinction and do not present idle-simulator results as end-to-end VR FPS.
