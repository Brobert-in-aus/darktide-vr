# Mission control audit — 8 September 2026

## Retiring UI input services, 9 September

Inventory, smart-tag and tactical-overlay eligibility now protect both method
lookup and execution of the input service's optional null queries. A retiring
service previously threw before the stock consumer ran. Failed probes now pass
the original service through without VR injection. Stock errors still propagate;
tag rejection remains latched across both eyes and inventory edges expire with
their hotkey scope. This does not add a release-before-rearm rule to tactical
overlay holds or change the independent keyboard route.

The regression failed before the guard. Three related communication/prompt/UI
CTests pass in 0.12 seconds, all 69 Lua chunks compile, and the optional cached
stock tactical update passes. Fixture communication effects remain mocked.
This source follow-up is undeployed and needs a focused communication port before
updating its staged payload; the existing `2dded96` payload remains unchanged.

## Stock tutorial text contract checked 9 September

The controller-prompt fixture now optionally executes the actual cached
`HudElementPrologueTutorialInfoBox._get_input_description_text`,
`_should_update_input` and `TextUtilities.localize_with_button_hint` through both
the controller and menu prompt hooks. Pure VR remaps refresh the stock tutorial
cache; VR loss restores the keyboard hint and recovery restores the remapped
controller label. Stock keyboard/controller action aliases and held/released
wording are preserved without changing global input-device mode. The prompt
scope ends with the tutorial call.

Validation used the pinned `build/dependencies/luajit/src/luajit.exe` with
`tests/tooling/test-controller-prompts.lua` and its ordinary four module arguments,
then optional arguments 5/6 pointing to cached
`scripts/ui/hud/elements/prologue_tutorial_info_box/hud_element_prologue_tutorial_info_box.lua`
and `scripts/utilities/ui/text.lua`. Cached source revision:
`0f0cb45991e9305ef4a7b925370792d7d6035f95`. The actual-source contract passes;
`ctest --test-dir build/xr-frame-stage-timing -C Release --output-on-failure -R
'^(controller_prompts|menu_prompts|gameplay_ui_input)$'` passes 3/3 in 0.06 seconds.
Input lookup and localization are doubles; no game, settings, display or input
mode changed. This verifies the text route, not rendered layout or tutorial
completion in the headset. No production change was required.

## Current saved layout checked 9 September

Read-only inspection of the saved action-first settings, resolved through both
the integrated and accepted focused Lua binding modules, yields this layout.
No settings changed. Their source hashes differ, but both resolve these settings
to the same combat and hub control routes.

| Physical control | Current combat action |
| --- | --- |
| Right trigger / left trigger | Primary / alternate |
| Right grip / left grip | Weapon special / combat ability |
| X | Mission device **and** cycle carried items |
| Y / B | Crouch / Blitz |
| A | Jump and dodge |
| Left stick click / right stick click | Sprint / tag |
| Right stick up / down | Quick weapon switch / interact and reload |
| Right stick horizontal | Smooth turn |
| Menu | System menu |

Hub overrides replace right-grip weapon special with inventory; all other
listed actions inherit. Direct carried-item and stim selection, weapon inspect
and target inspect have no assignment. Cycle carried items can route to the
normal or small pocketable slot under stock equipment rules, so lack of a direct
stim binding alone does not establish inaccessible stims.

The focused mapper's isolated neutral-to-X test emits both `device` and
`cycle_pocketables` on the same press. These correspond to stock `wield_5` and
`wield_3_gamepad`, which select different inventory routes. This is a concrete
overlap to check with relevant equipment, not proof of a live progression bug
or permission to overwrite the user's choice. Stock action precedence and
equipped-item transitions still need verification. Communication-wheel,
tactical-overlay and voice/chat controller-route gaps remain as below.

Further offline evidence executes the actual stock parser `_evaluate_input`
with real mapper output. Both requests are true, and reversing their order in
the parser's input array reverses which raw request wins. The common wield list
is populated from `pairs(slot_configuration)`, so there is no documented explicit
device-over-cycle priority to rely on. This is not an equipment-aware fallback:
selection occurs before slot eligibility. Separate physical assignments remove
this raw-input ambiguity in the fixture, but no replacement layout is imposed.
The optional `test-wield-overlap-stock-contract.lua` passes with both integrated
and accepted focused mappers. Full action-queue/weapon execution remains untested.

The old recommendations to bind unused stick directions and move ability onto
one of them no longer apply: both directions and left grip are already assigned.
Normalized diagnostic extracts stay under ignored `artifacts/unattended/`;
neither the full settings file nor account data is committed.

The integrated source now offers `/dtvr_binding_conflicts`, a read-only report
for the mapper's current combat/hub profile. It lists physical controls assigned
to multiple selectors from stock's common wield list: quick weapon switch,
carried item, stim, mission device and carried-item cycle. It does not report
intentional jump/dodge or interact/reload combinations as wield conflicts, and
excludes horizontal directions owned by turning. Hub overrides and remaps use
the same resolved mapping as actual input; no settings or input state is changed.
Running the report offline against the earlier saved snapshot identifies the X
device/cycle overlap in both profiles. This command is not deployed and is not
included in the separate focused tactical-overlay port at `8eab44e`.

## Communication-wheel stock contract checked 9 September

9 September inventory follow-up: a regression reproduced a retained inventory
input proxy continuing to request opening after the stock hotkey handler returned.
Each request now belongs to a unique handler scope and input sample. A retained
proxy cannot revive in a later call, cross player replacement, survive routing
loss, or remain active after an exception. Expiration preserves independent
keyboard input, and both null-service forms remain blocked. Five focused input
tests pass in 0.08 seconds; the pinned LuaJIT gate compiles 62 chunks. This source
fix is undeployed and is not part of the earlier focused overlay port.

The related tag/overlay follow-up binds both HUD proxies to unique handler scopes
and input samples too. A retained tag proxy previously injected after return;
an old tactical proxy could revive during another update of the same HUD.
Nested remote HUD calls now suspend tag injection and restore the outer scope
afterward. Exceptions, replacement players and newer samples cannot keep an old
proxy alive; independent keyboard inputs and repeated same-frame tag reads are
preserved. The five focused input tests and actual stock overlay update fixture
pass; all 62 Lua chunks compile. This follow-up is also undeployed.

The cached stock `_handle_com_wheel` is now exercised by
`tests/tooling/test-communication-wheel-stock-contract.lua`. Its input is held
`com_wheel`, separate from pressed `smart_tag`. It opens after the saved delay
(strictly after the threshold), or sooner through stock controller navigation.
The mouse route pushes a cursor; the controller route reads
`navigate_controller_right` and retains a 0.15-second close delay.

Release queues a physics-safe callback. Until that callback clears the start
time, a repeated handler call can queue another stop. A null/blocked input also
looks like release, rather than cancellation. Pending single-tap location tags
can mature while input is blocked. The fixture demonstrates these branches with
mocked side effects; it never calls game, voice, chat or network services.

The future VR route therefore needs all of the following before deployment:

- A hold binding that remains unassigned until deliberately configured, retaining
  the current R3 tag route and saved layout.
- Exclusive right-stick ownership from wheel gesture start through closing and
  neutral rearm, covering horizontal turn and up/down gameplay actions.
- An owned, fresh navigation vector: the stock presentation mutates its returned
  vector into screen coordinates, so the shared controller sample cannot be used
  directly. No global gamepad-mode flip to obtain this behavior.
- One stock handler update per input frame, with the same decision for both eyes.
- Explicit cancellation on tracking/player/menu transitions, including stale
  deferred release and pending tap requests. A false held value alone is not a
  cancellation contract. Preserve independent keyboard/mouse gestures.
- Local HUD ownership and stock action selection, physics-safe callback and
  communication policy. Do not directly emit chat, voice or tag events from the
  VR mapper.

These are source-backed integration requirements, not a working wheel binding
or live acceptance. Selection geometry and stock cursor/camera ownership still
need an isolated adapter before adding the option to the installed runtime.

The unloaded `darktidevr_communication_gesture.lua` candidate implements the
gesture boundary: first neutral acquisition, hold/release state, right-stick
claim through closing and neutral rearm, immutable copies of the first input
frame decision, and a generation token for one deferred release. Blocking,
owner change, invalid stick samples, backwards frames and explicit cancellation
revoke that token. The adapter must call `take_release` inside the deferred
callback, and `closed` only after stock cursor/close-delay cleanup. It must also
cancel on adapter failure or abandoned HUD lifecycle; this pure component cannot
observe engine callbacks or apply a guessed timeout. A release retains the
stock's prior hover selection rather than providing a new navigation sample.

This component is not loaded, adds no binding option, and sends no game input.
The remaining adapter must cancel owned stock wheel context and pending tap
state without affecting keyboard/mouse ownership, provide private navigation
vectors, consume all stick actions and preserve stock action execution. Three
focused CTests pass and the pinned LuaJIT gate compiles 61 chunks.

The unloaded `darktidevr_communication_navigation.lua` now supplies private
navigation vectors while a valid held gesture owns the wheel. It maps a raw
stick sample to stock cursor coordinates for mouse-mode presentation, and
returns fresh raw vectors for stock gamepad navigation/instant-open reads.
It never changes `InputDevice.gamepad_active`, warps the OS cursor, injects a
button, or sends a game/chat/voice event. Existing source methods and unrelated
inputs remain bound to the stock service.

The proxy copies the sampled coordinates and expires on callback return/error
or token revocation. The caller must supply a vector factory and a live ownership
predicate; null services are never overridden. Call this only for an owned,
held gesture. The future HUD adapter must skip owned presentation on intentional
release to retain the prior hovered option, cancel deferred/pending tap state
on invalidation, and suppress gameplay stick actions through neutral rearm.
Those integration duties and the unassigned hold binding remain unfinished.

Eighty cases execute actual cached stock wheel presentation across two viewport
sizes, two UI scales, eight outer directions plus center/deadzone samples, and
both current input modes. Selection, label, angle and highlight agree with the
stock gamepad baseline, with no sample/global-mode mutation. Three focused CTests
pass in 0.10 seconds; the pinned LuaJIT gate compiles 63 chunks. This is offline
adapter evidence, not a working installed wheel or live communication test.

The binding and turning consumers now accept an optional final `exclusive_stick`
boolean. An explicit claim cancels all directional shortcuts without synthetic
attack-release edges and disables smooth/snap turning. Ending the claim requires
a valid stick sample within the existing turn-neutral radius (0.25 on both axes)
before any directional shortcut can resume; changing sectors cannot escape that
rearm. Physical buttons and healthy trigger aliases retain their normal edges.
Existing callers omit the argument and keep their prior behavior.

Seven focused tests pass in 0.24 seconds, including both snap modes, smooth turn,
support-grip coexistence and a composed wheel gesture/turn sequence. All 63 Lua
chunks compile. The actual gameplay adapter still applies turning before binding
sampling: the future wheel route must determine its claim and pass it to **both**
consumers before either applies gameplay. The new optional gates are not wired
into that route or deployed yet; they do not establish a working wheel binding.

## Tactical overlay hold source candidate, 9 September

The action catalog now has **Hold tactical overlay**, unassigned by default.
It is routed to stock `tactical_overlay_hold` only while the current human HUD's
`HudElementTacticalOverlay.update` executes. That method fetches Ingame input
again internally, so routing uses the existing central InputManager hook rather
than adding a competing hook or injecting a gameplay-cache alias stock never
reads. Stock owns activation, animation, menu blocking and release.

The hold is cancelled with gameplay routing/tracking loss and player replacement;
the binding mapper requires neutral before reactivation. Menu/inventory requests
take precedence. Keyboard input remains available, null services are preserved,
nested remote HUD updates cannot borrow the local scope, and exceptions restore
the previous scope. A retained proxy stops injecting outside the owning update.
The action's prompt alias and option label are included. No saved setting changed.

Seven focused checks pass, all 61 Lua chunks compile, and an optional cached-source
fixture executes the actual stock update for hold, release, repeated frames and
menu blocking. This source change is **not deployed**. Worn readability, complete
overlay navigation/scrolling and interaction with its own input-taking panels
remain unverified; this supplies hold access, not the entire overlay interaction
route. Communication-wheel and voice/chat access remain separate work.

## Historical 8 September audit

This is the **earlier pre-preview-relaunch binding snapshot**, not the final
saved layout. Subsequent action-first menu testing changed assignments (the
user later reported an L Grip ability label). Read current saved settings before
changing controls or claiming an action remains unbound. See the
[next-session control checklist](phase1/todo-2026-09-09.md) for unresolved route
coverage, and the [night handoff](handoffs/2026-09-08-night.md) for acceptance.

Reviewed before the frame-clear preview relaunch. Sources: saved VR mappings in
user_settings.config, the installed/focused controller binding, gameplay UI and
spectator modules, stock Ingame/View aliases, and the local Steam cloud save.
No bindings were changed. Account identifiers and the full save are excluded.

## Quest layout at the time of this audit

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

## Gaps at the time of this audit

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
