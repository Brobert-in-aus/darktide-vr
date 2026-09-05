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
| `chain_lightning` | lightning force staff | Existing target-module and damage hooks retained |
| `weapon_throw` | dual shivs special | Separate copied `ActionSpawnProjectile` subclass; not covered by the gun fix, requires its own origin/targeting audit |

Non-gun `spawn_projectile` grenade abilities remain outside the staff-only
projectile target policy. `aim_projectile` generated grenade/luggable trajectories
remain a separate throwing-input task. The projectile class's alternate cached
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
