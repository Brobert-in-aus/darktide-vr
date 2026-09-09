# Saved camera-history comparison

The 10 September Streamline capture supports consistent same-viewport camera
history during its sampled continuous-stereo interval. It does not establish
the contents of SR history or the correctness of object motion vectors.

For 169 consecutive-frame samples at or after the first continuous presentation
(`present_frame=4840`), reconstructing the clip-to-previous-clip transform from
the logged camera basis, position and projection agrees with the reported
matrix. Maximum absolute element difference is `4.884662e-6`; median is
`1.391688e-6`. Matching uses the previous present frame and the **same viewport**,
not adjacency in the log or an assumed left/right call order.

## Method and limits

The engine projection maps view X to clip X, view Z to clip Y and view Y to
clip W. Build each row-vector camera-to-world matrix from the logged right,
forward, up and position rows, using homogeneous components 0, 0, 0 and 1.
For current camera `C`, previous same-viewport camera `P`, and their projections,
compare the reported history matrix with:

```text
clip_to_camera_view(C) × camera_to_world(C)
    × inverse(camera_to_world(P)) × camera_view_to_clip(P)
```

The calculation uses the decimal floats actually logged, ordinary double
precision matrix arithmetic and partial-pivot Gauss-Jordan inversion. These are
residual measurements, not an SDK-defined tolerance or proof of pixel history.
Streamline constants concern the observed frame-generation path; they cannot
replace separate SR feature/input observation.

Across all 181 armed camera samples, projection/inverse pairs have maximum
identity residual `2.950500e-7`. History matrices contain startup exceptions:

| Constants call | Present | Finding |
| --- | --- | --- |
| 239 | 4005 | History/inverse residual `0.000251371` |
| 240 | 4005 | History/inverse residual `20253.498` |
| 242 | 4835 | Non-finite `clip_to_prev_clip` |
| 243 | 4835 | History/inverse residual `1` |

All four precede continuous stereo's first presentation at 4840; their logged
reset values are zero. They must not be presented as ongoing continuous replay
failures. They remain useful evidence for future startup handling, but no runtime
guard, reset or camera-matrix replacement was added on this evidence alone.

Source `streamline-probe.tsv` SHA-256:
`128BD72DFAD8F4298A090E235D4EFB19A3ED1AA350072B84703748C64264D34A`.
The saved capture is under `artifacts/diagnostics/sr-inputs-20260910`.
Ignored calculation receipts are `saved-streamline-matrix-inverses-20260910.json`
and `saved-streamline-camera-history-20260910.json` under `artifacts/unattended`.
This was offline analysis, with no new gameplay verification or deployment.
