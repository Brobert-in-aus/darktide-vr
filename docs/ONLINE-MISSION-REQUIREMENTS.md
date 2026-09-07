# Online mission requirements

7 September 2026. Requested alongside local-server mission support. This is a
source audit with an isolated input-stream check, not an online test or an
enabled gameplay mode. The user is away and worn verification is pending.

## Finding

There is a plausible client-only route to online VR using the stock action
inputs and aim-angle stream. It would preserve the server's normal firing
origins, weapon actions, collision and damage rules. It needs a distinct online
compatibility mode; admitting remote missions to the current local-authority
hooks would produce disagreement between the local view and server attacks.

Independent tracked weapon origins, two independent authoritative hand poses,
and always-active physical-contact melee are a separate requirement. The
audited stock input stream does not describe those things. Exact support needs
server code/protocol support, not just a client hook or matching mods on the
other players' PCs. No way to install our code on official mission servers has
been established by this audit.

## Evidence and its limits

Audited local game source: `_downloads/Darktide-Source-Code`, commit
`0f0cb45991e9305ef4a7b925370792d7d6035f95`. DMF snapshot:
`fc08c1cb772f86248c7ae9e957543e801a0dbf64`. Paths below are under the game
snapshot's `scripts/`. These findings are specific to the inspected snapshot;
the executable's RPC serialization schema and current official-server build
have not been established from it.

| Stage | Source and observed behavior |
| --- | --- |
| Aim producer | `managers/player/player_game_states/human_gameplay.lua`, `fixed_update` and `initialize_client_fixed_frame`, ask the selected player-orientation object for yaw/pitch/roll. The selected object can also represent a forced view or non-playing state. |
| Client history | `human_input_handler.lua` in that directory stores the angles with the same fixed-frame index as actions. `update` sends unacknowledged columns using `rpc_player_input_array`. `input_handler_settings.lua` specifies a 600-frame client ring and a 20-frame send window. Explicit Lua `Network.pack_unpack` applies to four movement inputs; this does **not** establish angle precision on the wire. |
| Server history | `authoritative_player_input_handler.lua` receives those columns, tracks frame bounds, discards old/duplicate packets and handles a skipped send window by resetting its parsed base. `get_orientation` bounds its lookup to received history. |
| Simulation input | `extension_systems/input/human_unit_input.lua` reads the handler at its current fixed frame. `player_unit_input_extension.lua` chooses the human or bot input provider. |
| Authoritative pose | `extension_systems/first_person/player_unit_first_person_extension.lua`, `fixed_update`, calculates position from locomotion plus stock character height, including peeking. Rotation comes from input angles with stock recoil offsets and action rotation blocking. Independent controller position is not an input to this calculation. |
| Ranged preparation | `extension_systems/weapon/actions/action_shoot.lua`, `_prepare_shooting`, takes first-person position/rotation and retains stock recoil, sway, targeting and spread before storing the grouped shot. |
| Projectiles/throws | `action_shoot_projectile.lua` creates its network projectile on the server. `action_aim_projectile.lua` derives the cached throw from first-person pose; `action_throw_grenade.lua` and `action_throw_luggable.lua` consume stock parameters under their own release rules. Client-only edits to the aim cache do not author the server's cache. |
| Button melee | `action_sweep.lua` initializes and updates its reference from first-person pose, then uses weapon sweep splines and stock damage windows. A hand-directed reference can steer a stock swing; it cannot make the server trace the physical weapon's actual path. |
| Damage | `utilities/attack/attack.lua`, `_handle_attack`, applies health changes on the server. Client impacts and animations are insufficient evidence. |
| Correction/replay | `extension_systems/unit_data/player_unit_data_extension.lua` restores components and calls `fixed_update_resimulate_unit` during correction. Replayed frames must use their recorded inputs, not the newest tracking sample. |

The inspected DMF `dmf/scripts/mods/dmf/modules/core/network.lua` contains
unimplemented dictionary/ping functions, not a server installation or pose
transport facility. Its [primary repository](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework)
describes a community modding framework. This is evidence about those inspected
facilities, not proof that every possible future transport is impossible.
[Fatshark's policy](https://forums.fatsharkgames.com/t/darktide-modding-policy/75407/1)
does not offer official mod support or a server-extension deployment interface.
Technical authority conclusions above come from the code, not that policy.

## Capability boundary

| Feature | Candidate for an unmodified mission server | Additional work or limitation |
| --- | --- | --- |
| Stereo, HUD, local hands and weapon presentation | Client presentation | Keep rendering independent of simulation aim; mission transition and remote-player regression checks still required. Other clients would retain stock presentation without a separate supported replication path. |
| Buttons, reload, sprint, dodge, slots, objectives | Existing stock action stream | Split input eligibility from local-authority attack hooks; preserve UI ownership, neutral/release guards, input packing and server validation. |
| Controller-directed guns and staff | Send the chosen hand direction as stock simulation aim | Both client prediction and server must use that same recorded angle. Authoritative firing origin remains stock. Audit targeting assistance, recoil, charge and simultaneous groups per weapon family. |
| Grenades and carried-object throws | Stock aim/release directed by the chosen hand | Stock spawn clearance, throw parameters and release timing remain; local preview must reflect them. No independent real hand origin or arbitrary controller throw velocity. |
| Button melee, block and push | Stock weapon action aimed with the hand | Preserve stock reach, sweep, charge, cleave and attack cadence. Determine orientation selection across held block, push, charge and release. |
| Always-active physical melee with unlimited cleave | Not represented by the audited stock action stream | Requires an authoritative contact evaluator, accepted pose history, per-target cooldowns and server damage integration. Keep this local-authority work separate. |
| Independent off-hand attacks or accurate remote hand IK | Not represented as two independent poses | A second hand displayed locally does not provide a second server-authoritative aim stream. |

## Main engineering work

1. **Separate presentation, input and authority policies.** The existing
   `darktidevr_gameplay_context.lua` deliberately gates mission body/input and
   hand aim together. Online mode must admit the local human's stock inputs
   without enabling temporary hand-origin overrides, local server aim-field
   writes, physical damage experiments or changes to remote players. Continue
   rejecting unknown/loading/retiring contexts.
2. **Create one deterministic simulation-aim sample per fixed frame.** Capture
   the selected hand orientation at the input boundary used by HumanGameplay,
   before stock caching/sending. Use the same angles for prediction, resend and
   replay. Sending different angles only in `send_rpc_server`, or rereading live
   hand pose during replay, would leave the local simulation inconsistent.
   Preserve initialization, forced views, disabled states and pitch constraints.
   Decide aim selection for UI/interaction, targeting, melee and throws; a
   trigger-only override misses held aim, charged releases and delayed throws.
3. **Keep the HMD view independent.** The stock local first-person rendering
   path also reads player orientation, while server/remote presentation uses
   the first-person component. Do not turn the headset camera with the gun.
   Keep simulation components authoritative; derive the VR view separately.
   Audit existing HMD/body-follow hooks for local predicted locomotion edits
   that would be corrected by the mission server.
4. **Reconcile locomotion with hand aim.**
   `character_states/utilities/accelerated_local_space_movement.lua` rotates
   local movement by first-person yaw. It also smooths local axes, applies
   backward speed scaling and tests sliding against that heading. Air movement,
   body facing, ledge finding and peeking also consume it. Transform the intended
   movement into the sent aim basis before stock input packing on both sides;
   a client-only movement rotation is insufficient. A simple inverse rotation
   preserves a direction geometrically but does not promise identical speed or
   acceleration because these stock rules are direction-dependent. Minigame
   device axes must continue bypassing locomotion transformations.
5. **Use one honest firing origin.** Start with the stock body/eye-derived
   authoritative ray, pointed along hand aim. A visible muzzle-to-target line
   can differ at close range. Converging that ray on a point selected by the
   hand ray is another candidate, but changes near-cover behavior and needs
   obstruction checks from the stock origin. It does not turn that origin into
   the hand. Do not claim precise muzzle-origin combat without server support.
6. **Verify each action family and lifecycle.** Cover hitscan, grouped shots,
   projectile guns, continuous fire/staff, target selection, throws, button
   melee/block/push, interaction, downing, rescue, spectating, death, reconnect,
   extraction and return to hub. Preserve stock server validation and weapon
   statistics throughout.

## Validation ladder

The first isolated check executes actual stock methods for fixed-frame angle
caching, resend, receive and history lookup with an in-memory RPC sink:

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-online-input-stock-contract.lua _downloads/Darktide-Source-Code
```

PASS: corresponding action/angle frames, preserved earlier aim after later
samples, duplicate/old packets, ring wrap, skipped windows and latest-received
fallback. A deliberately smaller ring exercises wraparound. Input parsing and
engine/network serialization are stubs; this does not establish wire precision,
server acceptance, damage, locomotion correctness or visual acceptance. The
optional source snapshot is not required by the normal portable test suite.

Completed offline follow-up: the range-only adapter now has stock first-person,
movement, camera and shot-preparation checks. Passing its two module paths after
the source-root argument in the input-history test also exercises the actual
adapter through stock send/receive and `HumanUnitInput` frame lookup. Eight
representative action/movement/angle columns retain their paired history,
including UI/tracking fallbacks, later changed live aim, resends and ring wrap.
This does not restore engine component state or establish wire precision.
Real corrections and remote admission remain later checks.

The optional fixture now also executes actual `ExtensionManager`,
`ExtensionSystemHolder` and `ExtensionSystemBase` replay dispatch against three
recorded frames. Correction callbacks run before replay; each frame advances
the stock input reader before the simulation consumer. Old aim, movement and
action columns remain paired even when reading current hand tracking would
throw. No input recapture or packet send occurs. System maps/lists clear before
replaying a different unit. The correction component and consuming simulation
are supplied fixtures, so this covers Lua replay orchestration and history
ownership, not engine component restoration or live correction convergence.

The correction-boundary follow-up executes stock
`PlayerUnitDataExtension._read_server_unit_data_state` and `_copy_components`,
plus stock input-handler clock acknowledgement/panic methods. With a small
supplied number/boolean/array schema, a mismatch corrects the cached state,
copies the next ring entry, notifies action input and enters/exits replay.
Matching, duplicate and older snapshots do not replay. Future or expired-window
snapshots acknowledge stock clock state and enter its panic path without
decoding components or overwriting newer ring entries; an in-window recovery
clears panic. Game-object decoding, the field schema, clock effects, telemetry
and the simulation consumer remain substitutes. Engine vector/quaternion
userdata restoration and live correction convergence are not exercised.

Objective-device follow-up runs stock minigame input against both the client
and server `HumanUnitInput` readers after recorded send/receive. Eleven frames
cover primary/interact/jump holds, release, alternate cancellation, stock dodge
arbitration, device-axis quadrants and zero, blocked weapon actions and a missing
wielded device. The range adapter leaves this state in stock view/axis ownership
despite changed live hand aim. Animation, minigame and weapon endpoints are
sinks; this does not complete an actual objective or test its rendered scanner.
The separate portable scanner-stick test covers bypassing the optional
left-hand locomotion rotation for device axes.

Follow-up user direction: configure Psykhanium to use the same combat/input
rules as online where possible, and improve that path there first. This changes
the next implementation target to a range-only online-rules proving mode.
The [initial candidate](PSYKHANIUM-ONLINE-RULES.md) is now implemented offline.
Local server simulation still cannot reproduce real network latency or prove
official-server compatibility; the later remote check remains necessary.

Live checks require successful Ready preflight. First establish controlled
client/server attack agreement and correction behavior; then verify a real
remote-server mission, including close cover and head/hand disagreement, with
server-confirmed outcomes. No public mission, packet experiment, deployment or
matchmaking action was performed for this audit. Worn view, alignment and
comfort checks remain pending until the user is available.
