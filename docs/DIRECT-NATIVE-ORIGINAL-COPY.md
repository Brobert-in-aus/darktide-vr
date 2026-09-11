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

## Focused comparison build

Focused revision `d8cafb3` ports only the viewer change and its copy helper onto
benchmark viewer revision `a8061e8`. Its Release executable is built under
`build/focused-direct-original-viewer`, SHA-256
`972CD7A5A8108FA039A5661B96DE9C61FDB6E254F8D14D11741B7EBBDC279D5E`.
The comparison uses the same executable with the process option off/on, native
ring DLL `D4AB131A`, saved 2496x2688 eye resolution, Quality DLSS, FG Off and the
same stationary SoloPlay mission. It excludes the separate on-demand desktop
capture candidate. The physical Ready check still failed with Quest asleep;
the explicitly authorised isolated simulator fallback is used.

## Native off/on/off result

| Run | Direct copy | Distinct native FPS | Viewer GPU-completion wait, ms |
| --- | --- | ---: | ---: |
| A | Off | 88.07088 | 1.57865 |
| B | On | 90.02198 | 1.45487 |
| A2 | Off | 89.68635 | 1.56349 |

FPS uses the existing ten-second warm-up exclusion. Wait figures are the final
60 accepted world-mode timing windows, not the identical FPS interval. They are
CPU-observed waits for GPU completion, including dependencies, not GPU timestamp
measurements of the copy itself. The reduced wait is consistent across the
reversal, but B exceeds A2 by only 0.37%; a reliable throughput gain is not
established. Keep the option disabled by default.

All runs exit cleanly, restore files and report zero pose mismatches. There are
30/27/27 valid GPU activity records respectively, plus one unavailable record
per run; no Streamer busy sample was observed. Coverage remains incomplete.
Consumer records confirm direct submissions only in B. Evidence is under
`artifacts/unattended/synthetic-descriptor-demand-direct-viewer-{a,b,a2}-20260911`,
including `summary.json` and `viewer-stages.json`. FG-path compatibility is the
next check; physical performance and worn acceptance remain pending.

## FG compatibility result

With the option requested, the FG-tested `FB244186` native baseline, Quality
DLSS, 120 Hz and a 120 FPS cap, the viewer delivered 119.60083 distinct FPS:
59.79410 original plus 59.80676 generated, with 0.39238 repeats/sec. One direct
original was submitted during startup before generated surfaces attached; no
further direct submissions were logged. FG continued through the queued path.

The run exited cleanly, restored files and reported zero pose mismatches. GPU
recording returned 26 valid and two unavailable records, with no observed busy
Streamer sample. This checks mode compatibility, not a new FG speedup or worn
acceptance. Evidence: `synthetic-descriptor-demand-direct-viewer-fg-20260911`.
