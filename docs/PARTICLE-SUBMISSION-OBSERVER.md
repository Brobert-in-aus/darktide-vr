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

## First live capture

Focused accepted-baseline branch `codex/focused-particle-observer-2026-09-11`,
commit `9042fca`, built DLL SHA-256
`796515A86F36658E57BD8D2CAE97D656F8F721168ED1E94BFB3CA2BF120EB7EA`.
The isolated Quality/native mission capture completed with 1,024 readable
snapshots. Calls came from seven renderer threads:

| Batch | Calls | Mean original-helper duration |
| --- | ---: | ---: |
| `gpu_visalizer_emit` | 470 | 1.588 microseconds |
| `gpu_visalizer_sim` | 471 | 1.390 microseconds |
| `gpu_visalizer_render` | 83 | 3.128 microseconds |

This is command preparation, not compute dispatch execution or GPU cost. The
bounded sample spans only three observed Present counters, with partial edges;
worker durations overlap and must not be added as a render-thread frame cost.

No emit/sim object/resource/batch/update-counter combination repeated in these
941 compute preparation records. One render combination repeated with the
update-needed flag changing from one to zero. This gives no evidence for a
safe duplicate-simulation removal in this sample, and is not a whole-frame
census or proof that simulation never repeats.

There were 708 unchanged pending-eye contexts, all labelled eye 1; the other
316 calls had two queued eyes. No strict cross-eye pair could be formed. The
seven-thread preparation explains why application queue tags cannot serve as
view attribution here. A future eye-specific observation needs engine view
identity or command metadata, rather than assigning these workers to the
currently pending capture tag.

The first collector attempt failed to read the actively written launch log
because of incompatible file sharing. No records were admitted in that run;
the reader was corrected and a fresh run completed. Both game sessions exited
cleanly and restored saved files. The successful run had zero pose mismatches;
normal proximity handling and the two temporary probe flags were restored.

Virtual Desktop was actively encoding in all 21 valid GPU activity samples
(one additional sample unavailable). This run's roughly 50 native FPS is not
comparable to the earlier idle-encoding baseline. No performance gain or
regression is attributed to this observer.

Analyze a complete log with `tools/renderer_probe/read-particle-submissions.py
<capture.log> --output <summary.json>`. Three Python reader tests cover complete
capture validation, changed inputs, ambiguous tags and duplicate groups.
Local evidence: `artifacts/unattended/synthetic-particle-submissions-b-20260911`.
Accepted native/viewer defaults remain unchanged.
