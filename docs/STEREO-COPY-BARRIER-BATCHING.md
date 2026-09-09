# Batched stereo input-copy transitions

Continuous stereo capture previously transitioned each input to COPY_SOURCE,
copied it, and restored it before moving to the next input. With four distinct
inputs this emits eight ResourceBarrier calls per eye; optional UI raises that
to ten. The candidate batches independent source transitions before the copies
and restores them in one batch afterwards: two calls per eye when transitions
are needed, zero when every source is already COPY_SOURCE.

All four/five copies, destinations, retained source references, command lists,
fences and retirement rules remain intact. Duplicate source pointers retain the
original per-copy ordering, including restoration between roles. Destinations
are the existing separately allocated COPY_DEST textures. No cross-eye aliasing
or frame-history reuse is introduced.

This follows Microsoft's recommendation to
[batch transitions when possible](https://learn.microsoft.com/en-us/windows/win32/api/d3d12/nf-d3d12-id3d12graphicscommandlist-resourcebarrier).
It reduces API calls, not copied bytes or the number of transitions for distinct
sources. Live CPU/GPU timing is required before claiming a frame-rate gain.

## Validation

Native Release build passes. The isolated WARP test uses real textures and the
D3D12 debug layer, verifies exact copied pixels and restored states over repeated
four/five-input captures, verifies duplicate-source fallback, and checks that
already-COPY_SOURCE inputs emit no barriers. No debug warnings/errors occur.
Together with existing submission, input-lifetime and native hook checks, all
four focused checks pass in 0.62 seconds.

Receipts: `artifacts/unattended/stereo-copy-barrier-{build,tests}-20260910.log`.
Built only; no deployment or basic gameplay verification. Use a focused build
against the accepted native baseline and a successful Ready check before a live
comparison. Keep precise pair waiting enabled for that performance comparison.
