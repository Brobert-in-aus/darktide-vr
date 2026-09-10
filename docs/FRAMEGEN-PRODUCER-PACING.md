# Match production to stereo display demand

The corrected consumer delivered 90 distinct pairs/s while the uncapped game
published about 80 original and 80 generated pairs/s. The display selected
roughly 45 of each. Pacing the producer may reduce unused work, independently
of shader or stereo-history changes.

The simulator wrapper now exposes the stock 30, 40, 60, 72, 90 and 120 cap
settings as well as Preserve and Unlimited. Each sets both the menu selection
and actual renderer value; detected-user caches are preserved. The selected
setting is not assumed to equal original-pair rate when FG is active. Actual
ring publication and display rates determine its effect.

Trials use the same 90 Hz simulator, 2112x2304 eyes, DLSS Quality, one generated
frame, consumer `69A5845...` and focused native `B052535...`, with no diagnostic
trace flags. Every trial restores the installed DLLs and settings exactly.
Board telemetry is sampled through the installed NVIDIA utility once per
second while the trial runs. Its process is stopped by the owning runner.

`analyze-synthetic-gpu-load.py` selects the interval from the launcher's explicit
UTC workload start plus ten seconds through its requested duration. The CSV's
timezone offset is supplied explicitly (Brisbane: +10). It reports weighted
sample means and coverage, preserves unsupported readings as unknown, rejects
invalid/duplicate time samples, and does not fill gaps over three seconds.
The utility defines GPU utilization as the fraction of the sample period when
one or more kernels execute, not shader occupancy. On this RTX 4090, power is a
one-second average for the whole board, with reported accuracy of +/-5 W.
These are board-level observations, not isolated game-process measurements.

The first 120-second cap-90 trial published 44.98 originals and 44.97 generated
pairs/s. The consumer delivered 89.88 distinct pairs/s, with 0.119 cached
repeats/s. Over the 110-second telemetry window, GPU busy time averaged 55.43%
and board power 240.58 W, with complete coverage and a 2715 MHz graphics clock.
Clean shutdown and exact restoration passed. Two uncapped controls delivered
89.93 and 89.99 distinct pairs/s, while publishing 82.28 and 77.70 originals/s.
Their board power averaged 337.58 and 330.93 W and GPU busy time 93.91% and
91.29%, with complete telemetry coverage. Both restored and exited cleanly.
The cap-90 trial used about 90–97 W less for nearly identical 90 Hz delivery;
this is a hub result with one capped trial, not mission performance evidence.

The user's target is 120 FPS: preferably 60 original plus 60 generated frames,
or the highest sustainable native rate without FG. Subsequent comparisons use
a 120 Hz simulator clock and test cap 120 with FG against uncapped production
and FG off. Actual SoloPlay mission measurements are also required to assess
representative load; the hub measurements cannot establish that target there.

The first 120 Hz cap-120 FG trial delivered 119.65 distinct pairs/s (59.83
original and 59.82 generated), with 0.339 cached repeats/s across 109.01 seconds.
The producer published 59.99 originals and 59.98 generated pairs/s. Its
110-second telemetry window averaged 70.84% GPU busy time and 275.33 W, with
complete coverage. There were no pose mismatches, shutdown was clean and exact
restoration passed. Runtime `C08DA027...` includes the optional refresh patch;
all other listed binaries and eye settings match the 90 Hz trials.

Validation: all six stock cap mappings preserve unrelated and cached settings;
telemetry tests cover timezone conversion, clipped windows, missing readings,
gaps and invalid data. PowerShell parsing and diff checks passed. Evidence is
under `artifacts/unattended/synthetic-framegen-producer-*` and the adjacent
`framegen-producer-*-gpu-20260910.csv` files. No permanent cap was installed.
