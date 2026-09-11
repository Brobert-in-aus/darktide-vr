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
