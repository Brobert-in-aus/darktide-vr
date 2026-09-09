# GPU profile percentile selection — 10 September 2026

The eye-profile report previously sorted all detached durations to read its p50
and p95 ranks. It now selects the median, then selects p95 from the upper
partition. Reports of 32 samples or fewer retain sorting. Empty output, integer
rank rounding, sample harvesting, counters, and the lock boundary are unchanged.
The p95 index uses quotient/remainder arithmetic to avoid size multiplication
overflow. Only the detached vector is mutated.

Windows x64 Release validation:

```powershell
cmake --build build/xr-frame-stage-timing --config Release --target darktidevr_native_capture darktidevr-profile-percentile-tests darktidevr-native-capture-tests
ctest --test-dir build/xr-frame-stage-timing -C Release -R '^(profile_percentiles|native_capture_hooks)$' -V
```

Both checks passed in 3.80 seconds. The comparison checks exact agreement with
the old sort for every size 0–4096, using random 64-bit values, repeated values,
sorted/reversed values, and all-maximum values: 20,485 cases.

Five alternating timing trials use the same non-inlined call boundary, preallocated
scratch storage, identical input copying, and consumed results. Median milliseconds
for 2,000 reports:

| Samples | Full sort | Selected ranks |
| --- | ---: | ---: |
| 16 | 0.0405 | 0.0424 |
| 120 | 0.6944 | 0.3619 |
| 1,024 | 8.5166 | 2.8004 |
| 8,192 | 483.984 | 33.0927 |

These timings repeat one seeded random input per size; they do not model live
sample distributions or establish frame-time/FPS savings. Small reports retain
the same sort, with a small extra dispatch cost. The change is built, not deployed.
Receipts are local `artifacts/unattended/profile-percentiles-{build,tests}-20260910.log`.
The initial all-selection experiment is retained in
`profile-percentiles-comparison-20260910.log`; its 16-sample result motivated the
small-report fallback.
