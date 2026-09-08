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
census candidate has now completed the bounded capture below.

## 8 September capture

Focused commit `128a50f` (PR #36) ran after Ready passed. Native/Lua startup
agreed, census state stayed 3 (diagnostic + observe, write bit clear), and final
telemetry reported zero direct patches and zero basis patches. The final
identity slice is
`artifacts/unattended/billboard-scene-identities/character-select-20260908-115714.tsv`.
Submission samples are in the game console beginning
`console-2026-09-08-01.57.34-b50223eb-a918-4df1-b7cd-c8b469bd3977.log`.

Between 01:58:26.248 and 02:00:41.171 UTC, 62 samples show:

| VS family | Submission delta |
| --- | ---: |
| `42e436fb1ef1b392` | 14,638 |
| `42f73c7d12e99db7`, `c403cfbf17d9fc49` | 8,314 each |
| `30408e39c8028272`, `e18a274cd89282e8`, `f0c85040e349f799`, `fe64037664924d52` | 7,319 each |
| `9edf5361a4db2da1` | 6,212 |
| `6a0153ef1f6c56fd` | 144 |
| `f1f1510767c58664` | 0 (remained 157) |

Exact VS/PS pairs and counts are saved in
`artifacts/unattended/billboard-submission-deltas-20260908.csv`. The simple
view-basis quad family did not gain observations during this settled sample;
this narrows the next investigation, rather than proving visibility absence.
The ordinary 1920x1080 menu was captured in
`artifacts/unattended/character-select-census-window-20260908/`. Its two BMPs
are left/right halves of a flat desktop image, **not stereo eye captures**.

Offline reconstruction of the eight active non-production VS files is saved
under `artifacts/unattended/billboard-vertex-analysis-20260908`. Three shaders
(`42f73...`, `30408...`, `f0c850...`) use atlas-index-derived clip XY with Z=0,
W=1; their companions use the camera view-projection. Reflection identifies
`r_atlas_index_buffer`. This is evidence of atlas-generation/display families,
so changing all reflected `c_billboard` shaders identically is inappropriate.
Reconstructed HLSL has not been compiled into or deployed as a replacement.

All eight temporary deployment entries were restored through a verified
transaction after another Ready pass. The accepted preview returned to the
Psykhanium with fresh stereo. Integrated commit `0c246d2` builds, and the full
Windows x64 suite passes **147/147 in 61.41 seconds**. No smoke ownership or
worn horizon/size acceptance is claimed.
