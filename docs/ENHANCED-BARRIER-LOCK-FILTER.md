# Enhanced-barrier capture lock filtering

11 September 2026. The enhanced D3D12 barrier hook previously locked shared
capture bookkeeping for every nonempty texture-barrier batch. With resource
diagnostics disabled, the protected loop only records swapchain PRESENT
transitions; other texture layouts do not modify its state.

The admission scan now checks for PRESENT before taking the lock, or admits any
texture batch when resource diagnostics are active. PRESENT aliases COMMON, so
COMMON remains conservatively admitted. Buffer/global batches, null groups and
empty texture batches need no capture lock. Existing readback invalidation,
focused counters and cluster observations run before this filter. Every original
Barrier call is still forwarded once with the original arguments. No barriers,
GPU operations, ownership rules or resource lifetime are changed.

Windows x64 Release native build passes. `enhanced_barrier_interest` and
`native_capture_hooks` pass 2/2 in 0.48 seconds. Coverage includes mixed groups,
late PRESENT, COMMON aliasing, diagnostic override and empty/null arrays.

```
cmake --build build/xr-window-capture-demand --config Release --target darktidevr_native_capture darktidevr-enhanced-barrier-interest-tests
ctest --test-dir build/xr-window-capture-demand -C Release -R '^(enhanced_barrier_interest|native_capture_hooks)$' --output-on-failure
```

Do not deploy the accumulated native build or infer a speedup merely from
removing a lock. Use the focused candidate for any further comparisons.

Focused revision `4354209` applies only this filter to `10550a4`; its native
diff is the helper include and lock-admission replacement. Build directory
`build/focused-enhanced-barrier-filter`, DLL SHA-256
`3871870004D4F47D52E4FA14D3949FD710FB79077EB0578FAC987417393FB29C`.
Focused native/interest tests pass 2/2 in 0.64 seconds. The first configure
encountered cherry-pick markers; they were resolved without importing the
accumulated diagnostics, then configuration, compilation and checks passed.

The focused Quality mission trial delivered 89.39994 native FPS over 76.51
selected seconds, versus repeated ring controls of 89.56705 and 89.34302. This
does not demonstrate a throughput gain. All files were restored, the session
exited cleanly and pose mismatches remained zero. GPU observation has 32 valid
and two unavailable records, with no Streamer activity in valid records.
Evidence: `artifacts/unattended/synthetic-descriptor-demand-barrier-filter-a-20260911`.
Actual enhanced-barrier call frequency was not separately instrumented; the
result does not establish that this removed a significant live workload.
Keep the candidate separate from the proven descriptor/ring improvement.
