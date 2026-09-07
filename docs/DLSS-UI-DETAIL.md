# Matched UI detail measurement

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
This rejects size mismatches; it does not establish content identity for a
different bitmap of the same size.

The two focused CTests (`dlss_ui_detail|dlss_ui_capture_identity`) pass in 1.22
seconds, including both CLI rejection paths. Re-running the original pose-8589
readback accepts its 4992x2688 packed layout and reproduces the prior contrast
results below. Evidence: `artifacts/unattended/ui-detail-extent-validation-20260908.json`.
No new live capture, synthetic visual experiment or blur acceptance is claimed.

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
