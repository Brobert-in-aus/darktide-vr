# Menu interaction audit and offline rework

## Follow-up coverage pass after live feedback

Latest acceptance: after the follow-up build was launched, the user reported
"Menus seem good." Record the tested menu behavior as accepted; this is not
evidence of individual visual testing of every one of the 72 registered views.

User confirmed Options cursor alignment, Operative highlight/selection and
premium-store input on aa1d10c. The Change Operative confirmation dialog remained
uninteractable and Commodore's Vestures was vertically compressed. Follow-up
changes below are built/tested but not yet deployed into that running game.

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

Next gate: reconnect VD and run the required Ready preflight before any sync or
launch, then execute the matrix above. Require fresh stereo initialization and
nonzero `shared_ready`; neither those counters nor an OpenXR session substitute
for real pointer/highlight and visual acceptance. Saved HUD layouts and the
accepted HUD size/distance are unchanged.
