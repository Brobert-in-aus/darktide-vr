# Existing dispatch category costs

The exact engine build documented in ENGINE-DISPATCH-JOB-LAYOUT.md already
times dispatched command bundles. Callback `7a6ac0` invokes `7cb490`, which
selects a category from each 32-byte bundle descriptor's flags at `+18`:

| Category | Selection, in precedence order |
| --- | --- |
| 3 | Sign bit set |
| 2 | Otherwise bit `0x20` set |
| 1 | Otherwise bit `0x4` set |
| 0 | Otherwise |

At `7d0040`, elapsed clock ticks are converted using frequency and a millisecond
scale, added to the selected record, and its counter incremented once per
bundle. A bundle can contain several commands. These counters are not draw-call
counts. The callback separately records total job elapsed time when enabled.
The caller merges per-job records through `7a5d20` after the dispatch wait.

The bounded sampler now reads four aggregate 16-byte records through dispatcher
`+b0` (count) and `+b8` (data), only at the previously verified wait and only
when the count is exactly four. It preserves the existing executable-hash gate
and performs no target writes. Failed category reads remain explicitly absent.
The reader rejects nonfinite/negative costs and implausible counts, and accepts
older captures without category columns.

## Mission diagnostic

The 1,000-sample capture returned 78 valid category snapshots. Cost ranges in
the engine's accumulated units were 0–0.7626, 0–4.1069, 0–10.4932 and 0–4.2695
for categories 0–3. Corresponding bundle-count ranges were 0–1,801, 0–706,
0–1,172 and 0–2,034. Category 2 is a useful lead, but repeated snapshots are
not independent frame measurements or CPU-time shares. Do not name a rendering
pass from these flag values without tracing the descriptor producer.

The [11 September command/branch follow-up](ENGINE-DISPATCH-BUNDLE-COMMANDS.md)
identifies compute-command preparation on the graphics queue for all 121
sampled category-2 first commands. This narrows the target without converting
the historical aggregate costs into per-frame or CPU-time shares.

Mean sampler pause was 53.33 microseconds, p95 115.7 and maximum 300.0.
The simulator mission run exited cleanly and restored all files. Native build
and `thread_residency_self` passed, including preservation of a pre-existing
suspend count. The reader successfully processed both the new capture and the
earlier layout capture without category fields.

Ignored local evidence under `artifacts/unattended`:
`synthetic-solo-dispatch-categories-a-20260910/thread-residency`,
`engine-dispatch-job-callback-20260910.txt`,
`engine-dispatch-job-collect-20260910.txt`, and
`engine-dispatch-job-timing-merge-20260910.txt`.
