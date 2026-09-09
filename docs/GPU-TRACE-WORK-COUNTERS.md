# Unknown GPU work counters

Older GPU batch traces contain timing and command-list identity but omit draw,
dispatch and other work counters. The analyzer previously defaulted omitted
fields to zero, making a timed render segment appear to contain no work.

Omitted counters now remain JSON `null` and render as `unknown` in Markdown.
Missing indexed or non-indexed draws make the combined draw count unknown.
Unknown values propagate through a batch and its render segment; unrelated
complete counters remain available. A missing declared command list also makes
its batch totals unknown. Explicit zeros, including a declared empty batch,
remain zero. Negative or overflowing native counters are rejected.

The existing regression script passes with additional legacy, partially missing,
multi-batch, missing-list, explicit-zero and invalid-counter cases. Reprocessing
the 1 September trace preserves its 24 batches, 6.958944 ms timing and PSO
comparisons while correctly showing unknown work counts. Counter availability
does not independently invalidate complete timing evidence.

Validation: `python tools/stereo/test-analyze-gpu-batch-trace.py`.
Local receipts: `artifacts/unattended/gpu-work-count-availability-*-20260910.*`.
No native/Lua code, deployment or gameplay validation changed.
