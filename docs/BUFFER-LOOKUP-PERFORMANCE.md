# Repeated GPU-buffer address lookup

9 September 2026, offline native candidate, undeployed. This change is separate
from the staged three-optimisation native trial `8b3697a`.

`resolve_buffer_resource` scanned the tracked buffer vector backwards on every
query, including repeated constant-buffer addresses used by rendering hooks.
The registry now keeps a bounded 64-slot exact-address cache under its existing
mutex. It stores vector indices, not additional resource references. Hits read
current mapping metadata from the live record. Misses retain the original reverse
scan, including newest-overlap preference and half-open extent checks.

Registration, refresh and owner destruction invalidate every slot. This also
expires cached misses and indices displaced by vector erasure. Registry storage
is private; mapping hooks receive a span so they cannot append/erase behind the
cache. Identity/extent changes remain the responsibility of `track`. The separate
byte-range lookup is unchanged because its overlap/size selection is different.

## Validation and measurement

Windows x64 Release native and lookup test builds pass. `native_capture_hooks`
and `buffer_address_lookup` pass, 2/2 in 0.82 seconds. The latter creates actual
WARP resources with constructed registry addresses and verifies cached miss to
registration, overlap ordering, owner destruction, re-registration, moved indices,
live mapped/unmapped metadata, exact endpoints, collisions and equivalence to
reverse scan across 8,192 queries. All owners are released at the end and the
registry is empty; the cache does not retain them.

Five alternating-order benchmark trials use 1,023 tracked resources and 16
repeated early addresses, 100,000 queries per trial, including the registry lock:
old 35.3970-41.2041 ms (median 38.0049), cached 1.7980-2.1162 ms
(median 1.8084). This is a constructed cache-friendly lookup workload, not a
captured game address distribution or FPS result. Cold/colliding queries still
scan and have cache bookkeeping overhead. No timing threshold is a test gate.

```powershell
cmake --build build/xr-frame-stage-timing --config Release --target darktidevr_native_capture darktidevr-buffer-address-lookup-tests darktidevr-native-capture-tests
build/xr-frame-stage-timing/tests/streamline_stereo_inputs/Release/darktidevr-buffer-address-lookup-tests.exe
ctest --test-dir build/xr-frame-stage-timing -C Release -R 'buffer_address_lookup|native_capture_hooks' --output-on-failure
```

Use Visual Studio 2022 Community bundled CMake/CTest here. Evidence under
`artifacts/unattended`: `buffer-lookup-build-20260909.log`,
`buffer-lookup-build-final-20260909.log`, `buffer-lookup-benchmark-20260909.log`,
`buffer-lookup-tests-20260909.log`. No game, installation, settings or headset
changes. Live workload benefit remains unmeasured and any deployment needs Ready.
