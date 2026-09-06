# Mission input and attack ownership

7 September 2026. Source audit and offline candidate; no mission was launched.
The follow-up [online requirements audit](ONLINE-MISSION-REQUIREMENTS.md)
traces the stock angle stream and defines a possible client-only compatibility
mode separately from exact tracked origins and physical-contact melee.
The user is at work and cannot provide worn acceptance today. SoloPlay remains
the later test stage after Psykhanium functionality is accepted.

## Why removing the range guard is insufficient

The local source snapshot under `_downloads/Darktide-Source-Code` shows these
owners. Function names identify the audited paths; this is build-specific source
evidence, not a claim about uninspected game updates.

| Path under stock `scripts/` | Relevant behavior |
| --- | --- |
| `managers/player/player_game_states/human_input_handler.lua`, `fixed_update`, `get_orientation`, input send path | Caches yaw/pitch/roll per fixed frame and sends cached arrays through `rpc_player_input_array`. |
| `managers/player/player_game_states/authoritative_player_input_handler.lua`, `get_orientation`, `rpc_player_input_array` | Server consumes the corresponding frame-indexed input stream. |
| `extension_systems/input/human_unit_input.lua`, `get_orientation` | Reads orientation for the active fixed frame from that handler. |
| `extension_systems/weapon/actions/action_shoot.lua`, `_prepare_shooting` | Derives shot position/rotation from the first-person component; applies recoil, sway, assistance and spread before writing the action component. Simultaneous groups share the prepared result. |
| `extension_systems/weapon/actions/action_shoot_projectile.lua`, `_shoot` | Uses the prepared aim, but creates the network projectile only when `_is_server` is true. |
| `utilities/attack/hit_scan.lua`, `process_hits`; `utilities/action/ranged_action.lua`, `execute_attack` | Raycast results feed the common Attack path; suppression/explosions include server-only branches. |
| `utilities/attack/attack.lua`, `_handle_attack` | Health application requires server authority. Client prediction/results alone do not establish damage. |
| `extension_systems/aim/player_unit_aim_extension.lua`, `fixed_update` | Server writes the `aim_direction` game-object field from first-person rotation. |

The VR candidate supplies a temporary first-person pose around stock action
preparation and restores the original component afterward. That changes the
local action instance. Its `PlayerUnitAimExtension.fixed_update` hook is also
limited to the local player on a local server; it does not send an independent
hand origin/rotation to a remote mission server.

Inference: the current local hooks can author the server's action when the
local process owns simulation, but cannot establish remote-server attack
agreement merely by admitting the mission mode. Before online enablement,
trace the orientation input producer and its effects on prediction/camera/body,
then verify how the authoritative action can receive the intended origin and
direction. Do not repurpose the camera stream or add a protocol without that
ownership design. Keep stock spread, simultaneous grouping and authority intact.

## Local-authority candidate

`darktidevr_gameplay_context.lua` centralizes body/input and hand-aim admission:

| Context | Body/input | Hand aim |
| --- | --- | --- |
| Hub | Existing behavior | Disabled as before |
| Shooting range / training grounds | Existing behavior | Existing behavior |
| `coop_complete_objective`, `survival`, `expedition`, `prologue` with local server authority | Candidate enabled | Candidate enabled for the local player only |
| Those missions with remote, missing, retiring or invalid authority | Disabled | Disabled |
| Unknown/default/loading modes | Disabled | Disabled |

Mission names come from stock game-mode settings. `host_singleplay` metadata
alone is not permission: the live session must return boolean true from
`is_server()` each time the policy is queried. Missing methods, errors and
truthy non-booleans are rejected. Authority is not cached across loading or
host loss. Existing private-range-only synthetic fire/probe gates remain narrow.

The main body predicate now uses this policy, as does controller hand-aim
selection. Existing local-unit checks, transport freshness, UI/modal exclusion,
controller context release guards and stock attack preparation remain in place.
The standalone aim module's compatibility path remains private-range-only when
the presentation policy is absent.

This is a candidate for future local mission testing, not completed SoloPlay
compatibility or online support. Body, movement, interactions, scanner/objective
screens, server impacts, actual loadouts, death/spectating and extraction/return
still need lifecycle checks. No SoloPlay files were installed or changed.

## Validation

Pinned LuaJIT compiles all 34 mod chunks. The policy test covers explicit modes,
missing/retiring sessions, strict authority values and host loss. Ranged tests
exercise the policy through the actual preparation hooks: local-authority hand
position/direction, stock remote/client behavior, restored components, authority
loss, and server-only aim-field writes. Existing grouped-shot, grenade, melee,
turning and controller binding checks pass.

```powershell
tools/stereo/test-darktide-lua-source.ps1
cmake --preset windows-vs2022 -DDARKTIDEVR_ENABLE_HEADSET_TESTS=OFF
ctest --test-dir build/windows-vs2022 -C Release --output-on-failure
# PASS: 99/99 on Windows x64, including the new gameplay_context test
```

Evidence: ignored `artifacts/unattended/mission-authority-configure-20260907.log`
and `artifacts/unattended/mission-authority-ctest-20260907.log`.
No deployment or worn/mission acceptance in this task.
