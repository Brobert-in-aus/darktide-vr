# Two bodies on loading into the Psykhanium, 19 September 2026

Not worn acceptance. This is a fault read out of the last worn session's log,
fixed at the point the log names, with a test that fails on the fault and on
the fix's own reversal. The worn test is item 1 of
[test-checklist-2026-09-19.md](test-checklist-2026-09-19.md).

## What was reported

Two bodies on the player when loading into the Psykhanium, with the
"Full body (experimental)" option on. The 19 September checklist's item 1 had
already hidden the stock third-person model wholesale while the copy draws,
and the log confirms that part worked:

```
DARKTIDEVR_BODY one_body copy_draws_body=true
    hidden_slots=slot_gear_upperbody,slot_gear_head,slot_gear_extra_cosmetic,
                 slot_body_legs,slot_body_arms,slot_body_face,slot_grenade_ability,
                 slot_unarmed,slot_secondary,slot_gear_lowerbody
    visible_3p_units=2
```

So the second body was not the stock model.

## What the log names

`console-2026-09-18-23.10.40-e7a28687-….log`, the session that ran the
deployed `c99d9aa` Lua. The whole handover takes sixteen milliseconds:

```
23:13:07.453  DARKTIDEVR_IK visual_proxy=active   mode=upper_body
23:13:07.933  DARKTIDEVR_BODY_MIRROR spawn mode=overlay kept_slots=26 ignored_slots=28
23:13:07.948  DARKTIDEVR_IK hand_rig=body
23:13:07.957  DARKTIDEVR_IK visual_proxy=inactive mode=upper_body
23:13:07.964  DARKTIDEVR_IK visual_proxy=active   mode=upper_body
```

and the arm census, at the next weapon swap, lists the two spawned bodies at
the same wrist:

```
DARKTIDEVR_ARM_CENSUS wielded=slot_primary source=proxy_body  arms=4 meshes=1 wrist=0.077,5.855,2.020
DARKTIDEVR_ARM_CENSUS wielded=slot_primary source=mirror_copy arms=4 meshes=1 wrist=0.077,5.855,2.020
```

`proxy_body` is `darktidevr_body_proxy`'s own unit -- the profile named
`DarktideVRUpperBody`, spawned with `slot_body_arms`, `slot_body_torso`,
`slot_gear_upperbody` and `slot_gear_extra_cosmetic` retained. `mirror_copy` is
the body overlay's full-profile copy. The same two lines, with the same
sequence of `visual_proxy` flips, are in the 22:27 log from the session before.

## Why

Three body systems are layered in this build, and the layering is the fault:

| system | turned on by | what it spawns |
|--------|--------------|----------------|
| gloves (default) | nothing | two rigid glove units |
| headless third person | dev flag `darktidevr_full_body_experimental` | the proxy's upper-body profile, solved by the full-body IK path in the main file |
| body overlay | option `vr_full_body_experimental` | a full-profile copy, which takes the hand rig |

The deploy for the checklist writes the dev flag `enabled` ("item 1 lives
behind it"), so the proxy is in upper-body mode (`hands_only=false`) while the
overlay runs. `BodyProxy.update` had two branches that knew about the hand rig
and both were gated on `hands_only`:

```lua
if hands_only and hand_rig and not Unit.alive(hand_rig) then ... end
if hands_only and hand_rig then  -- pose only, no units
```

When the copy called `set_hand_rig`, the proxy's `safe_destroy` cleared
`state.world`. The upper-body branch, which never looked at `hand_rig`, then
read `state.world ~= world` as "nothing spawned yet" and spawned the
torso-and-arms profile again on the next frame. The copy's hands were the
hands (the source avatar's arms were hidden on the rig's account, the 18
September fix) and a second torso-and-arms body stood inside the copy.

## The fix

**`darktidevr_body_proxy.lua`.** The rig is checked before the caller's mode,
which is the same rule `hides_source_slot` was given on 18 September: a body
that owns the rig is the body, in either mode, and the proxy spawns nothing of
its own while it lives. When the rig's unit dies the proxy falls back to
whatever the mode asks for -- gloves, or the upper body under the flag. A new
`BodyProxy.hand_rig_active()` says whether a rig owns the hands.

**`darktidevr.lua`, `apply_body_ik`.** With no proxy body the proxy hands back
the gameplay avatar as the unit to solve, and the full-body path would then
have run on the avatar itself: `apply_calibrated_body_height` scales the root
of the unit it is given. Under a rig the IK takes the tracked-hands path, flag
or no flag. That path is what records the wrist poses the copy solves its own
arms to, so nothing the copy needs is lost. The `visual_proxy=` log line says
`body_rig` in this state; before, it said `upper_body` whether or not the
proxy had a body, which is why the two spawns read as one.

**`darktidevr_body_mirror.lua`.** A copy whose scene graph does not match the
avatar's is hidden and never posed. It no longer takes the hand rig on the way
to being hidden: had it done so, the gloves would have been destroyed, the
source arms hidden on the rig's account, and the player left with a floating
weapon and no hands. This is the same ownership rule from the copy's side; it
is not tested by a harness (the module's `install` path has none) and is
flagged here for that reason.

Not changed: the hub, where the overlay never runs and the flag's headless
presentation stands as before; the stock model's wholesale hiding from item 1;
the weapon staying on the stock unit.

## Validation

```
build/dependencies/luajit/src/luajit.exe tests/tooling/test-body-hand-rig.lua \
    mods/darktidevr/scripts/mods/darktidevr/darktidevr_body_proxy.lua \
    mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua
build/dependencies/luajit/src/luajit.exe tests/tooling/test-rigid-hand-readiness.lua ... (same two)
build/dependencies/luajit/src/luajit.exe tests/tooling/test-body-mirror.lua \
    mods/darktidevr/scripts/mods/darktidevr/darktidevr_body_mirror.lua
ctest --test-dir build/windows-vs2022 -C Release
```

`test-body-hand-rig.lua` now runs the proxy in upper-body mode under a rig and
asserts no spawn, then slices the real `apply_body_ik` out of the main file
and asserts the tracked-hands path with the flag on and off, then kills the
rig and asserts the upper-body fallback spawns and the full-body path comes
back. Both guards were mutated before being believed:

| mutation | caught by |
|----------|-----------|
| the proxy's two branches gated on `hands_only` again (lines 607 and 627) | `test-body-hand-rig.lua:214: upper-body mode under a rig did not hand back the source unit` |
| the IK gate without `or body_rig` | `test-body-hand-rig.lua:241: the full-body path ran under a rig` |
| control, unmutated | passes |

A first cut of the first mutation also rewrote an unrelated `if hand_rig then`
at line 478 and tripped an earlier assertion; the harness above is the
line-limited one.

The full tooling suite: 281 of 282 passed. The one failure, `online_reticle`,
is not this change's: another session was editing the reticle's zoom
correction and its test in the same working tree while this was written
(`zoom_corrected_aim_point` calling a `zoom_aim_correction_enabled` that does
not exist yet), and the same test passes against `c99d9aa`'s main file. This
commit carries none of that work: the main file's index entry was built from
`c99d9aa` plus the two hunks named above.

## Limits

- Read out of a log and reproduced in a harness with stand-in units; not worn.
- The mirror-side change (no rig on a layout mismatch) has no harness.
- Whether the copy needs the dev flag at all is a separate question. With the
  flag off the tracked-arms visibility branch already hides every stock slot
  but the arms (hidden under a rig) and the weapon, so the overlay may stand
  alone on the option; that has not been run.
