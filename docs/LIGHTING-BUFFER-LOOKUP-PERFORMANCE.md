# Narrow lighting buffer lookup

10 September. Lighting FOV patch queuing only needs a resource pointer and its
GPU base address, but previously requested a complete 200-byte buffer record,
including diagnostic map-stack storage. It now receives a 16-byte location.
The complete record API remains for consumers that need mapping/staging data.
Both APIs share one internal address lookup, so cache expiry, newest-overlap
precedence and conservative bounds cannot diverge between the two routes.

The caller holds the same registry mutex during lookup and snapshot creation.
Neither snapshot extends the resource lifetime. The patch queue, actual FOV
write, counters and admission rules are unchanged. This caller is eligible in
the production lighting path, unlike diagnostic-only Map/Unmap hooks, but its
actual game frequency and frame-time contribution remain unmeasured.

Five alternating trials of 100,000 queries compare the two APIs with identical
locking and non-inlined return boundaries. Both consume and check the returned
pointer/base; the benchmark includes no GPU submission or game session.

| Workload | Full-record median | Location median |
| --- | ---: | ---: |
| First 16 live resources | 1.6833 ms | 1.4966 ms |
| Newest resource | 1.7801 ms | 1.4815 ms |
| Cycle 1,023 resources | 22.2711 ms | 21.9785 ms |
| Unique out-of-bounds misses | 1.5055 ms | 1.4891 ms |

Early/newest ranges are separated; cycling/miss ranges overlap. These isolate
return-size cost within the refactored registry, not two complete game builds.
The compiler may eliminate other copies at integrated call sites; no FPS claim.

6,144 additional location/full-record comparisons cover present/absent addresses
and boundaries after an index shift. Explicit overlap/expiry cases and the
existing full metadata/lifetime suite pass. Native Release and both affected
executables build; `buffer_address_lookup` and `native_capture_hooks` pass 2/2
in 2.86 seconds. No installed or staged candidate changed.

Windows validation: build targets `darktidevr_native_capture`,
`darktidevr-buffer-address-lookup-tests`, `darktidevr-native-capture-tests` in
`build/xr-frame-stage-timing` Release. Run the buffer executable directly for
all measurements and CTest with
`-R '^(buffer_address_lookup|native_capture_hooks)$' --output-on-failure`.
Receipts: `artifacts/unattended/narrow-buffer-location-{comparison,final-build,tests}-20260910.log`.
