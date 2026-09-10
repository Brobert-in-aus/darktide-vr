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
unarmed/exhausted paths, nested timing and invalid address rejection. The
underlying particle recorder's concurrent-bound test also remains available,
but does not itself establish this probe's live engine ABI. Live validation is
pending. Do not deploy the accumulated development DLL; use a focused build.
