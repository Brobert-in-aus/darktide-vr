# DLSS Quality and Performance mission comparison

The 120 Hz native-only mission currently delivers about 74 FPS while the GPU is
about 62% busy. The saturated presentation thread is separate from the Lua
render caller. This comparison tests whether reducing reconstruction input
resolution improves throughput before selecting further engine changes.

The synthetic runner accepts `-DlssQuality Preserve|Quality|Performance`.
Preserve is the default. An explicit choice requires DLSS already enabled and
updates both the active master selection and renderer quality. Stock
`scripts/settings/options/render_settings.lua` maps Performance to selection 3
and `"performance"`, Quality to selection 5 and `"quality"`. Detected-settings
caches are preserved, and the existing wrapper restores the exact settings file.
The runner records both the requested override and resulting renderer setting.

Validation: `tests/tooling/test-synthetic-framegen-settings.ps1` passes, including
round-trip choices, cache preservation, missing/duplicate fields and disabled
DLSS rejection. The runner parses successfully. Run comparisons at the same
mission start, difficulty, eye extent, refresh, worker count, cap and native DLL.
These are throughput tests and do not establish worn image-quality acceptance.

## Results

Two 120-second SoloPlay `cm_archives` difficulty-3 trials used the unchanged
diagnostic-cleanup native baseline, FG off, unlimited cap, 13 workers,
2112x2304 eyes and the 120 Hz simulator. Analysis excludes ten seconds of warm-up.

| DLSS mode | Native pairs/s | GPU busy | Board power |
| --- | ---: | ---: | ---: |
| Performance | 74.42 | 53.50% | 233.58 W |
| Quality | 74.12 | 63.05% | 267.83 W |

The 0.4% throughput difference is too small to establish a native FPS gain.
Performance substantially reduced GPU work/power without improving the CPU-side
ceiling in this scene. Together with the saturated render-side thread, this
supports prioritizing CPU rendering work for native throughput. It does not
establish behavior in combat or GPU-bound scenes, nor justify reducing image
quality as the accepted default. Quality was restored.

Fresh stereo readiness, clean exit and exact restoration passed for both runs.
Evidence: `synthetic-solo-dlss-performance-a-20260910` and
`synthetic-solo-dlss-quality-a-20260910` under ignored unattended artifacts.
