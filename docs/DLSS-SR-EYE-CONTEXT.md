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

## Simulator result

The schema-4 simulator capture in `synthetic-sr-conventions-20260910` completed
all 64 before/after context records. None qualified as a stable single pending
eye tag: before-evaluation queue sizes were two (12 observations), three (32)
or four (20). Two feature lifetimes still alternated with 32 samples each, but
the queue's asynchronous backlog does not identify which eye owns either one.
No eye label is inferred from call order or the front of an ambiguous queue.
Further attribution needs a render-command or camera linkage; repeating this
same queue-only probe would not resolve ownership.

## Synchronous Streamline context

Schema 5 adds one `NGX_SR_STREAMLINE` record per sampled SR evaluation. With the
optional SR probe enabled, an API hook stores a thread-local context during
`slEvaluateFeature`. Only feature zero, one readable input, and a matching
version-1 viewport structure qualify. It copies the numeric viewport, frame
token pointer, command-buffer pointer and observation sequence; it never
retains the input structure pointer. Guarded reads reject inaccessible metadata.
Nested calls replace and restore context, including unrelated features.

The reader accepts schemas 1–5 and separately reports record presence,
availability and matching command buffers. A matching synchronous context
links the NGX feature lifetime to a Streamline viewport; it does not name an
eye, validate the camera, establish GPU completion or prove image quality.
Missing hooks, unsupported input shapes and asynchronous evaluations remain
explicitly unavailable. The hook is installed only for the optional SR probe,
and record output remains within the existing 64-evaluation process budget.

Windows Release builds and the native scope test passed, including nested
context restoration during exception unwinding. Twelve reader tests cover the
actual native formatter, missing/unavailable/mismatched context, duplicate and
malformed records, numeric bounds, older schemas and rejected attribution
claims. The official pinned Streamline ABI comparison also passed.

The 30-second simulator trial used focused native `c58b94e`, DLL SHA-256
`53904CFD2662141C66F8B9712E6D25709BDDF92530B8AE2CB5B69D54D9530DCA`.
All 64 schema-5 records had available synchronous context: lifetime 2 always
appeared inside viewport 920637560, lifetime 3 inside viewport 3367681085, with
32 observations each. All direct command-pointer comparisons failed; the API
layers supplied different addresses. An SL proxy is a plausible explanation,
but no native-interface identity check was made. The pinned SDK documents
`slGetNativeInterface` as not thread-safe, so it was not injected into these
worker-thread evaluations. The nested call association is recorded separately
from command identity and still does not identify a physical eye.

The consumer submitted 1,309 fresh and 1,279 generated pairs with zero reported
pose mismatches, stopped cleanly and restored all saved files. Five focused
native checks and all twelve reader tests passed with the focused formatter.
Evidence: `artifacts/unattended/synthetic-sr-streamline-context-20260910`.

The [11 September native-interface follow-up](DLSS-SR-NATIVE-COMMAND-IDENTITY.md)
resolved the proxy/native mismatch in all 64 sampled calls through the SDK's
documented QueryInterface mechanism. No rendering behavior was changed.
