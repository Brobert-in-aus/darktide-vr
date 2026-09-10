# OpenXR D3D12 color-image state

The viewer assumed runtime-owned color swapchain images arrived in COMMON.
The OpenXR D3D12 contract instead requires RENDER_TARGET after waiting for an
image and before releasing it. The simulator already creates these images in
RENDER_TARGET. A strict 120-frame check exposed 358 DirectX validation errors
in the previous viewer.

The viewer now retains RENDER_TARGET for direct scene rendering and fallback
clears. Stereo and flat image copies transition RENDER_TARGET to COPY_DEST and
back. Cuff rendering retains RENDER_TARGET, and optional readback returns from
COPY_SOURCE to RENDER_TARGET. Application-owned shared, cached and original
textures retain their existing COMMON-based ownership protocol.

Contract: [Khronos XR_KHR_D3D12_enable swapchain image state](https://registry.khronos.org/OpenXR/specs/1.1/man/html/XR_KHR_D3D12_enable-swapchain-image-state.html).

The benchmark runner's optional `-DebugLayer` enables viewer validation and
records `debug_layer` in its receipt. Keep it off for performance comparisons.
It does not enable the game's debug layer.

## Validation

Windows x64 Release viewer build passed. With the normal 120 Hz simulator,
`--flush-log --frames 2 --debug-layer --require-openxr --require-rendering
--xr-frames 120` submitted all 120 frames and exited zero with `result=pass`
and no error output.

Local evidence is under ignored `artifacts/unattended`, prefix
`xr-state-fix-smoke3-20260910`. No physical viewer deployment or worn visual
acceptance is implied. This is a resource-state correctness fix; no performance
gain is claimed.

The 30-second stationary SoloPlay mission run with FG enabled and the viewer
debug layer also exited cleanly. It submitted 1,813 fresh original pairs and
1,780 generated pairs, with zero pose mismatches and exact file restoration.
Evidence: `synthetic-solo-xr-state-debug-120-20260910`. Debug instrumentation
makes its frame rate unsuitable for a performance comparison.
