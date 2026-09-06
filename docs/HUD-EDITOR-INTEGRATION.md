# Optional Custom HUD editor integration

The VR mod interoperates with a separately installed and enabled Custom HUD.
The inspected local distribution identifies itself as 2.1.6; its changelog
credits current maintenance to Sungrief. The package contains no LICENSE file
or other explicit redistribution grant. Attribution by itself is not a grant.
The release approach is therefore an optional dependency, not bundling or
copying Custom HUD source into this mod. Upstream redistribution permission
remains unverified and would be needed before changing that approach.

`tools/stereo/install-custom-hud-editor.ps1` is a developer helper for installing
an existing user-supplied source directory. It preserves an existing installed
copy and is not a downloader or permission to redistribute the dependency.

## Player flow

With the VR HUD active in gameplay, open Mod Options > Darktide VR and select
**Toggle editor**. Close the menus and the full Custom HUD editor opens in the
flat desktop mirror, using the VR canvas and existing border/cursor adapter.
The same button requests closing an active editor. Selecting it again while
still in menus cancels the pending request. Custom HUD's own configured editing
key continues to work.

While editing, the shared HUD texture displays:

> Use the desktop view to edit your HUD layout.

Both eyes consume the same instruction texture. The instruction disappears on
editor close; it does not take over the cursor or modify saved element positions.
Custom HUD owns editing, visibility, persistence and its keybindings. The adapter
waits for its normal menu-input guard instead of toggling while a menu owns input.
Missing/disabled dependencies and attempts before an active gameplay HUD produce
an explanatory notification. Pending requests are cleared on HUD destruction or
dependency disable, so they cannot unexpectedly open after a level transition.

## Validation

Windows x64 CTest `hud_panel`, `hud_options` and `lua_source_compile` pass.
The fixture covers missing dependency, unavailable HUD, deferred execution,
cancellation, one-shot toggling, dependency disable, persistent instruction
drawing only while editing, and restoration of renderer pass state.
Live editor rendering and worn readability are tracked separately from these
offline checks.

The initial live check reached the private range with fresh shared eyes and
the accepted HUD dimensions. Opening Esc then left the desktop showing the
world while the harness switched to native menu presentation mode 5. This
blocks the new button/notice acceptance until the menu rendering path is fixed;
the editor itself had not been activated when it occurred. Initial evidence is in
`artifacts/unattended/hud-editor-live-20260906.log` (ignored). The implementation
was checkpointed before repairing that separate rendering issue.

The follow-up menu mirror fix unblocked the check. The new options button
responded at its displayed position, closing menus opened the full Custom HUD
editor with its border and element list, and the desktop instruction rendered
in the shared HUD texture. F3 closed the editor, removed the instruction, and
restored the alive HUD group (26 elements). Fresh eye pairs continued without
pose mismatches. No saved item positions were edited during this check.
See `artifacts/unattended/menu-mirror-live-20260906.log` and the
[menu follow-up](MENU-INTERACTION-AUDIT.md). Worn readability remains pending.

## F3 editor with DLSS (6 September 2026)

The generated-stereo path now routes Custom HUD editing explicitly as a desktop
menu. Its image is drawn by a dedicated final UI overlay viewport; the gameplay
HUD GUI resolves into an eye texture under DLSS and cannot supply the desktop
editor. Closing F3 deactivates the overlay and restores the existing world HUD.
The original Custom HUD still owns input, layout edits and persistence.

Continuous generation pauses on non-world presentation or a rejected Present
binding. Captured inputs are discarded only after their GPU fences complete;
previously tagged inputs retain their exact completion-ticket lifetime. Returning
to gameplay starts a fresh temporal sequence. An expired original ring also lets
the XR consumer use current legacy stereo instead of freezing on old ring data.

Live check: the editor border, element list, selected-element properties and
instruction are visible with DLSS enabled. Closing F3 returned to approximately
51 original plus 51 generated distinct frames per second. No saved layout was
changed during this check. Cursor dragging/persistence and worn acceptance remain
user checks. Evidence: artifacts/unattended/dlss-editor-overlay-live-20260906.log.
The earlier mode-only attempt recovered gameplay but showed a stale loading/menu
image; that attempt was not accepted as an editor fix.

Validation: Release native/XR builds, all 31 Lua chunks, continuous_recovery,
hud_panel, hud_options, streamline_submission and the existing generated transport
checks pass. The recovery test repeats partial/full capture interruptions on WARP;
the HUD fixture checks overlay reuse, close/deactivation and resize destruction.

### Stock crosshair versus weapon counter

The saved Custom HUD layout hides HudElementWeaponCounter|pivot. That element
shows weapon-specific kill charges, cooldown charges and overheat lockout
indicators near the crosshair. It is separate from HudElementCrosshair, which
Custom HUD excludes from its editable element list.

The VR HUD adapter now suppresses only HudElementCrosshair's active aiming widget
while VR HUD is enabled, preserving the element's base hit-feedback widgets and
restoring its pointer even after a draw error. It leaves the hand-aimed XR reticle
and user layout settings intact. LuaJIT 31 chunks and hud_panel regression pass;
next-launch worn confirmation remains required.

The user reports that generated motion now feels consistent with the reported
frame rate. They also report blur around HUD/world item markers. Current FG uses
HUDless colour and the complete final colour, without a tagged UI colour/alpha
buffer. Inspect explicit UI isolation before changing temporal quality settings;
NVIDIA's v2.7.30 ProgrammingGuideDLSS_G recommends premultiplied UI colour/alpha
for improved HUD/nameplate quality. Edge blur has not been declared fixed.

### UI input capture, 6 September 2026

A one-shot readback of exact owned input textures in live PID 138708 confirms
HUD/nameplate/item-marker separation. Both eyes are 2496x2688; the scene input
contains no visible HUD/markers. Final-minus-scene differs on 98,912 left pixels
(1.474%) and 83,644 right pixels (1.247%), confined visually to the overlays.
Both scene and final alpha channels are entirely 255, so a true UI transparency
layer cannot be read from their alpha channels. This rules out the previous
resolution mismatch and obvious UI contamination of HUDless input in this sample.
It does not by itself identify the exact generated-frame blending artefact.

Optional diagnostic: create %TEMP%/darktidevr-ui-readback.request after gameplay
stabilizes. The native continuous submitter consumes it once per process, copies
four exact owned COPY_DEST textures into readbacks on the existing stage list,
restores states, and exports only after a dedicated queue fence completes.
Each allocation is bounded at 128 MiB, with dimensions read from the texture.
No output image is altered. Export runs off Present. Current live export passed.
Use tools/stereo/compare-dlss-ui-inputs.py STEM --output DIRECTORY to generate
per-eye statistics and scene/final/difference comparison. The difference is not
claimed to be a recovered alpha mask. Generated files stay ignored under artifacts
or temp. Evidence: artifacts/diagnostics/dlss-ui-quality-20260906/comparison.png
and comparison.json; artifacts/unattended/dlss-ui-quality-live-20260906.log.

Native Release build, continuous_recovery, hud_panel and pinned 31-chunk LuaJIT
gate pass. The duplicate stock crosshair change is included in this live run;
user visual acceptance is pending. F3 was not automatically pressed on this run.

### 2026-09-06: preserve desktop input alongside VR

User requirement: keyboard and mouse must remain available alongside VR controls.
The DLSS editor's mode-5 output had unintentionally enabled the menu pointer
proxy, suppressing right/middle/confirm actions and replacing mouse wheel input.
The adapter now retains stock mouse buttons and confirmation actions, combines
wheel input with XR scrolling, and preserves stock mouse movement. Desktop-only
Custom HUD editing bypasses that proxy; actual views and modal dialogs still
receive the combined menu route. Right/middle mouse holds also select the desktop
pointer position in the harness, as left mouse already did.

Validation: Release harness and menu-input tests built; ctest menu_input,
menu_input_injector, hud_panel, hud_options and lua_source_compile all passed.
The Lua gate compiled 31 chunks. Live editor right-click/wheel acceptance remains
pending. Two Ready preflights created a VDXR session but submitted zero of 600
frames. Game was closed for the planned update; no deployment/relaunch followed
the failed readiness checks. Do not mark the editor regression visually accepted.
