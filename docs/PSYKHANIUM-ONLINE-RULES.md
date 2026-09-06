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

Controller and keyboard movement already combined in the head basis is
transformed into the transmitted hand-aim basis, then passed through stock
movement packing before simulation. Stock acceleration, backward speed scaling,
sliding, collision and recoil-related effects remain. The isolated stock-method
test confirms a concrete consequence: looking/aiming behind while walking in
the head's forward direction retains the server's backward-movement penalty.
The mode does not implement a local speed compensation that the server lacks.
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
build/dependencies/luajit/src/luajit.exe tests/tooling/test-online-rules-stock-contract.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_online_rules.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_gameplay_context.lua _downloads/Darktide-Source-Code
```

Both pass. The first covers stock buffering/send/receive/history behavior. The
second applies the actual VR adapter before stock first-person and walking
methods, verifying body-height origin, stock recoil, intended movement direction
and backward penalty. It also executes the actual stock orientation selector
across forced look, both weapon-lock forms, force-look weapons, melee stickiness,
ledge hangs, communication/emote wheels and death. Engine math and transport are isolated substitutes, so
these do not establish executable wire precision or live server acceptance.
The actual stock local `_update_rotation` and camera-root orientation methods
also pass with distinct head/hand angles: local rendering reads the original
view owner while the fixed combat component keeps hand aim.

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

Follow-up ownership fix: four focused CTests and the expanded stock-source
check pass; the last full 105-test suite is the preceding candidate checkpoint.
