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
| Luggable aim / throw / cancel | `luggables/luggable.lua` uses primary hold then release; alternate cancels/pushes. | Existing controls supply the actions. Physical carry alignment and throw origin are separate from button coverage. |
| Scanner minigame action / cancel / knob | `PlayerCharacterStateMinigame._update_input` reads primary/interact/jump holds, alternate press and `move`. | Existing RT/X/A, LT and left-stick routes. `ScannerDisplayView.is_using_input` returns false; it renders the device rather than owning those gameplay actions. Visual readability, axis behavior with left-hand movement reference, and lifecycle remain unverified. |
| Inspect operative / companion | Interaction templates override the input to `interact_inspect_pressed`. | Separate from ordinary interaction and weapon inspection; still lacks a controller assignment. |

Source paths are under `_downloads/Darktide-Source-Code/scripts/`. Revive's
`stop` method only applies success on the server; input delivery alone cannot
establish that a teammate was revived. Interaction targeting uses the stock
first-person ray/validity checks, so this audit does not claim hand-pointed use.

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

## Follow-up found during audit

The main gameplay adapter compares `UIManager.inputs_in_use()` with boolean
true, but the audited stock function returns `_ui_inputs_in_use`, a key table.
The separate `using_input()` API reports whether views/HUD/constant elements
own input. Review and correct that guard as a separate task, retaining scanner
gameplay input and native-menu release behavior.
