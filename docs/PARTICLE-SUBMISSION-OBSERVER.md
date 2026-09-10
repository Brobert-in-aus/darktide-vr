# Bounded particle submission observer

Optional diagnostic for the exact engine build in
[particle ownership](ENGINE-PARTICLE-STEREO-OWNERSHIP.md). It records the
`GPUVisualizer` kernel-building helper at RVA `564e80`, forwarding all six
arguments unchanged and preserving the original call's LastError result.
The helper's direct callers and stack loads establish four pointer arguments,
a 64-bit sort key and a stack float; all inspected callers discard its return.

The missing/default-disabled flag installs no hook. Explicit enablement requires
the executable SHA-256 and a matching 20-byte in-memory prologue. Registration
uses the existing MinHook installation lifecycle. A requested but unverified
probe fails closed; it does not select another address heuristically.

Place `darktidevr_particle_submission.flag` beside the loaded native DLL:

```ini
[probe]
enabled=1
capture=0
```

An isolated diagnostic run must save this file first and restore its exact
contents or absence afterwards. Once the matched mission and stereo session
are ready, change `capture=1`. The observer polls for this trigger at most once
per second, then records at most 1,024 helper calls. Do not combine this with a
clean performance comparison or deploy the accumulated development DLL.

Each record contains the object, resource and batch tags, update counters,
two parity-selected buffer identities/handles, and 192 bytes of the observed
per-frame constants. Buffers are labelled A/B because their roles vary by
binding; no input/output direction is assumed. Failed or inaccessible reads
discard the snapshot. The probe never writes particle state or reads GPU memory.

It records pending-eye context both before and after the call. These application
tags are not independent proof of GPU eye attribution. Exclude changing/ambiguous
tags when investigating same-update submissions across eyes. Durations enclose
the original command-building helper, including its nested work, not GPU time.

Output is `%TEMP%/darktidevr-particle-submission-<pid>.log`. Records are stored in
separate bounded slots and written once all admitted calls complete. Require
`PARTICLE_COMPLETE samples=1024`; an incomplete file is not a complete census.
Logging and snapshot reads sit outside the measured original-call interval but
still perturb the workload. Later calls use the forwarding-only path.

## Offline validation

Windows x64 Release builds passed with warnings treated as errors. CTest
`particle_submission_snapshot` and `particle_submission_forwarding` passed.
Coverage includes every failed snapshot read, invalid pointers, recovery without
source mutation, unarmed/exhausted forwarding, preservation of stack float bits
and LastError, and eight concurrent callers filling the bound with one complete
output. This does not establish the engine ABI through a live run or a speedup.

Live simulator validation and analysis are the next step. Accepted native/viewer
defaults remain unchanged.
