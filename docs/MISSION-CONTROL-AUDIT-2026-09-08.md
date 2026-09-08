# Mission control audit — 8 September 2026

Reviewed before the frame-clear preview relaunch. Sources: saved VR mappings in
user_settings.config, the installed/focused controller binding, gameplay UI and
spectator modules, stock Ingame/View aliases, and the local Steam cloud save.
No bindings were changed. Account identifiers and the full save are excluded.

## Current Quest layout

| Physical control | Mission action |
| --- | --- |
| Right trigger | Primary attack/fire |
| Left trigger | Block/aim/alternate action |
| Right grip | Weapon special |
| Left grip | Blitz |
| X | Interact and reload |
| Y | Quick weapon switch |
| A | Jump and dodge; cycle spectator camera when dead/observing |
| B | Crouch/slide |
| Left stick | Movement relative to head; click to sprint |
| Right stick | Smooth turn left/right at saved 90 degrees/second; click to tag |
| Right stick up/down | Unassigned |
| Menu | System menu |

Hub overrides inherit the above except right grip opens inventory. Combined
X and A mappings emit both configured action semantics; they are not separate
tap/hold shortcuts. They do not reproduce the user's separated keyboard jump.

## Gaps

| Action | Status / consequence |
| --- | --- |
| Combat ability | Implemented but no physical assignment; distinct from left-grip Blitz |
| Carried item / stim / mission device | Implemented as wield_3 / wield_4 / wield_5, all unassigned; mission-device access is a mission progression concern |
| Cycle carried items | Implemented as wield_3_gamepad, unassigned |
| Weapon inspect / inspect target | Implemented, unassigned |
| Communication wheel | No mapper action; R3 only sends a tag press, not wheel hold/release |
| Tactical overlay and its controls | No mapper action |
| Push-to-talk / open chat | No Quest action; keyboard remains available |
| Direct weapon slots 1/2, weapon scroll | No dedicated mapper action; Y covers quick switching |

There are two unused stick directions with smooth turning retained. Left/right
virtual action bindings are deliberately ignored while turn mode is enabled.
Suggested first assignment: up = combat ability, down = mission device. This
still leaves carried items and stims requiring an additional binding scheme;
it is not a complete mission layout. Do not overwrite saved bindings as part of
a review-only request.

## Saved keyboard overrides and mod shortcuts

The account save contains Ingame overrides for jump = keyboard_left alt and
voip_push_to_talk = mouse_extra_2, and View show_chat = keyboard_numpad plus.
An additional saved profile has a separate dodge override; do not blend profiles.
Stock defaults are references, not proof of the current user's assigned keys.

Saved mod shortcuts: F6 toggles melee preview; F4 requests DMF options; Custom HUD
uses F2 to hide HUD and F3 for customization. SoloPlay's direct menu shortcut is
empty, with I assigned to its inventory shortcut. F4 therefore is not a direct
SoloPlay menu binding. The earlier user-reported invisible F4 menu remains a
separate visual/input issue even though the saved bindings have distinct keys.

## New visual report

The user confirms the mission crosshair works but reports hit markers are not
stereo. The HUD panel hook suppresses only the stock aiming widget and preserves
base hit/kill widgets in HudElementCrosshair. Those feedback widgets need a
stereo-aware position/depth audit against the hand-aimed reticle; the working
crosshair does not establish correct hit-marker presentation. Added to active
TODO; no hit-marker fix is included in this preview frame-lifetime deployment.

