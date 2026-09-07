# Online server pose and combat capability assessment

7 September 2026. The user has paused the firing-only aim-switch proposal and
requested a broader assessment of client control, especially reporting the head
at the hand. This is source inspection and isolated execution, not an online
server experiment. The running Psykhanium session retains continuous hand aim
and stock firing origins; no experimental network messages or backend changes
were made.

## Answer to the head-at-hand question

There is no independent head-position input in the inspected combat input
stream. The server computes the first-person position as:

```text
first-person position = simulated character position + (0, 0, character height)
```

Changing the position field in our local process does not send it as a head
report. The next stock first-person update also recomputes that field. Changing
the local wanted height can persist in local prediction, but the remote server
has its own height state and sends corrections back. A successful local-server
override therefore does not demonstrate remote acceptance.

Height is **more than a standing/crouching bit**: stance transitions interpolate,
slide and vault have their own heights, character customization scales heights,
and eligible cover peeking continuously changes eye height between crouching
and standing. All these remain vertical offsets above the character position.
None supplies the horizontal displacement needed for a hand held forward or to
one side. [Stock first-person calculation](https://github.com/Aussiemon/Darktide-Source-Code/blob/0f0cb45991e9305ef4a7b925370792d7d6035f95/scripts/extension_systems/first_person/player_unit_first_person_extension.lua)

The broad client freedom is to choose inputs that the server already understands,
including aim angles. An arbitrary new origin would need another active server
path that accepts position, a server implementation change, or an unestablished
validation gap. The inspected code does not establish such a combat path.

## What the client controls

| Quantity | Inspected route | Assessment for VR |
| --- | --- | --- |
| Aim direction | One yaw/pitch/roll triple per fixed simulation frame | Hand aim can occupy the stock aim stream. No independent head and hand aim streams. The receiver shown in Lua does not apply an obvious angular-speed limit; compiled packing and live-server acceptance remain unknown. |
| Action requests | Stock held/pressed/released inputs | Gestures can request fire, charge, block, push, reload, crouch and other actions. The server still runs weapon timing, costs and state transitions. |
| Movement request | Four packed movement magnitudes | We can choose the requested movement vector. Server movement, acceleration, collision and directional speed rules determine actual position. |
| First-person/head position | Reconstructed from locomotion and height | No independent position column found. Local camera or hand transforms do not publish authoritative eye position. |
| Height/stance | Simulated state plus profile-derived height table | Intermediate vertical heights exist; they are not arbitrary client height reports. Crouching also changes character behavior, not merely camera height. |
| World body position | Locomotion simulation and server state replication | Ordinary movement changes it. Editing local locomotion alone causes disagreement/correction. Matching a hand origin by moving the whole body also moves the collision body and server character. |
| Weapon spawn offsets/nodes | Server-side action and projectile templates | Existing offsets can depend on aim and stock animation. Client template edits do not change the server's template. The tested staff has zero configured offsets. |
| Throw velocity and spawn clearance | Server's aim/trajectory and obstruction calculation | Controller motion can select a supported throw action or direction; no arbitrary hand velocity report was found in this route. |
| Target selection/placement | Stock targeting, lock-on and position-finder components | Aim can influence targeting, but local replacement of the component is not a target-position report. Cached target and release behavior differ by action. |
| Melee contact | Stock sweep spline, aim reference and damage window | A gesture can trigger or steer a stock swing. Exact tracked-blade contact, reach and independent off-hand contact are not represented. |
| Pings/tags | An actual client request includes a target unit/location | A useful separate route for hand-directed pointing. It retains tag semantics and validation; it is not a shot-origin field. Tags may have their own gameplay effects. |
| Stereo, local hands, muzzle effects | Local presentation | Considerable freedom. Visual relocation alone cannot relocate authoritative collision or damage. |

The input settings describe 57 columns including the three angle columns:
four movement magnitudes, 50 action/settings values and three angles. There is
no positional vector among them. The outer message also carries player/frame
identifiers. `StateGameplay.rpc_player_input_array` resolves the player from
the sender's connection plus local-player ID, then routes to that player's
handler. A local-player ID is not an arbitrary remote-player selector.
[Input settings](https://github.com/Aussiemon/Darktide-Source-Code/blob/0f0cb45991e9305ef4a7b925370792d7d6035f95/scripts/managers/player/player_game_states/input_handler_settings.lua)

The ordinary local orientation producer clamps pitch to approximately +/-81
degrees and sets roll to zero. Those producer choices are not proof of identical
server checks: the audited receiver stores the supplied angle columns and the
server first-person calculation consumes them. Forced views, recoil and action
rotation locks still influence the resulting pose. Exploiting out-of-range or
non-finite values is neither implemented nor established as useful support.

## Height, peeking and profile details

The human breed defines default, sprint, crouch, slide and vault height values.
The inspected state callers explicitly request crouch, slide, vault and default;
the presence of a sprint entry alone does not prove it changes authoritative
height during every sprint. Transitions include 0.3-second crouch/slide changes
and use easing rather than an instant arbitrary-height input.

Cover peeking requires a significant obstacle, crouching, the veteran cover
peeking special rule, a suitable ledge, and an alternate-fire configuration
that enables peeking. The admitted calculation uses aim pitch and the detected
ledge height, clamps the target to crouch/standing heights and rate-limits
height changes. It is not a generally available hand-height channel, especially
for a Psyker staff. Steering pitch to change peek height also steers the shared
combat aim. [Peeking admission](https://github.com/Aussiemon/Darktide-Source-Code/blob/0f0cb45991e9305ef4a7b925370792d7d6035f95/scripts/utilities/player_unit_peeking.lua)

The character-height customization affects the profile and body scale as well
as first-person heights. The human UI range comes from `size_variation_range`
(0.95 to 1.08 in this snapshot). This is a UI range, **not a verified backend
validation limit**. `PlayerHeight` does not itself clamp a supplied profile
height; that does not mean a remote client can supply any value the host uses.

For profile updates, the client's notification contains only its local-player
ID. The host checks whether profile changes are allowed and fetches the account's
character profile from the backend before synchronizing it. Arbitrary local
profile edits or adding a height to that notification do not replace that
fetch. Backend acceptance of unusual height values and initial profile-loading
validation have not been exhaustively audited. Even an unusual accepted profile
height would be a character-wide scalar, not a high-frequency 3D hand pose.
[Height calculation](https://github.com/Aussiemon/Darktide-Source-Code/blob/0f0cb45991e9305ef4a7b925370792d7d6035f95/scripts/utilities/player_height.lua),
[host profile update](https://github.com/Aussiemon/Darktide-Source-Code/blob/0f0cb45991e9305ef4a7b925370792d7d6035f95/scripts/loading/profile_synchronizer_host.lua)

## Can existing offsets be made to behave like a hand origin?

For the inspected spawn-projectile action, the more complete launch calculation
is approximately:

```text
origin = stock first-person position OR a configured first-person animation node
       + aim-rotated template offset
       + aim-rotated action offset
       + character velocity * time since projectile payment
```

Each term has an existing owner and meaning. It is not a packet containing a
client-selected final origin. Lag compensation can affect the payment/launch
timing, but its calibration is derived by the server from frames and latency;
no independent rewind-duration field exists in the inspected input message.
The precise bounds of compiled transport and production timing remain unknown.

For `forcestaff_p4_m1`, rapid and charged shots use `force_staff_ball` and
`force_staff_ball_heavy`. Both locomotion templates specify `(0,0,0)` spawn
offsets, and the inspected weapon actions specify no spawn node/action offset.
Rotating a zero offset cannot move it to the hand. This matches the user's
observed reticle-directed, face-origin staff shots. Movement compensation can
displace the launch point, but it is tied to body velocity/timing and offers no
general hand-position control.

For another weapon with a nonzero offset, varying aim rotates that fixed offset.
Geometrically, roll could rotate a lateral offset around the aim axis while
leaving forward direction unchanged. This is a theoretical, weapon-specific
degree of freedom: it cannot change the offset's length, the tested staff has
no such offset, and server acceptance of non-stock roll is unverified. It is
not an arbitrary six-degree-of-freedom weapon pose.

Moving the character so its eye coincides with the hand is also geometrically
possible at a particular instant, but moves the authoritative body. Compensating
the local camera afterward does not undo the body's collision, enemy targeting,
traversal or correction behavior. It is unsuitable as an invisible general
hand-origin substitution.

## Other position-bearing messages

The broader receiver-signature and sender inspection found these relevant
alternatives. Message existence is not evidence of active server registration.

| Route | Finding |
| --- | --- |
| Debug free-flight teleport | A handler can accept a position and teleport the sending player's entire character when instantiated on a server. However, the inspected gameplay free-flight initialization does not instantiate the teleporter, and the source-wide search found no constructor call. Its presence does not establish an active official-server endpoint. |
| Smart-tag request | An active server request carries a location/target and creates a tag after template/target checks. It does not assign first-person position or projectile origin. |
| Projectile/impact/muzzle effects | Audited receivers start effects on existing units or render impacts. They do not create a new authoritative staff attack from a reported hand position. |
| Pickup/deployable movement | Audited senders publish server movement to clients; these are not player-position inputs. |
| Expedition airstrike | Server initiates it; the position-bearing message is registered with the client RPC list. It is not a general client projectile request. |
| Kill-health notification | HealthSystem registers it only on clients; a misleading function name is not a server damage API. |
| Attack/block/explosion results | Previously audited result and husk-effect paths. They do not supply an independent client hand-origin attack. See the earlier origin-message audit. |

The debug teleport path is worth recording rather than declaring every
position-bearing RPC impossible. Its reachability on production servers is
unestablished, and even reachable teleportation would not solve independent
head/hand pose representation. No such messages were sent.

## Engineering choices and difficulty

| Approach | Difficulty and expected result |
| --- | --- |
| Continuous hand direction, stock origin | Most concrete online candidate. Moderate integration work remains for remote-mode admission, lifecycle, UI, targeting and correction agreement. Staff behavior is accepted only in local Psykhanium so far. |
| Hand-ray target, stock-eye ray aimed at that target | Moderate per-family work. Improves convergence at the chosen distance; near cover and different depths still distinguish the two origins. Needs a stock-origin obstruction check and clear feedback. |
| Local staff-origin visuals reconciled to stock collision | Moderate to substantial per-family work for projectiles, beams and effects. Can improve appearance, but cannot promise shooting around cover with only the hand exposed. |
| Physical crouch mapped to stock crouch | Straightforward input mapping, followed by comfort/clearance checks. Limited to the game's stance behavior; does not track arbitrary hand height. |
| Existing weapon offset/roll interpretation | Speculative and narrow. First requires an applicable nonzero offset and a controlled acceptance test. No benefit established for the tested staff. |
| Arbitrary authoritative hand origin on official servers | No supported route established. This is an open server/protocol constraint, not a small client-side patch with a defensible estimate. |
| Exact origins and physical melee under local authority | Feasible as a separate mode because we own simulation. Substantial collision, damage-window, prediction and per-weapon work remains. Other clients having the mod alone would not modify an official server. |
| Aim changes only during firing | Explicitly on hold at the user's request. Earlier timing/movement findings are retained for reference, with no implementation. |

## Evidence, reproducibility and unknowns

Snapshot: `0f0cb45991e9305ef4a7b925370792d7d6035f95`, locally available under
`_downloads/Darktide-Source-Code`. These are inspected game scripts, not proof
that today's official server executable is identical. The source inventory
does not include a complete native RPC serialization/ownership specification.
Lua producer clamps, field names and receiver bodies cannot establish all wire
ranges, connection filtering, anti-cheat behavior or backend validation.

The optional fixture runs actual stock first-person calculation and profile
height code with isolated engine math and supplied state:

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-server-head-position-stock-contract.lua _downloads/Darktide-Source-Code
```

PASS: client/server pose recomputation, server-only height publication,
intermediate stance heights, admitted peeking bounds, all 57 input columns and
profile height scaling. The fixture deliberately also shows that changing
`wanted_height` locally changes local calculation; it does not mislabel that
as server acceptance. Peeking admission is source-inspected separately rather
than bypassed by the fixture's pre-admitted state.

The existing input-stream and broad online-rules stock contracts also pass on
this checkout, and the pinned LuaJIT gate compiles all 37 mod chunks. No new
CTest registration or full native build was needed for this documentation and
optional source-fixture change.

Useful next validation is a controlled remote-authority comparison: identical
recorded inputs in prediction and a separate stock authority, with measured
first-person origin, action target, collision result and correction state.
Psykhanium with local overrides can expose client/server algorithm differences
but cannot test what an unmodified remote server will accept. Official-mission
testing of the ordinary compatibility candidate remains pending. No arbitrary
origin claim should be promoted to confirmed without remote evidence.

Additional inspected paths under stock `scripts/`:

- `game_states/game/state_gameplay.lua`: sender/player input routing.
- `managers/player/player_game_states/authoritative_player_input_handler.lua`:
  recorded angle/action consumption.
- `extension_systems/first_person/character_state_orientation/default_player_orientation.lua`:
  local pitch limits and zero roll.
- `extension_systems/unit_data/player_unit_data_extension.lua`: server state
  publication, client correction and resimulation.
- `extension_systems/locomotion/player_unit_locomotion_extension.lua`: body
  movement, collision and server position publication.
- `utilities/alternate_fire.lua`, `utilities/player_unit_peeking.lua`,
  `utilities/character_create.lua`, `settings/breed/breeds/human_breed.lua`:
  peeking admission and customization range.
- `extension_systems/weapon/actions/action_spawn_projectile.lua`,
  `settings/projectile_locomotion/templates/weapon_projectile_locomotion_templates.lua`:
  launch offsets and staff zero offsets.
- `extension_systems/weapon/actions/action_aim_projectile.lua`,
  `actions/modules/ballistic_raycast_position_finder_action_module.lua` in the
  same weapon directory: server-reproducible throw and position finding.
- `extension_systems/free_flight/free_flight_teleporter.lua` and
  `game_states/game/gameplay_sub_states/gameplay_init_step_states/gameplay_init_step_free_flight.lua`:
  dormant teleport path and inspected initialization.

Related assessments: [online requirements](ONLINE-MISSION-REQUIREMENTS.md),
[paused aim-window investigation](ONLINE-AIM-WINDOW-AUDIT.md),
[Psykhanium approximation](PSYKHANIUM-ONLINE-RULES.md).
