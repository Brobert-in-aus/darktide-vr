# Bounded stereo marker input measurements

The pickup-sizing investigation needs to distinguish different GUI inputs from
different projected/rendered extents. `darktidevr_marker_metrics.lua` adds an
opt-in measurement scope around primary/replay marker, interaction-popup and
smart-tag draws. It changes no size, position, font, color or GUI ownership.
The accepted live preview has not been updated with this candidate.

When the candidate is deployed, `/dtvr_marker_metrics` measures the next 60
scoped draws and stops automatically. `/dtvr_marker_metrics_off` cancels it.
These are draw passes, not 60 frames: a frame can contain several HUD elements
and both eyes. Run it while the relevant popup/marker is visible. No native
diagnostic hooks, synthetic tracking or color replacements are requested.

Each scope records at most 128 primitive inputs. Pairing requires the same HUD
instance, element kind and frame time; the second-eye scope consumes its primary
record. Calls are compared in order, with matching primitive method and supplied
material/resource or text/font identity. Identity mismatches make the comparison
incomplete. Identical repeated primitives still rely on draw order; this is not
a persistent widget-ID trace. Text and resource names are never logged.

The `DARKTIDEVR_MARKER_METRICS` summary includes:

- Left/right primitive totals and the number of matched calls.
- Shape, font-size, renderer-scale, renderer-alpha and style-color-alpha
  mismatch counts. Logical-coordinate primitives are scaled to pixel inputs;
  already-scaled script primitives are not scaled again.
- The maximum difference in submitted position or transform translation.
  This is expected to be nonzero under stereo reprojection and is not an error.
- An `incomplete` flag for truncated lists, extraction errors, unsupported
  primitives, unequal counts or mismatched call identity/order.

Tracked paths cover bitmap/UV/rotated bitmap, text/3D text, rectangles/rotated
rectangles and vector icons/pictures, including direct text calls inside damage
indicator logic. Triangles, circles and video are explicitly marked unsupported
if encountered. Transformed draws compare their X/Z-plane basis and translation;
they do not reconstruct final rasterized bounds. Optional GUI settings, material
shader behavior, glyph outlines and pixel snapping are not measured.

A complete pair with zero shape/font/scale differences establishes matching
observed inputs only. It does not prove matching angular sizes or rendered
pixels. Empty pairs provide no sizing evidence. Nonzero differences need the
associated draw count/order and animation state interpreted before choosing a
fix. This measurement is one input to the [full marker audit](STEREO-MARKER-SIZING.md),
whose worn and rendered-extent checks remain open.

## Validation, 8 September

The integrated Windows x64 Release suite passes **149/149 in 63.63 seconds**:
`artifacts/unattended/marker-metrics-149-20260908.log`. Final style-alpha/logger
coverage then passes the two affected marker CTests in 0.06 seconds, and all
50 Lua chunks pass the pinned LuaJIT gate. Evidence:
`artifacts/unattended/marker-metrics-final-focused-20260908.log`.

The focused fixture covers default-off transparency, sparse return values,
GUI-wrapper ownership, same-frame/instance matching, real geometry/font/scale
differences, logical/already-scaled inputs, transforms, style alpha, bounded
storage and expiration, cancellation, unsupported/non-finite inputs, draw-error
cleanup and logging failures. None of these offline checks establishes a live
pickup measurement or worn acceptance.
