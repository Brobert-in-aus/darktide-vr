# Residency function-mapping correction

The residency reader used `starts` for both its PE unwind-function index and
dispatch chunk boundaries. After the first valid chunk record, the function
lookup closure searched the chunk positions instead of function addresses.
Subsequent function-owner labels, including caller/peer owner labels, could
therefore be wrong or reported as unmapped.

The two arrays now have distinct names. Raw instruction addresses, module
attribution, exact dispatch-wait admission, chunk/category/command observations,
pause measurements and FPS counters were not derived from the overwritten
index and are unchanged. Older captures without admitted chunk records were
not affected by this collision.

A two-observation fixture exercises the complete reader with a synthetic PE
unwind table and a valid chunk record between lookups. It reproduces the old
failure (the second wait becomes unmapped) and passes with the fix. The four
bundle-reader tests also pass. No game launch was needed for this correction.

Three local captures contain admitted chunk records and were reprocessed from
their original CSV/receipt/module data. Prior summaries were retained separately.

| Capture | Samples | Valid chunk records | Corrected main wait owner observations |
| --- | ---: | ---: | ---: |
| 10 September dispatch chunks | 1,000 | 79 | 138 |
| 11 September bundle opcodes | 1,000 | 73 | 119 |
| 11 September kernel routes | 1,000 | 88 | 139 |

These remain instruction-residency observations, not CPU-time shares. Some
addresses legitimately have no unwind entry; the fix does not invent owners
for those. Aggregate correction receipt:
`artifacts/unattended/residency-unwind-corrections-20260911.json`.
