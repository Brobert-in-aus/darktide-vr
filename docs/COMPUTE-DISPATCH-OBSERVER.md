# Bounded compute dispatch CPU observer

Diagnostic only; no queue policy, resources or dispatch arguments change.
The observer measures engine compute-command recording at RVA `7c8410` and
its nested binding helper at `7e21b0`. Both require executable SHA-256
`6FCE8DB87A77A412B22EF9F33F74FA16EF85126CC0FBB24187D78B85FC7A19D3`
and matching in-memory prologues. A missing opt-in flag installs neither hook.

Static call site `7cbc22` supplies context, payload, sort key, alternate-queue
boolean and a fifth 32-bit stack argument. The binding helper receives four
pointers, two stack booleans, a stage integer and root-signature pointer; it
returns a boolean consumed at `7c8528`. The observed original signatures are
forwarded with LastError preserved. This is not a generic hook for other builds.

Create `darktidevr_compute_dispatch.flag` beside the loaded DLL with
`[probe]`, `enabled=1`, `capture=0`; change capture to one only after the matched
mission is ready. The trigger is checked at most once per second. A maximum of
4,096 outer calls are admitted across workers. Binding is timed only inside an
admitted outer call, using thread-local context and an outermost binding guard.
After exhaustion both hooks forward without recording.

Records include worker/context identity, an observed Present counter, kernel
metadata, branch flags, cached root-signature identity before/after, binding
call/success counts and inclusive CPU wall durations. Root-cache equality is
an observation, not proof that every other binding can be skipped. Present
counters do not identify a worker's render frame or eye. Neither duration
measures GPU execution, and nested-hook timing adds overhead inside the outer
interval. Do not interpret duration differences as exact uninstrumented cost.

Output: `%TEMP%/darktidevr-compute-dispatch-<pid>.log`. Require the complete
4,096-record footer. Records are buffered and written after all admitted calls
finish; unavailable metadata remains explicitly invalid. Isolated runs must
restore the exact original flag state and deployed files.

Windows x64 Release build and `compute_dispatch_forwarding` test pass. The test
checks five/eight-argument forwarding, both boolean return values, LastError,
unarmed/exhausted paths, nested timing and invalid address rejection. Eight
concurrent test callers also fill the 4,096-record bound and verify one complete
output. These tests do not establish this probe's live engine ABI. Live validation is
recorded below. Do not deploy the accumulated development DLL; use a focused build.

## First live result

Focused branch `codex/focused-compute-observer-2026-09-11`, commit `653dec4`,
DLL SHA-256 `0BEE5B5EF2052B9D97937E272077A50867316FA2B6CC871020FF9A25AB08C0A6`.
The high-resolution Quality/native simulator mission completed all 4,096
observations across eight threads. Every metadata read and binding succeeded.
All observed commands selected the graphics command list.

Mean outer duration was 7.733 microseconds; mean nested binding duration was
7.144 microseconds. Across the recorded intervals, binding occupied 29.2628 of
31.6755 milliseconds of aggregate worker wall time (about 92.4%). This fraction
identifies the binding path as the next target; it is not a frame-time share,
unperturbed CPU cost or predicted speedup. The maximum outer duration was
356.2 microseconds, so scheduling/outliers also affect the mean.

The sample includes 1,879 particle-emission and 1,816 particle-simulation calls.
Their mean binding durations were 7.090 and 7.070 microseconds respectively.
The cached root identity changed in 1,348 of 4,096 calls. Unchanged roots do
not justify skipping resource binding, transitions or UAV ordering.

Static inspection splits `7e21b0` into calls to `7dec60`, `7db0a0`, `7e0fe0`
and `7dc320`. These routines include resource validation/resolution, constants
and descriptor-table work. Chained unwind records must be included: the entry
ranges of `7db0a0` and `7dc320` contain only prologues. Stage-level timing is the
next diagnostic before considering a narrower caching or binding change.

The mission exited cleanly, restored installed files and probe flags, and
reported zero pose mismatches. Physical readiness was unavailable. The Quest
was placed in standby for this simulator control; 23 valid GPU activity samples
showed no busy Streamer engine, with one unavailable sample. Approximately
74.73 native FPS returned under idle encoding. This differs from the previous
particle observer build and is not a matched performance comparison.

Local evidence: `artifacts/unattended/synthetic-compute-dispatch-20260911`.
The reader is `tools/renderer_probe/read-compute-dispatch.py`; two Python tests
cover complete-record validation, nested timings and unknown metadata.

## Optional binding stages

Set `stages=1` in the opt-in file before launch to install four additional,
exact-prologue-checked hooks at `7dec60`, `7db0a0`, `7e0fe0`, and `7dc320`.
Schema 2 records each stage's wall ticks and call count inside admitted binding
calls only. Stage zero also records its boolean result; the other returns are
unused. The first three forward nine arguments; the final helper forwards five,
including its unused third register slot. Byte flags retain all eight bits.

A thread-local depth guard prevents nested stages being counted twice. The
reader checks that their summed time fits within the measured binding interval
and still accepts schema 1. Additional timers perturb the binding measurement;
compare stage contributions within this instrumented run rather than treating
its absolute durations as a clean-launch benchmark.

The updated forwarding test exercises all stage argument/return/error paths and
the concurrent capture bound. Three reader tests cover schema compatibility,
disabled-stage records and impossible nested timings.

### Live stage result

Focused commit `0f53d13`, DLL SHA-256
`56A5A0861969DD6EB095658063D8C04670174011C59A658F30B359F06F13E721`,
completed 4,096 valid observations across eight threads. Mean outer/binding
durations were 8.318/7.673 microseconds. Stage means were 2.039 (`7dec60`),
0.991 (`7db0a0`), 4.451 (`7e0fe0`) and 0.049 (`7dc320`) microseconds.
The descriptor-binding stage `7e0fe0` occupied about 58% of aggregate binding
wall time. These nested, instrumented worker intervals are not frame-time shares.

Its allocator `7c6150` initializes descriptors individually through
`CopyDescriptorsSimple`, followed by a range `CopyDescriptors` in the caller.
Both APIs currently enter our metadata hooks even with diagnostics disabled,
because stock-menu render-target tracking installs them. Establish the required
heap types and bookkeeping cost before changing engine initialization.

The run exited cleanly with all runner-managed files restored and zero pose
mismatches. It returned 73.30 native FPS; this is an instrumented run, not an
optimization result. There were 21 valid GPU activity samples with no observed
busy Streamer engine and one unavailable sample. Physical readiness remained
unavailable. Evidence: `artifacts/unattended/synthetic-compute-stages-20260911`.
