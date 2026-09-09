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

A later focused buffer candidate `516f935` (PR #215) builds on `8b3697a` and
adds the point/range caches and conservative bounds only. It is **built, not
staged or deployed**; the original staged plans and their hashes remain unchanged.
Its native DLL and affected executables build; two affected checks pass in
2.76 seconds. The candidate branch contains
`docs/BUFFER-PERFORMANCE-FOCUSED-2026-09-09.md` with scope, commands and DLL hash.
Compare it against `8b3697a` to isolate the added buffer changes, after the first
focused comparison is understood. It excludes later shader, SR, pose and GPU
profiling edits.

Focused map candidate `28a5500` (PR #220) extends the buffer candidate with the
measured resource-pointer cache. Focused Lua projection candidate `e6cb46b`
(PR #217) extends `008e1b0` with the exact-output projection loop optimisation.
Both are separate source/build candidates and leave staged payloads unchanged.
Their candidate branches contain focused validation handoffs. The actual
[mapping measurements](NATIVE-HOOK-PERFORMANCE.md#retained-focused-pointer-cache-candidate)
remain distinct from game frame-time evidence.

The cumulative native extension `24687ff` (PR #224) adds the trace-only upload
lock guard to `28a5500` and is now staged separately as
`native-upload-performance-24687ff`. Its copied-file rollback passes and all
six plans' file preconditions match. Its baseline is accepted native `23345e5`,
so that plan measures the cumulative changes. The original smaller native and
Lua plans remain unchanged. See the [current staged plans](FOCUSED-DIAGNOSTIC-TRIALS-2026-09-09.md).

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
| Billboard pair snapshot sorting | PR #207, [measurements](BILLBOARD-SNAPSHOT-PERFORMANCE.md) | Actual candidate counts and lock contention unmeasured |
| Optional bulk shader snapshot | PR #208, [measurements](BILLBOARD-SHADER-SNAPSHOT-PERFORMANCE.md) | Requires new native export for faster path; older DLL keeps legacy reporting |

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

## Saved runtime trace findings

PR #209 measures temporal overlap from the existing raw-QPC captures. The
non-running-start async idle wait overlaps completed `OVR_BeginFrame` spans
by 99.77% at onset and 99.88% later. This supports the existing runtime-boundary
finding; overlap alone does not identify a backend cause or pair frame IDs.

PR #210 preserves raw runtime statistics and reports both all-sample and
after-first views. The later capture starts with render-CPU value 227,574,800,
raising its mean to 605,959 versus 3,919 after the first sample. Public runtime
source suggests a stale accumulator as a hypothesis; the installed binary has
not been proven to match that source. See [reported statistics](VDXR-REPORTED-STATISTICS.md).
No new capture, runtime setting change, deployment or gameplay check was made.

## Activation scope

The actual Map/Unmap gains are measured with diagnostic hooks enabled. Source
gates leave those hooks off when diagnostics and cluster tracing are both off.
The saved flags audited at 17:08 request the lighting fix, which can use the
same pointer cache in upload-staging updates; that call site is not timed by
the Map benchmark. GPU profiling is also opt-in and its saved enabled token is
currently absent. Keep reductions in instrumented modes distinct from normal
production frame-time claims. See [activation and upload scope](NATIVE-HOOK-PERFORMANCE.md#hook-activation-and-production-upload-path).

## GPU timing report lock scope

The source-only `dtvr_take_gpu_eye_profile` change releases `gpu_profile_mutex`
after harvesting and detaching the eye samples and snapshotting counters and
frequency. Sorting, percentile selection and destruction of that private vector
now run outside the shared lock. The return status uses the captured frequency,
so it describes the same snapshot as the report. Sample ordering, percentile
indices, counter resets and invalid-argument behaviour are unchanged.

This reduces work under the lock by inspection; contention and game FPS effects
have not been measured. No additional allocation or alternate percentile
algorithm was introduced. Windows x64 Release native DLL and hook test executable
build; existing `native_capture_hooks` passes 1/1 in 0.43 seconds with headset tests
OFF. Receipts: `gpu-profile-lock-build-20260909.log` and
`gpu-profile-lock-tests-20260909.log` under `artifacts/unattended`.
This change is outside the staged native performance payload.

## GPU profiling counters

The eight per-eye profiling counter arrays now use ordinary unsigned 64-bit
values under `gpu_profile_mutex`. All accesses were audited: the sole writer is
`harvest_gpu_profile_samples`, called only by `begin_gpu_eye_profile`,
`dtvr_take_gpu_eye_profile` and `dtvr_take_gpu_stage_profile`, each holding that
mutex. The two report readers reset values under the same mutex. Other profiler
flags remain atomic. Removing the redundant atomic increments, exchanges and
maximum CAS loops preserves unsigned arithmetic and snapshot/reset semantics.
Future counter accesses must retain this mutex requirement, documented beside
the declarations.

Windows x64 Release native DLL and hook executable build; existing
`native_capture_hooks` passes 1/1 in 0.44 seconds, headset tests OFF. Receipts:
`artifacts/unattended/gpu-profile-counter-build-20260909.log` and
`gpu-profile-counter-tests-20260909.log`. This is a source-level reduction in
synchronization instructions, without a measured frame-time claim or live
profiling exercise. It remains outside the staged native payload.

## Latest offline checkpoint

At 16:35 Brisbane the read-only Inventory still finds the Quest asleep, one
Virtual Desktop Streamer and no game or launcher processes. No proximity change
or Ready certification. Receipt:
`artifacts/unattended/performance-afternoon-inventory-20260909.json`.
The 20-minute heartbeat remains active; the user has not said home/stop.

PR #211 updates this review map; #212 narrows the GPU report lock scope;
#213 removes redundant atomics from mutex-protected profiling counters;
#214 adds conservative bounds to point lookup; #215 provides the separate
focused buffer build. All remain undeployed. The latest source audit also
retains `dtvr_focused_trace_count` attempt counting because it is an exposed
reporting contract; saturating it as a performance shortcut would change that
information. No new gameplay fixtures or live captures were added.
