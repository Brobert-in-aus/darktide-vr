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
