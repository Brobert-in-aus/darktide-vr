# Opt-in billboard submission census

The first-bind identity capture establishes that a PSO occurred in a run, but
cannot rank ongoing submission activity. The optional mod-root file
`darktidevr_billboard_draw_census.flag`, containing `enabled`, now activates the
existing selector observation mode (2) and its counters. Absent/disabled flags
retain the production path. Native bootstrap and Lua both include this request
when selecting the immutable diagnostic hooks.

This does not enable color replacements or descriptor writes. The retired
descriptor-write guard remains hard-disabled, and native tests verify it.
The existing census also observes ExecuteIndirect; counts describe submission
observations associated with the currently classified graphics PSO, not visible
pixels, particles or an exact rasterized-draw count. Indirect work can retain
stale graphics state. Do not infer smoke ownership from a high count alone.

The Lua `billboard_pairs` line now copies a complete ranked native snapshot
under one counter lock. Previously each hash half and count independently
sorted changing counters, which could combine parts of different shader pairs.
The ABI returns explicit 32-bit hash halves and 64-bit counts, with a bounded
capacity. Old exports remain for compatibility.

Windows x64 Release native/bootstrap/tests build. Seven focused CTests pass in
32.77 seconds: 69 actual proxy startup cases, 256 Lua flag combinations, native
snapshot ordering/tie/capacity checks, production write rejection, cached probe
apply/fallback and both Lua gates. Evidence is in this worktree's
`artifacts/unattended/draw-census-tests-20260908.log`.

Deploy only matching focused Lua/native/bootstrap with a verified backup and
Ready preflight. Capture without synthetic tracking or color probes, then
restore the accepted preview and verify fresh Psykhanium shared stereo. This
census candidate has not yet been deployed at this checkpoint.
