# Matched UI detail measurement

## Blur around HUD items

9 September: the user explicitly reports DLSS blur **around HUD items**.
Track the surrounding scene and HUD boundary separately from detail inside
opaque text. The saved opaque contrast measurements below neither measure nor
exclude that symptom. No cause or visual fix has been established.

For the next user-worn comparison, retain the same scene, pose, per-eye
resolution, HUD placement and streaming settings. Record the precise SR and
frame-generation settings independently; "DLSS on" alone is ambiguous. Compare
HUD visible/hidden with SR off/on while keeping frame generation fixed, then
vary frame generation separately if the symptom remains relevant. Confirm that
each requested setting actually took effect before comparing results.

Inspect three regions separately: opaque HUD interiors, translucent boundaries,
and nearby world pixels outside HUD coverage. Ask whether the surrounding blur
is present while still, appears during head movement, or persists after motion
stops. Record duplicated or displaced HUD as a separate observation rather than
assuming it explains blur. These are planned observations, not completed tests.

For capture analysis, preserve each sample's own pose/resource/call identity
and checksums. Sequential HUD-visible/hidden captures cannot be assumed to have
identical world pixels, even at a fixed pose: animation, exposure and temporal
history can change. Never subtract those images and label every difference a
HUD artifact. The opaque UI tool cannot use transparent UI RGB as a reference
for the surrounding scene; that requires independently verified scene evidence.
Inspect HUDless input ownership and alpha at the actual reconstruction boundary
before proposing offsets, masks or history changes. Retain worn visual acceptance
as the final check, including both eyes and moving gameplay.

This investigation does not authorize installing the accumulated native
candidates. Preserve the accepted mixed build and run Ready preflight before
any new live session.

## UI RGBA exporter candidate: 8 September

### Source audit and diagnostic request follow-up, 9 September

The accepted native source `23345e5` and current candidate share this frame-
generation input distinction: depth, motion and HUDless scene are separately
tagged; the final eye colors fill the presented backbuffer; independent UI tag
23 is optional. Disabling that optional tag does not remove HUD pixels from the
final backbuffer. This is a source contract at the FG boundary, not a measured
cause of blur and not an audit of the separate SR reconstruction boundary.

In the accepted native source, `stage_stereo_ui_readback` receives owned UI
copies only when that optional UI path is enabled. With it disabled, diagnostic replay can instead supply two
observed overlays with matching pose identity. Those exports record
`owned_ui=0`; they do not arm `arm_ngx_copy_ui_match`. The strict native-proof
checker intentionally requires `owned_ui=1`. Therefore an observed six-image
capture is not the same owned-image/NGX match proof as the enabled path. Do not
enable the UI tag merely to obtain that proof: doing so changes the condition
being investigated. A diagnostic-only owned UI snapshot independent of tag
submission is implemented in the subsequent source candidate below.

The one-shot request now waits when UI capture was explicitly requested but a
complete matching overlay pair has not arrived. Previously the first attempt
could consume the request and export four scene/final images, leaving diagnostic
replay active. Replay now ends when an eligible attempt is consumed, including
failure before staging; the separate staged flag still reports actual staging.
An enabled Streamline UI tag continues its normal replay independently.

The missing-overlay regression failed before this fix. Five readback CTests pass
in 2.80 seconds: missing/stale-pose overlays retain the request, a matching pair
exports six images without arming owned matching, source failure stops replay
without claiming staging, and existing content/export-failure/native-roundtrip
checks pass. Windows x64 `darktidevr_native_capture` also builds successfully in
the isolated `build/xr-frame-stage-timing` tree. No runtime was deployed; the
accepted viewer hash and game/streaming/settings state are unchanged.

### Owned diagnostic snapshots with the UI tag disabled

The candidate now separates UI snapshot allocation from tag submission.
`StreamlineContinuousSubmission::initialize` accepts diagnostic UI allocation
with `tag_ui=false`, keeping `ui_alpha=0` while reporting `ui_capture=1` in its
ready record. Native capture uses the existing explicit pre-launch diagnostic
flag to request these resources. Initialization waits for valid captured UI
resources; this path does not infer empty coverage from missing draws.

Each eye copies valid UI through its ordinary capture list/fence. Only a complete
current-pose pair reaches readback after the stage queue waits for both capture
fences. Partial pairs, pauses and discarded frames expose no UI pair. When the
one-shot request is consumed and replay ends, missing diagnostic UI is permitted
without stopping generation. Tagged UI remains mandatory whenever UI submission
was enabled; existing missing/unconfigured/alias rejection stays in place.

The readback now receives owned UI copies and can arm the existing NGX match even
when the optional UI tag is disabled. The strict proof checker is unchanged.
Actual live NGX correlation and worn blur comparison are still required; the
source candidate does not establish a visual fix or complete raster coverage.
The accepted installed native build does not contain this change.

Seven related CTests pass in 3.31 seconds, including WARP diagnostic/tagged/no-UI
capture modes, partial pairs, replay cessation, pause/discard and distinct owned
textures. Both the recovery test and native DLL build in the isolated tree.
The fixture rejects presentation intentionally and does not run NVIDIA frame
generation. No accumulated main-tree DLL was deployed. Prepare a deliberate
focused native candidate before any live trial, then run fresh Ready.

The one-shot native UI exporter now records a per-image RGBA checksum and
extent after a successful BMP write/close. It declares
`image_checksum=rgba_fnv1a64` on its staged/exported status records. Both analysis
CLIs require the declared left/right UI metadata, verify all input RGBA bytes
(including transparency), and check both eyes before producing report files.
Missing, duplicated, inconsistent or unknown checksum evidence is rejected.

Historical logs without checksum declarations remain readable but explicitly
report `ui_content_evidence=legacy_metadata_only` and
`ui_rgba_hash_verified=false`. Their UI pixels cannot be retroactively verified.
The original pose-8589 capture retains its existing measurements and this legacy
label; generated RGB hashes still verify. Evidence:
`artifacts/unattended/ui-detail-legacy-evidence-20260908.json`.

The native regression uses WARP and a process-local temporary directory, checked
before its request flag is written. It does not address the running game's
request directory. It verifies row padding, BMP channel order, RGBA checksums and
a deliberately unwritable image destination. A Python round trip reads the
actual exported BMP/log and rejects altered alpha. NGX output metadata in that
round trip is a fixture, not a GPU-generated frame.

The first full run exposed missing completion records during concurrent log
polling. Changing the test reader alone did not resolve it: secure CRT append
opens could exclude an already-open monitoring reader. Diagnostic log writers
now use explicit shared opens. The native tests deliberately hold a reader open
throughout export; both success/failure cases pass 20 consecutive runs each
(4.02 seconds). This fixes a diagnostic log-sharing issue, not image quality.

Windows x64 Release builds of `darktidevr-ui-readback-tests`,
`darktidevr-continuous-recovery-tests` and `darktidevr_native_capture` pass.
The new native candidate is **undeployed**; the accepted live game remains on
its prior DLL. No live capture or worn visual acceptance is claimed.
Full Windows x64 Release CTest passes **131/131 in 23.23 seconds**, headset
tests OFF, including all 45 Lua chunks. Command:
`ctest --test-dir build/windows-vs2022 -C Release --output-on-failure`.
Evidence: `artifacts/unattended/ui-rgba-final-131-20260908.log`.

`tools/stereo/measure-dlss-ui-detail.py` measures contrast between adjacent,
fully opaque UI pixels in an identity-matched generated frame. It does not
search for alignment or assign visual acceptance. Translucent boundaries, world
markers, motion, compositor output and streaming quality require other evidence.

The input log must record an owned UI copy and successful staging/export. The
generated log must record successful staging/export with matching pose, both
scene resources, both eye calls, resources and layout. Failed or incomplete
readbacks are rejected before measuring existing bitmap files.

8 September: the layout check now also requires positive even packed width,
positive height, a valid RGBA8 D3D12 row pitch and sufficient readback bytes.
Both CLI tools compare the loaded bitmap's actual extent/type with that logged
layout before measurement or report output. Matching log rows alone could
previously admit an unrelated bitmap of another size. Pose IDs must be positive.
This initial check rejects size mismatches. The subsequent RGB content check
below also validates the generated bitmap against its native export checksum.

The two focused CTests (`dlss_ui_detail|dlss_ui_capture_identity`) pass in 1.22
seconds, including both CLI rejection paths. Re-running the original pose-8589
readback accepts its 4992x2688 packed layout and reproduces the prior contrast
results below. Evidence: `artifacts/unattended/ui-detail-extent-validation-20260908.json`.
No new live capture, synthetic visual experiment or blur acceptance is claimed.

The next follow-up verifies each generated eye's RGB bytes against the existing
exported `left_hash`/`right_hash` values from `ngx_output_copy_probe.cpp`.
It reproduces the native FNV-1a 64-bit order: top-to-bottom RGB, without alpha
or row padding. Both CLI tools reject missing/invalid checksums, altered RGB
content and invalid eye-call ordering before producing measurements. Reports
record `generated_rgb_hash_verified=true` only after both eyes match; checksums
are decimal strings to preserve all 64 bits in JSON consumers.

Two focused CTests pass in 0.84 seconds with a known FNV vector, independent
eye corruption, row reversal and CLI rejection coverage. The original pose-8589
readback matches both native checksums and retains all prior contrast values;
evidence is `artifacts/unattended/ui-detail-content-validation-20260908.json`.
This verifies generated RGB content only. Generated alpha and the input UI
bitmap bytes are not covered by these native RGB checksums; the latter retain
the existing ownership/log and matching-extent checks. No rendering code changed.

Run against the original native RGBA readbacks, keeping their accompanying logs:

```powershell
python -B tools/stereo/measure-dlss-ui-detail.py <ui-readback-stem> <packed-generated.bmp> --output <report.json>
```

For each eye and axis, select neighboring pixels whose alpha is exactly 255
and whose source RGB contrast reaches 16 in at least one channel. At least 32
pairs are required. Contrast retention is the signed projection of generated
RGB differences onto the source differences, weighted by source contrast energy.
One represents unchanged contrast; zero represents no contrast in that direction;
negative values represent reversal. Values above one are possible. The report
also records median retention, reversed pairs and gradient error. These are
measurements, not a pass threshold or a perceptual sharpness score.

## Saved static sample: 7 September 2026

The original tenth-run capture from 6 September has matching pose 8589 and eye
calls 2804/2805. Its optional UI input was enabled. The current default keeps
that input disabled, so this result does not characterize the current baseline.

| Eye / direction | Selected pairs | Contrast retained |
| --- | ---: | ---: |
| Left / horizontal | 2,138 | 97.33% |
| Left / vertical | 2,329 | 97.84% |
| Right / horizontal | 2,440 | 95.94% |
| Right / vertical | 2,982 | 97.31% |

No selected pair reversed contrast. This bounds detail loss inside the fully
opaque parts of this static sample. It does not resolve the user's motion blur
report or identify its cause. Blur remains the first image-quality task; the
rejected pose explanation is not reopened by this measurement.

Local evidence: `artifacts/diagnostics/hud-alpha-capture-20260906/opaque-detail-20260907.json`.
Unit fixtures cover unchanged contrast, known numerical smoothing, reversed
edges, insufficient opaque detail and invalid extents/types. Capture identity
fixtures reject incomplete exports and mismatched calls/resources/poses.

## Composition residual regions: 9 September 2026

`check-dlss-ui-alpha.py` now reports disjoint opaque UI, translucent UI,
transparent pixels near UI and transparent pixels farther away. The default
neighborhood is eight capture pixels in Chebyshev distance; use
`--near-ui-radius 0..64` to change it. This is a measurement neighborhood, not
an estimated blur radius. Coverage includes every captured UI primitive,
including world markers; it does not identify individual HUD widgets.

Each region records its pixel count, source-over residual count/fraction and
maximum channel error. Empty regions have null fractions and maxima. The
existing composition pass criteria remain unchanged. Both eyes are validated
before output creation. This standalone checker does not verify capture logs
or pixel checksums and explicitly reports `capture_identity_verified=false`
and `visual_acceptance=unverified`.

Reanalysis of the original pose-8589 six-bitmap sample found 44,438 left-eye
and 43,289 right-eye transparent pixels within eight pixels of coverage. All
four regions in each eye had zero residuals above the existing three-level
tolerance. This verifies composition arithmetic for the supplied older static
images only: it does not measure post-NGX temporal blur, establish sharpness,
characterize the current UI-input-disabled baseline or resolve the HUD blur.
Local report: `artifacts/unattended/dlss-near-ui-regions-20260909/alpha-check.json`.

Seven Python fixtures cover disjoint neighborhoods, clipped borders, empty
regions, invalid radii, known residual locations and malformed second-eye
input. Four focused CTests (`dlss_ui_|ui_readback_native_roundtrip`) pass in
1.40 seconds. No live capture or installed runtime changed.

### Optional native proof for composition inputs

Use `--verify-native` with the composition checker to require one positive-pose
owned capture, successful staged/exported records using `rgba_fnv1a64`, and
exactly one completed checksum/extent record for each of the six eye/role
images. All RGBA bytes must match before any report output is created. Only
this successful path sets `capture_identity_verified=true`; visual acceptance
remains unverified. The default retains explicit unverified analysis for older
captures. This proves the supplied images match their export records, not that
they represent a particular runtime setting or the user's reported visual state.

The original pose-8589 log predates these checksums and cannot pass this mode.
Nine Python fixtures include corruption of RGB and alpha in every role, missing/
duplicate records, invalid metadata and rejection before output creation. The
native roundtrip also verifies all six real exported images. Four focused CTests
pass in 1.49 seconds; no runtime rebuild or deployment was needed.
