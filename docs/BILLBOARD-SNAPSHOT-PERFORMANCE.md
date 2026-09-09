# Billboard counter snapshot performance

The bulk shader-pair export copies its counter map under the existing mutex,
then releases the mutex before ranking and packing the private records. Render
threads no longer wait for that sort. The full map copy remains inside the lock
to retain a coherent snapshot; hash halves and counts cannot come from different
ranking epochs. No GPU shader, billboard transform or draw behaviour changes.

When output capacity is smaller than the candidate set, only that sorted prefix
is selected with `partial_sort`. Full-capacity output retains `sort`. The ordering
is unchanged: count descending, then the complete vertex/pixel key ascending.
An empty output returns immediately.

Windows x64 Release, five alternating trials, 1,000 reads of up to 32 samples:

| Candidate pairs | Original median | Candidate median |
| --- | ---: | ---: |
| 8 | 0.0605 ms | 0.0647 ms |
| 32 | 0.2923 ms | 0.3226 ms |
| 128 | 1.3114 ms | 0.9263 ms |
| 1,024 | 15.9817 ms | 7.9448 ms |
| 4,096 | 153.3840 ms | 24.8385 ms |

The benchmark includes map copying, locking, ranking and packing. Small-set
differences are tiny in absolute terms; no universal speedup is claimed. The
actual game candidate count, polling frequency and contention were not measured.
These results describe diagnostic snapshot work, not game FPS or GPU timing.

The comparison covers zero/small/full/truncated capacities, count ties, high hash
bits, and ownership after the source map is cleared. Full output prefixes match
the original implementation. The native DLL and both affected test executables
build; native hooks and shader-pair snapshot checks pass 2/2 in 1.50 seconds.
No deployment; this is outside the staged focused native performance payload.

Ignored receipts: `artifacts/unattended/shader-pair-performance-{build,benchmark,tests}-20260909.log`.
