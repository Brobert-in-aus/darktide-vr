# Ranged reticle and firing-input pass

9 September: preserve the accepted mixed deployment in the
[night handoff](handoffs/2026-09-08-night.md). The 7 September migration and trial
status below are historical. Current input verification also covers the saved
right-stick reload route across all 62 templates; see the
[ranged audit](RANGED-WEAPON-AUDIT.md). Broader worn weapon-family acceptance
remains open; this document is not an instruction to deploy accumulated main code.

Implemented offline on 7 September 2026 after the roomscale chase at `72831bd`.
The combined candidate is now deployed with fresh stereo and target transport
readiness. The user is testing staff/gun alignment; ranged visual acceptance is
pending. Remote mission admission remains disabled.

## Corrected mismatch

The former online-rules reticle queried a stock-origin ray but sent only its
distance to the XR harness. The harness reconstructed a point along the live
right-controller ray. That discarded the simulated origin and direction:
near-target parallax, weapon recoil/sway, and independent roomscale head motion
could all produce a different visible reticle from the actual firing line.

Gun preparation also applies weapon recoil and sway after the first-person
component's camera recoil. The old ray omitted those later stages. The new
read-only preview follows the stock order for hitscan, pellet and projectile
guns, including stock trajectory assist only when the stock gamepad/buff gates
admit it. Idle, ADS and reload use the equipped gun's route. Direct staff, flame
and lightning routes keep their first-person direction rather than inheriting
gun preparation. Random spread and pellet distribution remain stock; the
reticle depicts their centre, not a prediction of the next random sample.

The actual ray target now crosses the native bridge. Lua converts the world
point into the calibrated tracking-anchor basis, including character scale,
and supplies the associated head sequence, publisher and recenter identity.
The harness resolves that point through a bounded history of the sampled XR
origins. Later controller motion cannot replace the published direction.
Expired/missing/wrong-epoch references suppress the overlay. Failed publication
clears the older target. A new Lua file with an old capture DLL clears the
online target rather than displaying an incorrect reconstructed ray.

This changes shared gameplay-aim transport from **v3 to v4** and adds
`dtvr_set_gameplay_aim_target`. That migration required **Lua, capture DLL and XR
harness together** after Ready. The accepted current deployment already includes
its later reviewed updates; follow the night handoff for preservation. The
existing distance-only export remains available for
legacy local-pose and isolated synthetic fixtures. Native startup now reports
`DARKTIDEVR_ONLINE_RETICLE target_transport=ready` when the new export is present.

## Source coverage

The reproducible inventory finds **62 directly declared player ranged templates
across 23 families** in source snapshot `0f0cb45991e9305ef4a7b925370792d7d6035f95`.
Three grenade/ability templates and one drone generator are listed separately.
These are source entries, including possibly unavailable/future content, not
an owned-inventory or installed-game availability claim.

| Route | Direct player templates | Reticle centre |
| --- | ---: | --- |
| Hitscan: rifles, pistols, dual pistols, heavy stubbers, plasma and other listed gun families | 43 | First-person pose + weapon recoil + sway + eligible stock assist |
| Pellets: shotguns, rippers, shotpistol/shield, pellet thumper | 11 | Same gun preparation; stock pellet distribution retained |
| Projectiles: gauntlet, missile launcher, projectile thumper | 3 | Prepared initial direction; gravity/ballistic travel is not a straight-line impact guarantee |
| Flamer | 1 | Stock first-person damage/cone direction |
| Force staffs | 4 | Direct stock first-person direction; existing staff cosmetic convergence retained |

All explicit input names have binding channels. The optional input contract
loads all 62 actual literal input tables and runs **530 combat input elements**
through the actual stock parser with 256 transitions produced by the real VR
binding mapper. Both hold and toggle ADS modes pass. This proves element
admission, not complete action-hierarchy progression or ammunition/charge
availability. The existing concrete-class and broad stock contracts cover
preparation, hitscan dispatch, pellet batches, projectile launch, flame queries,
charge/timing, and stock send/receive/replay without introducing pose overrides.

## Validation

Windows x64 Release build passes. All 40 Lua chunks compile with pinned LuaJIT;
source invariants pass. The integrated offline suite passes **124/124** in 22.92
seconds with headset tests disabled. After adding the actual DLL target-export
roundtrip and publication-failure checks, a rebuilt candidate passes nine
affected CTests in 1.67 seconds (native capture, target/head transports,
reticle surfaces, gun routing, roomscale and Lua gates).

The target transport fixture checks numeric coordinate transformation, metadata
roundtrip, invalid samples, publisher/recenter/sequence rejection and clear.
The actual DLL export is called in an isolated transport namespace. Lua checks
world/basis/scale conversion, fixed-frame time delivery, owner admission,
gun/direct-route selection, recoil/sway/assist order and fallback. Actual stock
recoil/sway are additionally exercised across five camera/weapon recoil splits;
that optional fixture uses additive rotation math and does not establish full
engine quaternion or raycast behavior. The native coordinate fixture uses the
real C++ quaternion math.

Optional source checks (run from the repository root):

```powershell
$auditText = python tools/stereo/audit-ranged-templates.py _downloads/Darktide-Source-Code mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_bindings.lua
$audit = $auditText | ConvertFrom-Json
$audit.templates | Where-Object scope -eq player_ranged | ForEach-Object path | Set-Content artifacts/unattended/ranged-template-paths.txt
& build/dependencies/luajit/src/luajit.exe tests/tooling/test-ranged-inputs-stock-contract.lua _downloads/Darktide-Source-Code mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_bindings.lua artifacts/unattended/ranged-template-paths.txt
& build/dependencies/luajit/src/luajit.exe tests/tooling/test-online-reticle-stock-contract.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_online_reticle.lua _downloads/Darktide-Source-Code
```

## Remaining acceptance

7 September, 18:45 Brisbane: Lua `4ad2520` and matching native components stamped
`23345e5` are deployed after Ready passed. Fresh target transport readiness,
stereo and nonzero `shared_ready` are verified in Psykhanium. The staff regression
and roomscale worn check are with the user; ranged-family acceptance is pending.

Resume VD, run Ready, deploy the matching three components, then confirm fresh
stereo and nonzero `shared_ready`. Check the accepted staff first, followed by
an owned hitscan gun and shotgun: hand aim away from the head, single/repeated
shots, ADS, reload, near targets and physical head translation. Observe whether
the visible reticle follows the firing centre under recoil. Remaining families
need their actual owned/equippable variants tested. No purchase or loadout
change was made while the user was away.

Stock server/body origins remain authoritative. The staff's one-metre visual
convergence does not imply gun/grenade muzzle-origin collision, model/barrel
alignment or equivalent cosmetic particle treatment. Those visual checks,
native timing under real rendering, spread/assist feel, and actual firing and
damage across owned weapons remain unproven. Firing-only aim switching and
physical crouch detection remain deferred.

## Bounded firing evidence for the next session

The follow-up observer records the first four stock `_shoot` dispatches per
weapon/route/visit across hitscan, pellets, projectiles and both flame classes.
`DARKTIDEVR_RANGED_EVIDENCE` includes the actual template/action, origin,
direction, charge, server/client context, angle to the last valid reticle point,
and the stock `hit_minion` result when supplied. It also records the observed
third-person muzzle position and node-forward direction, using the just-fired
barrel for alternating muzzles. Node-forward is diagnostic geometry, not an
assertion that every asset's node axis equals its visual barrel axis.
Further dispatches increment
the `dtvr_ranged_evidence` summary without per-shot logging. A pellet dispatch
can be one batch of a shell; a flame dispatch does not prove every later cone
tick. Reticle-angle differences include spread and timing and are not an
automatic failure verdict. Missing logs alone do not identify why firing failed.

This observer changes no inputs, action fields, positions or results. Remote
owners and resimulation are excluded; new owners/visits reset the count.
Diagnostic errors are contained and emit at most one informational fallback,
avoiding repeated audible mod errors. The five-route observer fixture passes
stock-return/result preservation, angle measurements, output bounds, ownership,
replay and failure isolation. All 41 Lua chunks and source invariants pass.
This follow-up is included in the current deployment; the integrated 124-test
baseline above predates its new CTest registration.
Five affected CTests pass after the muzzle observation addition (2.52 seconds).
The matching native components were rebuilt at `23345e5`; their implementation
is unchanged by this Lua observation follow-up.
