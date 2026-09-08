# Bounded billboard draw readback

8 September offline candidate. Three atlas display families remain possible
owners of the reported smoke. A before/after copy can identify affected pixels
without substituting a colored shader or changing tracking. Draw counts alone
do not establish visible ownership.

`BillboardDrawReadback` began as standalone checkpoint `7109841`, PR #45.
The integration candidate now links it into optional native diagnostics.
It accepts direct command lists and single-mip, single-slice,
single-sample 2D render targets in R11G11B10_FLOAT, RGBA8 or BGRA8. The caller
must establish an exact RTV in render-target state outside a render pass.
The collector verifies resource shape and matching device; it cannot infer
the caller's command-state proof. The hook layer requires an observed legacy
transition into render-target state within this exact recording, excludes
active render passes/MRTs, and matches the three stock atlas-display VS/PS
pairs. Aliasing clears evidence; split/other-subresource transitions revoke it;
enhanced barriers and more than 128 tracked resources exclude the recording.
Successful Reset clears state evidence. Implicit/inherited states are not guessed.

The collector reserves at most three shader pairs and 32 MiB per image. It
records copies immediately before and after a draw, restoring render-target
state after each copy. Buffers and their command-list/resource owners remain
retained for the collector's lifetime. Production ownership must extend to
process exit or explicit GPU-idle retirement of every referencing recording.
No game shader, descriptor or draw argument is modified. Copies bracket only
direct DrawInstanced/DrawIndexedInstanced calls, before optional UI replay.
ExecuteIndirect and atlas-generation shaders are excluded.

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

To arm, start with the separate draw-census flag, then use
`/dtvr_billboard_readback`, or add `darktidevr_billboard_readback.flag` containing
`enabled` before startup. The readback flag does not install hooks; the native
entry rejects missing census, render-pass or enhanced-barrier hooks. It permits
one session per process, at most three pairs, with a 120-second capture window.
The native module is pinned and the bounded collector lives to process exit.
All files are written off the game thread beneath the temporary directory's
`darktidevr-billboard-readback-PID-TICK` folder. Completed per-pair JSON is written
after both payloads. `session.json` reports how many pairs exported; zero is
absence of evidence. An export-error file invalidates incomplete output.

`tools/stereo/analyze-billboard-readback.py INPUT OUTPUT` validates completed
footprints, decodes the three formats, writes before/after/difference PNGs and
an analysis receipt with hashes, changed-pixel counts and bounds. HDR preview
tone mapping is for display only; numeric differences use decoded values.
NaN/infinity pixels are reported separately. The optional NumPy/Pillow fixture
checks known normal/subnormal values, all formats, row padding and short-file
rejection. The full integrated Release suite passes 150/150 in 64.00 s; pinned
LuaJIT compiles all 50 chunks.

This does not yet identify the live smoke owner or accept an orientation fix.
No readback candidate is deployed. The SoloPlay/accepted-preview session remains
running while the focused diagnostic build is prepared.
