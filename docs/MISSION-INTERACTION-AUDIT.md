# Mission interaction coverage

7 September 2026 source audit against the local stock snapshot. No mission or
SoloPlay run and no worn acceptance. The local-authority admission policy in
[MISSION-AUTHORITY-AUDIT](MISSION-AUTHORITY-AUDIT.md) still applies.

| Interaction | Stock consumer | Controller candidate / remaining check |
| --- | --- | --- |
| Use, pickups, revive, rescue and objective sockets | `InteractorExtension._check_current_state` reads the interaction's action (normally `interact_pressed`), then `interact_hold` for required holds. | X supplies both through the shared mapper. Target validity, hold cancellation and actual server completion need live checks. |
| Carry supplies / equip stim / device | `PlayerCharacterConstants.slot_configuration` maps `wield_3`, `wield_4`, `wield_5` to pocketable, small pocketable and device slots. | Newly assignable actions; defaults remain unbound. Stock equipment availability and action transitions still decide whether the slot can be wielded. |
| Cycle item and stim | `PlayerUnitVisualLoadout.slot_name_from_wield_input` handles `wield_3_gamepad` and available inventory. | Newly assignable cycle action; it does not promise a particular slot, so direct-slot hints do not substitute the cycle label. |
| Supply placement / push / give | `pocketables/settings_templates/pocketables_template_settings.lua` uses primary press, alternate press, and weapon-special hold respectively. | Existing RT, LT and combat R Grip routes. Targeting, placement and hand origin still unverified. |
| Luggable aim / throw / cancel | `luggables/luggable.lua` uses primary hold then release; alternate cancels/pushes. | Existing controls supply the actions. The subsequent [trajectory candidate](RANGED-WEAPON-AUDIT.md#luggable-trajectory-candidate-7-september) couples hand aim and preview, preserving cached release and stock drops. Physical carry alignment and live throw origin remain unverified. |
| Scanner minigame action / cancel / knob | `PlayerCharacterStateMinigame._update_input` reads primary/interact/jump holds, alternate press and `move`. | Existing RT/X/A, LT and left-stick routes. `ScannerDisplayView.is_using_input` returns false; it renders the device rather than owning those gameplay actions. Visual readability, axis behavior with left-hand movement reference, and lifecycle remain unverified. |
| Inspect operative / companion | Interaction templates override the input to `interact_inspect_pressed`. | Newly assignable Inspect operative / pet companion action, separate from ordinary interaction and weapon inspection. Stock companion ownership/idle checks and operative-view validation remain in charge. |
| Cycle spectator target | `CameraHandler.update` reads `spectate_next` directly from the selected local Ingame service. | A by default, following the configured jump binding, through a separate camera-only reader. Current local camera, stock service, mode and neutral-rearming guards apply without requiring a character. Matching cached hints follow remaps. Undeployed; stock target decisions and observer comfort still need live checks. |

Source paths are under `_downloads/Darktide-Source-Code/scripts/`. Revive's
`stop` method only applies success on the server; input delivery alone cannot
establish that a teammate was revived. The existing controller-aim module wraps
stock target acquisition and ongoing validity checks in a scoped right-hand
pose for the local player. Those source routes do not establish mission target
alignment or hand-pointed interaction acceptance.

## Slot selection candidate

The existing binding menu now includes Equip carried item / supply crate,
Equip stim, Equip scanner / mission device, and Cycle carried item / stim.
Each emits its stock wield press once through the existing input cache adapter.
There is no inventory mutation, automatic item use, key injection or native ABI
change. Hub overrides, remap quarantine, tracking/session neutral guards and
scoped prompts share the same catalog. Users must assign these actions before
controller use; existing saved controls and defaults are preserved.

Pinned LuaJIT compiles all 34 chunks. Focused CTests pass for controller
bindings, controller prompts, gameplay UI input and Lua invariants. Fixtures
cover each stock action, edge-only delivery, held aliases, blocked transitions
and distinct direct/cycle hints. Runtime deployment and mission acceptance are
pending a successful Ready preflight and later live checks.

## UI ownership correction

The main gameplay adapter compares `UIManager.inputs_in_use()` with boolean
true, but the audited stock function returns `_ui_inputs_in_use`, a key table.
The separate `using_input()` API reports whether views/HUD/constant elements
own input. The subsequent candidate uses `using_input()` without excluding any
owner. Missing, failing or invalid managers block VR input. The native and Lua
mappers still clear state while blocked, but the adapter no longer injects a
charged-release edge from that cancellation. Reopening gameplay requires held
controls to return neutral. Scanner gameplay input remains admitted because its
display reports no input ownership. Stock keyboard caches are preserved.

The isolated test exercises the actual adapter function and mapper across an
overlay opening during RT hold, cancellation, neutral resume, ordinary release,
scanner ownership and missing/retiring UI managers. Live chat/overlay and
scanner transitions still need verification.

## Scanner axis reference correction

The shared movement adapter formerly applied optional left-hand-relative walking
rotation to every `move` consumer. `PlayerCharacterStateMinigame._update_input`
uses that vector directly as a device knob/axis. The candidate bypasses the
walking transform while the current local character state is `minigame`, using
the same state distinction as stock `utilities/weapon/auspex.lua`. It queries
the current extension each sample, not the throttled diagnostic state name.

This leaves native stick deadzone, keyboard composition, scanner algorithms,
head-relative defaults and ordinary hand-relative walking intact. The real seam
test covers a 90-degree hand offset, both device axes, changing hand orientation,
immediate entry/exit, missing tracking and retiring/missing state. Five focused
CTests and the 34-chunk LuaJIT gate pass. Scanner readability, tactile controls
and mission lifecycle remain live acceptance items.

## Hub target interaction binding

The binding catalog now exposes the stock `interact_inspect_pressed` edge for
operative inspection and companion interaction. It remains unbound by default;
the hub override can assign it without replacing the combat interaction mapping.
Shared interaction hints read the same effective profile. No direct view-open,
companion event or network call is added. The stock player-inspect view remains
read-only, and companion ownership, target validity and idle conditions remain
stock decisions. Live target selection and hint appearance remain pending.

Online-rules follow-up: stock interaction searches and the inspected ability
targeting modules already read the simulated first-person component. Smart-tag
HUD marker selection had a separate screen-centre scan, however. The candidate
now selects the marker for the stock simulated target during the range proving
mode, preserving stock force-refresh and marker validity. A head-centred unrelated
marker no longer overrides that target. Five focused tests pass, including the
actual HUD hook with local/remote/retiring ownership and empty/invalid targets.
No live tag, revive, rescue or mission completion is claimed.

Validation: 34 LuaJIT chunks and four focused CTests pass. Fixtures cover the
stock edge name, held aliases/rearming, hub/combat hint changes and separation
from ordinary interaction and weapon inspection.

## Spectator input and rescue ownership, 7 September

On source snapshot `0f0cb45991e9305ef4a7b925370792d7d6035f95`,
`HumanGameplay.update` selects `_get_input()` again and passes it directly to
`CameraHandler.update`. Spectator cycling therefore needs a scoped local input
route at that consumer; adding an action to the fixed combat cache alone would
not reach it. The same null-service/UI/cinematic ownership rules must apply.
The present VR mapper intentionally requires a current live character object,
so it cannot be reused unchanged for a player whose character is unavailable.
The subsequent candidate below adds that separately admitted route and hint.

The stock camera selects its own transition policy. Entering the hogtied state
or beginning rescue returns observation to the player's own unit. A subsequent
cycle press can select a teammate while hogtied; recovery returns to the owner
and first-person mode. Death outside an expedition safe zone selects the dead
camera instead of immediately cycling. The safe-zone branch can select a
teammate, and unavailable players can cycle past their own unit. Cinematics
skip the ordinary switching branch. A future binding must feed the action and
let these decisions remain stock, rather than selecting targets directly.

`CameraHandler._camera_root_orientation` also has a separate first-person
observer branch: it uses the followed unit's interpolated spectated aim, falling
back to that unit's first-person component. The existing offline independent
HMD/hand check covers ordinary local first-person mode, not this observer
branch. Spectator view/comfort, transition to rescue and the disappearance of
the local character remain explicit mission acceptance items. The later input
candidate leaves this camera orientation policy unchanged.

The optional `tests/tooling/test-spectator-stock-contract.lua` now executes the
actual `HumanGameplay` input selection/update and `CameraHandler` update,
roster selection and root-orientation methods. It covers normal ownership,
hogtied entry/cycling/rescue, ordinary death, expedition safe-zone death,
unavailable and removed local units, lost follow targets, UI/ImGui null services
and cinematics. Actual roster selection skips bots, wraps between humans and
returns no target for an empty roster or an excluded sole owner. In particular,
the dead safe-zone branch selects away from the owner but does not consume cycle
input while that dead branch remains active. Preserve this stock distinction.

Validation command (PASS on the snapshot above):

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-spectator-stock-contract.lua _downloads/Darktide-Source-Code
```

Engine camera/mood/UI work and character-state components are supplied sinks or
fixtures. Input edges are supplied, not read from a headset. The observer checks
confirm followed-unit aim and its component fallback, not comfort or tracking.
This remains an optional source check, independent of the portable CTest suite.
The native gameplay mapper resets while combat ownership is unavailable; its
current held output therefore cannot simply be reused for spectator controls.
A separate admitted camera-input sample must preserve combat cancellation,
current local camera ownership, input-service restrictions and neutral rearming.

## Spectator controller candidate, 7 September

`darktidevr_spectator_input.lua` now supplies a pressed `spectate_next` only
inside the current local `CameraHandler.update` call. It follows the configured
jump action (A by default), including directional remaps and their turning
exclusion. A separate native mapper uses the same fresh controller transport
validation and button rules as combat, with independent cancellation history.
Its own publisher generation and right-stick validity travel with the sample.
The existing local-authority mode policy, stereo/gameplay enablement, UI owner
and stock null service remain required. Observer/dead camera modes are admitted;
the stock method still decides whether to consume the edge and which unit to
follow. No combat cache, target, aim or damage field is written.

Camera/player/service/mode changes, transport loss/replacement and remaps drain
inherited levels and require neutral input. Missing native exports fall back to
stock input. Spectator hints follow the jump remap and refresh their cached text
when mappings or availability change; an unbound action keeps the stock hint.
Deploy the paired Lua/native candidate together after a successful Ready check.

The full Windows x64 Release build succeeds and all 116 offline CTests pass in
15.52 seconds, including actual native exports/isolated transports, portable
camera ownership/remap checks and all 37 chunks through the pinned LuaJIT gate.
The optional stock contract also accepts trailing spectator, bindings and
gameplay-context module paths; that combined run passes real VR-driven cycling,
UI hold cancellation and stock rescue recovery. Native and engine fixtures do
not establish live headset input, observer comfort or mission acceptance.
