# Ranged weapon aim audit

6 September 2026. Active work after the documented DLSS output-association
blocker. User reports every ranged weapon except the force staff firing away
from hand aim. Source coverage is not live acceptance of every weapon.

## Findings and candidate

The local source snapshot is `Darktide-Source-Code` revision `0f0cb45`.
`scripts/foundation/utilities/class.lua` copies superclass methods into each
derived class. DMF replaces the method on the specified table. The old hook
targeted `ActionShoot._prepare_shooting`, after concrete classes may already
have copied that method. Hitscan, projectiles and both flamer classes could
therefore bypass the aiming hook. Pellets has its own preparation override
which calls the base dynamically and resets pellet counters, so that route
must retain its override rather than being classified as a copied-method bypass.
Staff spawn/lightning routes have their
own directly hooked classes, consistent with the user's exception.

The old safe hook also tested simultaneous-group membership after stock code
incremented `num_shots_fired`, while reusing the stock pre-increment expression.
That could skip the first projectile and transform the later reused rotation.
It rebased the shot after muzzle effects had already used head direction.

The candidate hooks all five concrete shooting classes and supplies an
action-local read proxy before stock preparation. Recoil, sway, aim assist,
spread, charge, fire timing, ammunition and projectile grouping remain in the
stock routine. The proxy restores on return and error. It uses the observed
muzzle converged toward the existing hand reticle, with hand-origin fallback.
Alternating muzzle lookup now uses the current pre-increment counter. It does
not mutate the shared camera/movement component.

Both flame classes independently read first-person pose when acquiring damage
targets and suppressed units; those four methods now use the same scoped hand
pose. The usual prepared rotation alone cannot fix those queries.

## Source route coverage

The table includes player weapon families found in top-level template files.
Counts are not used as claims about equipped variants or live class ownership.
Bot templates, grenade abilities, generated templates and luggables were also
searched and are distinguished from player ranged weapons below.

| Firing route | Template families | Candidate coverage |
| --- | --- | --- |
| `shoot_hit_scan` | arc rifle, autoguns, autopistols, bolt pistols, bolters, dual autopistols, dual stub pistols, galvanic rifle, lasguns, laspistols, needlepistols, Ogryn heavy stubbers, phosphor pistol, plasma rifles, stub pistols | Concrete preparation hook; includes charge/hip/aim/burst/automatic action routes using this class |
| `shoot_pellets` | ripperguns, shotguns, shotpistol/shield, pellet thumper | Concrete preparation hook; stock pellet spread and hit routine retained |
| `shoot_projectile` | grenadier gauntlet, missile launcher, projectile thumper | Concrete preparation hook; inspected configurations use `skip_aiming=true`, so spawn orientation/direction come from the prepared shot |
| `flamer_gas`, `flamer_gas_burst` | flamers, flame force staff | Concrete preparation plus damage-target and suppression pose hooks |
| `spawn_projectile` | force staffs | Existing explicit spawn/fire hooks retained; charged staff-tip and primary left-origin convergence unchanged |
| `spawn_projectile` | Zealot/Psyker knives | Explicit named-template right-hand spawn/launch policy; Psyker stock smart targeting and homing retained |
| `aim_projectile`, `throw_grenade` | generated grenades | Coupled action/preview/release hand pose for overhand/underhand; placement excluded |
| `chain_lightning` | lightning force staff | Existing target-module and damage hooks retained |
| `weapon_throw` | dual shivs special | Concrete spawn/launch hooks now provide right-hand pose for the audited straight-throw configuration; worn acceptance pending |

Other non-gun `spawn_projectile` abilities remain outside the explicit
staff/knife policy. Luggable throws/drops still need their separate handling
described below. The projectile class's alternate cached
aim-component path must be audited before supporting a future gun configuration
without `skip_aiming=true`. New families in the source snapshot are not assumed
to be available on this installed game/account.

All changes retain the existing local-player, valid-tracking and private-range
authoring gates. Mission-wide enablement is not introduced by this bug fix.

## Validation and remaining acceptance

Pinned LuaJIT source compilation: 27 chunks pass. `test-ranged-aim.lua` exercises
the concrete-class dispatch for all five classes (including the pellet override
and its stock counter reset), four repeated single shots,
two simultaneous groups, retained stock offset, hand-origin and converged-muzzle
paths, muzzle effects, flame queries, remote/untracked/non-private fallbacks,
nil return preservation, error restoration and alternating-barrel selection.
The existing melee/interaction aim regression also passes.

Commands:

```powershell
tools/stereo/test-darktide-lua-source.ps1
build/dependencies/luajit/src/luajit.exe tests/tooling/test-ranged-aim.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_aim.lua
build/dependencies/luajit/src/luajit.exe tests/tooling/test-melee-aim.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_aim.lua
```

Live initialization passed: the fresh game console confirms all five preparation
hooks and four flame query hooks. The harness reached nonzero `shared_ready`
and fresh eye pairs, with no reported pose mismatches. No matching mod-load error
was found. Local evidence is `artifacts/unattended/ranged-aim-live-20260906.log`
and `artifacts/diagnostics/dlss-live-20260906/ranged-initialization.txt`.

Pending: worn firing verification. Face ahead, point the hand to the side and check
actual hit location, muzzle/tracer direction and reticle for a hitscan gun,
shotgun, projectile launcher and both flamer modes. Include repeated and
simultaneous fire, ADS/hip fire, charge/release and force-staff regression. Do
not equate a successful Lua load or synthetic counters with physical aim
acceptance. No such acceptance has been claimed.

## Throwing follow-up — 6 September

Both dual-shiv variants use `ActionWeaponThrow`, a copied-method subclass of
`ActionSpawnProjectile`. The staff-only base policy did not author its pose.
The candidate directly hooks `_spawn_projectile_unit` and `_fire_projectile`
on the concrete class. It accepts only local, tracked, private-range actions
with kind `weapon_throw` and the `dual_shivs` keyword. Node-based origins and
target/position-tracking variants fall back to stock pending separate audits.

The stock throw retains its 0.2 s fire time, 0.5 s total action time, special
charge consumption, 65 launch speed, 0.2 m forward spawn offset, small authored
yaw/pitch offsets, gravity and 0.2 m projectile collision radius. The scoped
read proxy changes the reference pose; it does not implement physical throwing
or claim the ballistic path is identical to the straight aim reticle.

The expanded `ranged_aim` fixture covers copied throw-class dispatch, both
spawn/launch stages, nil returns, exactly-once stock calls, scope restoration
on error, and unsupported-owner/tracking/mode/configuration fallbacks. It is
now registered in CTest alongside `melee_aim`; both and the 30-chunk LuaJIT gate
pass. Staff-only base behavior remains unchanged.

Grenade/luggable routes need a coupled pass, not a camera-pose-only patch:

- `ActionAimProjectile.fixed_update` authors trajectory state from camera pose.
- `ActionThrowGrenade._spawn_projectile` combines a fresh camera-based direction
  with cached aim rotation/speed/momentum; release occurs after an authored delay.
- `AimProjectileEffects.update_unit_position` independently reads the first-person
  unit's root transform and recomputes its visual arc. It also applies a separate
  cosmetic arc-start offset. Updating only the action would leave the preview
  pointing elsewhere.
- `ActionThrowLuggable` consumes the cached aim state for throws and a different
  first-person physics helper for drops.
- Zealot knives use another `spawn_projectile` route with `zealot` rather than
  `grenade` keywords. Psyker homing knives require target-module ownership too.

The grenade and knife candidates below address their respective routes.
Luggables remain unmodified. Private-range acceptance does not
establish remote-server hand-pose transport for mission play.

Dual-shiv live initialization: both concrete hooks installed; `shared_ready=2162`
with 42.9 fresh pairs/s, zero interval fallback and zero pose mismatches. No
matching mod error was found. The weapon was not equipped or thrown unattended;
physical hand-aim acceptance remains pending.

## Coupled grenade candidate

`darktidevr_grenade_aim.lua` redirects the local action's read-only first-person
component during `ActionAimProjectile.fixed_update` and
`ActionThrowGrenade._spawn_projectile`. The shared right-hand target retains
existing tracking, authoring and private-range gates. Only `grenade` templates,
`aim_projectile`/`throw_grenade` kinds and `throw`/`underhand_throw` routes qualify.
Node-origin variants and mine placement retain stock behavior.

The independent arc root read occurs inside `AimProjectileEffects._update_trajectory`
(called from `update_unit_position`). During that synchronous call only, Unit
position/rotation accessors redirect the local first-person root node. Other
units/nodes delegate to the original functions, which are restored on both
return and error. The copied trajectory settings omit cosmetic start offsets
so the displayed arc begins on the simulated hand-based path. There is no
permanent world-transform hook and the original settings remain intact.

Stock collision sweeps, charge-speed/pitch curves, delayed release, ammo/ability
costs, grenade splitting and physics remain in charge. In particular, stock
release combines fresh direction with cached aim rotation/speed/momentum; this
patch changes its reference pose without redefining those timing semantics.
This is button-driven throwing, not a controller-velocity throwing system.

Validation: CTest `grenade_aim`, `ranged_aim`, `melee_aim` and
`lua_source_compile` pass (31 Lua chunks). The grenade fixture exercises local
pose ownership, unsupported-route fallbacks, nil returns, error restoration,
arc settings isolation, root-only redirection and nested scope restoration.
Worn checks still need grenade arc versus actual impact, close wall clearance,
overhand/underhand release and moving-hand release. No physical throw was
simulated unattended; successful hook initialization is not aim acceptance.

Live load: all three grenade hooks installed in the fresh console; the private
range reached `shared_ready=713`, 42.0 fresh pairs/s, zero interval fallback and
zero pose mismatches. No matching mod error was found. Local evidence:
`artifacts/unattended/grenade-aim-live-20260906.log`. The initial launch raced
process shutdown and correctly refused deployment while Darktide was still
visible; retry after exit performed the 31-chunk gate and sync successfully.

## Zealot and Psyker knife candidate

The two named templates `zealot_throwing_knives` and `psyker_throwing_knives`
use `ActionSpawnProjectile` directly. Its old force-staff-only pose policy left
their initial spawn and delayed launch head-relative. The candidate accepts
these exact template names and `spawn_projectile` actions without a node origin
or position-tracking module. Zealot remains non-homing; Psyker must retain the
audited `smart_target_targeting` target module and target tracking. Other Psyker
or Zealot abilities do not qualify merely through their class keyword.

Both launch stages now use the right-hand pose through the existing scoped
component proxy and local/tracked/private-range gates. Staff origin/convergence
behavior and its counters remain unchanged. Authored offsets, spread, projectile
speed/physics, charge consumption and release delays remain stock (Zealot fire
time 0.1 s; the inspected Psyker knife attacks 0.25 s).

Psyker target acquisition already flows through the hand-authored
`PlayerUnitSmartTargetingExtension.fixed_update`: `_targeting_parameters` reads
the scoped component before the stock precision query. `SmartTargetingActionModule`
consumes that extension's targeting data, retains the stock range validation,
sticky/soft-sticky behavior and previous-target preference, and stores
`target_unit_1`. Spawn/launch consume that target independently of the reference
pose. No replacement target-finder or homing algorithm was added.

The expanded `ranged_aim` fixture passes both knife templates/stages, exact-name
guards, owner/tracking/private-mode fallbacks, unsupported targeting/node/action
variants and pose restoration. Grenade, melee and the 31-chunk LuaJIT gate also
pass. Worn verification must include head-away free throws, primary and aimed
Psyker throws, target changes/sticky lock and force-staff regression. This source
audit and hook coverage do not establish physical or remote-mission acceptance.

Live knife candidate initialization passes: the existing concrete spawn/launch
hooks install without matching mod errors; `shared_ready=307`, 44.1 fresh pairs/s,
zero interval fallback and zero pose mismatches in the private range. Evidence:
`artifacts/unattended/knife-aim-live-20260906.log`. No knife was thrown unattended.
