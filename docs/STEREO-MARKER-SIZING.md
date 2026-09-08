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

## Work and acceptance checklist

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
