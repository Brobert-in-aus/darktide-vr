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
- `layer` counts differing draw-order inputs; `start_layer` counts differing
  renderer layer offsets. `max_layer_delta` is the largest raw layer-input
  difference. 2D calls use position[3], while 3D bitmap/text calls supply a
  separate scalar. These inputs are not multiplied by XY scale or included in
  spatial anchor differences. They do not predict final depth/occlusion or
  primitive-specific clamps (rotated slug icons clamp their layer to one).
- `text_layout` counts matched text calls whose stock max-extents width, height
  or minimum glyph/layout origin differs; `text_measured` counts matched measured
  text calls. The query uses the final pixel font size, box and options for 2D
  and 3D script draws. Font/box equality alone does not establish equal layout.
- An `incomplete` flag for truncated lists, extraction errors, unsupported
  primitives, unequal counts or mismatched call identity/order.

Tracked paths cover bitmap/UV/rotated bitmap, text/3D text, rectangles/rotated
rectangles and vector icons/pictures, including direct text calls inside damage
indicator logic. Triangles, circles and video are explicitly marked unsupported
if encountered. Transformed draws compare all three components of their X/Z-plane
basis and translation, including depth. Rotated rectangle/vector-icon calls also
compare their scaled pivot coordinates;
they do not reconstruct final rasterized bounds. Text options are forwarded to
stock layout measurement, but arbitrary GUI settings, material shader expansion,
actual glyph outlines/shadows and pixel snapping are not certified by that API.

A complete pair with zero shape/font/scale differences establishes matching
observed inputs only. It does not prove matching angular sizes or rendered
pixels. Empty pairs provide no sizing evidence. Nonzero differences need the
associated draw count/order and animation state interpreted before choosing a
fix. This measurement is one input to the [full marker audit](STEREO-MARKER-SIZING.md),
whose worn and rendered-extent checks remain open.

## Validation, 8 September

9 September 3D-offset follow-up: the observer now records the third component
of bitmap/text `position_offset` separately from the explicit 3D draw layer.
`offset_depth` counts differing matched inputs and `max_offset_depth_delta`
reports their largest raw difference. This does not apply XY scale, combine
the offset with matrix translation or infer a native depth/occlusion effect.
Non-finite offsets mark extraction incomplete while the stock draw still runs.

A regression failed before the fix. Two focused marker CTests pass in 0.04
seconds and all 66 Lua chunks compile. The cached stock bitmap fixture confirms
distinct third-component values reach `Gui2.bitmap_3d` unchanged, independently
of its start-layer-adjusted layer. No live measurement or sizing fix is claimed.

9 September layer follow-up: a failing fixture reproduced omitted 2D/3D ordering
inputs. The observer now records those inputs before stock 2D drawing mutates
position[3], preserving the separate 3D layer argument and renderer offset.
Non-finite layers mark evidence incomplete without preventing the actual draw.
Two focused CTests (`marker_metrics|marker_gui`) pass in 0.18 seconds, and all
61 Lua chunks compile with the pinned LuaJIT gate. The optional cached-source
fixture also executes actual stock 2D/3D bitmap draws and verifies their final
layer arguments and return values. No installed runtime or settings changed.

9 September text follow-up: the observer also compares stock maximum text
layout extents and origin without drawing again, rescaling pixel arguments or
logging text. Failed/malformed measurements mark extraction incomplete while
the real draw still runs. The default-off path makes no layout calls. Fixtures
cover unchanged-font glyph-origin differences and both text signatures; an
optional cached-source run executes stock `UIRenderer.text_size` to check final
pixel dimensions, options forwarding and returned negative origin. Two focused
CTests pass in 0.05 seconds; the pinned LuaJIT gate compiles 61 chunks. No live
diagnostic was deployed and this does not supply complete popup raster bounds.

9 September follow-up: a failing fixture reproduced omitted depth-axis basis/
translation changes. Metrics now include these components and rotation pivots;
missing transform components mark extraction incomplete. The expanded
`marker_metrics` and `marker_gui` checks pass 2/2 in 0.04 seconds, and the pinned
Lua source gate compiles 58 chunks. This remains an offline diagnostic candidate,
not a deployed measurement or correction of pickup sizing.

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

The 97-file `b4baefc8faec-697097e6` development package passes staged and deep
extracted validation, including all 50 Lua chunks and pinned runtime hashes.
Its receipt is `artifacts/unattended/marker-metrics-package-receipt-20260908.json`.
It includes the default-off measurement module but has not been installed as a
full package. New atlas orientation candidates are excluded from the package.
