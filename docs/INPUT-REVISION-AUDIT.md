# Input revision audit — 6 September 2026

7 September continuous-work follow-up: a failed native controller read now
cancels Lua delivery without injecting the mapper's synthetic release into stock
attack caches. Previously the policy could still be active while the native
read failed, and nonzero cancellation releases passed the final guard. The real
adapter regression reproduces this and covers cleared/stale returned button
levels, reconnect with a held attack, neutral rearming, ordinary release and
preserved keyboard input. Six focused input/policy/source checks and 36 LuaJIT
chunks pass. This covers unavailable/stale native reads (native return code 2)
and defensive nonzero errors; it does not claim all per-hand tracking-loss or
worn charge-cancellation behavior has been validated. Candidate is undeployed.

This records the routing audit and subsequent candidates. The raw OpenXR actions
already include both sticks and both stick clicks. The current gameplay mapper
is in `src/core/gameplay_input.cpp`; its game-side delivery table is
`presentation.gameplay_input_bindings` in the stereo Lua module.

End-of-day checkpoint: turning, tested menu changes and right-wrist alignment are
user-accepted. Hub/combat override profiles, stock inventory delivery and shared
onboarding/tutorial hints through 04b6053 are tested offline but not deployed.
Talent deactivation right-click remains an explicit unfixed broad-pass case.
See the [handover](handoffs/2026-09-06-end-of-day.md) and the latest implementation
sections at the end of this document; older pending labels below are historical.

| Quest control | Current gameplay routing | Menu routing |
| --- | --- | --- |
| Right trigger | Primary attack/fire | Select |
| Left trigger | Alternate attack/aim/block | None |
| Right grip | Weapon special, including staff melee/push | None |
| Left grip | Blitz/grenade ability | None |
| X | Interact and reload together | None |
| Y | Quick wield | None |
| A | Jump and dodge together | Select |
| B | Crouch | Back |
| Left stick | Movement, configurable head/left-hand reference | None |
| L3 | Sprint | None |
| Right stick | Four optional directional shortcuts; all unbound by default | Vertical scrolling |
| R3 | Smart tag through stock HUD handler | None |
| Left menu button | Opens stock system menu | Back |

The initial missing R3/menu consumers are now implemented below. Combat ability
is a configurable action, unbound in the legacy default layout; blitz/grenade is
a different action. Communication wheel and push-to-talk still lack explicit VR
routes. Runtime/system buttons remain reserved by OpenXR/the headset.

## Immediate defect found

The XR menu-primary state machine imposed a 1.25 s activation lockout. It now
requires only its existing 0.25 s settled release before accepting a fresh edge.
The game retains its own loading/synchronization gates. The earlier game-side
readiness investigation missed this native gate; the menu audit is corrected.
Tests cover early deliberate clicks, inherited holds, reconnects, heartbeat
sequence changes, ray misses and mode transitions.

## Revision order

1. Complete semantic delivery for the already assigned R3 tag and menu button.
   Use stock input/menus, preserve mouse/keyboard input, and ensure a held button
   cannot cause an action on return from menus or on reconnect. The current
   jump/dodge entry guard covers A only; audit equivalent handoff behavior for
   fire, special, ability and future remapped actions before exposing remapping.
2. Separate jump from dodge and interact from reload where useful. Add combat
   ability, communication and remaining weapon/action contexts explicitly. The
   right stick has gameplay capacity but is already a menu-scroll control;
   turning and action shortcuts require separate context rules.
3. Expose physical-control mappings in VR mod options, preserving a legacy
   preset and validating conflicts. DMF keyboard keybind widgets alone do not
   configure OpenXR analog controls. Changing mappings while held must release
   old actions and require neutral input before activating their replacements.
4. Generate controller prompts from the same resolved mapping. Do not globally
   force gamepad mode merely to change glyphs: it also changes menu input and
   communication-wheel behavior. Describe unbound actions visibly.

This checkpoint changes only the menu-primary lockout; gameplay bindings remain
unchanged. Right-stick turning, new defaults and controller ergonomics need
worn acceptance. Native Release and targeted input/presentation tests pass.

## Semantic delivery follow-up

The next implementation adds the missing R3/menu delivery without changing
their physical bindings. A separate Lua module feeds a pressed `smart_tag` into
the local stock HUD handler and opens `system_view` through UIManager for the
menu button. It preserves stock null-service suppression, keyboard input,
same-frame reads and nil return values. Blocked events expire rather than
opening/tagging later. It does not call network tag functions or synthesize keys.

The native mapper now quarantines every gameplay button held on activation or
transport-generation change until that action is released. This extends the
previous A-only entry guard to fire, block, special, blitz, tag and menu too.
Both pressed and held levels are suppressed: preventing only press edges is
insufficient because stock windups can start from held input. Other released
controls can rearm independently. Movement mapping and existing control choices
are unchanged.

Windows Release and `gameplay_input`, `panel_pointer`, `gameplay_ui_input`,
`menu_input`, and the pinned LuaJIT gate pass. The Lua gate now covers 28 chunks.
Fixtures cover inherited holds, reconnect release, independent rearming, local
HUD ownership, blocked events, menu precedence, same-frame tag reads, keyboard
preservation and stock error/return behavior. Worn R3/menu acceptance is pending.

Live validation: the newly deployed `_handle_tagging` hook installed after
gameplay HUD creation. Harness `shared_ready=10621`, fresh-pair rate about 44 fps,
zero interval fallback and zero pose mismatches. No physical controller action
was simulated; this establishes load/render health, not worn input acceptance.

## Configurable gameplay bindings

Mod Options > Darktide VR > Gameplay controller bindings now exposes all eleven
existing button/trigger/grip channels. The original choices remain the defaults.
New choices include separate jump/dodge, separate interact/reload, combat
ability, inspect weapon and unbound. Right-stick axes, menu pointer controls,
aim handedness, communication wheel and push-to-talk are outside this change.

The Lua catalog defines both options and game action delivery. Native bits stay
physical channels; resolved held/pressed/released masks are game-side state.
Combined and split actions aggregate before edge detection, so two controls
bound to jump cannot retrigger it while either remains held. Duplicate mappings
are intentional aliases, not conflicts. A changed mapping releases old actions
and quarantines currently held physical controls until individually released.
Invalid saved choices fall back to the corresponding original binding.
Bindings do not overwrite mouse/keyboard input or globally select gamepad mode.

Offline checks: `controller_bindings`, `gameplay_ui_input`, `hud_options`,
`hud_panel` and pinned LuaJIT compilation pass (29 chunks). Tests include live
remapping, aliases, combined/split overlap, inactive/reentry transitions,
unbound/invalid values, unrelated setting callbacks, localization and the
audited stock input-name contract. Physical combat-ability use and revised
layout ergonomics still require a worn check. Matching controller prompts and
right-stick gameplay use remain separate backlog items.

Live desktop validation: dropdown labels/options render and accept selection.
Right trigger was temporarily set to Unbound; entering gameplay persisted that
value in `user_settings.config` and reopening Mod Options retained it. Primary
fire was restored through the dropdown. After closing menus, `shared_ready=4587`,
fresh-pair rate 44.4 fps, no interval fallback and no pose mismatches; no mod
errors were found. The installed DMF saves changes on game-state transitions,
so a menu reopen alone is not proof of a disk save.
Normal Quit Game and its confirmation worked; after shutdown the settings file
confirmed the original right-trigger `primary` value was restored.

## Controller prompt text

The next candidate scopes the stock input-text helper to weapon, ability,
interaction, tag and WieldInfo HUD text construction. It displays compact VR
control labels from the same resolved binding catalog, including combined/split
aliases. Each hint shows the first assigned control in catalog order; additional
aliases remain usable and appear in Mod Options. Known actions without a VR assignment
show Unbound. Unknown aliases retain stock text; View-service menus and calls
outside those HUD scopes are unchanged. It does not force gamepad mode.

Stock Text utilities retain localized hold/release wording. Weapon-slot HUD
hints label quick wield as `Y switch` with original defaults, rather than claiming
Y directly selects either numbered slot. Cached weapon/ability/WieldInfo labels
refresh when mappings or VR availability change. The scope restores on stock
errors and preserves nil return values. These are text labels, not new icon art;
tutorial, spectator, onboarding and other unreviewed hints remain separate work.
Ability badge labels use the stock font-width fitter within their existing
60-unit text box, avoiding wrapping longer labels such as Unbound. Measurements
are cached by text, renderer scale and box width; leaving VR restores stock size.

Offline validation: `controller_prompts`, `controller_bindings`,
`gameplay_ui_input`, `hud_options`, `hud_panel` and pinned LuaJIT compilation
pass (30 chunks). Live desktop shows `[R Grip] Charge Sword` and `[RT] Eviscerate`.
Temporarily remapping right grip to reload changed the former to
`[Unbound] Charge Sword` after closing menus, without a weapon switch/restart.
Ability text remains on one line with the width fitter. Harness `shared_ready`
reached 861 at 44.4 fresh pairs/s with no interval fallback, pose mismatch or
matching mod error. This establishes desktop rendering and dynamic refresh;
worn readability, pickup/tag visual coverage and icon artwork remain pending.
Right grip was restored to Weapon special in Mod Options; the saved settings
still contain `vr_bind_right_grip = "special"` and right trigger `primary`.

## Optional right-stick directional shortcuts

Mod Options now exposes right-stick up/down/left/right alongside the eleven
existing controls. All four default to Unbound. They use the same action catalog,
held/pressed/released delivery and prompt labels (`RS Up`, etc.). This adds
digital shortcuts, not artificial turning or a radial weapon wheel. Menu
scrolling retains its native route.

Each direction activates at 0.65 deflection and releases below 0.45 to avoid
threshold jitter. Diagonals can activate two assigned directions; aliases still
aggregate before logical edge detection, so shared actions do not double-fire.
The channels are formed in Lua from the observed right-stick axes; native
controller transport and its eleven button bits remain unchanged. Unknown native
bits are masked before directional channels are added.

Gameplay/menu handoff, invalid/lost right-hand tracking, writer-generation
changes and live remapping quarantine deflected directions until release.
Invalid/nonfinite/out-of-range axes cannot fire a shortcut. The original control
defaults and every direction's Unbound default remain intact. Ergonomic defaults,
turning policy, communication wheel and push-to-talk remain separate work.

Validation: controller bindings/prompts, gameplay UI delivery, HUD options and
the 31-chunk LuaJIT gate pass. Cases cover thresholds/hysteresis, diagonals,
opposite-direction aliases, menu return, tracking reacquisition, transport
restart, remapping while held, invalid axes, native-bit isolation and directional
HUD labels. Physical controller use and revised layout comfort still need a worn
check; no gameplay shortcuts were actuated unattended.

The candidate was deployed and the Darktide VR settings page opened at character
selection. Desktop wheel scrolling and a scrollbar drag did not move the list,
so the four new dropdowns below the fold were not visually verified or changed.
This is an unresolved menu-input observation, not established as a directional
shortcut regression. Inspect desktop wheel/held-pointer ownership in the native
menu proxy before changing routing. This launch remained in flat menu mode 5
with `shared_ready=0`; it does not establish fresh gameplay stereo acceptance.
The five targeted CTest cases above passed again at final handoff.

## Right-stick turning candidate (6 September)

Smooth turning is now the default, with 45-degree and 90-degree snap modes and an
Off option. Smooth speed is configurable from 30 to 180 degrees/s, default 90.
The right horizontal axis edits the shared scene heading; physical head tracking,
hand/world transforms and locomotion continue using their existing common basis.
The legacy live-game-camera yaw feedback route stays disabled. No mouse movement
is synthesized and keyboard/mouse or menu input routes are not replaced.

Smooth input uses a 0.25 deadzone and proportional deflection. Snap requires 0.65
deflection and a return inside 0.25 before another turn, including opposite turns.
Menus, lost tracking, transport/recenter/world changes, settings changes and long
clock gaps require neutral before resuming. Repeated callbacks at one timestamp
cannot integrate twice. Clock gaps above 100 ms never accumulate deferred yaw.

When turning is enabled, saved horizontal shortcuts are inactive and omitted from
prompt lookup. Turning Off restores those mappings after release; vertical stick
shortcuts and native button mappings remain available. Options explain the policy.

Validation: pinned LuaJIT passes 32 chunks. Nine focused CTests pass: turning,
controller_bindings, controller_prompts, gameplay_heading, gameplay_ui_input,
hud_options, wrist_transform, melee_aim and ranged_aim. Tests cover frame-rate
independence at 30/60/120 Hz, snap thresholds and reversal, tracking/context/clock
changes, option refresh, shortcut conflicts, and preservation of prior aim seams.
Worn direction, comfort, hand alignment, room-scale turning pivot and hub/range
transitions remain to be checked. This is implementation, not visual acceptance.

Live initialization: the turning build reached the private range with fresh
synchronized stereo initialization, shared_ready=359 and about 51.6 original +
51.6 generated pairs/s, zero interval fallback and zero pose mismatches. Deployed
turning-module hash matches source; no matching Lua error was found. F3 editor
uses presentation mode 5, so the gameplay-only turning gate also excludes it.
No physical stick deflections were synthesized; direction/comfort/pivot remain
for a worn check. Evidence: artifacts/unattended/right-stick-turning-live-20260906.log.
Experimental HUD-alpha capture/submission flags were removed for this gameplay
run; no graphics settings were changed. Headset proximity override remains off
for the continuing development session. No desktop-control session is held.

Worn acceptance: user confirms both smooth and snap turning work. Mark those
controls accepted; no claim was made about every optional speed or room-scale
pivot extreme. The deployed c27ee63 implementation remains unchanged.

## Native-menu controller hint candidate (6 September)

Source audit: the XR menu adapter provides right-trigger pointed left click,
right-stick vertical scroll and Back from right-secondary B or the left Menu
button. It does not provide keyboard/gamepad confirm, right click or arbitrary
menu hotkeys. Text labels must reflect those actual routes.

The new menu prompt module scopes the stock Text.localize_with_button_hint helper
by action/service. View back shows B / Menu; left_pressed/left_released/left_hold
show Point + RT. A ViewElementInputLegend entry with an explicit click callback
can also show Point + RT, since stock binds that callback to its pointer hotspot.
Unknown/non-clickable actions retain the stock binding. Hold/release localization,
patterns, suffixes and legend width recalculation remain in the stock helper.
No global gamepad-mode switch or input suppression is introduced.

DMF's same-mod duplicate-hook policy replaces an existing hook handler. Therefore
menu and gameplay labels share ONE InputUtils hook owned by controller_prompts;
the menu module supplies its scoped label through an API. Combined tests reject
duplicate registrations and verify both menu and gameplay output. Error/nested
scope restoration, nil return values and cached legend refresh are covered.

Pinned LuaJIT passes 33 chunks. Seven CTests pass: menu_prompts,
controller_prompts, menu_input, turning, controller_bindings, hud_options and
gameplay_heading. Native-menu hints outside the shared text/legend routes and
unsupported controller actions remain stock. Live labels/readability pending.

Live initialization passed: all three menu-text/legend hooks and exactly one
InputUtils prompt hook installed. Fresh synchronized stereo reached shared_ready
652 at about 51 real + 51 generated pairs/s, with zero fallback or pose mismatches.
No matching Lua error was found. Evidence: artifacts/unattended/menu-controller-hints-live-20260906.log.
This verifies loading and hook coexistence, not a visual read of every footer.
Menu footer appearance and readability remain pending user observation.

Worn/menu acceptance: user confirms menu changes verified. Supported Back and
pointed-click hints are accepted; keyboard-only actions remain intentionally
accurate to their available routes. The deployed be43948 implementation is unchanged.

### Additional worn acceptance and hint coverage (6 September)

User confirms the unarmed right hand is fixed (2477d82). The retry reached
hub_ship with automatic Psykhanium entry explicitly disabled and nonzero shared
stereo readiness. The earlier menu acceptance covers tested routes, not every
prompt: the hub unused-talent-points notification still says press [I].
Add a broad binding-hint pass across menus, notifications, tutorials and
contextual popups. Identify each action's actual controller route before changing
its label; if no route exists, add/plan that route rather than displaying a
nonfunctional button. Keyboard/mouse must remain available.

## Hub/combat controller profiles candidate (6 September)

Following the user's request to reuse the limited controls by context, hub now
has per-control overrides with Same as combat inheritance. Existing vr_bind_*
settings are preserved as combat bindings. Right grip defaults to inventory in
hub and remains weapon special in combat; other hub controls inherit by default.
Movement/turning and native-menu pointing/back/scroll routes are unchanged.
Changing context cancels old semantic state without emitting charged-release
edges, and quarantines held controls until release/neutral. Hints can query the
same effective profile and revision rather than a second binding map.

Inventory is delivered through the stock UIManager hotkey owner, retaining its
mode whitelist, transition/modal/null-input gates and view validation. Requests
expire on a blocked update and never replay. One shared input_service hook
composes the existing menu pointer and the gameplay hotkey adapter; there is no
keyboard injection or global template mutation. Keyboard/mouse remain usable.

Pinned LuaJIT passes 33 chunks. Seven CTests pass: menu_input, turning,
menu_prompts, gameplay_ui_input, hud_options, controller_bindings,
controller_prompts. Tests cover hub/combat inheritance, held context switches,
stock hotkey gates, shared hook coexistence, return values and keyboard input.
Candidate is not yet deployed; current running hub stays on accepted 2477d82.

Broad hint audit acceptance cases: unused-talent-points notification showing [I],
and talent deactivation showing right-click. User explicitly requested leaving
the latter untouched as a check for the broader automated pass. Do not mark a
hint pass from source inventory alone or rename a shortcut without a working
controller route. Handedness source audit is recorded in HANDEDNESS-AUDIT.md;
left-handed gameplay is not implemented by these binding profiles.

### Automated broad hint inventory

The source pass inventories the shared hint formatters and alias helpers across
all stock scripts/ui Lua files. Run:
python tools/stereo/audit-ui-binding-hints.py --source-root _downloads/Darktide-Source-Code --output artifacts/unattended/ui-binding-hint-audit-20260906.json

Current result: 103 calls in 44 files; 94 have dynamic action expressions and
require caller/route verification. The report retains source hashes, line numbers,
full argument expressions and conditional action candidates. It is a review
queue, not a claim of runtime or visual acceptance. Comments and strings are
ignored and nested argument expressions retained; four parser/coverage tests pass.

Both user cases are found automatically and remain explicitly unfixed acceptance
cases: onboarding inventory calls at 336/874/1131, and talent removal right-click
branches at 1680/1682. Missing either source case makes the audit fail coverage
instead of claiming the bug resolved. No talent deactivation patch was made.

Coverage follow-up includes shared button/checkbox/slider/stepper templates;
BaseView helpers; tab/menu panels; profile presets; tutorial overlays; onboarding;
prologue and spectator HUDs; talent/stimm tooltips; mission voting, board and end
screens; social/group-finder and event/penance views. Dynamic menu actions need
an actual input route or pointer callback before any label can become a VR hint.

### Shared onboarding/tutorial hint coverage candidate

The broad audit identified onboarding and prologue tutorial construction outside
existing HUD scopes. Both now use the shared binding formatter. Hub inventory
notifications use the effective hub inventory binding; an unassigned shortcut
retains the keyboard hint. The same change covers all three stock onboarding
inventory reminder calls, not just the reported talent message. Prologue action
hints reuse existing gameplay aliases. Scopes restore on error and preserve the
shared menu formatter. Talent deactivation remains untouched as requested.

LuaJIT passes 33 chunks. All eight focused CTests pass after CMake regeneration:
ui_binding_audit, menu_input, turning, menu_prompts, gameplay_ui_input,
hud_options, controller_bindings and controller_prompts. Worn/live acceptance
for hub profile and notification text remains pending. The source inventory
continues to list user cases; it cannot prove deployment or visual correctness.

### Tutorial remap refresh, 7 September

Stock prologue tutorial descriptions are cached. Their `_should_update_input`
checks keyboard alias identity and device selection, which do not necessarily
change after a VR remap. The controller-prompt module now also requests a refresh
when the effective binding revision or VR availability changes. Stable mappings
do not refresh every frame; the original keyboard refresh decision is retained.
No tutorial progression or notification activation is replayed.

Five focused CTests pass: controller prompts/bindings, menu prompts, Lua compiler
and source invariants. The regression covers remap, unchanged frames, missing
info, stock refresh and VR loss/recovery. This candidate is undeployed; actual
cached tutorial text and sizing still require a live check. Talent deactivation
remains untouched as the user's shared-hint acceptance case.
