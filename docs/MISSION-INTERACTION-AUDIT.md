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
