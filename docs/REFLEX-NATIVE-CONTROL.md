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
