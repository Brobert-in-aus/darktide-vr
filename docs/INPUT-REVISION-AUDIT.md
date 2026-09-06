# Input revision audit — 6 September 2026

This records actual routing before revising defaults. The raw OpenXR actions
already include both sticks and both stick clicks. The current gameplay mapper
is in `src/core/gameplay_input.cpp`; its game-side delivery table is
`presentation.gameplay_input_bindings` in the stereo Lua module.

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
| Right stick | No gameplay axis consumption | Vertical scrolling |
| R3 | Native smart-tag bit produced, **not delivered by Lua** | None |
| Left menu button | Native menu bit produced, **not delivered by Lua** | Back |

R3 is not absent from the native bindings, but the missing Lua consumer explains
why it appears unused. Smart-tag targeting hooks currently change the target,
not the input trigger. The stock HUD reads the pressed `smart_tag` input itself.
The combat ability has no mapper bit or delivery route; blitz/grenade is a
different action. Communication wheel and push-to-talk also lack explicit VR
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
