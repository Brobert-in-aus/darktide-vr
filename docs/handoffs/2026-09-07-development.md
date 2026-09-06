# Development continuation: 7 September 2026

The user resumed development and requested continued work until told to stop.
They are at work all day and cannot provide in-headset verification. Continue
automated checks and offline work; keep worn checks pending without waiting for
immediate feedback. The task has an active 20-minute heartbeat. Automation state
and device identifiers remain outside Git.

The day's continuation is collected in
[draft review #2](http://192.168.8.181:3000/robert/warhammer-40k-darktide-vr/pulls/2),
based on the saved 6 September backlog branch. The aggregate review branch is
`codex/development-continuation-2026-09-07`; keep it advancing only by ordinary
fast-forward pushes from validated checkpoints. Nothing is merged or deployed
by that review. Preserve each task's separate implementation branch.

## Controller candidate deployed

Ready preflight passed before deployment: one authorized Quest, Streamer/VDXR,
awake power state and 600/600 rendered XR frames. Proximity override was applied
with Disable then Status. Evidence: ignored
`artifacts/unattended/resume-preflight-20260907.log`.

Launched the saved 04b6053 Lua candidate from the inherited 1505a51 checkout:

```powershell
tools/quest/set-proximity-override.ps1 -Action Disable
tools/quest/set-proximity-override.ps1 -Action Status
tools/unattended/invoke-unattended-preflight.ps1
tools/stereo/start-darktide-vr.ps1 -AutoEnterHub -EnableHudPanel -DlssGeneratedStereo
```

The launcher retained the pinned LuaJIT gate (33 chunks), synchronized the saved
controller context/onboarding changes and explicitly disabled automatic range
entry. Stock Start fired once after character readiness. Console confirms
`hub_ship` and fresh `DARKTIDEVR_STEREO active mode=synchronized_sequential`.
One shared InputUtils hook and onboarding scope installed; the prologue scope
is delayed until its class loads. No matching Lua error or duplicate-hook
replacement was found in the startup check.

XR reached shared_ready 2295 with roughly 47 original + 47 generated pairs/s,
zero interval fallback and zero pose mismatches. These are initialization and
delivery observations, not controller/hint appearance or performance acceptance.
Evidence: `artifacts/unattended/controller-hub-resume-20260907.log` and the stock
console log beginning 6 September 19:45:41 UTC. Game/XR remain running at this
checkpoint; restore normal proximity behavior when live development ends.

## Broad hint audit expansion

The previous scanner missed `_get_input_text`, `_localized_input_text` and
`_get_localized_input_text` call sites. Added these shared helper families, plus
raw `localized_string_from_key_info` and `key_axis_locale` formatters. Named
method declarations are excluded. Raw key data has its own classification and
does not become a falsely resolved action or inflate the dynamic-action count.

Inventory now contains 138 calls in 47 files: 34 helper calls, 100 hint/alias API
calls and four raw-key formatters; 108 action expressions remain dynamic. Both
user acceptance sentinels remain present. The inventory is a review queue and
does not mark any runtime route or visual defect resolved.

Source review findings:

- Button/checkbox labels are gated by gamepad navigation; slider hint visibility
  is additionally gated by selection/focus. Pointer support alone does not make
  these hidden gamepad labels visible defects.
- Stepper helper calls cover both arrows and custom left/right gamepad actions.
  Tab, profile-preset and tutorial navigation hints are hidden during cursor
  navigation. Preserve those visibility rules.
- Chat and keyboard-rebinding previews use raw key formatters. Preserve real
  assignment text; a global string replacement would mislabel these controls.
- Talent removal still requests `right_pressed`; the generic menu adapter only
  supplies left-click and Back. A shared secondary-click route requires native
  pointer transport and guarded Lua delivery before its shared label can change.
  No isolated talent handler or hint patch was made.

Validation on Windows x64:

```powershell
python -B tests/tooling/test-ui-binding-audit.py
# PASS: 6 tests, including helper declarations and raw-key classification
python -B tools/stereo/audit-ui-binding-hints.py --source-root _downloads/Darktide-Source-Code --output artifacts/unattended/ui-binding-hint-audit-20260907.json
# PASS: both user source cases found
ctest --test-dir build/windows-vs2022 -C Release -R '^(ui_binding_audit|menu_input|turning|menu_prompts|gameplay_ui_input|hud_options|controller_bindings|controller_prompts)$' --output-on-failure
# PASS: 8/8
```

Next: continue shared menu route coverage and the mission ownership audit. Keep
hub/combat remap persistence, held-input transitions, notification appearance and
accepted hand/turning regressions pending user verification. Do not install
SoloPlay before the later Psykhanium acceptance stage. Preserve the worker/pool
rollback and the blur-first DLSS priority.

## Shared secondary-click candidate

Branch `codex/shared-menu-secondary-2026-09-07` adds a general LT secondary click
at the existing right-hand pointer. Shared `right_pressed`, `right_hold` and
`right_released` delivery covers native menus; no talent-specific handler or
tooltip was patched. The common hint formatter can now show Point + LT for
these actions when the V3 native export exists. Older native exports retain the
keyboard hint and their original eleven-value ABI. The new export checks a
thirteen-value capacity; the shared-memory mapping is versioned to v5 so mixed
native binaries cannot reinterpret a changed layout.

Secondary uses the existing native menu-entry/release state machine independently
of primary. Lua cancels holds on modal/owner and transport changes, handles
tracking loss once, retains off-panel release coordinates and consumes missed
edges before a later UI frame. Keyboard/mouse and left-click routes coexist.
This candidate has not been deployed or visually accepted.

Completed the earlier hub initialization run after shared_ready 5116, with no
fallback or pose mismatch in the final sampled interval. Closed Darktide and
restored proximity automation using Enable then Status (asleep). Current live
state supersedes the running checkpoint above: game/XR are closed. Re-run Ready
preflight before deploying the native/Lua candidate together.

Validation:

```powershell
tools/lua/build-luajit.ps1
tools/stereo/test-darktide-lua-source.ps1
# PASS: rebuilt pinned compiler; 33 chunks compile
cmake --preset windows-vs2022 -DDARKTIDEVR_ENABLE_HEADSET_TESTS=OFF
cmake --build --preset windows-vs2022-release
# PASS: Windows x64 Release
ctest --test-dir build/windows-vs2022 -C Release --output-on-failure
# Initial result: 95/98. See failures and resolution below.
```

Menu transport, independent button lifecycles, shared hint fallback, missed-edge
expiry and V1/V2/V3 export bounds pass. Native capture's pre-existing fixture
expected reconnect with RT already held to fire immediately, contradicting the
current release quarantine. Corrected the fixture to require release, then a
fresh press, retaining the stale-frame release check; native_capture_hooks now
passes. Seven affected compiler/menu/native CTests pass after that correction.

Remaining full-suite failures to resolve as a separate validation task:

- `lua_source_invariants`: obsolete weapon assertions expect post-preparation
  `action.shooting_position` writes and the old shot-counter location. The
  current ranged behavior test passes; the implementation scopes the first-person
  pose before stock preparation and owns the counter through the action component.
- `window_capture_recovery`: expected client extent is read in the test's default
  DPI context while production capture returns physical pixels. The test reports
  an aspect mismatch on this scaled display. Investigate the fixture's units.

Logs: `artifacts/unattended/secondary-build-20260907.log`,
`secondary-validation-build-20260907.log`, `secondary-ctest-20260907.log`, and
`secondary-native-fixture-build-20260907.log` in the same ignored directory.

## Validation fixture refresh completed

Branch `codex/validation-fixture-refresh-2026-09-07` resolves the remaining two
failures. The window fixture now reads its expected client rectangle inside the
same physical-pixel DPI scope as production; capture still runs from the original
caller context, exercising the production scope. No capture behavior changed.

The legacy source assertions now follow the already-established ranged pose scope,
boxed reticle point, configured HUD dimensions and completed render-target material,
stock-ready startup callback, bounded Streamline state probe and gameplay release
quarantine. Removed expectations for retired implementation text; retained the
prohibition on sampling the in-flight HUD target. Existing behavioral tests remain
the stronger evidence, and the pinned LuaJIT gate remains unchanged.

Final Windows x64 validation: `lua_source_assertions=pass`; full Release CTest
**98/98 passed** in 9.60 seconds with headset tests disabled in configuration.
Evidence: `artifacts/unattended/fixture-refresh-build-20260907.log` and
`artifacts/unattended/fixture-refresh-ctest-20260907.log`. This supersedes the
initial 95/98 result above. Shared secondary click remains undeployed and
worn acceptance remains pending. Continue next with mission input/attack ownership.

## Mission authority candidate completed offline

Branch `codex/local-mission-authority-2026-09-07` contains the source ownership
audit and shared body/input/hand-aim policy. Read
[MISSION-AUTHORITY-AUDIT](../MISSION-AUTHORITY-AUDIT.md) for exact stock paths and
remaining online work. Four explicit mission modes are admitted only while
the local session owns simulation. Other-player hooks and remote-server sessions
remain stock/gated; authority is rechecked and never latched across host loss.

Validation: pinned LuaJIT 34 chunks; full Windows x64 Release CTest **99/99 pass**.
The real ranged preparation hooks and server aim-field callback are tested for
local authority, local player ownership, remote exclusion and authority loss.
Game/XR remain closed. No mission or SoloPlay run, no new deployment, and no
headset acceptance. Next work can proceed with remaining offline combat/input
coverage or blur/performance investigation; retain the user's blur-first order
and do not resume the rejected HUD-pose hypothesis.

## Live readiness unavailable; offline detail diagnostic

Before deploying the shared-secondary/mission candidate, Ready preflight and
one retry both returned `openxr.system=hmd-unavailable`, skipping session render.
The headset could be woken, but VDXR did not expose a usable HMD. No deployment,
game launch or VD restart followed. Restored proximity with Enable then Status
(asleep); game/XR remain closed. Continue offline while the user is at work.
Evidence: `artifacts/unattended/secondary-mission-preflight-20260907.log` and
`secondary-mission-preflight-retry-20260907.log` in the same directory.

Branch `codex/dlss-ui-detail-diagnostic-2026-09-07` adds a numerical contrast
measurement and strengthens the existing capture identity gate to reject
incomplete UI exports or changed output calls/resources/layout. See
[DLSS-UI-DETAIL](../DLSS-UI-DETAIL.md) for use, evidence and limitations. The old
tenth-run static sample retains 95.9–97.8% contrast in selected fully opaque
neighbor pairs. That sample enabled optional UI input; the current baseline
disables it. No motion-blur fix, pose hypothesis or worn acceptance is claimed.

Validation: both Python suites pass (five tests each), and both newly registered
CTests pass. Full Windows x64 Release CTest also passes **101/101** (headset tests
disabled), logged in `artifacts/unattended/ui-detail-ctest-20260907.log`.
No runtime code changed. The numerical smoothing fixture is an
isolated test of the metric, not a synthetic headset or game experiment.

## Mission slot bindings candidate

Branch `codex/mission-slot-bindings-2026-09-07` adds four optional controller
actions: carried item/supply crate, stim, scanner/device, and stock pocketable
cycling. Each emits its own stock wield press through the existing adapter.
Direct-slot hints remain distinct from cycling; defaults and saved assignments
are unchanged. See [interaction coverage](../MISSION-INTERACTION-AUDIT.md) for
the audited consumers and pending mission checks.

Validation: pinned LuaJIT 34 chunks, four focused CTests pass (bindings, prompts,
gameplay UI input and Lua invariants). No native rebuild is needed. Still
undeployed; game/XR remain closed with proximity automation restored.
Next: correct the UI ownership guard discovered during this source audit.

## Gameplay UI ownership corrected offline

Branch `codex/gameplay-ui-ownership-2026-09-07` replaces the incorrect boolean
comparison of `inputs_in_use()` (a stock key table) with the stock `using_input()`
ownership query. Chat, HUD and views are included; unavailable/retiring managers
block VR input. Blocked sampling clears native/Lua state and pending UI actions,
then skips action-cache writes so cancellation cannot inject a charged-release
edge. Neutral rearming and ordinary gameplay releases remain intact.

The real adapter seam is exercised with the real binding mapper in the new
`gameplay_ui_ownership` test: RT held across UI open/close, stock cache preservation,
neutral resume, ordinary release, scanner ownership and invalid managers.
Pinned LuaJIT compiles all 34 chunks and five focused CTests pass. This candidate
remains undeployed; no new readiness attempt or live session.
Full Windows x64 Release CTest passes **102/102**, recorded in
`artifacts/unattended/ui-ownership-ctest-20260907.log`.

## Luggable hand trajectory candidate

Branch `codex/luggable-hand-trajectory-2026-09-07` adds explicit support for the
three audited luggable templates to the shared aim/preview scope. Both concrete
preview classes load before hooks are installed, addressing Stingray's copied
inheritance. The stock throw consumes the authored cache after its existing
delay; no release hook or physics replacement. Drops retain the stock near-feet
path. See [ranged audit](../RANGED-WEAPON-AUDIT.md#luggable-trajectory-candidate-7-september).

Validation: 34 pinned LuaJIT chunks, four focused CTests pass, plus the optional
source-snapshot integration test executing actual stock aim/release methods.
It confirms collision parameters, speed/momentum, cached delayed release,
once-only/server physics and stock drop references. No native changes, deployment,
game session or worn acceptance. Existing runtime still has only the earlier
saved controller/onboarding candidate; all subsequent changes remain offline.

## Scanner stick reference candidate

Branch `codex/scanner-stick-reference-2026-09-07` keeps scanner minigame axes
direct while retaining optional hand-relative locomotion outside that state.
The live local state is queried per sample, avoiding the cached diagnostic name.
Validation: pinned LuaJIT 34 chunks; five focused CTests pass for scanner axes,
gameplay heading, turning, UI ownership and source invariants. The actual movement
seam is tested across differing hand/head orientation and immediate state changes.
No deployment or live session; worn scanner/lifecycle acceptance remains pending.

## High-resolution Present timing candidate

Branch `codex/present-cpu-timing-2026-09-07` corrects a measurement limitation in
the saved performance evidence. Present CPU duration formerly used whole
`GetTickCount64` increments and accumulated integer milliseconds, so short calls
could appear as zero. The candidate brackets the same `original_present` call
with `steady_clock` and keeps fractional milliseconds through aggregation.
High-resolution queries run only when health or detailed timing is requested.

Health keeps its existing field names, emits four decimals and adds
`present_clock=steady`. Detailed traces retain coarse begin/end ticks for log
correlation and add the separately measured `cpu_ms` / `clock=steady`. Timing
ends before logging and health locking; it is a CPU call duration, not an
independent GPU timeline. Existing old logs are not reinterpreted as precise.
No pacing, fences, resolution, quality or graphics settings change; no measured
framerate improvement is claimed. Live evidence awaits successful Ready preflight.

Validation: Windows x64 Release build passes; six focused CTests pass for native
capture hooks, original stereo ring, continuous recovery, direct/compute NGX GPU
timing and Lua invariants. Evidence: `artifacts/unattended/present-timing-build-20260907.log`
and `present-timing-ctest-20260907.log`. New native binary remains undeployed.

## Hub target interaction binding candidate

Branch `codex/hub-target-interaction-2026-09-07` adds optional Inspect operative /
pet companion through the stock `interact_inspect_pressed` action. It remains
unbound by default and can be assigned only in the hub profile if desired.
Shared hints distinguish it from regular interaction and weapon inspection.
No direct UI/network/companion action bypasses stock conditions.

Validation: 34 LuaJIT chunks and four focused CTests pass (bindings, prompts,
UI ownership, source invariants). Still undeployed; no game/XR session was opened.

## Reusable performance health analysis

Branch `codex/generated-health-analysis-2026-09-07` adds a parser that separates
focus, observed generation progress and timing-clock precision. It preserves
slow windows and accounts for invalid/reset/no-output intervals; it does not
infer FG settings or frame-time percentiles. Read
[performance health analysis](../PERFORMANCE-HEALTH-ANALYSIS.md) for the whole
saved-session result and why it cannot replace the earlier selected FG-off
interval. Five unit cases pass. The actual archived log was summarized without
running Darktide or changing graphics settings.

## Reproducible checkpoint instructions

Branch `codex/development-checkpoint-2026-09-07` consolidates the current-status
opening and documents the analysis packages now required by registered image
tests. `tools/stereo/requirements-analysis.txt` pins the already-tested NumPy
2.2.5 and Pillow 12.3.0 versions, validated with Python 3.13.3 on Windows x64.
CMake checks imports using its selected interpreter and provides an actionable
installation command when they are unavailable. No packages were changed in
this session. Configuration passes with the existing environment; all gameplay
and runtime acceptance boundaries above remain unchanged.

## Later readiness observation

After the offline checkpoints, Inventory still found one authorized Quest,
one Streamer process and no Darktide process. Applied Disable then Status and
ran Ready again; rendering remained unavailable. A read-only activity query
showed a Guardian dialog among focused headset activities. No dialog was
operated, no VD restart/resume was attempted and no new deployment occurred.
Restored Enable then Status. Continue offline; the user cannot resolve worn
setup today. This is new observed context for the live blocker, not a claim
about the dialog's unseen message or its cause.

Evidence is ignored: `artifacts/unattended/continuation-inventory-20260907.json`,
`continuation-ready-20260907.json`, associated logs and
`continuation-proximity-restored-20260907.log`. No device identifier is recorded
in Git. Current source checkpoint remains fully committed and on draft review #2.

## Ownership-query recovery review

Branch `codex/ownership-query-recovery-2026-09-07` protects the method lookup as
well as its invocation for mission authority, UI ownership and scanner-state
queries. A retiring proxy can throw from `__index` before a method is obtained;
malformed owners also no longer escape the guard. Valid inherited methods keep
their receiver. One shared helper avoids allocating a closure for every query.

Validation: pinned LuaJIT 34 chunks, successful configuration, five focused
CTests pass for context, actual gameplay adapter, scanner movement seam, ranged
aim and source invariants. New cases cover invalid owners and throwing lookup
proxies. Logs: `artifacts/unattended/ownership-recovery-ctest-20260907.log` and
the matching compiler/configuration logs. Runtime candidates remain undeployed.

## Online mission investigation

Branch `codex/online-mission-audit-2026-09-07` records the requested dedicated
server investigation in [online requirements](../ONLINE-MISSION-REQUIREMENTS.md).
Stock frame-indexed aim angles provide a plausible client-only path, with
stock origins and combat rules. Independent physical origins/contact melee
need server support. Movement, room-scale body translation, prediction/replay,
camera independence and target selection need explicit treatment.

The optional `test-online-input-stock-contract.lua` executes stock input cache,
send/receive and lookup methods with an in-memory transport. PASS on pinned
LuaJIT: action/angle pairing, resend, duplicate/old packets, wraparound, gaps and
missing-frame fallback. No engine serialization or server acceptance claimed.
Documentation and tooling only; no deployment or online session.

Latest user steering: make Psykhanium operate on online-compatible rules where
possible and improve that path first. Proceed with a range proving mode while
keeping actual mission-server validation and worn acceptance separate.

## Requested ADB recovery investigation

See [Quest recovery](../QUEST-PASSTHROUGH-RECOVERY.md). Verified passthrough
toggle and VD resume via ADB. Screenshot identified actual tracking-loss prompt
("Finding position in room"), not an established accidental DoubleTap event.
Generic `PT is: ON` was not a reliable full-passthrough indicator. Ready still
fails; normal proximity restored. No boundary/tracking setting disabled and no
game/deployment performed. Continue Psykhanium online-rules implementation offline.

## Psykhanium online-rules candidate

Branch `codex/psykhanium-online-rules-2026-09-07` adds the requested proving mode,
defaulting on for the next locally hosted `shooting_range` visit. Details and
limitations: [Psykhanium online rules](../PSYKHANIUM-ONLINE-RULES.md).

The actual cached stock input frame receives right-hand aim and movement
converted/packed into the same basis. Stock simulation supplies origins,
recoil, spread, button-melee sweeps and damage rules; common temporary combat
pose proxies and room-scale extra mover velocity are excluded. The reticle
uses simulated stock pose. UI/tracking/state/owner and packing failures retain
stock input. Settings latch per visit. Tutorial training grounds and online
mission admission are unchanged. Range invulnerability, inert targets and
pickup replenishment remain explicit training limitations.

Validation: pinned LuaJIT 35 mod chunks; **105/105** Windows x64 offline CTests
pass. Optional stock-source checks pass for input history and for actual
first-person/walking methods, including stock origin/recoil and backward speed
penalty. Engine serialization, remote correction and worn camera/aim/comfort
remain unverified. Logs: `artifacts/unattended/online-rules-ctest-20260907.log`
and `online-rules-configure-20260907.log`. No deployment due to failed Ready
after the requested ADB recovery. Normal Quest proximity behavior is restored.

## Online-rules forced-view ownership

Follow-up branch `codex/online-rules-forced-view-2026-09-07` fixes a concrete
source-audit finding: walking can coexist with a forced weapon view or sticky
melee orientation. Observe the actual stock orientation object chosen immediately
before input caching, using a weak handler-keyed ownership table. Only its
default/free-aim owner admits hand input; unknown selection retains stock input.
The selector and all returned objects remain unchanged.

Four focused CTests pass (compiler, invariants, ranged and online rules), plus
the optional source test now executes the real selector for forced look, ledges,
both weapon-lock forms, force-look weapons, sticky melee, communication/emote
wheels and death. No native change, deployment or new live readiness attempt.
The prior full-suite result remains 105/105 at `e3647d0`.

Further source test: actual local first-person rendering and camera-root methods
retain the original head/view owner while the combat component uses hand aim.
The optional stock test passes. Direct-bone review found no configured
`spawn_node` assignments in equipment settings; existing optional action branches
remain a future-template boundary. Sweep hit-stop bone reads feed animation;
the inspected sticky damage path uses the first-person component/target actor.
No additional production changes or live acceptance from this review.

## Online movement direction fix

Branch `codex/online-movement-direction-2026-09-07` fixes a reproduced input
conversion error: a diagonal rotated outside the stock input square had its
axes clipped independently, changing world direction. Scale both axes together
before stock packing. The targeted regression failed before the fix and passed
afterward. The actual stock-walking check covers four vectors at twelve aim
headings, retaining direction and stock speed rules at settled input.

Four focused CTests pass (Lua compiler/invariants, online rules and scanner)
and the expanded optional stock-source check passes. The only explicit settings
rotation constraint found in this snapshot belongs to Ogryn lunge; its lunging
state already falls outside the hand-input allowlist. No new constraint hook
was added. Rapid aim-change/transient movement and live acceptance remain open.

A subsequent isolated 90-degree step probe characterized stock desired steering
over four hypothetical 60 Hz updates (65.1/30.1/3.0/0 degrees of heading error).
This is not root displacement or worn evidence. See the proving-mode document
and ignored `online-movement-transient-20260907.log` for conditions/limits.

Optional user question is pending: retain training aids or also enable enemy
attacks/incoming damage. Source audit found three separate owners: minion-init
perception flag, a recurring unperceivable-buff loop and player invulnerability.
No training-aid changes were made. A combat option would also need controlled
encounters and downing/death recovery; continue independent work meanwhile.

## Guardian dialog recovery follow-up

ADB successfully clicked the freshly inspected `Continue without tracking`
button when Guardian gained window focus. Ready now creates an OpenXR session
but fails creating swapchains; settled retry and one Quest VD app restart
reproduce it. VDXR reports underlying texture-swapchain result -7000; cause is
not established. PC Streamer unchanged, normal proximity automation restored,
headset asleep, game closed and candidates undeployed. Exact observations and
ignored evidence are in [Quest recovery](../QUEST-PASSTHROUGH-RECOVERY.md).

## Per-visit online-rules diagnostics

Branch `codex/online-rules-session-diagnostics-2026-09-07` fixes stale readiness
evidence across range visits: counters reset when a new session is latched,
so its first authored frame and first failure are reported again. The regression
failed before the change and passes afterward, including session replacement
without an observed hub and bounded repeated errors. Three focused CTests
(compiler, invariants, online rules) and the optional stock-source contract pass.
No native change or deployment. The full-suite baseline remains `e3647d0`.

## Stock shot-preparation integration

The optional stock-source test now executes `ActionShoot._prepare_shooting`
using the pose produced by the VR adapter and actual first-person method. It
passes body-origin, charge, recoil/sway/assist/spread ordering and grouped-shot
sample retention checks. The engine weapon operations are tagged substitutes;
their math, bullet collisions and damage are not covered. No production change,
deployment or broader suite rerun was needed for this fixture extension.

## Heartbeat: stock transport with actual VR input authoring

Branch `codex/online-rules-stock-replay-2026-09-07` extends the optional input
source test with trailing paths to the online-rules and gameplay-context modules.
It runs the real adapter through actual stock caching, send/receive and both
`HumanUnitInput` per-frame readers. Eight action/movement/angle columns agree
through resend, old/duplicate packets, ring wrap and skipped send windows.
UI-owned and tracking-unavailable frames retain stock samples; changing live
aim before history reads does not resample it. Both plain and adapter-enabled
invocations pass. Source parsing, engine packing/serialization and actual
component correction remain outside this in-memory fixture.

No production change or live attempt. Quest remains under normal proximity
automation; no new evidence justified repeating the failed rendering recovery.

## Heartbeat: online throw preview correction

Branch `codex/online-rules-throw-preview-2026-09-07` fixes a discovered visual
reference mismatch: stock throw previews read the rendered first-person root,
which stays head-driven while online-rules simulation uses hand aim. Add an
optional preview-only simulated-pose provider to the existing grenade/luggable
trajectory scope. The provider verifies the local live first-person owner and
contains retiring-extension failures. Action components and stock physics remain
untouched; cosmetic preview offsets are omitted as in the existing hand preview.

The scoped regression failed before the fix. Five focused CTests pass (compiler,
invariants, online rules, ranged aim, grenade aim). A new optional
`test-grenade-stock-contract.lua` passes actual stock aim/preview/release methods,
including moved-pose reference agreement, cached release fields, strict delay,
half-rewind timing, once-only spawning, charge and server ownership. Trajectory
and physics are substitutes, so real impacts and worn arc alignment remain open.
No live attempt or deployment; full-suite baseline remains `e3647d0`.
