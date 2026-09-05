# Tracked melee: accepted direction and implementation investigation

Status: design based on the local Darktide source snapshot, 5 September 2026.
Not enabled in the current live build. Button-driven stock melee remains the
interim system; the user accepted its hand-directed aim on 5 September.

## User-selected rules

The weapon's VR melee collision volume is always active, sized to the ordinary
melee attack hitbox. Damage eligibility is per enemy: after a hit, that enemy
cannot be hit again until the normal attack interval expires. There is no global
attack cooldown, motion-speed threshold, required swing gesture or stock damage
window gating the physical volume. Continuous overlap becomes eligible again
when the target cooldown expires, even without leaving and re-entering.

Cleave is intentionally unlimited. The user accepts the advantage over flatscreen
as a tradeoff for the naturally slower VR play. Do not reintroduce a stock hit-mass
budget or stop processing later enemies because an earlier target used up cleave.
Normal armour damage/resistance, shields and world obstruction remain distinct
from a numerical cleave limit. Resolve special armour/breed stop behavior
explicitly in implementation so it does not silently restore finite cleave.

Heavy attacks use a per-enemy cooldown based on the stock charge time, and start
on cooldown. Track an initial heavy-ready timestamp on weapon/mode activation;
newly encountered enemies inherit that initial gate, rather than receiving a new
full charge delay every time they are first observed. After a heavy hit, that
specific enemy gets its own charge-duration deadline. No banked burst damage.
Light and heavy eligibility must share target history enough that toggling attack
mode does not bypass a cooldown already owed to that enemy.

An explicit heavy intent using the existing input is a provisional control
mapping. Weapon power activation, chainsaw sticky damage and force/power-weapon
specials are distinct from heavy attacks. No motion-only heavy gesture has been
selected. The earlier suggestions for global cadence, deliberate-stroke gating
and finite stock cleave are superseded by the user's clarification above.

## Reuse the stock collision and damage pipeline selectively

ActionSweep performs swept oriented-box collision, with a sphere-sweep variant,
rather than colliding the rendered mesh. `_weapon_half_extents` uses weapon/action
`weapon_box` plus width/height/range modifiers. For example, chainsword_p1_m1 uses
half-extents 0.15, 0.15, 1.1 and some actions multiply range by 1.25. Use the chosen
normal attack's effective volume, not a guessed mesh-sized collider.

Replace the authored trajectory with successive tracked weapon poses. Align a
fixed grip-to-hilt transform to the stock sweep axis convention: `_modify_sweep_position`
already offsets by the box half-length, so avoid applying it twice. Preserve the
requested normal combat volume dimensions when positioning it at the tracked
weapon; make its effective reach visible in the diagnostic overlay.

The useful starting seam is ActionSweep._do_overlap / _run_sweeps. The complete
stock pipeline cannot be reused unchanged: it has damage windows, a once-per-action
hit set, finite cleave, attack abort rules and head-view rejection. Adapt these
parts to the selected continuous/per-target design. Preserve hit-zone selection,
armour damage, critical behavior, stagger, appropriate blessings and hit effects,
without accidentally firing stock attack-start/finish procs once per render frame.

Use stock Attack.execute via a dedicated adapter around the existing action
context rather than inventing damage formulas. Decouple hit-mass/target-index
bookkeeping from eligibility: infinite target count must not quietly produce
zero damage at later stock target indices. Retaining normal target-index damage
falloff versus primary-target damage for all contacts is an explicit balance
choice still to resolve, not something the current design claims implemented.

Stock `_pick_best_sweep_result_per_unit` rejects contacts outside the player's
head-facing view. Physical melee must be based on validated weapon contact,
regardless of head gaze. Interim button-driven hand aim instead uses the attacking
hand's frame for that eligibility test; do not globally remove it for other actions.

The stock selector also uses action-specific hit-zone priorities and a dynamic
shield priority based on whether the shield is blocking and the attacker's
position relative to its blocking arc. A plain first-actor overlap result would
lose this behavior. Collect all hurtboxes for a target before selecting its
contact, including across rotational substeps. Do not spend its cooldown on an
arbitrary arm result before a shield or higher-priority hit zone is considered.

`_process_hit` is not a stateless damage helper: it writes the action's hit set,
mass, target index, enemy/kill counters and weakspot state, invokes weapon specials,
may extend the current action and may initiate chain lightning. Its resimulation
guard covers damage/effects but not all of those mutations. Calling it every
eligible physical contact on an idle action would therefore be incorrect.
The dedicated adapter must own valid attack context and proc lifetimes, and
execute damage only once for an authoritative/predicted simulation event.

Physics sweep tables are reused. Stock deferred sweep processing boxes actor,
position and normal values before a later query can overwrite them. The VR
collector must likewise copy contact data before the next subdivision query;
keeping a reference to a reusable result table is unsafe even within one frame.

## Continuous collision sampling

Sample in simulation time, with swept boxes between valid poses and overlap at
the current pose so a stationary contacting weapon stays active. Subdivide large
rotations to cover the blade arc, within a bounded per-update work budget. A long
frame, teleport, recenter or tracking loss must reset history instead of sweeping
across an artificial discontinuity. Invalid tracking suspends the volume until a
fresh valid pose is established; this is input validity, not a movement threshold.

Deduplicate multiple hurtboxes, repeated substeps and duplicate physics results
per target before applying cooldowns. Cooldowns use simulation-clock deadlines
and stable unit generation identities. Do not clear them on a pose-history reset
or a quick weapon/mode switch. Despawn cleanup must prevent stale-unit retention.
Misses do not impose a global penalty. Blocked/zero-damage contacts should consume
that target's contact interval so they cannot generate unlimited stagger/procs.

Do not skip physical obstruction merely because a target is on cooldown: that
must not let an unavailable shield contact turn into a hit through the shield.
Likewise unlimited cleave is not permission to hit through scenery. Separate
blocking/occlusion results from damage-eligible target filtering.

The inspected stock box sweeps request at most 5, 20 and 20 raw results, and
the sphere variant requests 20. Removing hit mass alone therefore cannot
establish unlimited target collection. A saturated result buffer is incomplete
evidence, not an empty remainder. The contact adapter needs a verified engine
strategy for collecting the full local set (for example, supported larger-query
retries or spatial partitioning), with saturation telemetry. Do not assume a
pagination or exclusion option exists without checking the engine API. Actor
deduplication and target deduplication are separate: several shield/body actors
can consume raw capacity before reaching many distinct enemies.

For stationary contact, `PhysicsWorld.immediate_overlap` is already used with
`shape="oobb"`, position, rotation and size in `MinionAttack._melee_with_oobb`.
It returns an actor list and count without an explicit Lua-side result maximum.
Other stock overlaps use the melee collision filter; push attacks also pass
`rewind_ms`. This is a concrete candidate for the non-damaging overlap probe,
not proof of unlimited engine capacity or of box-query rewind support. Overlaps
provide actors, whereas sweeps provide contact positions/normals as well; the
damage adapter must resolve proper hit-zone/contact data before using this path.

## Timing data

Use seconds per normal attack, including effective weapon handling and attack-speed
buffs. Full animation length is not the normal attack cycle: the inspected chainsword
example has total_time 1.3, damage window 0.3-0.4, and an attack chain at 0.55 before
speed scaling. Use the stock action/chain timing resolver rather than copying a
single display stat. Some action kinds invert time-scale handling.

Specifically, `_calculate_time_scale` combines weapon handling, the action's
listed stat buffs and gameplay/network clamps. `_validate_single_chain_action`
divides chain time by this scale, except designated inverted action kinds below
scale 1, where it multiplies. Select the ordinary attack-chain transition, not
the earliest arbitrary allowed chain: the example permits blocking/special at
0.45 but another attack at 0.55. Follow any intermediate windup before calling
that value a complete attack interval. Reusing the live handler's calculation
avoids incorrectly reading a single attack-speed buff or current idle action.

The relevant heavy threshold is the windup-to-heavy transition. In this example
it is 0.5, whereas windup total_time is 3. The user's selected heavy cooldown is
that effective charge duration, not a silently added stock recovery/global cycle.
Readiness starts unavailable as described above. Snapshot or consistently advance
existing target deadlines when buffs change; changing weapons or modes must not
manufacture an immediate extra hit.

## Prototype order and verification

1. Non-damaging always-active volume/contact overlay in the private range, matched
   to the normal action's collision volume and tracked grip-to-weapon transform.
2. Continuous light contacts through a dedicated stock-damage adapter, per-enemy
   cooldowns and unlimited target count. Keep tracked hands active throughout;
   the interim stock-arm-animation override does not apply to physical melee.
3. Heavy initial/per-enemy readiness, shared target history and existing heavy
   input; then weapon specials, push/staff actions and weapon-specific geometry.
4. Verify authority, prediction/resimulation and lag compensation before claiming
   multiplayer support. A local range prototype does not establish host/client
   behavior or remote animation/contact correctness.

Acceptance: stationary contact repeats only at cooldown; tiny motions cannot
increase same-target rate; several enemies can each receive eligible damage;
multiple hurtboxes/substeps do not multiply hits; no finite cleave cutoff; shield
and wall obstruction; no initially free heavy; no accumulated bursts; light/heavy
switching, speed buffs, weapon swaps, tracking loss/recenter, frame-rate changes
and duplicate simulation updates. Measure per-target damage and proc counts.
The user-selected infinite cleave is intentional and must be documented publicly.

## Source map (local inspected snapshot)

Paths below are beneath ignored `_downloads/Darktide-Source-Code`; game source
is not redistributed by this document.

- scripts/extension_systems/weapon/actions/action_sweep.lua: start (201),
  _update_sweep (483), _do_overlap (956), _pick_best_sweep_result_per_unit (1128),
  _process_hit (1320), _run_sweeps (1524), _weapon_half_extents (1611).
- scripts/extension_systems/weapon/actions/utilities/sweep_spline_exported.lua:
  position_and_rotation (14), authored trajectory seam.
- scripts/extension_systems/first_person/player_unit_first_person_extension.lua:
  is_within_default_view (503), head-facing rejection.
- scripts/utilities/action/action_handler.lua: effective time scale (362),
  chain validation (828), action lifecycle and proc ownership.
- scripts/settings/equipment/weapon_templates/chain_swords/chainsword_p1_m1.lua:
  sweep box (42), heavy threshold (193), light timing (212), chain (284).
- scripts/settings/equipment/action_sweep_settings.lua: sweep modifiers and
  shield/hit-zone priority functions.
- scripts/utilities/minion_attack.lua: _melee_with_oobb (1322), immediate oriented
  box overlap returning actors/count; scripts/utilities/attack/push_attack.lua
  (36), immediate overlap with lag-compensation rewind.

## Offline foundation now available

`darktidevr_melee_contact_policy.lua` implements the per-target eligibility ledger,
with shared light/heavy target deadlines and initial heavy readiness. It is not
imported by the active mod and cannot cause damage. Its isolated test exercises
continuous contact, several independent targets, duplicate contacts, initial
heavy delay, mode changes and no banked burst. Future physics integration must
supply validated simulation contacts, effective intervals and stable target
generation keys, and retain stock obstruction separately from damage eligibility.

`darktidevr_melee_sweep_plan.lua` separately plans rotational subdivision and
current-pose overlap, with explicit gap/discontinuity and query-budget outcomes.
It also is not imported by the live mod. Its inputs are validated hilt displacement,
shortest-arc rotation, simulation interval and the collision volume's maximum
corner radius about the hilt. Do not substitute the box half-length for this
radius: the centre offset makes the far corner roughly a full box length away.
The adapter must derive that radius from the actual volume and grip transform.

The planner bounds rotational travel per substep; it does not claim that sampled
linear boxes exactly cover a rotating box's swept volume. Thin-target and tip-arc
tests remain required against game physics. It keeps current overlap when history
is unsafe or exceeds the query budget and reports that loss instead of silently
coarsening the sweep. Limits in the isolated test are fixtures, not calibrated
release defaults. No cooldown state is owned or cleared by pose planning.

`darktidevr_melee_volume.lua` resolves the chosen action's stock box override,
width/height/range modifiers and axis convention into half-extents, local centre
offset and origin-based corner radius. Matrix-authored and older spline actions
use different length axes; treating both as the same would distort the hitbox.
Sphere-sweep actions retain their explicit radius with no box centre offset.
Missing/invalid geometry produces no volume rather than a guessed default.
This module remains offline and unimported. A real tracked grip-to-sweep-origin
transform still needs calibration before physics queries or visible overlays.
