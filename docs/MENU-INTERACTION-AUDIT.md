# Menu interaction audit and offline rework

## Null-service recovery, 9 September

A stock input block can retain the same menu owner. Previously the VR sampler
kept its armed state while the null service bypassed input reads, so queued
controller presses/back/scroll could replay when the same view recovered.
The null route now retires the controller gesture without reading blocked input.
The first recovered sample drains accumulated edges and requires release before
a new hold. Both manager and direct View-service entry points share this rule.

The regression reproduced the delayed click before the fix. Tests cover both
primary and secondary buttons, queued back/scroll, held recovery, same-frame
direct-service recovery and subsequent fresh presses. Existing immediate mouse
and keyboard checks still pass. Five related menu/prompt/UI checks pass in 0.14
seconds, and all 69 chunks compile. Focused port `29b30bd` (PR #158) passes all
64 Lua checks in 0.895 seconds and compiles 56 chunks. Its staged fifteen-file
payload passes copied-install deployment and rollback, preserving original files
and removing additions. No real deployment occurred; worn menu behavior is open.

Latest checkpoint: the user accepted tested menu changes, but requested a broad
binding-hint pass beyond menu footers. The hub talent-points [I] reminder and
talent deactivation right-click are acceptance cases; do not patch the latter
in isolation. The automated hint inventory and hub/combat profile candidate are
documented in [the input audit](INPUT-REVISION-AUDIT.md) and
[night handover](handoffs/2026-09-06-end-of-day.md). New profile/hint code is not
yet deployed. Earlier entries below are chronological evidence.

## Packed-render desktop mirror follow-up — 6 September

The editor integration check found that Esc in the private range selected
native menu mode 5 while the desktop retained its previous world image. The
packed path gives the engine a private backbuffer; its Present mirror selection
copied that buffer for loading mode 2 but skipped native interactive modes 5/6.
The candidate fix includes all three flat modes in the engine-buffer copy rule,
while immersive modes continue using the completed eye mirror. The non-packed
path keeps its existing behavior. This changes desktop presentation, not menu
input, layout or shared-eye ownership.

Release build and CTest `stereo_color_resample`, `presentation_policy`,
`menu_input`, `hud_options`, and the pinned LuaJIT gate passed. The GPU test
includes the mode-selection regression and existing resample/resource-lifetime
checks. Live desktop validation in
`artifacts/unattended/menu-mirror-live-20260906.log` restored Esc rendering,
correct Mod Options clicks and the new editor button. Closing menus opened
the full Custom HUD editor; F3 closed it and restored all 26 alive HUD elements.
Afterward the harness reached `shared_ready=12442`, about 43 fresh pairs/s,
zero pose mismatches and zero interval fallback frames. No mod errors appeared.
The desktop retains the established eye-aspect encoding for gameplay menus;
the XR panel's existing aspect correction is unchanged. Worn acceptance of
this follow-up and individual shop visits remain pending.

## Follow-up coverage pass after live feedback

Latest acceptance: after the follow-up build was launched, the user reported
"Menus seem good." Record the tested menu behavior as accepted; this is not
evidence of individual visual testing of every one of the 72 registered views.

User confirmed Options cursor alignment, Operative highlight/selection and
premium-store input on aa1d10c. The Change Operative confirmation dialog remained
uninteractable and Commodore's Vestures was vertically compressed. Follow-up
changes below were subsequently deployed and received the acceptance above.

- Move shared adaptation from UIViewHandler to UIManager, covering constant
  elements such as confirmation popups as well as normal views. Popup identity
  owns the input sample while open, draining the opening/closing trigger edge.
- Also adapt direct `InputManager:get_input_service("View")` consumers. Source
  search found these in mission-board definitions, live-event templates,
  onboarding templates, expedition continuation and mission buffs. Already
  adapted services are not wrapped twice. Ingame, chat and ImGui services remain
  separate; stock UIManager null-service suppression still applies.
- Route every interactive view registered in stock `scripts/ui/views/views.lua`,
  including all 27 separately declared views. The checked-in
  [72-view inventory](../tests/tooling/menu-view-inventory.txt) is exercised by
  the input test: 63 interactive, seven loading/cinematic, two spatial/blank.
  Future game/mod-added views must be audited separately; this inventory is not
  a claim to cover unknown future content.
- Premium-store mode 6 now uses the same attached-eye aspect rule as mode 5.
  Both retain landscape presentation before shared eyes are attached. Native
  presentation tests cover both modes with and without shared eyes. This fixes
  the identified inconsistent rule; worn visual acceptance remains required.

| Registered menu family | Covered surfaces |
| --- | --- |
| System/Options | Escape, player options, custom settings, confirmation constant element |
| Operative | Inventory background, equipment, weapons/details, cosmetics/inspection, marks, mastery, talent and stimms |
| Armoury/Melk/cosmetics/barber | Credits and goods, marks and goods, contracts, cosmetics vendor and backgrounds, character appearance |
| Hadron | Crafting main, modify, barter, upgrade item/expertise, replace trait/perk |
| Premium store | Store, item details, premium currency purchase; external platform checkout is outside the game's UI service |
| Activities | Mission board/voting, lobby, training grounds/options, penance, Havoc background/play/reward, Horde, expedition |
| Social | Social menu/roster, group finder, report player |
| Other interactive | News, class/main selection/background, end/end-player, credits, live events/progress, DLC purchase, survey |
| Loading/cinematics | Splash/title/loading/mission intro/video/splash video/cutscene: flat loading route |
| Spatial/blank | Scanner keeps its Ingame input and spatial presentation; blank view remains a transition |

All normal view update/draw paths and persistent UI input routes were inspected.
Store receipt/checkout windows owned by Steam/platform software and text entry
are not converted into VR keyboards by this pass. Existing desktop handling
applies. No purchases, character changes, reports or inventory mutations were
performed for this code audit.

Validation: 26 Lua chunks compile; menu_input (including registry, direct-service,
popup ownership and click-through fixtures), menu_widgets,
presentation_state_transport and lua_source_compile pass. Release presentation
tests and XR harness build. Full live visual checking of every family is still
pending; code coverage must not be reported as visual acceptance.

5 September 2026. Baseline: `c3768e7`. This pass follows the reports that
Operative clicks fail and the Options cursor does not match highlighting.
VD is closed at the user's request. The rework below is built and tested
offline, not deployed or accepted in a headset.

## Findings

| Area | Evidence | Consequence and response |
| --- | --- | --- |
| Hit geometry | The old `widget_contains_menu_pointer` reconstruction omits pass scenegraph overrides, inherited transforms, style scale, size additions and widget scale, and uses the resolution scale rather than the actual renderer scale. Four isolated fixtures reproduced missed hits for scenegraph overrides, style scale, size additions and renderer scale 1.3. | Stop reconstructing widget rectangles for native menus. Feed the cursor into stock UI passes, which already apply these transforms. |
| Operative coverage | Stock Inventory draws private item grids, loadout widgets, wallet and background view elements. The previous private-grid hook covers only part of this. | Use the view handler's input service so all stock controls receive the same input contract. |
| Competing pointer owners | Legacy forced hover/press handlers coexist with desktop input. The harness moved the OS cursor even without explicit input injection enabled. | Bypass legacy handlers in native menu modes; stop default OS cursor movement. Explicit legacy injection remains opt-in. |
| Nested views | Stock UIViewHandler supplies null input to blocked views. Hand-written handlers do not consistently share that policy. SystemView exit unconditionally selected gameplay. | Preserve stock input suppression and reconcile the remaining view stack on exit. Drain held input when ownership changes. |
| DPI | Capture used a per-monitor DPI scope; extent and desktop pointer reads did not. Logs include a 1536x864 pointer source while other paths used 1920x1080. This establishes inconsistent handling, not proof that DPI alone caused the reported offset. | Apply the same physical-pixel DPI scope to capture, source extent, pointer reads and explicit injection. |
| Routing | Inventory has child pages beyond its main grid, including weapons, cosmetics, mastery, talents and stimms. | Route the inventory family and explicit related settings/character pages through native-window mode. |

The fixture is retained locally under
`artifacts/diagnostics/menu-audit-20260905/geometry-characterization.lua`.
Its geometry comparisons are isolated reproductions, not a full game renderer run.

## Input contract

`darktidevr_menu_input.lua` adapts the shared XR pointer at
`UIViewHandler._get_input`. It maps source pixels to the UI canvas exactly once;
stock UI passes apply their own renderer scale, geometry and clipping. An
immutable sample is shared by update and draw queries in the same frame.

Press, hold, release, movement, scroll and Back use that sample. Consumed
transport edges cannot repeat on subsequent frames. Modal ownership or transport
generation changes drain held input. Tracking loss cancels a drag once, then
returns input to the desktop. Reacquiring a held trigger cannot create a click.
Dragging outside the panel retains the last valid position until release.
Keyboard shortcuts remain available; secondary mouse/confirm actions are
suppressed while the XR pointer owns input. Stock null services and locked
bindings remain authoritative.

Twelve legacy per-view handlers are bypassed in modes 5/6, including the custom
Options dropdown/slider path. Other presentation modes retain their existing
paths. Capture and rendering lifecycle work is retained; this is an input
rework, not a claim that every menu render path has passed live validation.

## Functionality and acceptance matrix

All rows below require a fresh live run after deployment. Source review and
isolated tests do not establish end-to-end acceptance.

| Surface or transition | Required check |
| --- | --- |
| Character selection | Hover and one selection per trigger; no selection from hover alone. Existing non-native route remains a regression check. |
| Escape and Options | Cursor/highlight agree at centre and all corners; categories, toggles, sliders, dropdowns, scrolling and Back work. Back closes a dropdown before leaving its view. |
| Operative, direct and through Escape | Item grid, loadouts, tabs, weapons, cosmetics, mastery, talents and stimms receive clicks. Preview images remain visible and menus do not show a nested VR scene. |
| Scrolled/clipped controls | Hidden rows cannot activate; visible rows and scrollbars work after scrolling. |
| Vendors, crafting and store | Tabs and non-transactional navigation work through the shared service. Do not buy, destroy or otherwise commit inventory changes for testing. |
| Modal handoff | Holding a trigger while opening/closing a child does not click through. Repeated open/close cycles restore the correct remaining view. |
| Desktop and DPI | Physical mouse fallback aligns after controller loss, window resize and display scaling changes; Alt-Tab does not move or recapture the cursor. |
| Tracking loss | A held drag releases once; reconnecting while still holding does not activate a control. |
| Return to gameplay | Lighting, stereo motion, HUD and reticule recover after every menu exit, including nested menus. |
| Pickup markers | Both eyes retain the marker and edge scaling is checked separately; asymmetry remains open. |

Before the rework, the user confirmed reticule recovery and safe Escape
open/close, but Operative clicks and Options alignment remained broken.
Those confirmations are baseline evidence only. A prior shutdown error in
`flow_callbacks.lua:485` remains a separate unresolved observation.

## Offline validation

- Release builds passed for `darktidevr-xr-harness` and
  `darktidevr-menu-input-tests` using `cmake --build build/windows-vs2022
  --config Release --target <target>`.
- Pinned LuaJIT source gate passed for all 26 chunks using
  `tools/stereo/test-darktide-lua-source.ps1`.
- CTest passed all nine selected tests: `menu_pointer_state_transport`,
  `panel_pointer`, `presentation_policy`, `presentation_state_transport`,
  `menu_widgets`, `menu_input`, `menu_input_injector`, `hud_panel`, and
  `lua_source_compile`. Command: `ctest --test-dir build/windows-vs2022
  -C Release --output-on-failure -R
  '^(menu_pointer_state_transport|panel_pointer|presentation_policy|presentation_state_transport|menu_widgets|menu_input|menu_input_injector|hud_panel|lua_source_compile)$'`.
- New input fixtures cover coordinate extents/scales, immutable frame delivery,
  drag/release, modal ownership, tracking loss, transport restart, filtered
  bindings, null services, scroll/Back consumption and legacy bypass returns.
- The broader ten-test selection has one known baseline failure:
  `lua_source_invariants`, at `test-darktide-lua-invariants.ps1:519`, expects
  an obsolete unboxed reticule assignment. Running the same check on tracked
  baseline Lua files reproduces it. It was not weakened to make this change pass.
- `git diff --check` passed.

The follow-up launch received the user's "Menus seem good" acceptance. Preserve
saved HUD layouts and size/distance. Future renderer or input changes still need
targeted regression checks of the matrix; this does not claim every registered
view has been visited. The later DLSS world/loading/mirror checkpoint is recorded
in [current status](CURRENT-STATUS.md), separately from menu-interaction coverage.

## Character-select startup delay, 6 September

User reports hover working while clicks are initially ignored for about a
second. The source handler disables input throughout its transition, with
`TRANSITION_SPEED=0.3` for each fade direction. MainMenuView also disables Start
while character synchronization or an archetype entitlement promise is pending;
profile synchronization and server migration can block the whole view.

A passive startup trace now distinguishes the stock null service, profile sync,
character sync, disabled view and Start readiness. It logs state changes only,
at most 16 records in the first ten seconds of a view instance. A live launch
measured `stock_null_service` at elapsed 0.000 and full list/Start readiness at
0.572 seconds. No controller press was reproduced during that interval.
The initial conclusion that no extra VR timer existed was incomplete: the
subsequent native-input audit found a separate 1.25 s minimum menu age in
`MenuPrimaryInputState`, in addition to its 0.25 s released-input interval.
The fixed age requirement is now removed. A settled release still arms the
next fresh press, including after mode changes/reconnects, while an inherited
held trigger never clicks merely because the menu appeared.

The adapter also records why an observed XR press is rejected (view ownership
change, required release, outside surface, unavailable sample). It retains
same-frame expiration and never replays a missed click. Backend and transition
gates remain intact. This removes the native 1.25 s lockout; it does not remove
stock synchronization or transition waits. Worn early-click acceptance remains
pending and can be distinguished with these records.

Validation: 27 LuaJIT chunks pass; the 72-view menu fixture passes, including
separate list/Start gates and bounded diagnostics. Live evidence:
`artifacts/diagnostics/dlss-live-20260906/character-select-readiness.txt` and
`artifacts/unattended/character-select-readiness-20260906.log`.
The follow-up native Release build and `panel_pointer`, `gameplay_input`,
`presentation_policy`, and `menu_input` tests pass. New regression cases accept
a fresh click at 0.26 s while rejecting inherited holds and brief release
transients. The first full build encountered the running harness's file lock;
after stopping the live processes, the rebuild completed successfully.

## Optional resource-renderer error cleanup, 7 September

The crafting/system draw hooks temporarily replace the view renderer. A stock
draw error previously skipped restoration; the begin/end pass hooks likewise
left temporary pass fields and stack entries behind. These paths now restore
their own fields before propagating the original error. Failed pass-queue setup
does not mark that UI frame complete, allowing the next attempt to register it.
Successful and nested draws retain their previous renderer ordering.

The fixture executes the actual hooks and reproduces the old view/pass failures.
It covers stock errors, failed diagnostic drawing, same-frame setup retry,
nested passes and disabled/inactive/unavailable bypass. Five focused CTests pass
in 0.83 seconds, including all 37 Lua chunks. This affects only the optional
resource redirection path; it does not repair stock engine state after a failed
draw or diagnose a previously observed live transition. Undeployed.
