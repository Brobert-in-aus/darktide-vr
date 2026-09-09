# DLSS SR pending-eye context

The 10 September live scalar capture had two alternating SR feature lifetimes,
but call order alone could not connect either feature to an eye. The optional
SR probe now samples the pending capture-tag queue before input inspection and
after the SR evaluation returns. Each snapshot records queue size, eye/pose for
exactly one queued tag, and arm/reset counters under the existing queue mutex.
The callback releases the mutex before logging or entering NGX.

This is bounded by the existing 64-evaluation process budget and disabled with
the optional SR probe. It adds no GPU copies, parameter writes or rendering
changes. The hook installation receives an immutable context-reader callback;
an absent callback produces an explicitly unavailable record.

Schema 3 adds two `NGX_SR_CONTEXT` records per sampled evaluation. The reader
retains schema 1/2 compatibility and reports context completeness separately from
resource/scalar completeness. `stable_pending_eye_tag` requires identical,
available before/after snapshots with exactly one tag, a valid eye, nonzero pose
and nonzero arm counter. Changed counters, absent end records and ambiguous
queues do not qualify. Even a stable tag **does not prove GPU eye attribution**:
the reader always reports `eye_attribution_verified=false`. Worker scheduling
and unrelated SR work still need to be considered when analysing a live capture.

## Validation and deployment state

Native capture and the SR observation formatter build in Release. Three focused
native checks pass in 0.51 seconds; all ten parser checks pass, including actual
native context formatting, changed eye/pose/counters, missing end observations,
ambiguous queues, unavailable readers and rejected attribution claims. The
saved schema-2 live capture remains readable. No Lua changes or basic gameplay
checks were made.

Receipts: `artifacts/unattended/dlss-sr-eye-context-*-20260910.log`.
This change is built only. The accepted installation remains restored; a new
Ready result and a focused baseline build are required before a live trial.
