# Direct native original copy

11 September 2026 candidate, disabled by default. Set the viewer process variable
`DTVR_XR_NATIVE_ORIGINAL_DIRECT=1` to compare it with the existing native-ring
viewer path. The option is inactive while generated surfaces are attached.

The existing path copies a packed original into two pending eye textures, then
copies those eyes into the OpenXR outputs and repeat-frame cache. The candidate
copies the current packed original straight into the outputs and cache. It saves
one complete stereo copy per delivered original, approximately 51.2 MiB at
2496x2688 RGBA8 per eye. This is reduced copy payload, not measured bus traffic or
an FPS prediction. Pending textures remain allocated for fallback/FG operation.

The existing completed-fence, age, generation, pose-history and projection-settle
checks remain prerequisites. The viewer waits for the producer's ready fence
before execution and signals consumed only after submitting the copies. Cached
repeats retain the image and matching poses. FG's queued-original path and legacy
mailbox transitions remain in place. Optional eye readback uses the same packed
eye regions, rather than reading unpopulated intermediate textures.

`openxr.native_original_direct requested=1` reports configuration. Bounded-rate
submission counters confirm actual use. This option changes transport copies,
not HUD geometry, reconstruction inputs or game settings.

## Offline validation

Windows x64 Release viewer and native ring tests build. Actual WARP resource
tests verify both eye colors in separate and vertically stacked outputs, both
repeat caches, and optional per-eye readbacks. Existing ring tests retain
unconsumed-slot, pose/generation mismatch and in-flight allocator checks. Typed
and typeless cases pass 2/2 in 0.11 seconds.

The first added readback check incorrectly included padding beyond the last
allocated row and failed with E_INVALIDARG. Its map range was corrected to cover
only bytes read; both cases then passed. This was an offline test issue, before
any deployment. Native/Lua accepted defaults remain unchanged. Live timing and
worn acceptance are pending; no speedup is claimed.

Validation commands:

```
cmake --build build/xr-window-capture-demand --config Release --target darktidevr-xr-harness darktidevr-native-original-ring-tests
ctest --test-dir build/xr-window-capture-demand -C Release -R '^native_original_ring(_typeless)?$' --output-on-failure
```
