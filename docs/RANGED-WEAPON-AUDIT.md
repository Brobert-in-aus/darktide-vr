# Ranged weapon aim audit

## 9 September: preserve acceptance and check saved input routes

The [8 September night handoff](handoffs/2026-09-08-night.md) owns the accepted
mixed installation and tested reticle/feedback/stabilization changes. The dated
candidate and deployment wording below is historical; do not rebuild or deploy
main native sources to repeat it. Full weapon-family and mission acceptance
remain open in the [active todo](phase1/todo-2026-09-09.md).

The stock input fixture now resolves representative primary/alternate/special/
reload controls from an optional saved-binding table, including stick sectors.
Current saved settings still match the 43-key reviewed snapshot. Both main and
focused `848b78d` mappers pass all 62 template tables and 530 combat input elements
with hold/toggle ADS and 256 real mapper transitions, using right-stick-down
reload. All 14 duration-based elements now require valid input at interval start
as well as deadline completion; deadline-only stock evaluation could otherwise
pass without the input held. This assumes the sampled state stays held between
those observations and does not simulate a full input sequence. Both mappers
also retain the default-profile pass. A supplied unbound reload is
rejected instead of silently using default X. Settings and installed files were
not changed. These are element-admission checks, not full action hierarchy,
ammo/charge progression, every alias or live firing acceptance.

Receipts: `artifacts/unattended/ranged-input-{main,focused}-{default,saved}-timed-20260909.log`
and `ranged-saved-bindings-recheck-20260909.json` in the same directory.

## Historical 7 September: online-rules pass while VD is closed

The [ranged reticle candidate](RANGED-ONLINE-RETICLE.md) fixes two newly confirmed
online mismatches: missing gun recoil/sway in the reticle ray and distance-only
native transport that rebuilt that ray from the controller. It now transports
the actual target with its sampled tracking reference. The source inventory
covers 62 player ranged templates in 23 families; 530 actual stock combat input
elements accept real VR binding transitions. Release build, 40-chunk Lua gate
and 124/124 offline CTests pass. Matching Lua/DLL/harness deployment and worn
firing across owned guns remain pending. Older local-pose findings below are
historical and do not establish acceptance of this new candidate.

## 7 September cached catalogue scope

Read-only inspection of the game's local HTTP cache found general catalogue
version 135417, but no owned-inventory response. Thirty non-empty ranged weapon
templates carry the `psyker` archetype tag; all thirty have matching files in
source snapshot `0f0cb45991e9305ef4a7b925370792d7d6035f95`. Direct lexical action
kinds divide them into 22 hitscan, four pellet and four staff templates. Fourteen
additional ranged-tagged catalogue entries have an empty template and are not
counted as independent firing routes. Catalogue tags/feature flags do not prove
current availability or ownership. The user's purchased gun models remain unknown.

The optional online-rules fixture now covers stock pellet shooting/count/state
progression and special-shell selection after shot preparation. Constructed
4/4/1 and 2/2/1 batches preserve grouped aim and final-batch processing; engine
spread, ray hits and damage remain substitutes. See PSYKHANIUM-ONLINE-RULES.
Derived local evidence is `artifacts/unattended/psyker-cached-catalogue-20260907.json`;
the full cache and any connection/account data remain outside Git.

Actual hitscan dispatch is also exercised after that prepared pose across local
and remote units on client and server. Twenty constructed cases cover the
default ray and combined ray/sphere routes, mixed hit distance representations,
empty results, power precedence, charge thresholds, shot/proc metadata, optional
chain dispatch and line-effect endpoints. Collision, damage and rotation math
remain substitutes; catalogue coverage is not live weapon acceptance.

## Earlier findings

6 September 2026. Active work after the documented DLSS output-association
blocker. User reports every ranged weapon except the force staff firing away
from hand aim. Source coverage is not live acceptance of every weapon.

Subsequent worn testing rejects the non-staff candidate: reticle and gun are
misaligned, a duplicate HUD crosshair appears despite Custom HUD hiding it,
and shots only sometimes damage an enemy with the muzzle pushed into them.
Investigate actual firing origins/directions and collision exclusions before
expanding coverage. Gun self-collision is unconfirmed. The crosshair visibility
regression also needs its own renderer/Custom HUD routing check.

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
staff/knife policy. The 7 September luggable candidate below couples its aim
cache and preview while preserving stock drops. The projectile class's alternate cached
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
The luggable candidate added on 7 September is described below. Private-range acceptance does not
establish remote-server hand-pose transport for mission play.

## Luggable trajectory candidate: 7 September

The three audited templates `luggable`, `luggable_light` and `luggable_mission`
now admit the shared hand-pose scope for their `aim_projectile` / `throw` action
only, requiring the `luggable` keyword. The existing local-player, tracking and
context/authority checks still own the target. Unknown templates, alternate
routes, node origins and drops are excluded.

`ActionAimProjectile.fixed_update` writes the hand-based pose into the stock
aim cache using stock collision checks, radius, speed curves and momentum.
`AimLuggableEffects` has its own copied `_update_trajectory` method: load it and
`AimProjectileEffects` before hooking both concrete classes. Its inherited
preview then reads the same hand reference with cosmetic start offsets removed.
The luggable's own trajectory-settings method retains the existing item's
locomotion template, mass and radius.

`ActionThrowLuggable` already consumes that complete cached pose; it needs no
release hook. Preserve its authored delay (0.32 s for the ordinary/light
templates), once-only physics transition and server authority. Later hand
movement during the delay does not redefine the game's cached release.
Drops intentionally retain `Luggable.enable_physics`, including its near-feet
radius-based placement and owner-velocity contribution. No controller-velocity
throwing or physical carry-model change is implemented.

Validation: pinned LuaJIT 34 chunks and focused `grenade_aim`, `ranged_aim`,
`gameplay_context`, `lua_source_invariants` CTests pass. The shared fixture covers
all three templates, concrete preview dispatch and unsupported/remote/tracking
fallbacks. An additional optional test executes the actual local source-snapshot
aim and throw methods with engine stubs:

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-luggable-stock-contract.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_grenade_aim.lua _downloads/Darktide-Source-Code
# PASS: stock aim/collision parameters, cached delayed release, once-only/server
# physics, equipment transition and untouched drop component references
```

The optional check requires the source snapshot and is not a CTest dependency.
Evidence: `artifacts/unattended/luggable-stock-contract-20260907.log`.
No deployment, real throw or worn/mission acceptance. Later live checks must
cover preview/origin alignment, obstacles, moving-hand release, cancel/drop,
objective sockets and the carried model; SoloPlay remains the later test stage.

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

## Test equipment follow-up: 6 September

The user purchased ranged guns on the Psyker. They can be equipped through the
Operative menu for reticle/weapon alignment, muzzle origin and real impact tests.
Inspect the available models before claiming weapon-family coverage; no exact
models were specified. Use this character for the next gun validation pass and
retain force staff as a regression control. See MISSION-READINESS.md for the
separate mission-mode/authority requirements beyond private-range success.

## Reticle cache ownership: 7 September

The convergence cache previously accepted any sequence difference at most 60,
including a negative age after a publisher restart. A cached world point now
requires age 0–60, the same controller generation, the same game-session object
and the current live local player unit. Invalid identity clears the cache and
uses the existing hand-ray fallback. Valid convergence math and the age window
remain unchanged. Online-rules combat continues to use stock simulation origins.

The hand-origin HUD tag path now uses the same checked cache getter instead of
reading target fields directly. A missing observation, ray error, unavailable
hand aim or missing online simulation component clears cached points/targets
and retained owner references. Online stock forced-targeting remains unchanged.

The actual publication/convergence fixture reproduces the negative-age fault
and passes age boundaries, publisher restart that has advanced beyond the old
sequence, player/session replacement, dead owner and missing/failed observations.
Concrete targeting-hook and HUD fixtures check cache invalidation and empty-tag
fallback. Six focused CTests pass, including all 36 LuaJIT chunks. No deployment,
live transition or worn convergence acceptance; full 110/110 baseline is `aadf4f3`.

## Stock scheduler and ammo gates: 7 September

The optional scheduler contract executes inspected `ActionShoot.fixed_update`,
`_next_fire_state`, ammo admission/spending helpers, attack-speed scaling and
`FixedFrame` rounding. It covers 135 combinations: 30/60/90 Hz, three attack-speed
factors and 15 supplied scenarios. Single and repeated fire, shot limits, empty
and insufficient magazines, reload/free-transfer returns, permitted partial
shots, free-ammo and critical-only keywords, double cost, half/full charge and
resimulation all pass. Preparation observations change pose on each shot, and
the stock scheduler forwards that shot's supplied pose and clears prior results.
Twelve further actual-stock pellet-scheduler cases cover 30/60/90 Hz, normal
versus special shells and resimulation: batches retain the shell's prepared pose
and consume one ammo cost only after the final batch. Engine pellet dispatch
and damage remain substituted.

```powershell
& build/dependencies/luajit/src/luajit.exe tests/tooling/test-ranged-scheduler-stock-contract.lua _downloads/Darktide-Source-Code
```

An admitted trigger alone cannot establish that a gun will fire: stock ammo
gates can return a reload request or enter the completed-shot state without
dispatch. Auto-fire timing is rounded to fixed frames after attack-speed buffs;
later shots go through preparation again. Resimulation advances the shot state
and ammo spending while omitting effect/damage dispatch. Existing stock rules
retain ownership of these behaviors; this check changes no runtime code.

The fixture uses supplied action settings, one abstract ammo pool and substituted
preparation, shot dispatch and secondary effects. It does not execute the full
action hierarchy, engine pellet dispatch, real aim/spread, engine damage or installed
weapon templates. It is additional scheduler evidence, not acceptance of 135
weapons, all ranged families, wire behavior or headset firing. The current user
check remains staff shots/reticle while leaning, followed by an owned gun.

During that live check, the bounded observer records four stock hitscan
dispatches each for `stubrevolver_p1_m1` (08:56:41 UTC onward) and `lasgun_p3_m2`
(08:57:21 UTC onward). This identifies two actually used owned templates and
confirms dispatch on their hip-fire route. Recorded rows report no minion hit;
they do not establish damage or visual alignment. Await the user's observations.
The current console starts at 08:50:52 UTC; no mod WARNING/ERROR was found in the
checked log. Source-based family coverage is still separate from this evidence.
The user confirms staff shots/reticle are good, but the lasgun visibly fires
from barrel back toward the face, fails to hit enemies in their test, and its
reticle appears about 45 degrees above-left of the expected barrel direction.
This is a failed gun visual/aim/hit check despite stock dispatch. Trace the
actual hit endpoint, local-body collisions and barrel transform next.

The next diagnostic session (console beginning 09:06:35 UTC) confirms the cause:
lasgun hits end at the exact firing origin, with zero-distance collisions on the
VR left/body and right-hand profile copies. Stock skips the real attacker unit;
it treats these separate, non-damageable copied character actors as blockers.
The user completed the requested shots and observed no change, as expected for
an observation-only build.

The correction disables collision and scene-query participation on actors of
the locally spawned visual profile roots when they become ready. A guard rejects
the gameplay source body; stock ray filters, hit processing and damage are not
modified. The fixture verifies both collision flags and no repeated cleanup on
a stable ready hand. The hit diagnostic remains to verify that these objects
disappear from the real shot's collision list after deployment.

A separate visual alignment module resolves the equipped gun's third-person
muzzle and rotates only the hidden weapon-attachment node so that muzzle
orientation follows dominant controller aim. It preserves attachment translation
and the accepted anatomical hand pose. It restores its last rotation before the
next solve, respects intervening animation writes, and releases ownership for
staff, reload/melee/wield actions, missing tracking and inactive contexts. The
current right-handed presentation is required; other handedness remains open.
This does not alter first-person simulation aim or randomized firing spread.

Nine focused CTests pass in 1.18 seconds, including 43 Lua chunks/invariants,
collision/readiness, equipment-hand synchronization and the new 120-pose
multi-axis alignment fixture. The normal configured count is now 126; no full
126-test run is claimed. Native components remain unchanged. Deployment and
worn enemy-hit/barrel/reticle checks are the next boundary.
The first correction launch exposed nil actor slots in the copied character.
`9b5981b` skips them like stock pickup/deployable loops. Four affected tests pass
in 0.88 seconds, including a sparse-list cleanup regression. The corrected
session reports 24 actor disables in 44 slots on each of the two tracked-hand
roots, successful hand readiness and a 0.0000-degree lasgun muzzle post-angle.
Actual hit endpoints now reach distant scenery (62–82 m); owned visual roots
are absent from those collision lists. Fresh stereo is verified with nonzero
shared readiness. The user's enemy damage and barrel/reticle observation is
still pending; these measurements alone do not establish worn acceptance.

The user subsequently confirms gun/reticle agreement but rejects their shared
misalignment with the hand. The next candidate removes attachment rotation and
derives firearm aim from the resting held muzzle basis relative to the live
controller grip. It caches that basis across recoil animation, preserves staff
native aim and changes no firing origin. Nine affected CTests pass (1.32 s),
including a 120-pose gun-aim fixture and all 43 Lua chunks. Deployment and worn
hand seating/reticle/enemy-hit checks remain pending. See the latest handoff;
the prior visual-rotation approach above is historical and superseded.

The user rejects the held-muzzle basis too and specifies controller alignment,
not hand-model alignment. `859b460` restores direct native controller simulation
aim and places the visual gun attachment at controller grip position, with its
muzzle rotated to controller aim. This differs from the first visual correction,
which retained the hand-model attachment position. Nine affected tests pass in
1.27 seconds, including 120 translated/rotated/scaled parent cases and the real
aim reader. Deployed after wireless ADB recovery and Ready; worn acceptance pending.
