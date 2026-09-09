# Buffer range lookup performance

Tracked buffer copying now uses an exact address-and-length cache. A separate
64-entry cache preserves the existing point-lookup path. Full-range reads keep
the newest allocation that contains the entire range; a newer, smaller overlapping
allocation does not hide an older allocation that fits. The newest allocation
is checked before hashing. Cache entries store indices, not mapping metadata or
owning resource references. Registration, refresh and destruction invalidate
them; Map/Unmap and staging changes remain visible through current records.
Conservative minimum/maximum address bounds reject requests outside the tracked
envelope before hashing/scanning. Bounds expand on registration and reset when
empty; removing an extreme allocation can only leave extra scans, never a false
rejection. The upper endpoint saturates at the integer maximum and includes
zero-length one-past reads. Gaps inside the envelope still use normal selection.

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
| Repeated 16 early allocations | 47.6754 | 1.8156 |
| Newest allocation | 1.4581 | 1.4753 |
| Cycle through every allocation | 25.3902 | 17.6438 |
| Unique misses above the envelope | 49.0400 | 1.4670 |
| Unique misses in internal gaps | 52.6048 | 46.3112 |

Repeated reads and out-of-envelope misses benefit substantially. Internal-gap
misses still scan; ranges overlap (45.55-56.14 versus 45.78-50.81 ms), so their
median difference does not establish a robust improvement. The initial variant
without bounds cost about 5.8% more on unique high misses; those earlier receipts
are retained. The cache adds bounded storage, and no game hit rate or
FPS improvement is claimed. Results include lookup/metadata copying, not the
subsequent memory copy or rendering. The existing point-lookup implementation
is unchanged.

Validation compares 20,480 address/length combinations with the original scan
for non-overflowing inputs. It also checks different lengths at one address,
overlap winners, endpoint/zero-length reads, overflow rejection, destruction,
refresh, moved indices, saturated bounds with an older extreme allocation, retired
extremes, and live mapped/staging metadata on cached older entries.
Native Release builds; buffer lookup and native hooks pass 2/2 in 2.73 seconds.
No deployment; this is outside staged focused native candidate `8b3697a`.

Receipts under ignored `artifacts/unattended/`:
Final: `buffer-range-bounds-{build,benchmark,test-build,tests}-20260909.log`.
Earlier variant: `buffer-range-performance-{build,benchmark,test-build,tests}-20260909.log`.
