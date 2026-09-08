# Pickup popup sizing and related marker audit

The user reports that the item-pickup popup shrinks near a screen edge and has
different apparent sizes in the two eyes. This is an active visual bug. Earlier
worn reports on 4 and 5 September also left pickup edge sizing unresolved.
Central alignment and visibility in both eyes do not establish correct sizing.

## Source findings, 8 September

The stock source snapshot is `0f0cb45991e9305ef4a7b925370792d7d6035f95`.
Paths below are relative to its `scripts` directory.

| Surface | Shared behavior to inspect | Current source finding |
| --- | --- | --- |
| Pickup/interact marker icons | Distance scale, hover growth, tagged edge clamp | `ui/hud/elements/world_markers/templates/world_marker_template_interaction.lua` changes ring/icon/background sizes in its update. Clamped markers ignore distance scale. |
| Pickup/interact text popup | Background, description, key hint and hold progress | `ui/hud/elements/interaction/hud_element_interaction.lua` sizes from text and intro animation; its position helper copies the marker offset. No explicit edge-dependent shrinking rule found there. |
| Smart-tag prompt | Marker-relative line, text and hint | The VR draw hook positions this separately from the interaction popup. Include it even if the stock pickup popup is corrected. |
| Location ping, attention and threat | Distance scale, hover and edge transitions | Their marker templates set `ignore_scale` when hovered or clamped. |
| Unit threat, veteran and companion threat | Distance scale, hover, clamped arrow/text | These three threat templates use the same scale exemption. |
| Player assistance | Distance scale, clamped icon/text | The template derives `content.scale` from the clamp state. |
| Objectives and hub objectives | Per-style scale and clamped arrows | Their templates have scale settings inside widget definitions; do not assume only top-level template settings matter. |
| Combat, companion and hub-companion nameplates | Distance scale and offscreen representation | Templates switch presentation using `content.is_clamped`. |
| Generic/party nameplates and chat bubbles | Distance scaling | Include in the common replay check even without a confirmed edge symptom. |
| Training-ground marker | Clamped-arrow visibility | Include the boundary transition; no top-level distance scaling was found. |
| Beacon | Vector icon, distance text and clamping | `world_marker_template_beacon.lua` is registered, uses `slug_icon`, and has distance fade plus a clamped edge policy. |
| Health bar | Rectangles, text, distance fade and culling | `world_marker_template_health_bar.lua` is registered and does not clamp. Preserve its normal disappearance at the shared boundary. |
| Damage indicator | Animated damage text, bars and custom logic | `world_marker_template_damage_indicator.lua` draws text directly from a `logic` pass. A correction limited to declarative text passes would miss these numbers. |

The VR code already skips stock `_apply_scale` during the second-eye replay.
That function otherwise eases mutable sizes, offsets and pivots on every draw.
It also snapshots each HUD element's render settings, refreshes the interaction
pivot for each eye, and uses a shared angular boundary for clamping. These
existing protections must be preserved; simply disabling stock distance scale
would not establish a fix for the reported defect.

The scene is rendered through two rotated, symmetric optical projections.
Current marker replay adjusts the anchor position but reuses widget geometry.
A fixed pixel extent subtends a smaller angle toward a perspective image's
edge, and the two optical centers differ. This is a geometric explanation to
investigate, **not a confirmed cause of the user's popup symptom**. Shader-level
GUI behavior and per-pass geometry still need to be distinguished from it.

## Complete primitive inventory and projection model

The source pass now covers all **20 registered world-marker template files**,
plus the separate interaction popup and smart-tag prompt. Its local inventory
is `artifacts/unattended/marker-primitive-inventory-20260908.json`. The template
passes are `texture`, `texture_uv`, `rotated_texture`, `text`, `rect`,
`slug_icon`, and `logic`. Damage-indicator logic calls `UIRenderer.draw_text`
directly. Beacon vector icons, health bars and animated damage numbers expand
the initial family list above; none is excluded merely because it is not a
pickup. This is source coverage, not live visual acceptance of all 20 families.

The popup definition combines text, textures, UV textures and rectangles.
`UIRenderer.draw_texture` and `draw_texture_uv` multiply positions and sizes
by the renderer scale before passing them to the GUI. Their script draw
functions apply alpha, layers, material flags and snapping without an explicit
screen-edge shrink rule. `script_draw_text` likewise forwards the font/extent
to the GUI without such a rule. Rotated textures use a transform through
`script_draw_bitmap_3d`. The underlying GUI shader is still an unmeasured part
of the path; these source facts alone do not establish its output extents.

A projection-only model uses the running session's logged 2496x2688 eye
extent and runtime FOVs, with the same rotated symmetric projection convention
as `darktidevr_projection_math.lua`. It compares a hypothetical **100x100 pixel
square**, not a measured popup. Eye translation, finite depth, clipping and
actual material/shader behavior are excluded. At zero pitch:

| Shared direction | Left angular width | Right angular width | Left/right width | Left/right height |
| --- | ---: | ---: | ---: | ---: |
| Center | 4.892 degrees | 4.892 degrees | 1.000 | 1.000 |
| 20 degrees right | 3.944 degrees | 4.715 degrees | 0.837 | 0.915 |
| 35 degrees right | 2.745 degrees | 3.873 degrees | 0.709 | 0.843 |
| 35 degrees left | 3.873 degrees | 2.745 degrees | 1.411 | 1.187 |

The model inverse-projects the square's edge midpoints into rays and measures
their included angle. Evidence is
`artifacts/unattended/marker-angular-size-model-20260908.json`. The source log
is `melee-preview-post-census-session-20260908.log` in the same directory.
This quantitatively reproduces the *kind* of symptom, without proving it is
the whole live cause. Unequal width/height ratios also show why a single
per-eye scalar cannot generally establish agreement.

There are two distinct geometric requirements: project the full primitive
into both eyes consistently, and define its intended size away from center.
Mapping only the anchor satisfies neither. An eye-to-eye homography can align
the second eye with the first while retaining the first eye's edge shrink.
A shared tangent-plane representation can define angular size first, then
project geometry into both eyes; it must preserve finite-depth anchors and
cover text, rotated/UV textures, bars, icons and direct logic draws together.
Do not adopt a partial scalar or texture-only change as the completed fix.

## Work and acceptance checklist

- [x] Prepare a bounded, default-off [primitive measurement candidate](MARKER-PRIMITIVE-METRICS.md)
  for marker, popup and tag draws; offline checks pass, live measurements pending.
- [x] Inventory all 20 registered templates and their primitive families,
  including the separate popup/tag paths and custom damage-number draws.
- [ ] Determine whether actual popup primitive extents, projection, or both
  produce the reported asymmetry. Use the existing worn report and passive
  evidence before selecting a correction.
- [ ] Correct sizing with a shared stereo policy that preserves depth and
  alignment, rather than independent edge thresholds for each eye.
- [ ] Audit all surface groups above, including material, text, icon, arrow,
  hover, hold-progress and fade behavior where present.
- [ ] Check a nearby pickup at the center and near the left, right, top and
  bottom edges, with both eyes observed. Repeat at another distance.
- [ ] Check tagged versus untagged items, a hold interaction, objectives,
  teammate/help markers and pings through their edge transitions.
- [ ] Confirm worn size/position agreement, readable text, sensible offscreen
  visibility and recovery after turning back to center. Do not infer this from
  frame counters or compiler success.

No sizing correction has been deployed or visually accepted. Billboarding
retains the user's priority after the pre-launch work.
