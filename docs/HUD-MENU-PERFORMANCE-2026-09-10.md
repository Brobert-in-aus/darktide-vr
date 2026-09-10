# HUD and menu-input performance controls, 10 September 2026

The first both-off validation returned 91.45 distinct FPS (45.72 original +
45.74 generated), with all 50 foreground samples owned by Darktide. Disabling
these switches did **not** recover the historical 112.68 FPS baseline. The
HUD/menu configuration therefore cannot explain most of the historical gap.

## Method

Sequential cm_archives difficulty 3 mission-start runs: both off, HUD only,
legacy menu input only, both on, both off repeat. Each runs 60 seconds after
mission readiness; the analyzer excludes ten seconds of warm-up. Quality DLSS,
framegen on, 120 Hz/cap, 2496x2688 per eye, 13 configured workers, Reflex on,
preview off, optional diagnostics cleaned, graphics validation off. Native
FB244186, viewer 216E3F76, simulator CB8B5202; legacy simulator display clock.

The benchmark now exposes `-EnableMenuInput` separately. Both booleans default
true. HUD-off writes the explicit `disable` command and verifies the console
acknowledgment; the original flag bytes are restored after each run. This avoids
inheriting an already-enabled installed HUD. HUD-on still validates target width.

The menu switch controls legacy Windows input dispatch (`--enable-menu-input`).
The native UI service and shared pointer processing remain active in both states;
this is a control of the historical switch change, not an all-UI-disabled test.

Foreground is sampled approximately every second. Position and head yaw are
checked against the existing locomotion log. This cannot exclude sub-second focus
changes, and mission-start trials do not lock every AI/world-state detail.

## Baseline identity

The old high-resolution run and new both-off run have identical recorded binary
hashes, explicit rendering settings and saved game-settings bytes. Both log
position approximately 335.1354,111.0239,-20.4500 and head yaw 1.5708. Older receipts
do not record every optional flag or background workload, so identical recorded
settings do not establish complete machine-state equivalence.

The both-off run's original and generated publication rates also fell to about
45.7 each; generated-frame selection reports no missing/rejected new frames.
The loss exists before viewer selection, rather than being explained by discarded
generated frames. This observation does not yet identify its cause.

## Validation

Ready preflight passed before the session. No game Lua/native code was changed.
The normal repository and installed Lua gates run on every benchmark launch.
A HUD-only startup attempt encountered an empty-log read race before game launch;
all recovery entries restored. Treating the initial log as a string allows an
empty read to retry through the existing readiness timeout. That failed attempt
is excluded and the HUD-only trial uses a fresh output directory.

Evidence is kept under ignored `artifacts/unattended/resolution-cause-hud-*` and
`resolution-cause-menu-only-20260910`, with `hud-menu-focus.csv` and
`hud-menu-comparison.json`. The matrix is complete; results follow below.

## What the simulator title bar measures

The simulator title's `XR ... FPS avg` is populated by `ProjectionTimingTracker`:
`xrEndFrame` observes stereo projection submissions, without identifying new game
images. The viewer can submit a previously displayed pair again. Its title rate
therefore includes repeats and is not the distinct image rate used here.

The first both-off run logged 114.24 submissions/sec, comprising 91.45 distinct
original/generated images and 22.79 cached submissions/sec. This reconciles the
user's approximately 115 FPS title-bar reading with the approximately 91 FPS
benchmark. The historical 112.68 figure was also distinct FPS, so that comparison
does not mix title-bar and distinct-frame metrics.

## Completed results

| HUD | Legacy menu input | Distinct FPS | Submissions/sec | Repeats/sec | Game foreground samples |
|---|---|---:|---:|---:|---:|
| Off | Off | 91.45 | 114.24 | 22.79 | 50 |
| On | Off | 91.36 | 114.47 | 23.12 | 49 |
| Off | On | 88.08 | 111.34 | 23.26 | 50 |
| On | On | 88.22 | 111.12 | 22.90 | 50 |
| Off | Off | 89.07 | 110.14 | 21.07 | 50 |

All five accepted runs had uninterrupted sampled game focus, zero pose mismatches,
clean exits and exact file restoration. HUD-only showed no material loss relative
to the first both-off run. Menu-only and both-on were near 88.1-88.2, but the final
both-off control was 89.07: baseline drift is comparable to much of the apparent
menu effect. Each run logged zero menu events and zero dispatched events. Do not
claim a measured 3 FPS menu cost or a significant HUD cost from this small series.

The older 112.68 distinct FPS remains unreproduced even with both switches off.
The approximately 24 FPS historical difference cannot be assigned to either of
these changes. Next isolate background workload, runtime timing and upstream
production timing with contemporaneous controls; do not stack another causal
claim on sequential runs alone. No additional broad optimization was attempted.

The final session closed, the simulator DLL returned to the original 3C3F41C3
baseline, both installed native DLLs returned to FCCDD0DE, and proximity automation
was re-enabled. PowerShell parser validation and `git diff --check` passed. The
five successful launches exercised the explicit HUD states and both menu switch
states. The startup empty-log fix was exercised by all remaining successful runs.
