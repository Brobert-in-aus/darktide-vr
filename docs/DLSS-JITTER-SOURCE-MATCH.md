# DLSS jitter source comparison

All 64 SR evaluations in the 10 September capture exactly match the installed
engine's 32-entry jitter table, including its Y sign inversion. The sequence is
`8,8,9,9,...,31,31,0,0,...,7,7`: paired evaluations share an entry and advance
once per pair. This capture does not exhibit a jitter sequence advancing once
for each eye. No jitter replacement or reset change is justified by this result.

## Evidence

The `upscale_pass` preparation function has unwind primary RVA `373e50`.
At `373fc3` it loads a context field, masks the index to five bits at `373ff4`,
and reads an eight-byte pair from table RVA `1102130` at `374035`/`374040`.
The second float has its sign flipped at `37404d`. Comparing those 32 float
pairs against the saved SR scalar observations produced 64 exact matches,
without a tolerance or rounding transformation.

Executable SHA-256:
`6fce8db87a77a412b22ef9f33f74fa16ef85126cc0fbb24187d78b85fc7a19d3`.
Capture source SHA-256:
`f3e0e386897344a87d6d776c6109f76b0668954d5d90be83fbcaf4292ef0115a`.
See [the original capture](handoffs/2026-09-10-sr-input-capture.md) for scope.

The freshly verified renderer configuration declares `upscaling_instance` in
the default viewport's resources. Its named previous-depth/motion resources
and copy passes are specifically gated to PS5 MFSR. Their presence in the
configuration is not evidence that Windows DLSS has those extra copies or that
removing them would save time. Windows SR history must be investigated through
its actual upscaling context and NGX feature lifetime.

This is an offline comparison of an existing capture, not another gameplay
check. It does not establish eye attribution, correct projected motion,
history contents, or a fix for blur around HUD items. The pending-eye candidate
and subsequent motion-history analysis remain separate work.

Ignored receipts: `engine-upscale-history-map-20260910.json`,
`engine-upscale-functions-20260910.txt`, and
`engine-jitter-table-comparison-20260910.json` in `artifacts/unattended`.
No game asset, binary, setting or running process was modified.
