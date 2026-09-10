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
