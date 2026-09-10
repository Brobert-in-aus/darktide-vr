# Paired camera metadata in the simulator

The schema-5 SR capture consistently linked feature lifetimes 2 and 3 to
Streamline viewports 920637560 and 3367681085. Its camera constants initially
appear to disagree: the two forward directions differ by about 13.9433 degrees.
That difference is explained by the existing asymmetric-frustum recentering,
not evidence of a camera synchronization defect.

The consumer reported eye-0 horizontal angles (-0.942478, 0.698132) and eye-1
angles (-0.698132, 0.942478), with vertical angles (0.767596, -0.947190).
The mod uses each frustum's angular centre to rotate a symmetric projection.
Reconstruct each camera basis from its right/forward/up columns, then remove
the optical rotation `Rz(-horizontal_centre) * Rx(vertical_centre)` on the right.
The resulting basis describes the common head orientation.

`tools/stereo/analyze-stereo-camera-coherence.py` compares both assignments of
the two viewport IDs. It pairs only unique successful constants with identical
present number, frame index and token pointer, rejects non-finite or improper
camera bases, and uses the consumer's recorded frusta and IPD. It does not use
pending eye tags or adjacency in the log. The minimum present is 3361, the SR
capture gate recorded in the same run; 67 complete pairs meet that boundary.

For viewport 920637560 assigned to runtime eye 0 and 3367681085 to eye 1:

| Metadata comparison | Maximum residual |
| --- | ---: |
| Corrected forward direction | 0.000014081 degrees |
| Corrected right direction | 0.000013977 degrees |
| Corrected up direction | 0.000003818 degrees |
| Separation versus recorded 0.064 m IPD | 0.000006059 m |
| Eye baseline versus corrected right axis | 0.006019 degrees |

Separation spans 0.063993941–0.064005473 m. Swapping the viewport assignment
produces approximately 28 degrees of corrected forward/right disagreement and
a baseline pointing approximately 166 degrees away from the expected right
axis. The reported decimal precision limits the residuals, especially world
positions. These are measured errors, not SDK acceptance thresholds.

This supports a consistent camera-based assignment for the two SR-associated
viewports in this simulator sample. It does not verify the command-buffer
proxy relationship, GPU history contents, actual eye display, latency, HUD
blur or worn visual acceptance. No camera or rendering settings were changed.

Validation: three isolated tests cover known asymmetric optical rotations,
reversed assignment, invalid bases/frusta, ambiguous duplicate records and the
capture boundary. The analysis passed on the captured logs. Local report:
`artifacts/unattended/synthetic-sr-streamline-context-20260910/camera-coherence-continuous.json`.
The earlier unfiltered draft included 79 pairs and reached the same conclusion;
the 67-pair report is the continuous-capture result used here.
