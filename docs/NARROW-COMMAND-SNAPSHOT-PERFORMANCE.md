# Narrow command-state copies

The cluster-light visibility path consumes only graphics CBV addresses 0 and 2.
It now snapshots those two values (16 bytes) under the existing trace lock instead
of all 2,896 bytes of fixed command state. The stock menu redirect similarly
copies only its original target (8 bytes). Existing admission checks remain under
the same lock, and buffer order, ownership, counters and redirect restoration
are unchanged. Other consumers still use their full snapshots.

The existing command-snapshot executable now measures the full versus narrow
local-copy pattern with identical non-inlined function boundaries, lock scopes,
16-byte return values and result checks. Both select indices 0 and 2. The full
snapshot does not escape the baseline function, so the compiler can eliminate
unused fields if capable; this does not force a full-copy output for the baseline.

Windows x64 Release, five alternating trials, 100,000 reads: median full-copy
2.6584 ms versus narrow-copy 1.1712 ms (ranges 2.5839-2.9966 and 1.1594-1.2117).
The menu scalar path is not separately benchmarked. This is an isolated CPU
measurement; actual game call frequency and frame-time impact are unmeasured.

Native Release builds. Focused command-snapshot and native-hook checks pass.
No deployment, game launch or visual acceptance. This change is outside the
staged focused native performance payload `8b3697a`.

Local receipts: `artifacts/unattended/narrow-command-snapshot-{build,benchmark,tests}-20260909.log`
and `artifacts/unattended/narrow-command-native-build-20260909.log`.
