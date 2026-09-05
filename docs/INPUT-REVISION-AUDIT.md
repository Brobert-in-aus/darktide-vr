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
