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

Live frequency and throughput benefit are unmeasured. Do not deploy the
accumulated native build or infer a speedup merely from removing a lock. Use a
focused candidate on the repeated native-ring baseline for comparison.
