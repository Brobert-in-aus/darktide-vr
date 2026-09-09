# Performance review and trial order

The accepted installation is unchanged. These candidates reduce measured
offline CPU/allocation costs; none establishes a game FPS increase or resolves
the sustained VDXR submission slowdown. The user's current instruction is to
continue development without further basic-gameplay verification until home.
The 20-minute heartbeat remains active. Billboarding and pickup sizing still
take priority when the user's worn observations become available; physical
melee remains paused. DLSS blur around HUD items remains open.

## First focused comparisons

| Candidate | Scope | Evidence | Status |
| --- | --- | --- | --- |
| Native `8b3697a`, PR #189 | Exhausted menu diagnostics, short resource names, fixed command snapshots | Actual hook recording: 15 processes/version; diagnostic and name paths faster, control medians similar; identical admitted logs | Staged, copied-file rollback passed |
| Lua `008e1b0`, PR #197 | Prompt/draw result-table removal and HUD follow allocation reduction | Actual module comparisons, preserved error/return/restoration behaviour, exact follow fields; package's 49 chunks compile | Staged, copied-file rollback passed |

Evaluate each separately against its accepted baseline, restoring that baseline
between trials. Use the staged hash preconditions and save the transaction and
rollback receipts. Native UI diagnostics replace the same DLL as native
performance. Communication overlaps the Lua performance prompt module.
The [read-only package report](FOCUSED-DIAGNOSTIC-TRIALS-2026-09-09.md)
checks these overlaps and file preconditions; it does not certify compatibility.

Before any deployment or new live session, run the required Ready preflight.
After Lua deployment, retain the required fresh stereo initialization and nonzero
`shared_ready` checks. These are installation/readiness requirements, not an
additional basic-gameplay validation pass. Keep accepted viewer, settings,
resolution, bindings, scene and capture overhead matched. Report original pairs,
generated pairs and XR submissions separately. CPU call durations include waits;
they are not GPU timings or display latency. No worn acceptance is inferred.

## Source follow-ups outside the staged packages

| Change | Review | Main limitation |
| --- | --- | --- |
| Point-address cache | PR #191, [measurements](BUFFER-LOOKUP-PERFORMANCE.md) | Game hit distribution unmeasured; cold misses retain overhead |
| Native pose normalization | PR #192, [measurements](POSE-MATH-PERFORMANCE.md) | Small floating-point differences; not bit-identical |
| Projection signs/tangents | PR #199, [measurements](PROJECTION-LOOP-PERFORMANCE.md) | Engine value doubles limit timing interpretation |
| Narrow native state copies | PR #202, [measurements](NARROW-COMMAND-SNAPSHOT-PERFORMANCE.md) | Isolated CPU pattern; actual call frequency unmeasured |
| Full-range cache and bounds | PR #204, [measurements](BUFFER-RANGE-PERFORMANCE.md) | Internal gaps still scan; actual hit distribution unmeasured |

Do not deploy accumulated mainline binaries to obtain these changes. Port and
validate a focused candidate first, then compare it separately. Retain the staged
native/Lua payload hashes as recorded; later commits do not silently update them.

## Experiments not retained

The numeric-loop projection rewrite regressed its JIT benchmark; the retained
variant preserves `ipairs`. The scalar hand-pose rewrite reduced interpreter
allocation, but LuaJIT already removed those tables; production code remains
unchanged. See the [hand-pose review](TWO-HAND-ROTATION-PERFORMANCE-REVIEW.md).

The existing stage timing and [VDXR analysis](VDXR-SUBMISSION-SLOWDOWN.md) remain
the route to investigating the sustained submission delay. A fresh-session
restart and these microbenchmarks are not evidence of a fix.
