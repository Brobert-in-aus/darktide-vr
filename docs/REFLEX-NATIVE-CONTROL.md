# Reflex native-only scheduling control

Native mission throughput stayed near 74 FPS after reducing DLSS input
resolution and after confirming a real six-to-four worker-pool change. The
next control checks whether Reflex scheduling contributes to that ceiling.

The benchmark accepts `-Reflex Preserve|On|Off`, defaulting to Preserve. On maps
the master selection to 1, low-latency mode to true and boost to false. Off maps
selection 0 and disables mode/boost, matching the installed stock options Lua.
Markers remain unchanged. Off requires FG off and Reflex Warp already disabled.
The master selection and render settings change together; detected-settings
caches remain intact and the exact settings file is restored after the trial.

Settings fixtures pass for on/off mapping, cache preservation, missing/duplicate
fields, and incompatible FG/Warp rejection. The runner parses successfully.
Compare the unchanged native baseline at the same mission start, DLSS Quality,
worker setting, unlimited cap and 120 Hz simulator. Throughput alone will not
establish input latency or justify changing the accepted default.

The completed 120-second Reflex-off trial delivered 73.94 native pairs/s over
110.36 analyzed seconds, with 63.00% GPU busy time and 269.08 W board power.
The preceding matching Reflex-on Quality control delivered 74.12 pairs/s,
63.05% and 267.83 W. This comparison shows no throughput benefit from disabling
Reflex. The live settings file confirmed mode off during the trial. Fresh
readiness, clean exit and exact restoration passed; Reflex on remains accepted.
Evidence: `synthetic-solo-reflex-off-a-20260910` in ignored unattended artifacts.
