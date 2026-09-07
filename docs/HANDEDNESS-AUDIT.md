# Handedness implementation audit

6 September source audit, followed by implementation work on 7 September.
Left-handed gameplay is not yet available or visually accepted. The user accepted
the right-wrist correction in hub build 2477d82. Current continuous work is tracked
in the [development handoff](handoffs/2026-09-07-development.md).

## Implemented role foundation, 7 September

### Rigid tracked equipment mapping, 8 September

The tracked rigid-hand path now resolves each authored equipment hand through
dominant/support roles. Same-side destinations retain the accepted proxy wrist
pose. Opposite-side destinations use the physical destination's calibrated wrist
position and grip rotation, composed with the weapon hand's original measured
anatomical basis. They do not import the opposite glove's joint axes or mutate
anatomical hand meshes, item-local animation or raw tracking.

Each hand's placement result is returned separately. A successful left placement
cannot authorize a stale right pose, or vice versa. Missing roles, missing source
calibration, retired owners and unavailable hands decline equipment writes.
World-to-parent conversion retains the existing avatar-scale handling.

Actual-branch tests cover both role policies, .94/1/1.08 scales, distinct authored
bases, partial placement and unknown roles; 3D anatomical tests cover the exported
rotation helper and owner/readiness rejection. Runtime still constructs the
accepted right-dominant policy. This is an undeployed attachment foundation,
not complete left-handed gameplay: stock animated melee, two-hand calibration
ownership, bindings and menu pointer
still need coordinated role mapping before exposing the setting.

Validation: full Windows x64 offline CTest passes 134/134 in 22.74 seconds;
the pinned LuaJIT gate compiles 47 chunks. Evidence is
`artifacts/unattended/handedness-attachment-final-134-20260908.log`.

### Effect ownership follow-up, 8 September

Stock `is_in_first_person_mode()` reads equipment visibility, separately from
`wants_first_person_camera()`. The existing VR split therefore selects 3P
weapon VFX and breed-node VFX while retaining the first-person camera. Those
registered nodes follow their moved equipment/hand ancestors; an additional
global particle-pose redirect would duplicate that routing and risk gameplay
consumers of the same accessor.

Initial `_register_fx_sources` nevertheless always registers weapon sounds on
the 1P item. Stock `_move_fx_sources` moves them later when equipment mode or
attachment readiness changes. `darktidevr_weapon_sound.lua` now redirects that
initial sound registration for a current local VR slot already using 3P
equipment. It requires exact 1P slot/attachment identity, a live 3P tree and
usable node/attachment lookup; all other cases retain stock registration.
Unknown/retiring owners, missing metadata and dead attachments decline the
redirect. Stock movement, unregistration, result tuples and exceptions remain
intact. No particle, attack-origin, damage or global camera API is changed.

The actual stock registration helper passes through this hook with sound and
VFX selecting the 3P item. Portable ownership/fallback cases also pass. This
does not establish spatial-audio perception or all effects under left-handed
animation. The candidate is undeployed, with no new live acceptance.

### Gun alignment at either dominant grip, 8 September

The gun visual correction now admits either known dominant side. The stock
right-authored weapon attachment remains the weapon owner; its world target
comes from the selected physical grip/aim. The visible destination glove uses
its own measured joint basis, converted from the weapon's authored wrist pose.
Same-side right-hand math is unchanged. A missing opposite-hand calibration or
failed glove placement restores the tentative attachment transform rather than
leaving a gun correction without its hand.

Tests exercise actual gun and glove functions, default pitch/draw/reload
behavior, destination rejection and independent anatomical-axis checks in both
conversion directions. Full Windows x64 offline CTest passes 135/135 in 22.91
seconds and 48 Lua chunks compile. Evidence:
`artifacts/unattended/handedness-gun-135-20260908.log`. Runtime handedness remains
fixed right; this candidate is undeployed and needs future worn acceptance.

Measured two-hand profiles now also retain their physical support-hand owner.
They cannot carry the other hand's measured socket/orientation into a new role
policy. Role changes during calibration cancel the countdown. A failing-before
regression and six focused checks pass. Animated melee/finger retargeting,
binding presets and pointer choice remain before exposing handedness.

`darktidevr_weapon_hand_roles.lua` constructs a fixed dominant/support policy.
Physical left/right identities remain unchanged; invalid policy input defaults
to right dominance and unknown role names produce no target. Gameplay attack,
reticle, staff support origin, throw, block and targeting consumers now request
roles explicitly. The online fixed-frame adapter requests dominant aim. The
non-damaging contact probe reads the selected physical grip's validity and pose.
No opposite-hand fallback occurs when the selected hand loses tracking.

The runtime constructs the accepted right-dominant policy. No left-handed setting
or binding preset is exposed yet: attachments, weapon effects, held-input rearming
and independent menu-pointer selection remain unfinished. This fixed constructor
does not provide an in-session handedness mutation API. Raw tracking, anatomical
wrists/calibration, movement selection and native controls remain physical.

The role/physical helper fixture passes both choices, invalid input and tracking
loss. Concrete ranged hooks also pass a left-dominant test policy with distinct
physical poses and stock fallback when that hand becomes unavailable. Existing
grenade, melee, block, animation, online-input and contact-probe checks pass.
LuaJIT compiles 36 chunks; the full Windows x64 offline CTest suite passes
**107/107**. Source invariants retain the same staff convergence guard under its
new support-role diagnostic name. No deployment or attachment/visual acceptance.

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

The 7 September follow-up found and fixed a partial-rig diagnostic failure:
one hand could sync successfully, then the first scale log unconditionally
resolved the missing opposite hand/parent. Detailed scale logging now requires
both successful hand syncs; ordinary sync/error counters still cover partial
success. A regression reproduces the original fault and exercises rotated
parents, source scales 0.94/1/1.08, the existing near-zero scale fallback,
missing source/proxy hands or parents, dead units and unchanged proxy/item-local
transforms. Five focused CTests and all 36 LuaJIT chunks pass. This verifies the
existing same-side relocation math, not a left-hand attachment basis.

More specifically, stock `_register_fx_sources` initially registers weapon sound
on `slot.unit_1p` while selecting 1P/3P VFX ownership by camera mode. Its
`_move_fx_sources` later moves both sound and VFX to the selected unit. Base breed
VFX are registered separately on the first-person or gameplay unit, with an
optional gameplay-node counterpart. `PlayerUnitFxExtension.vfx_spawner_pose`
reads the stored unit/node's current world pose; it does not cache the transform.
Thus a moved registered ancestor should carry that source, but moving only 3P
equipment does not establish that 1P sound or breed-hand effects follow it.
The planned mapping must cover those ownership paths and mode changes explicitly.

## Integration and acceptance order

The rigid glove's anatomical solve maps little-to-index to grip forward,
fingertips to negative grip up, and its signed cross normal to negative grip
right on both hands. Each authored wrist has its own inverse anatomical basis.
Moving a weapon's authored right wrist directly to the left glove quaternion
would import the left joint basis into that weapon. A future rigid relocation
must retain the weapon's authored basis while expressing it in the destination
grip frame; stock animated attacks and separately owned effects still need their
own mapping. This is an implementation constraint, not left-hand acceptance.

An offline 3D regression now exercises the actual anatomical calibration with
distinct left/right authored bases, arbitrary world/grip rotations and scales
0.94/1/1.08. It preserves valid cached calibration under later finger animation.
Zero-length, zero-width, collinear and nonfinite initial geometry previously
could produce and cache an invalid rotation; calibration now leaves that cache
unset and retries. Both tracked and authored-animation placement wait before
copying finger animation over the initial anatomy. Missing nodes also retry.
Seven focused CTests, including the 36-chunk LuaJIT gate, pass. These are
constructed failure cases, not evidence that malformed anatomy caused a live
alignment issue. Accepted offsets and valid-basis math are unchanged.

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
