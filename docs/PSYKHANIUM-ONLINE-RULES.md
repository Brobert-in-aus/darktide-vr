# Psykhanium online-rules proving mode

7 September 2026. Requested by the user after the dedicated-server audit.
Implemented as an offline candidate; not deployed or worn-accepted. Actual
online missions remain gated.

## Behavior

**Online combat rules in Psykhanium** defaults on in mod settings. It is latched
for the current range session and changes on the next visit. It applies only
to `shooting_range` with local server authority; it does not change tutorial
training grounds, the hub, unknown modes or remote mission admission.

The right hand supplies stock simulation aim angles. The existing controller
adapter first merges ordinary controls, then the new module finalizes the same
fixed-frame input cache that stock simulation and the network sender read.
Subsequent frames do not rewrite earlier samples. No custom RPC is introduced.
Stock pitch limits and zero roll are retained; HMD view/orientation is not
replaced with hand aim.
The adapter observes `HumanGameplay._player_orientation_class` and only authors
free/default aim. Forced look, weapon locks (including chainsaw-style attacks),
sticky melee, ledge hangs, camera-owning wheels and death retain the actual
stock-selected orientation even when the character still reports walking.

The mode declines the common action-pose overrides, including weapon origins,
staff/throw convergence, button-melee reference proxies, left-hand block proxies
and local aim-field writes. Stock actions instead read their normal first-person
component, reconstructed from the chosen input angles and body/character height.
Weapon spread, recoil, charge, sweep shapes, damage windows, cleave and damage
calculation remain stock. The reticle ray uses that simulated origin/direction.
The visible tracked weapon can therefore diverge from the firing ray near cover;
this candidate does not promise muzzle-origin collision agreement.

There is one chosen simulation direction, currently the dominant/right hand.
Block eligibility and block cost therefore use that direction too; the visible
support hand does not independently orient a shield in this mode. Selecting a
different hand for a blocking action is a possible later policy, but two
independent simultaneous authoritative directions are not present in the audited
input stream. The proving mode deliberately retains the single-direction rule.
The stock blocking flag alone is not a safe hand selector: `ActionBlock.finish`
deliberately retains it into some push, sweep and shooting transitions. A later
selection policy must handle those attacks and their first cached frame.

Grenade and audited luggable previews also use the simulated first-person pose.
The stock trajectory renderer otherwise reads the visual root, which continues
following the head and can differ from simulation aim. The preview-only scope
redirects that local root during trajectory calculation and removes cosmetic
weapon-origin offsets. It does not proxy the action component or change throw
physics. Foreign, stale and retiring first-person owners cannot supply a pose;
native accessors are restored after success or error. This mismatch was reproduced
in the scoped fixture before the fix.

Smart-tag marker selection follows the stock simulated targeting result in this
mode. Previously, disabling hand-origin proxies restored a screen-centre marker
scan, allowing an unrelated marker under the head view to win over the aimed
unit. The HUD now resolves and validates the marker belonging to the actual
stock target. Stock forced target refresh and its position result remain intact.
The exception is admitted only for the live local player in active VR simulation;
unknown/remote/retiring authority and inactive presentation retain stock behavior.
The actual-hook regression reproduces the old wrong marker and passes with the fix.

Controller and keyboard movement already combined in the head basis is
transformed into the transmitted hand-aim basis, then passed through stock
movement packing before simulation. Stock acceleration, backward speed scaling,
sliding, collision and recoil-related effects remain. The isolated stock-method
test confirms a concrete consequence: looking/aiming behind while walking in
the head's forward direction retains the server's backward-movement penalty.
The mode does not implement a local speed compensation that the server lacks.
Slide entry also requires sufficient velocity along the simulated aim direction.
With forward world velocity, aiming sideways or backward can prevent entry;
once sliding, stock friction continues along existing world velocity. This is a
confirmed stock-rule consequence, not a new controller-direction correction.
Rotated diagonal inputs now use one shared saturation scale, preserving their
world direction instead of clipping axes independently. This was a reproduced
adapter bug; the regression check failed before the fix and passes afterward.
The stock walking integration also checks four input vectors at twelve headings.
These are settled-input checks. Stock smoothing retains previous local axes, so
rapid hand-aim changes while moving still need transient steering/comfort checks.

An isolated abrupt-turn probe confirmed this distinction. With stock acceleration
19/deceleration 6, a hypothetical 60 Hz update, settled forward input and an
instantaneous 90-degree hand-aim change, the requested movement heading settled
after four updates. Its error was approximately 65.1 degrees at 16.7 ms,
30.1 at 33.3 ms, 3.0 at 50 ms and zero at 66.7 ms. These are the stock method's
**desired movement** outputs, not measured body displacement, collision results
or a worn observation. Ordinary gradual hand movement was not characterized by
that abrupt-step probe. Input conversion cannot promise to eliminate stock
stateful acceleration by rotating only the incoming axes. Evidence remains
ignored in `artifacts/unattended/online-movement-transient-20260907.log`.

Room-scale translation is not injected as extra mover velocity. Existing visual
head/hand/body presentation remains within its current tracking envelope.
Menus, unavailable tracking, foreign handlers and non-playing/forced states
retain stock input. Scanner/minigame axes bypass the hand-aim conversion.
Malformed samples or packing failures leave the original input columns together
and emit a bounded diagnostic. The original local-range behavior is available
by switching the option off before entering the range.

## What the range does not reproduce

Traversal has an additional stock-aim constraint. First-person fixed update
passes the recorded aim, before recoil, into ledge discovery. Its forward sweep
therefore follows the dominant hand in this mode even when movement remains
head-relative. Vault admission then checks movement against the discovered
ledge, with stock height/distance limits and the carried-object restriction.
A ledge in front of the headset can be missed while the hand points elsewhere.
Changing only the client's discovery direction would not establish agreement
with an unmodified server. This needs a deliberate traversal aim policy and a
later live test; no traversal behavior was changed here.

The optional stock-rules fixture now executes the actual first-person-to-ledge
call, discovery entry method and vault admission. Three horizontal aim headings
and grounded/airborne offsets retain stock search direction, collision filters,
obstacle flags and recorded data during replay. Supplied ledges exercise reverse
priority, height/distance boundaries, air limits, movement and luggable gates.
Collision hits, ring indices and yaw-only engine math are substitutes; real
geometry, pitched traversal, climbing and correction convergence remain open.

This is a combat/input compatibility proving mode, not a simulated dedicated
server. It does not add latency, packet loss, remote prediction correction,
matchmaking, remote teammates or mission transitions. Those need later tests.

Stock Psykhanium still uses training scaffolding. The inspected
`shooting_range_scenarios.lua` includes `make_player_invulnerable`;
`shooting_range_steps.lua` sets player invulnerability, adds an unperceivable
scenario buff and replenishes pickup stations. The mode settings disable
minion perception. These remain explicit limitations for incoming damage,
enemy behavior and resource-exhaustion acceptance. No mission-equivalent
survivability or AI behavior is claimed.

Outgoing-rule follow-up: the inspected shooting-range init/loops add the
unperceivable buff, whose template only supplies that keyword. They do not add
the tutorial's `tg_player_nerfed_damage` (-0.95 damage stat), shortened ability
cooldown or no-overcharge buffs. Shooting-range settings also omit
`force_base_talents`; the shared mode class only selects base talents when that
flag is set. This is source-scenario evidence, not an inventory of every live
buff or other mod. Pickup stations still allow repeated ammo and stimulant use.

Difficulty must match the intended mission comparison. Stock range Options maps
the chosen danger level to `mechanism_context.challenge_level`; the difficulty
manager uses challenge for minion health and other tables. The two literal 2s
in the target spawn call are dissolve duration and enemy side, not difficulty.
The first successful online-rules input record now includes `challenge` and
`resistance` read from the live difficulty manager. Missing, invalid or retiring
managers report `unknown` independently per field without disrupting input.
This records the setting; it does not change difficulty or claim Havoc/modifier
parity. Three focused checks and the LuaJIT gate pass.

Incoming-combat follow-up audit: changing only the perception mode flag is not
sufficient. Minion construction reads that flag, while the range's
`sr_unperceivable_loop` continually re-adds the player's unperceivable buff.
The range also explicitly sets invulnerability at initialization. A future
combat option must handle all three owners, preserve return/re-entry behavior,
and establish a usable recovery path after downing/death. The stock target loop
spawns enemies with an aggroed state; enabling everything together is not a
controlled single-enemy test. The user has been asked whether incoming combat
belongs in this proving mode; no training-aid changes were made during the audit.

Always-active physical-contact melee with unlimited cleave remains separate
local-authority research; it is not a compatible replacement for stock online
melee. This mode uses normal attack inputs and server-style weapon sweeps.

## Validation and next live checks

Pinned LuaJIT compiles 35 mod chunks. The new portable policy test exercises
the real cache adapter: range/session admission, hand angles, pitch limits,
movement conversion/packing, UI/tracking/owner/state exclusions, unchanged prior
frames and all-or-nothing fallback after a packing error. Ranged-hook tests
check stock origins/preparation and reticle pose in this mode, including the
unchanged remote-unit path.

Full Windows x64 offline suite: **105/105 pass**, with headset tests disabled
at configuration. Evidence: `artifacts/unattended/online-rules-ctest-20260907.log`
and the matching configuration log. No native implementation changed in this
checkpoint; the prior Release build is used by the suite.

Two optional checks execute methods from the inspected game source snapshot:

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-online-input-stock-contract.lua _downloads/Darktide-Source-Code
build/dependencies/luajit/src/luajit.exe tests/tooling/test-online-input-stock-contract.lua _downloads/Darktide-Source-Code mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_online_rules.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_gameplay_context.lua
build/dependencies/luajit/src/luajit.exe tests/tooling/test-online-rules-stock-contract.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_online_rules.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_gameplay_context.lua _downloads/Darktide-Source-Code
```

Both fixtures pass. The first covers stock buffering/send/receive/history behavior.
Its optional adapter arguments pass the actual VR cache authoring through those
methods and both actual `HumanUnitInput` readers. All eight representative
columns (attack, four movement axes and three angles) retain their paired frame
through resend, old/duplicate packets, ring wrap and a send-window gap. Mixed
UI-owned and unavailable-tracking frames retain stock inputs; changing live aim
before replay does not resample it. This is an in-memory transport fixture with
a range-authority stub, not production remote admission or an engine correction
test. Engine packing remains substituted.
The
second applies the actual VR adapter before stock first-person and walking
methods, verifying body-height origin, stock recoil, intended movement direction
and backward penalty. It also executes the actual stock orientation selector
across forced look, both weapon-lock forms, force-look weapons, melee stickiness,
ledge hangs, communication/emote wheels and death. Engine math and transport are isolated substitutes, so
these do not establish executable wire precision or live server acceptance.
The actual stock local `_update_rotation` and camera-root orientation methods
also pass with distinct head/hand angles: local rendering reads the original
view owner while the fixed combat component keeps hand aim.

The stock-source check also executes actual `ActionShoot._prepare_shooting`
against that simulated pose. It verifies the body origin, returned charge level,
recoil/sway/optional assist/spread sequence and retained sample for the second
simultaneous bullet. Engine-dependent weapon operations are tagged substitutes:
their order and data ownership are tested, not spread distributions or live
damage. Changing the component rotation between grouped bullets does not replace
the already prepared shot sample.

Actual `ActionShootPellets._shoot`, pellet-count progression, next-fire-state
and normal/special-shell selection also execute after preparation. Constructed
nine-pellet (4/4/1) and five-pellet (2/2/1) batches retain the prepared reference,
each shell's spread/range fields, indexed pellet order, rewind/filter arguments
and final-batch processing/proc metadata. Special state clears at stock shot
completion; missing special shells fall back to the normal shell. Spread math,
ray hits, damage processing and effect endpoints are supplied. These are
orchestration checks, not actual shotgun distributions, pellet damage or loadout
acceptance. The optional stock-rules fixture passes without production changes.

Projectile firing coverage now runs actual `ActionShootProjectile._shoot` and
both stock spawn-parameter readers after that preparation. Eight combinations
of client/server, immediate/cached aim and explicit/default locomotion retain
the prepared origin/direction, projectile/weapon metadata, critical state,
owner side and server-only spawning. The cached branch takes rotation, speed
and momentum from the aim component while retaining fresh origin/direction.
Optional buff-proc metadata is preserved; a missing proc table does not block
spawning. Trajectory math, proc handling and the network spawner are substituted.
This does not prove projectile clearance, impact damage, current loadout coverage
or correct aim-component production for a new template using the cached branch.

The same optional fixture now executes actual `ActionSweep` reset, sweep update,
damage-window and abort-mask methods against stock first-person poses produced
from the real VR adapter. Two tagged splines receive successive simulated
body-origin/hand-angle references, including the exact start/end, final segment
after the window closes, single/all-spline aborts and stock time-scale/offset
rules. Rendered hand-node access is rejected in this fixture. Spline geometry,
overlap queries, damage and exit procs are substitutes; this proves orchestration
and reference ownership, not actual contact/cleave or live damage. The common
melee-hook test also verifies that online-mode admission leaves both the action
component and view extension untouched even with valid live hand tracking.

The stock-source fixture also executes continuous and burst flame target
acquisition, ray loops, hit processing and fixed-update authority branches.
Both use the current stock simulation component produced after the VR adapter;
no rendered weapon origin is read. Client prediction casts the central ray and
updates its obstruction preview, while the server casts eight rays and owns
damage/burn calls. Supplied hit lists cover self/afro/duplicate filtering,
friendly-fire policy, wall and shield stops, a buff-only target, burst distance
delay and an empty frame clearing preview validity. Rewind arguments and spread
call counts remain stock. Collision results, spread distribution and final
damage/buff application are substitutes; this is source-level orchestration
evidence, not proof of live flame damage, effects alignment or server acceptance.

Smart-targeting coverage now runs actual `_targeting_parameters` and fixed-update
methods after the VR cache/stock first-person path. Body origin, recoil then sway,
base right/up axes, ordinary versus keyword-enabled auto-aim selection and
visibility-cache expiry remain stock. Precision target ranking is supplied by
the fixture. Actual Psyker smite and single-lightning modules retain sticky
charge targets, follow changed targets when stickiness is disabled, enforce the
strict range boundary and preserve recorded targets while resimulating. Stock
smart targeting clears its transient data and skips queries during replay;
this does not execute engine component rollback. Concrete local/remote lightning
hooks also leave the component/return values unchanged in online-rules mode.
No live lock-on, ranking/visibility, damage or server correction claim is made.

The optional fixture also loads the actual stock Block module against the
adapter-produced simulation component. Constructed attacks verify inner/outer
angles, melee/ranged stamina groups and buff/damage multipliers, ranged-block
permission, server-only revive auto-block with available stamina, the Psyker
97% block-conversion cap and excess stamina cost, block-break stun immunity and
stock outcome notifications. Final stamina depletion, stun and RPC delivery use
sinks; this does not apply live damage. The portable block-hook test separately
retains the stock component when pose overrides are declined despite an available
support-hand pose. Three focused CTests and the optional source fixture pass.

Interaction coverage executes stock acquisition and ongoing validity against
the same simulated pose, then the real interaction state/timer and revive stop
methods. Direct-target preference, fallback focus, holds, completion boundary,
release/obstruction/invalid/dead/missing-target cancellation, denied starts and
infinite/UI completion retain stock decisions. Revive success changes assisted
and knocked-down inputs and calls buffs/stats only on the server. Collision
queries, interactee services and event endpoints are substitutes; no real target
geometry, network or live rescue is exercised. Portable installed interaction
hooks retain the simulated component and return tuple when hand overrides are
declined. This strengthens the offline contract, not mission acceptance.

Actual stock air steering and jumping/falling updates also run after the adapter
and first-person update. Across six aim headings, three movement directions and
three starting velocities, they match the unconverted head-basis control for
air acceleration/drag and jump gravity, including weapon/player speed modifiers
and the same recoil offset. Sprint-jump speed thresholds and server-only fall
damage-check dispatch remain. Actual slide entry retains its facing gate, while
the sliding update retains ordinary/sprint friction along world velocity. Engine
math is isolated; transitions, collision, fall damage and stuck recovery are
substitutes, not live movement or comfort evidence.

An optional stock grenade check passes:

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-grenade-stock-contract.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_grenade_aim.lua _downloads/Darktide-Source-Code
```

It executes actual aim, trajectory-preview and delayed-release methods with
distinct simulated and rendered roots. After the simulated pose changes, preview
and release share fresh origin/direction and the stock cached rotation, speed
and momentum. Stock strict release timing, half-rewind adjustment, once-only
spawn, ability-charge use and server spawning ownership remain. Trajectory math,
collision and integration are substituted; this is not physical impact evidence.

The direct-bone audit found optional `spawn_node` branches in stock grenade and
spawn-projectile actions, but no `spawn_node` assignments in the inspected
equipment settings. Those branches remain a future template-coverage boundary;
do not assume a newly added node-authored attack has stock-server origin parity.
The inspected sweep bone reads used for hit-stop deltas write animation variables;
sticky damage reads the first-person component and the target actor. Charged
and sticky attacks still need live loadout checks.

Fresh live diagnostics should include `DARKTIDEVR_ONLINE_RULES` with the range
policy and first authored input frame. Ready preflight, fresh Lua/stereo
initialization and nonzero `shared_ready` are required before a live test counts.
Authored-frame and failure counters reset for each new range visit; the first
success and first failure are reported again, with repeated frame errors bounded.
Test actual loadouts, held/charged releases, throws, movement while hand aim
differs from the head, menu cancellation, near cover, range exit/re-entry and
camera independence. Worn aim, room movement and comfort remain pending while
the user is at work. ADB dismissed the Quest tracking-loss prompt, but current
readiness fails at VDXR rendering-buffer creation; see
[recovery evidence](QUEST-PASSTHROUGH-RECOVERY.md).

Current full offline suite: 113/113 at `e2aa82a`, with headset tests disabled
and desktop graphics tests explicitly skipping OpenXR discovery.
Full native Release build baseline: `df99611`, with the newer XR harness built
at `4298262`. Watcher/input fixes and source-contract expansions are recorded in
the current handoff. They remain undeployed.
