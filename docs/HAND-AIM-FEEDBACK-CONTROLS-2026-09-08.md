# Hand-aim feedback and Light assist

The staff charge indicator is part of HudElementCrosshair's dynamic widget,
which the VR HUD suppresses to avoid a second aiming reticle. It is not an
independently hidden Custom HUD item. At the user's request, charge bars and
hit/weakspot feedback now draw around the hand-aim target rather than on the
fixed HUD. The stock template still owns charge animation, UV masks, colour,
opacity, hit lifetime, offsets and rotated hit segments.

An immediate world GUI places the feedback at the existing validated reticle
target. Its pixel scale follows the accepted 41-pixel XR reticle atlas and size
caps. Both eyes see the same world geometry; screen-edge distance does not
change size. GUI ownership resets with the HUD/world and mod unload, and menus,
hidden HUDs, absent targets and stale owners suppress drawing. The fixed HUD
continues to suppress the original crosshair widget, avoiding duplicate bars.

The first menu-height change missed a persistent DMF view created before the
XR render extent changed. The user confirmed the lower half remained empty,
and a read-only desktop observation confirmed it. The options layout now checks
the fitted canvas during active updates, refreshing only when its height changes.
A layout diagnostic records the resulting bottom and scale. Worn acceptance is
still required; passing the sizing fixture is not a visual result.

PC aim assist is controller-gated. The VR adapter now uses the stock precision
target finder and assisted trajectory with Light selected, applying half the
stock correction and capping it at one degree. Corrections over five degrees
are rejected. This is a Light VR adaptation, not a claim that the complete
thumbstick slowdown/ADS-lock behaviour has been reproduced. It adjusts the
shared hand aiming direction before stock input packing, so shots and reticle
consume the same aim. It does not change headset tracking or force gamepad
input state. Actual gamepad input and auto-aim buffs retain stock handling.

Target freshness, local-player ownership, weapon identity, tracking generation,
UI ownership and the saved Light setting gate the adapter. Stock target queries
and visibility checks remain in place. The one-shot local startup file
`darktidevr_aim_assist_light.flag` containing `enabled` requests the existing
`controller_aim_assist=new_slim` setting through the save manager; restore that
file after the fresh `DARKTIDEVR_AIM_ASSIST setting=Light saved=true` message.
Subsequent user setting changes are not overwritten.

Validation on Windows x64: the existing isolated CMake build's nine relevant
Lua tests pass (weapon assist, crosshair feedback, menu layout, stabilisation,
HUD panel/options, reticle ownership/stock reticle, gun alignment). Fixtures
cover stock feedback geometry/masks, world target movement, immediate GUI
creation, hide/destroy, bounded correction, stale/foreign targets, weapon and
tracking changes, duplicate consumers and the one-shot settings save. Main
LuaJIT gate: 56 chunks; focused gate: 49 chunks. No native/viewer rebuild.

Pending: deployment/restart after the current worn test, fresh stereo init and
advancing shared_ready, no feedback/assist errors, then user observations of
staff charge and hit feedback aligned with the hand reticle in both eyes, full
menu height, and Light assist feeling useful without fighting hand movement.
Preserve accepted DLLs, viewer and SoloPlay settings. The prior menu/aim patch
was deployed successfully in the 08:57 UTC launch; generated stereo and nonzero
shared_ready were observed in the Psykhanium, not measured in a solo mission.
