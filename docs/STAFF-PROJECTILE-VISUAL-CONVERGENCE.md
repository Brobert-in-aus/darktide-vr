# Staff projectile visual convergence

7 September 2026. Implements the user's choice of a hand/staff visual origin
that rapidly converges onto the real projectile, over approximately one metre.

The current candidate covers the stock `force_staff_ball` and
`force_staff_ball_heavy` particle projectiles used by the tested
`forcestaff_p4_m1`. Primary fire uses the support casting hand. Charged fire uses
the staff tip, with a fresh dominant-hand fallback when the tip is unavailable.
It is admitted for the local player's existing Psykhanium online-rules mode.
Other projectile types, hitscan tracers, beams and remote mission admission are
not implemented by this change.

The release hook records the cosmetic origin and actual launch position after
stock launch. This runs through the existing controller-aim hook; DMF replaces
duplicate hooks from the same mod, so a separate second firing hook is invalid.
The regression now executes the real existing hook and rejects duplicates.
The stock projectile FX creates its normal particle at an offset
position. For the first metre of projectile travel, the visual position is:

```text
visual = real position + initial hand-to-launch offset * (1 - smoothstep(distance / 1m))
```

The hand position is captured once, so moving the hand after firing cannot drag
the projectile. Distance includes travel before the first effect update, then
accumulates rendered projectile movement. Effects first appearing beyond one
metre stay stock rather than jumping backward. Implausible offsets over three
metres or unavailable tracking also leave the ordinary effect intact.

Only the spawn particle is temporarily unlinked and moved. At one metre it
rejoins the original unit/node/pose with stock orphan cleanup. Impact or stick
events restore that link immediately before stock processing. Mode/owner loss
also ends the offset. Destruction during the free-particle interval explicitly
cleans the particle; stock stop and exception paths retain their ownership.
Stock charge variables, particle groups, sounds and effect IDs are preserved.

There are no writes to projectile unit transforms, physics, first-person
components, damage or network messages. Real near-cover impacts may therefore
occur before the visual path has converged. At the staff's nominal 60 m/s,
one metre is only about 17 ms; worn observation must determine whether the
transition is visible and comfortable. Particle-engine trail behavior is not
established by the isolated test.

Validation on Windows x64:

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-projectile-visual-stock-contract.lua mods/darktidevr/scripts/mods/darktidevr/darktidevr_projectile_visual.lua _downloads/Darktide-Source-Code
tools/stereo/test-darktide-lua-source.ps1
tools/stereo/test-darktide-lua-invariants.ps1
```

PASS: actual stock FX with isolated engine math/particles, hand/staff origins,
frozen release sample, one-metre handoff, unchanged simulation input, stock
charge/group preservation, impact alignment, destroy/stop cleanup, foreign and
retired owner handling, disabled mode, late rendering, stale/implausible tracking,
engine-move fallback and exception scope restoration. All 38 Lua chunks compile;
source invariants pass. No new CTest registration; configured count remains 122.

Live deployment and worn acceptance are recorded in the current handoff.
