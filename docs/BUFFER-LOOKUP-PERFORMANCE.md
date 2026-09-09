# Repeated GPU-buffer address lookup

9 September 2026, offline native candidate, undeployed. This change is separate
from the staged three-optimisation native trial `8b3697a`.

`resolve_buffer_resource` scanned the tracked buffer vector backwards on every
query, including repeated constant-buffer addresses used by rendering hooks.
The registry now keeps a bounded 64-slot exact-address cache under its existing
mutex. It stores vector indices, not additional resource references. Hits read
current mapping metadata from the live record. The newest buffer is checked
before hashing, preserving the already-cheap tail case. Misses retain the original reverse
scan, including newest-overlap preference and half-open extent checks.

Registration, refresh and owner destruction invalidate every slot. This also
expires cached misses and indices displaced by vector erasure. Registry storage
is private; mapping hooks receive a span so they cannot append/erase behind the
cache. Identity/extent changes remain the responsibility of `track`. The separate
byte-range lookup is unchanged because its overlap/size selection is different.

## Validation and measurement

Windows x64 Release native and lookup test builds pass. `native_capture_hooks`
and `buffer_address_lookup` pass, 2/2 in 1.54 seconds. The latter creates actual
WARP resources with constructed registry addresses and verifies cached miss to
registration, overlap ordering, owner destruction, re-registration, moved indices,
live mapped/unmapped metadata, exact endpoints, collisions and equivalence to
reverse scan across 8,192 queries. All owners are released at the end and the
registry is empty; the cache does not retain them.

The final comparison uses identical non-inlined lookup/lock boundaries so both
return complete metadata. Earlier inlined measurements allowed the compiler to
specialise pointer-only checks differently; use this final receipt when comparing
workloads. Five alternating-order trials, 1,023 resources, 100,000 queries each:

| Constructed workload | Old median | Final median |
| --- | ---: | ---: |
| 16 repeated early addresses | 43.3195 ms | 1.7254 ms |
| Repeated newest allocation | 1.3266 ms | 1.2705 ms |
| Cyclic access across all records | 22.6544 ms | 22.2357 ms |
| Unique missing addresses | 45.8822 ms | 46.3814 ms |

Newest/cold differences are small relative to variation and do not establish a
speedup. Unique misses retain scan cost plus cache overhead. The repeated-address
saving is clear in this constructed cache-friendly workload; actual game address
distribution and FPS benefit remain unmeasured. No timing threshold is a test gate.

```powershell
cmake --build build/xr-frame-stage-timing --config Release --target darktidevr_native_capture darktidevr-buffer-address-lookup-tests darktidevr-native-capture-tests
build/xr-frame-stage-timing/tests/streamline_stereo_inputs/Release/darktidevr-buffer-address-lookup-tests.exe
ctest --test-dir build/xr-frame-stage-timing -C Release -R 'buffer_address_lookup|native_capture_hooks' --output-on-failure
```

Use Visual Studio 2022 Community bundled CMake/CTest here. Evidence under
`artifacts/unattended`: `buffer-lookup-build-20260909.log`,
`buffer-lookup-build-final-20260909.log`, `buffer-lookup-benchmark-20260909.log`,
`buffer-lookup-tests-20260909.log`. Final expanded evidence:
`buffer-lookup-tail-build-20260909.log`, `buffer-lookup-boundary-build-20260909.log`,
`buffer-lookup-boundary-workloads-20260909.log`, `buffer-lookup-final-tests-20260909.log`.
No game, installation, settings or headset
changes. Live workload benefit remains unmeasured and any deployment needs Ready.

## Reuse conservative bounds for point misses

The point resolver now shares the conservative address envelope introduced for
full-range reads. It checks the newest allocation first, then rejects addresses
below the minimum start or above the saturated maximum end before hashing or
scanning. Retired extremes can only permit extra scans. The inclusive upper
bound preserves an older overflowing extent containing `UINT64_MAX`; a focused
assertion checks that case with a newer low allocation. Existing registration,
expiry and empty-registry resets maintain the envelope. Internal gaps still scan.

The existing Windows x64 Release comparison passes all overlap, lifetime,
metadata and reverse-scan equivalence checks. Five alternating trials of 100,000
point queries against 1,023 WARP-backed records report these median milliseconds:

| Workload | Original reverse scan | Current cache with bounds |
| --- | ---: | ---: |
| Repeated 16 early allocations | 44.3063 | 1.7134 |
| Newest allocation | 1.2915 | 1.2571 |
| Cycle every allocation | 21.5423 | 16.7608 |
| Unique misses above the envelope | 45.4019 | 1.1590 |

This table compares the original scan with the complete current cache, not the
incremental bounds change alone. The previous unbounded-cache result for unique
high misses was 46.3814 ms in an earlier run, so it is historical context rather
than a matched incremental timing comparison. No game hit distribution or FPS
claim follows from this constructed workload.

Native DLL and both affected test executables build. The lookup executable
passes directly; `native_capture_hooks` passes 1/1 in 0.47 seconds, headset tests
OFF. Receipts: `artifacts/unattended/point-buffer-bounds-build-20260909.log`,
`point-buffer-bounds-benchmark-20260909.log` and
`point-buffer-bounds-hook-tests-20260909.log`. No deployment or staged payload
update was made.
