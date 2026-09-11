# Hub performance after the descriptor and native-ring changes

The next control retains the saved 2496x2688 eye resolution, Quality DLSS,
FG Off, configured workers 13, 120 Hz, HUD/menu enabled and preview/debug off.
It uses native ring `D4AB131A` and benchmark viewer `216E3F76`, with the direct
copy option off. The existing hub workload rotates once every twenty seconds;
the mission controls are stationary. Scene and visibility workload differ,
so this cannot attribute a difference solely to a particular engine subsystem.
Public hub population can also change between runs.

## Readiness defect discovered before the first admitted control

The hub and synchronized stereo initialized successfully in the first attempt,
but the launcher continued waiting. Its readiness expression combined `-and`
and `-or` without separating the hub and SoloPlay alternatives. PowerShell
evaluates those operators left to right at equal precedence: the hub case also
required the missing SoloPlay-ready line. The mission case still worked.

Using the actual run log, the old expression returns false and the explicitly
grouped expression returns true. The launcher now calls a small pure predicate
with separate hub/mission branches, retaining the stereo-init prerequisite.
Twelve offline cases pass under PowerShell 7 and Windows PowerShell 5.1, covering
hub, mission, missing stereo/state, wrong mission/host, invalid difficulty and
literal mission matching. These tests invoke no launcher or game.

The first attempt is excluded from admitted benchmark results. After identifying
the defect, its authenticated game process was closed so normal wrapper cleanup
could run. All 13 saved file records restored, with runtime/ring flags and normal
proximity handling restored by the outer wrapper. Local evidence:
`synthetic-descriptor-demand-hub-quality-20260911`. Its temporary observed rates
are context only; the requested timed measurement never started.

Validation: `tests/tooling/test-offline-workload-readiness.ps1` under both shells,
registered CTest `offline_workload_readiness`, and `git diff --check`. A fresh
timed hub control is next. The physical headset remains unavailable; simulator
fallback does not establish physical streaming performance or worn acceptance.

## Completed controls

| Workload/configuration | Native DLL | Original FPS | Generated FPS | Distinct FPS |
| --- | --- | ---: | ---: | ---: |
| Hub sweep, native | D4AB131A | 92.58248 | 0 | 92.58248 |
| Hub sweep, FG/cap120 | FB244186 | 58.66892 | 58.68142 | 117.35029 |

The FG run submits 119.88544 frames/sec, including 2.53508 repeated images/sec.
The matching mission configurations previously delivered about 89.5 native
(D4AB131A) and 119.3 distinct FG (FB244186). Compare scenes within each native
build; subtracting these native and FG rows does not isolate FG overhead because
the native modules differ. Both hub controls use the unchanged benchmark viewer.

The native control analyzes 80.36 seconds after warm-up; the FG control analyzes
80.08 seconds. Both timed launches pass the corrected readiness gate, exit
cleanly, restore files and report zero pose mismatches. GPU recording contains
32/31 valid records with zero/one unavailable respectively, and no observed
Streamer busy sample. This is sampled activity evidence, not a physical VR
encoding workload or proof of complete counter coverage. The registered
readiness CTest also passes in 0.87 seconds.

These saved-resolution simulator controls do not reproduce the user's earlier
approximately 40 original / 80 displayed hub result. They weaken a claim that
the resolution or hub scene alone explains it under current settings. They do
not close the physical-runtime gap: headset streaming, exact scene/population,
pose and physical viewer conditions still need a matched comparison. Do not
equate an idle desktop encoder with the physical VR encoder's workload.

Evidence: `synthetic-descriptor-demand-hub-quality2-20260911` and
`synthetic-descriptor-demand-hub-fg-20260911` under ignored unattended artifacts.
