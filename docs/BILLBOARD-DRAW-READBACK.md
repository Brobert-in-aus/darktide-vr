# Bounded billboard draw readback

8 September offline candidate. Three atlas display families remain possible
owners of the reported smoke. A before/after copy can identify affected pixels
without substituting a colored shader or changing tracking. Draw counts alone
do not establish visible ownership.

`BillboardDrawReadback` is a standalone collector, currently linked only into
its offline test. It accepts direct command lists and single-mip, single-slice,
single-sample 2D render targets in R11G11B10_FLOAT, RGBA8 or BGRA8. The caller
must establish an exact RTV in render-target state outside a render pass.
The collector verifies resource shape and matching device; it cannot infer
the caller's command-state proof. Native draw-hook integration remains next.

The collector reserves at most three shader pairs and 32 MiB per image. It
records copies immediately before and after a draw, restoring render-target
state after each copy. Buffers and their command-list/resource owners remain
retained for the collector's lifetime. Production ownership must extend to
process exit or explicit GPU-idle retirement of every referencing recording.
No game shader, descriptor or draw argument is modified.

Readback requires both successful command-list Reset (retiring the recording)
and completion of the last submitted copy fence. Submission is marked before
ExecuteCommandLists and fenced after it returns; an intervening Reset cannot
publish incomplete work. Same-queue replay updates the fence; multi-queue replay
fails closed. Abandoned recordings and incomplete pairs never publish. Failed
Reset must not notify retirement. Device removal or fence failure also prevents
publication. Row padding is zeroed rather than exporting undefined GPU bytes.

The D3D12 WARP fixture executes real texture clears/copies in all three formats,
checks before/after pixels across padded rows, delays a repeated submission
behind a GPU gate, retires it before post-execute bookkeeping, and checks
abandoned, incomplete and multi-queue exclusions. The D3D12 debug layer reports
no errors. Release build and `billboard_draw_readback` pass (0.12 s).

This does not identify the live smoke owner, establish source-state tracking in
Darktide, or accept any orientation correction. Nothing from this candidate is
deployed. The SoloPlay/accepted-preview live session remains running.
