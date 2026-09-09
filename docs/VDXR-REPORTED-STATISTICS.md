# Runtime reported-statistics caveat

The saved later capture contains an extreme first `AppRenderCpuTime` value.
It must not be silently averaged into a claim that ordinary viewer rendering
takes hundreds of times longer than its independently timed frame loop.

`tools/stereo/summarize-vdxr-app-statistics.py XML --process-id PID --output REPORT.json`
reports raw values without converting units. It preserves all samples, makes the
first value explicit, and provides a separately labelled after-first summary.
It does not automatically declare the first sample invalid or discard it.
Fields and threads remain separate; decreasing frame IDs start new epochs.
Duplicate-frame samples remain visible and counted. Invalid values/duplicate
fields are excluded explicitly. Input and hardlink aliases cannot be overwritten.

Saved capture observations, raw reported values:

| Capture / field | Samples | First value | All-sample mean | After-first mean | After-first maximum |
| --- | ---: | ---: | ---: | ---: | ---: |
| Onset / render CPU | 1,863 | 3,061 | 3,496.609 | 3,496.843 | 8,682 |
| Later / render CPU | 378 | 227,574,800 | 605,958.603 | 3,919.236 | 7,619 |
| Later / frame CPU | 378 | 14,783 | 12,777.209 | 12,771.889 | 25,777 |
| Later / render GPU | 378 | 4,311 | 4,093.138 | 4,092.560 | 8,611 |

No duplicate-frame samples or counter restarts occur in these groups. The onset
capture lost its prefix to circular overwrite, so its first retained sample is
not the tracing-start sample.

The public runtime's CPU timer accumulates on stop and resets on query; the
render-timer query appears inside the trace-writing expression. A stale
accumulation when tracing starts is therefore a plausible explanation for the
first-value outlier. This is an inference from public source, not proof about
the installed binary. The public timer returns microseconds; the analyzer keeps
the installed trace's values raw. Sources at public revision
`1a83fec8b5c565b14b06ffa8e1eb7e4768057573`:
[CPU timer](https://github.com/mbucchia/VirtualDesktop-OpenXR/blob/1a83fec8b5c565b14b06ffa8e1eb7e4768057573/virtualdesktop-openxr/utils.h#L219)
and [render-statistic query](https://github.com/mbucchia/VirtualDesktop-OpenXR/blob/1a83fec8b5c565b14b06ffa8e1eb7e4768057573/virtualdesktop-openxr/frame.cpp#L263).

The [raw-QPC activity spans and overlap](VDXR-SUBMISSION-SLOWDOWN.md) remain the
basis for locating the sustained wait. This reported-statistics caveat neither
changes that evidence nor establishes a backend cause or fix.

Three Python cases pass: first-sample preservation and separate views; fields,
processes, duplicate frames and counter restarts; invalid/zero/unsigned
limits; CLI source/hardlink preservation. Reports are
`artifacts/unattended/vdxr-{onset,later}-app-statistics-20260909.json` with matching
logs. Validation: `vdxr-app-statistics-tests-20260909.log`. No new capture,
runtime/game operation, settings change or deployment.
