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
