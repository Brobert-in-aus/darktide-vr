# Handedness implementation audit

6 September 2026. Source audit only; left-handed gameplay is not implemented or
visually accepted. User accepted the right-wrist correction in hub build 2477d82.
Development is stopped for the night; game/XR are closed. See the
[end-of-day handover](handoffs/2026-09-06-end-of-day.md). The user's later follow-up
reactivates DLSS image-quality work with blur first; it does not change this audit.

## Decision

Separate physical left/right tracking from dominant/support gameplay roles.
Keep anatomical hands, wrist calibration and raw transport channels physical.
Route weapon aiming and blocking through roles, then adapt the weapon attachment
presentation to those roles. Start with rigid attachment relocation; identify
asymmetric assets requiring mirroring individually. Do not negative-scale the
entire player rig or swap raw tracking records: both would also affect anatomical
hands and consumers that intentionally refer to a physical controller.

This is a proposed implementation boundary, not evidence that every weapon can
be relocated without asset changes. Preserve stock damage, animation and item
lifetimes; never mutate shared weapon templates globally for one local player.

## Confirmed consumers

Paths below are relative to the repository. Lua modules are under
`mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/`.

| Consumer | Existing behavior | Required separation |
| --- | --- | --- |
| `darktidevr_stereo_probe.lua`, controller observation and grip/aim helpers | Physical left/right records and validity ages | Preserve physical identity; resolve roles at consumers |
| Same file, `body_ik_calibrated_wrist_target` and arm/rigid glove paths | Anatomical left/right wrist and skeleton | Keep anatomical mapping and accepted calibration |
| `darktidevr_controller_aim.lua`, `target`, reticle and shooting hooks | Main attack/reticle uses right aim | Dominant aim for both target and shot preparation |
| Same module, `projectile_target` | Staff uncharged origin left, converged toward right aim; charged origin staff tip | Support origin, dominant aim; tip must follow actual weapon |
| Same module, knives, lightning and animation aim | Explicit right aim | Dominant role, retaining weapon-specific homing rules |
| `darktidevr_combat_direction.lua` | Block direction uses left aim | Support aim, preserving stock angle/cost checks |
| `darktidevr_grenade_aim.lua` | Throw preparation and delayed launch use right aim | Same dominant role at preview, preparation and release |
| `darktidevr_melee_live_probe.lua` | Right grip validity and provisional grip volume | Dominant grip and matching validity; physical damage still unimplemented |
| Main Lua, `sync_equipment_hand_to_proxy` | Same-named source/proxy hands; 3P weapon units remain on authoritative loadout | Explicit source weapon-role to physical destination attachment mapping |
| Main Lua, stock melee animation path | Both wrists follow stock animation, rotated toward right aim | Dominant attack aim and a coherent swapped animation/attachment policy |
| `darktidevr_controller_bindings.lua` | Physical control catalog, independently saved action assignments | Handedness preset must not silently overwrite custom assignments |
| `src/xr/main.cpp`, menu pointer | Right aim/trigger, right stick scroll, B or left Menu back | Menu pointer handedness needs native selection plus matching Lua hints |
| Turning and movement | Right stick turning; physical left movement | Keep locomotion choice independent from weapon handedness |

The native pointer and Lua attack consumers are separate. A Lua-only aim toggle
would not provide a left-handed menu pointer. Likewise, changing triggers alone
cannot move the weapon model, reticle, grenade arc or block direction.

## Attachment and effect ownership

Stock source is in `_downloads/Darktide-Source-Code/scripts/` (read-only audit).
`extension_systems/visual_loadout/utilities/visual_loadout_customization.lua`
resolves wielded/unwielded and breed-specific attachment nodes, then calls
`World.link_unit`. `player_unit_visual_loadout_extension.lua` separately
registers and moves sound/VFX spawners by named node. Swapping one render transform
does not automatically prove the registered muzzle/effect owner has moved.

`wieldable_slot_scripts/force_weapon_block_effects.lua` explicitly uses
`fx_left_hand_offset_fwd`. Force-sword templates also specify left-hand block and
vent sources. Force-staff templates include `j_leftweaponattach` muzzle/charge
sources. Lightning effect scripts maintain two hand spawners. Audit these as
support/dominant/both roles rather than replacing every occurrence of "left".

The current equipment sync updates hidden source hand nodes to match accepted
proxy hands and retains the stock item-local animation. Reusing that mechanism
with different destination hands is a candidate for rigid weapon relocation.
It still needs a defined attachment basis: a right-hand grip moved to a left
wrist may retain an incorrect palm orientation. Shields, dual weapons, reloads,
ejection ports and text decals need individual visual decisions. No source-only
claim about negative-scale rendering/collision compatibility is made here.

## Integration and acceptance order

1. Introduce a shared role policy with right-handed behavior as the default.
   Test role resolution, invalid settings, tracking loss and revision changes.
   Do not expose an apparently complete left-handed option before presentation
   and attack routes agree.
2. Route attack, block, reticle, throw preview/release and contact queries through
   roles. Preserve per-source tracking validity and simulation sampling; never
   fall back to the other hand on tracking loss. Release/rearm held inputs when
   changing handedness, so a setting change cannot fire or complete a charge.
3. Map local weapon attachments and relevant effect sources. Keep anatomical
   hand meshes on their actual physical hands. Restore original ownership on
   weapon changes, disabling the feature, loading and teardown.
4. Add explicit controller-binding presets and independent locomotion/pointer
   choices. Existing custom bindings remain available. Derive prompts from the
   effective physical controls and keep keyboard/mouse fully operational.
5. Worn checks: hub hands; one-handed sword and pistol; two-handed gun; shield;
   staff casting and push; grenade/knife preview and release; reload/charge;
   both menu pointer choices. Head looking away must not redirect attacks.
   Include right-handed regressions and a manual hub/range transition.

Offline inspection identifies dependencies only. Real hit direction, attachment
basis, muzzle/effect positions and hand comfort require the user's worn checks.
