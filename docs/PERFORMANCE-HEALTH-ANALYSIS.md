# Generated-stereo health summaries

Use `tools/stereo/summarize-generated-health.py` to summarize a saved native
health log without treating every quiet-generation interval as FG disabled:

```powershell
python -B tools/stereo/summarize-generated-health.py <health.log> --output <summary.json>
```

The report separates foreground/background, observed generation progress and
Present clock precision. It reports medians and extrema of health-window values,
not frame-time percentiles. A median of window-average Present durations is not
a median Present call. Slow windows are retained.

Cumulative publication counters determine whether generated output progressed;
evaluation without publication is a distinct category. No progress does not
prove FG was disabled. Completion may retire after the final evaluation, so
publication progress takes precedence. Graphics settings, scene, motion and
render resolution are not recorded in these health rows and cannot be inferred.

The first valid row establishes a baseline. Counter resets, invalid rows and
explicit enable/disable markers break counter continuity. Focus/clock transitions
and windows with a reported original failure or no observed original output are
counted separately. New native logs mark `present_clock=steady`; older logs are
labelled `coarse_legacy` and never combined with precise durations.

The new native candidate records `focus_changes` across every measured Present
in each health window. A switch away and back can have identical foreground
flags at both endpoints; those mixed windows now appear under
`within_window_focus_transition` rather than stable foreground performance.
New groups carry `focus_tracking=per_present`; old logs are labelled
`endpoint_only` and are kept separate. Changes occurring entirely between sampled
Presents remain unobservable. This is measurement hygiene, not a performance fix
or a claim that earlier slow windows were caused by focus changes.

## Whole saved session: 7 September offline analysis

The saved 140744 log contains 541 health rows. The report accounts for all rows:
one baseline, 48 windows without observed original output, 14 focus transitions,
and 478 grouped observations.

| Focus / observed progress | Windows | Median engine FPS |
| --- | ---: | ---: |
| Foreground / generated publication | 137 | 50 |
| Foreground / no evaluation or publication progress | 252 | 45 |
| Background / no evaluation or publication progress | 89 | 70 |

All timing in this file is coarse legacy timing. The whole-session quiet group
includes unlabelled conditions and is not the previously documented selected
75-window FG-off interval. Its median must not be used as an FG-off benchmark.
This illustrates why the counter state alone cannot replace a controlled
SR-off, SR-on/FG-off, SR+FG comparison with matched foreground scene and extents.
The earlier selected-window result remains historical evidence with its stated
limitations; this report adds no causal attribution or performance fix.

Evidence: `artifacts/diagnostics/dlss-base-framerate-20260906/health-summary-20260907.json`.
Five unit cases cover fractional timing, retained slow windows, focus/clock
separation, delayed progress, counter resets, invalid rows and missing output.
Two additional cases cover within-window away/back transitions, old/new focus
evidence separation and invalid transition counts. The native window helper also
checks repeated stable samples, two transitions and reset across windows. Release
native-capture and generated-frame-state test builds pass; the two focused CTests
pass. The new logging is undeployed pending Ready; saved logs cannot be upgraded
to per-Present focus evidence retroactively.

## Continuous-frame trace cost

The Present path previously requested five detailed success records per frame:
one Present identity, two state reads and two completion tickets. The shared
writer formats accepted records and performs a mutex-protected synchronous
`WriteFile`; its total budget also means dense success traffic consumes evidence
capacity early. This establishes avoidable work, not a measured FPS cost.

The offline candidate samples those successful records for persistent delivery:
all first eight frames, then every 120th frame. A 1,200-frame interval requests
90 such records instead of 6,000, before the shared log budget is applied.
Short bounded probes retain complete records. State errors, failure reports,
pause/resume/binding rejection, GPU timing and health reporting retain their
existing paths. No fence, state query, completion validation or rendering work
is skipped by the trace policy.

The ready record declares `frame_trace=complete` or `startup8_then120`. The
bounded-probe reader rejects sampled or unknown policies even if a short prefix
looks consecutive; legacy complete logs remain accepted. Release native-capture
and generated-frame-state builds pass. Three focused CTests pass: generated
frame state, continuous observation and health analysis. Actual performance
effect needs a controlled live comparison after Ready succeeds.

## Rigid glove update cost and spawn readiness

The rigid-hand update and placement paths both reapplied full root/slot/attachment
visibility. With one update and one placement for each hand per frame, that was
four traversals. Ready-hand update now leaves visibility to placement, reducing
that case to two traversals. Initial visibility, placement-time enforcement and
streaming callback recovery remain; there is no measured frame-rate claim.

The same inspection found readiness based on `spawned_character_unit()` alone.
Stock UIProfileSpawner can return a unit before `spawned()` reports ready. Its
next updates complete streaming/visibility initialization and pending work. The
rigid-hand path now continues those updates until stock readiness, then initializes
its surface once. A regression reproduces premature readiness and checks pending
updates, 100 stable updates without repeated visibility work, dead/missing units,
failed streaming quarantine and a fresh replacement owner. Seven focused CTests
including the 36-chunk LuaJIT gate pass. Candidate remains undeployed.

Follow-up lifecycle protection requires both hand units to remain alive. Loss
of a previously ready unit retires the pair and uses the existing failed-owner
quarantine. The presentation seam forces a source-visibility refresh on active/
inactive changes, including complete teardown; stable frames retain the normal
cadence. Actual liveness/update/visibility seams pass constructed loss/recovery
cases, and the full offline suite passes 110/110. This establishes control flow,
not live rendering acceptance or a diagnosis of the historical hub teardown race.

## GPU timing workload boundaries

The NGX GPU timer previously averaged 120 successful samples per eye without
recording the feature lifetime or image extent. The candidate records
`feature_lifetime`, `eye_width` and `eye_height` from the observed frame-generation
evaluation. Completed samples with different keys cannot share an average.
On a key change, the previous partial group is emitted with
`boundary=workload_change`; an ordinary 120-sample group uses
`boundary=sample_limit`. Compare sample counts explicitly, and weight by them if
combining compatible groups. Unknown/zero lifetime or extents are not profiled.

Both direct and compute D3D12 WARP tests exercise feature, width and height
changes independently. Each eye produces three 60-sample groups and one
120-sample group with exact keys and boundary labels; fixed capacity,
unsubmitted-reset cancellation and completed readback checks remain. Release
profiler/native DLL builds and the two profiler tests pass, as do native hook
and generated-frame-state checks. No headset is needed for these isolated GPU
tests. These fields do not identify scene motion, SR quality, driver or streaming
conditions; controlled live comparisons and all performance claims remain pending.
