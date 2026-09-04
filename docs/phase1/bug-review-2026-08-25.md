> Historical research record. This is not the current operating policy or acceptance checklist. See [current status](../CURRENT-STATUS.md).

# Phase 1 bug review - 25 August 2026

## Review scope

This gate covered the current shared-eye producer/consumer synchronization,
pose association, OpenXR pacing and fallback, launch tooling, and active Phase 1
documentation. It did not launch Darktide or perform a headset comfort test.

## Fixed findings

1. **Stale IPC state survived an XR harness restart.** Darktide can keep the
   named mapping alive after the prior writer exits. A new writer now starts a
   clean seqlock epoch and invalidates both the previous pose and rendered-pair
   tag. A regression test holds the reader open across writer recreation.
2. **Rendered-pair metadata was validated only by the producer.** The consumer
   now independently rejects zero or unrepresentable counters, non-finite
   projection metadata, invalid FOV, and non-positive aspect ratios before
   accepting a pair tag. Pose publication applies the same signed shared-layout
   counter bound.
3. **The intended cadence was opt-in.** Shared-eye projection is pair-driven by
   default. It waits through legitimate rates below 30 fps; only after the
   existing 500 ms producer-stale threshold does a 33 ms timeout preserve
   loading/failure recovery. `--continuous-shared` explicitly selects the
   former compositor-rate A/B behavior.
4. **The stereo launcher was obsolete.** It invoked the old desktop SBS path
   and converted seconds to 120 Hz frame counts. The current launcher uses
   isolated shared eyes and `--xr-seconds`, so its duration remains wall-clock
   bounded at the producer's actual rate. The old filename is a compatibility
   alias.
5. **Generated capture files could appear under `--help/`.** That accidental
   output directory is ignored and the existing generated BMPs were removed.
6. **The shader-container utility trusted only the outer DXBC size.** It now
   validates every chunk offset and payload bound before extracting a container,
   rejects a missing input directory cleanly, and has been exercised against
   the 44-file local shader-group sample. The result was zero valid standalone
   DXBC containers: the raw `DXBC`/DXIL-related strings in those Stingray group
   files are not sufficient evidence of directly extractable shader blobs.

## Open findings and boundaries

- The motion artifact remains open: flashes oppose head rotation, occur in both
  eyes, and are substantially more frequent in the left. Pair-tag counters rule
  out frequent mixed-sequence pairs, but do not yet prove whether the remaining
  fault is capture timing, pose association, or a temporal render dependency.
- Current gameplay cameras and XR projection poses are deliberately 3DoF.
  Translation is transported and clamped but disabled in Lua; enabling only the
  Lua switch would be incorrect because projection anchoring currently removes
  the positional delta too. The 6DoF change must enable both sides together.
- Camera-reported FOV/aspect is diagnostic metadata. Treating it as literal
  OpenXR coverage was headset-falsified by the narrow-window result. The
  empirically accepted runtime-centered symmetric FOV remains active.
- The producer uses a single shared pair protected by a consumed fence. It is
  correct but can drop complete pairs under backpressure. A ring is a measured
  throughput optimization, not a correctness prerequisite.
- Two independent deferred renders remain the performance baseline. Hardware
  view-instancing tier 3 is available, but Darktide's live public VR globals are
  absent and no shader/PSO compatibility has yet been established.
- Repository provenance remains an operational risk: most implementation files
  are still untracked on `phase0/feasibility-bootstrap`. This review did not
  create a broad first commit implicitly; the working tree must be curated and
  committed before a PR or cross-device handoff can be authoritative.

## Current run command

With the guarded build already running under EAC-inactive private testing:

```powershell
tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 300
```

The wrapper verifies the patched executable hash, refuses an active EAC
service, requires one responsive Darktide window, and uses pair-driven shared
eye submission. Use the harness's `--continuous-shared` option only for an
explicit cadence comparison.

## Validation record

Run from the repository root:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build --preset windows-vs2022-release
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' `
  --test-dir build\windows-vs2022 -C Release --output-on-failure `
  -E '^xr_(projection|theatre|stereo_sbs)_smoke$'
```

Result: the full Release build succeeded and all 18 non-headset tests passed,
including the new shared-mapping restart regression. Both stereo launcher files
also pass PowerShell parser validation; repository-relative Markdown links and
`git diff --check` pass. The DXBC parser passes a synthetic valid/invalid-bound
test and correctly reports zero valid containers in the local shader-group
sample. The three compositor-visible tests were not run because this review
intentionally did not start a headset session.
With Darktide stopped, the rebuilt native DLL was deployed and source/deployed
SHA-256 both equal
`E7492BD32C30902B157ABEDA742B10264A5E4AC4F9BC43295002AAA463C18374`.
The deployed Lua already matched source at
`6C5C2F3A9D7B14BA21606E57B879C6EFB34ACAF936B4EC874A0F6734AF2E473A`.
No Mac-only validation applies to the Windows/D3D12/OpenXR changes.

## Live follow-up after review

The headset test closed the principal motion-flicker finding: pair-driven
submission removed the flicker, and the runtime-derived symmetric projection
now has correct scale and FOV. The new open visual issue is horizontal
camera-relative banding. It is visible in the raw shared-eye surfaces, so it is
not solely an OpenXR or Virtual Desktop compositor defect.

Two controlled checks narrowed it further:

- disabling only Darktide render jitter left the bands unchanged and reduced
  DLSS sharpness, so jitter was restored;
- disabling DLSS/upscaling changed the D3D12 output graph and exposed that the
  current selector targets a DLSS-path intermediate. A bounded census found
  full-size completed HDR format-26 buffers but no format-28 intermediate
  satisfying the selector. This does not imply native stereo requires DLSS.

The no-DLSS census is stored in
`artifacts/phase1/no-dlss-boundary-census-20260825`. The temporary always-on
census build was reverted, focused `native_capture|shared_eye` tests passed,
and the restored DLL was deployed with matching source/deployed SHA-256
`7343A4D9F6FFA23BCB3521C543B1914FDE98F20B633817AD036253B0950D3082`.
