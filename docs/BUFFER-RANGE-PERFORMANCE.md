# Buffer range lookup performance

Tracked buffer copying now uses an exact address-and-length cache. A separate
64-entry cache preserves the existing point-lookup path. Full-range reads keep
the newest allocation that contains the entire range; a newer, smaller overlapping
allocation does not hide an older allocation that fits. The newest allocation
is checked before hashing. Cache entries store indices, not mapping metadata or
owning resource references. Registration, refresh and destruction invalidate
them; Map/Unmap and staging changes remain visible through current records.

Containment uses subtraction after checking bounds. The previous
`offset + byte_count` expression could wrap and admit an invalid huge range;
such requests now fail. Zero-length reads at the resource end retain the old
selection rule. Copying, source preference, result flags and locking are unchanged.

Windows x64 Release benchmark: WARP resources with constructed addresses,
1,023 retained records, 100,000 queries, five alternating trials. Both variants
have identical non-inlined lock boundaries and full metadata returns. Each
request spans 128 bytes. Medians in milliseconds:

| Workload | Reverse scan | Range cache |
| --- | ---: | ---: |
| Repeated 16 early allocations | 51.2365 | 1.9242 |
| Newest allocation | 1.4532 | 1.4770 |
| Cycle through every allocation | 24.5319 | 22.5509 |
| Unique misses | 46.8489 | 49.5613 |

Repeated reads benefit substantially; cold misses cost about 5.8% more in this
constructed workload. The cache adds bounded storage, and no game hit rate or
FPS improvement is claimed. Results include lookup/metadata copying, not the
subsequent memory copy or rendering. The existing point-lookup implementation
is unchanged.

Validation compares 20,480 address/length combinations with the original scan
for non-overflowing inputs. It also checks different lengths at one address,
overlap winners, endpoint/zero-length reads, overflow rejection, destruction,
refresh, moved indices, and live mapped/staging metadata on cached older entries.
Native Release builds; buffer lookup and native hooks pass 2/2 in 2.45 seconds.
No deployment; this is outside staged focused native candidate `8b3697a`.

Receipts under ignored `artifacts/unattended/`:
`buffer-range-performance-{build,benchmark,test-build,tests}-20260909.log`.
