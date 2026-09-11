# Stereo shadow reuse investigation

The shared shadow-culling camera makes cascade reuse worth investigating, but
does not establish that the second eye's entire shadow stage can be skipped.
The installed renderer separates shadow-map generation from a depth-dependent
screen-space mask. The latter must remain per-eye.

## Asset evidence

On 10 September, the installed bundle `209fb8c3c0a8c3a4` was freshly extracted
with the local `dtex` tool and decoded with `decode-render-config.py`. The
193,700-byte render-config resource matches the earlier extraction exactly:
SHA-256 `3B64F1BED384CB2A6ECDA727B5D75E56C0475A0F5C92A21F58DF198D34E1487D`.
No same-prefix bundle patches were present. A full installed-bundle index scan
found exactly one `render_config` entry, in that bundle. This verifies the inspected asset,
not live resource identities or active settings.

The configuration establishes these dependencies:

| Stage | Outputs or dependencies | Reuse implication |
| --- | --- | --- |
| Global sun resources | `sun_shadow_map` and dependent `shadow_map_color`, both transient | A global name does not prove storage survives or remains unchanged between eye renders. |
| Cascade generation | Four atlas quadrants; first slice clears, remaining slices do not | Reuse must account for the complete atlas and clear sequence. |
| Cascade exports | Per-slice world-to-shadow, view-projection, scale, bias, near/far and viewport bounds; shared rotation | Keeping pixels without restoring the corresponding bindings is insufficient. |
| Sun shadow mask | Each slice reads the atlas with `depth_stencil_buffer` and writes transient `shadow_mask` sized from `output_rt` | Keep mask construction tied to the eye's depth and output. |
| Local-light shadows | Separate cached atlas generator and registry | Do not fold this into sun-cascade reuse without independent analysis. |

The Lua setup assigns the tracked primary camera as both viewports'
`shadow_cull_camera`. That is an existing parity measure, not proof that all
cascade inputs are identical. The native cascade wrapper at RVA `417f50`
resolves and normalizes light direction before calling `419910`. Thus camera
identity alone omits at least light/environment inputs from a prospective key.
See the executable hash and unwind ownership in
[the engine investigation](STEREO-ENGINE-PERFORMANCE-2026-09-10.md).

## Conditions before a reuse implementation

A useful live capture must establish repeated cascade execution and its cost,
then compare camera/projection, world update generation, light direction,
cascade settings and exported transforms across a paired render. Resource
allocation and command ordering must show whether the atlas can survive the
second eye, including transient aliasing and intervening writers. A cache would
also need explicit invalidation on any changed input or interrupted pair.

The exact-build six-pointer cascade ABI and a bounded observer are now validated;
see [the 11 September capture](CASCADE-STAGE-OBSERVER.md). Its 127 complete
two-call groups match all six addresses and selected input snapshots, averaging
about 0.21 ms CPU per call. This does not establish eye identity, the complete
cache key, GPU cost or a resource lifetime guarantee. No shadow work is skipped.
Physical readiness and worn visual acceptance remain pending.

Local receipts are under `artifacts/unattended/current-renderer-config-20260910`
and `engine-preparation-callers-20260910.txt`. Extracted game assets remain out
of Git.
