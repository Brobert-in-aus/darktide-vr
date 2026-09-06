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
