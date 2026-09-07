# Development continuation: 7 September 2026

The user resumed development and requested continued work until told to stop.
They are at work all day and cannot provide in-headset verification. Continue
automated checks and offline work; keep worn checks pending without waiting for
immediate feedback. The task has an active 20-minute heartbeat. Automation state
and device identifiers remain outside Git.

Latest integrated offline check: **113/113 CTests pass** at `e2aa82a` on the
`codex/offline-graphics-test-isolation-2026-09-07` candidate (14.84 seconds), with headset
tests disabled and all 36 Lua chunks compiling. Full Release build baseline is
`df99611`, with the newer XR harness built at `4298262`. Guardian pause/resume is
now verified via ADB; a settled Ready attempt still fails at VDXR texture
creation. Guardian and proximity automation were restored. Darktide is closed;
the day's later candidates remain undeployed. Chronological entries below retain
their older validation states; the final entries describe the newest changes.

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

## Continuous todo work: performance focus windows

User reiterated continuous work throughout the day. Continued the interaction
audit: inspected use/revive and ability-targeting consumers read simulated
first-person components, so no throw-preview-style root correction was needed.
Then found a diagnostics gap: foreground status only at each health endpoint
misses an away-and-back change inside the interval.

Branch `codex/performance-focus-windows-2026-09-07` counts focus changes at each
measured Present, emits them in native health rows and excludes mixed windows
from stable performance groups. Old endpoint-only logs stay separately labelled.
The new parser regressions fail before the fix and pass after it. Release builds
of `darktidevr_native_capture` and `darktidevr-generated-frame-state-tests` pass;
focused `generated_frame_state` and `generated_health_analysis` CTests pass.
No performance improvement, cause of earlier slow windows or live acceptance is
claimed. No deployment; normal headset sleep and existing graphics settings remain.

## Continuous todo work: cached tutorial binding hints

Branch `codex/tutorial-binding-refresh-2026-09-07` fixes prologue tutorial cache
invalidation after VR remaps and availability changes. Stock only checks keyboard
aliases/device selection. The shared prompt module adds binding-revision refresh
while preserving stock decisions and leaving stable frames alone. Five focused
CTests pass (prompts, bindings, menu prompts, Lua compile/invariants); regression
failed before the fix. No live test or deployment and no talent-specific patch.

## Continuous todo work: online smart-tag marker selection

While inspecting hand-dependent consumers before handedness work, found another
online proving-mode reference mismatch: the stock HUD marker scan used screen
centre and could select a different unit from the stock simulated aim target.
Branch `codex/online-rules-tag-target-2026-09-07` admits the existing target-to-marker
path for active local online-rules simulation. Stock raycast/forced refresh stays
in charge, and the marker still passes its stock validity check. Unknown/remote/
retiring authority and inactive VR fall back. Handedness implementation remains
pending; no role/presentation change was made during this discovery.

The actual-hook regression fails against the pre-fix source and passes afterward.
After configuring with headset tests off, five focused CTests pass: smart-tag
marker target, online rules, ranged aim, Lua compiler and invariants. The suite
now registers 106 tests, but no full-suite result is claimed on this head.
No live attempt or deployment. User's continuous-work instruction remains active;
continue through independent todo items instead of ending at a status checkpoint.

## Continuous todo work: weapon-role foundation

Branch `codex/weapon-role-foundation-2026-09-07` adds fixed dominant/support role
resolution while retaining physical tracking/wrist identity. Attack, reticle,
staff support origin, throws, block, tagging, online frame aim and the diagnostic
contact probe now request weapon roles. The latter also selects the corresponding
physical grip-validity field. Runtime is fixed right-dominant until attachment/
effect presentation, held-input rearming, presets and menu pointer are completed;
no incomplete left-hand option is exposed.

Validation: 36 LuaJIT chunks; full Windows x64 offline CTest **107/107 pass** with
headset tests disabled at configuration. Evidence:
`artifacts/unattended/weapon-roles-full-ctest-20260907.log` and matching configure
log. Role fixtures cover both choices, invalid roles and tracking loss. Concrete
ranged hooks pass left-role input and stock fallback without an opposite-hand
substitution. Optional stock grenade and online pose/shot contracts pass too.
The source invariant's staff-origin diagnostic literal was updated to support
terminology without removing its behavior guard. No native change since the
focus-window build and no deployment. Continue attachment ownership work next.

## Continuous todo work: partial equipment rig resilience

Branch `codex/equipment-sync-resilience-2026-09-07` fixes an attachment-sync
diagnostic crash: the per-hand path allowed partial success, but the first scale
log still resolved both source hands and parents unconditionally. Require both
successful hand syncs for that detailed scale log. Preserve ordinary partial
sync counters and all accepted pose math.

New `equipment_hand_sync` CTest reproduces the missing-hand fault before the fix,
then passes rotated-parent/scaled-root pose agreement, partial source/proxy/
parent cases, invalid owners, unchanged anatomical proxies and item animation.
Configure with `cmake --preset windows-vs2022 -DDARKTIDEVR_ENABLE_HEADSET_TESTS=OFF`;
run Release CTest with `-R 'equipment_hand_sync|wrist_transform|weapon_hand_roles|animation_aim|source_invariants'`:
**5/5 pass**. `tools/stereo/test-darktide-lua-source.ps1`: **36 chunks pass**.
108 tests are now registered; full-suite baseline remains 107/107 at `9f68b2b`.
No deployment or worn acceptance. HANDEDNESS-AUDIT now details separate initial
1P sound, camera-selected weapon VFX and breed-hand effect ownership; relocation
must cover these before any left-handed option is exposed. Continue todo work.

## Continuous todo work: reduce persistent success logging

Branch `codex/continuous-trace-sampling-2026-09-07` samples the five successful
continuous-submission records per frame: first eight frames then every 120th.
The existing log writer takes a lock and writes synchronously on the Present
path, until its shared record cap. Bounded probes retain every frame; failure,
lifecycle, timing, health and all rendering/ownership checks remain in place.
Ready records label the policy, and the bounded-proof reader rejects sampled or
unknown policies rather than certifying them as complete consecutive evidence.

Release builds pass for `darktidevr_native_capture` and
`darktidevr-generated-frame-state-tests`. Release CTest with
`-R 'generated_frame_state|streamline_continuous_observation|generated_health_analysis'`
passes **3/3**. The policy test covers startup/periodic boundaries and 1,200 frames;
reader checks accept legacy/explicit complete and reject sampled/unknown logs.
This removes avoidable logging work; no measured FPS gain or deployment claim.
Full-suite baseline remains 107/107 at `9f68b2b`, with the intervening equipment
regression increasing registration to 108. Continue the todo list while the user
is away; live swapchain creation remains blocked and normal proximity restored.

## Continuous todo work: stock melee proving contract

Branch `codex/online-rules-melee-contract-2026-09-07` extends the optional real-
source online fixture through actual ActionSweep orchestration. Reset/update,
authored damage-window edges/final segment, individual/all abort masks and
time scaling retain the stock simulated references after VR cache authoring.
The fixture rejects rendered hand-node reads. Geometry, overlaps, damage and
exit procs remain isolated substitutes; no physical contact acceptance.

The optional command documented in PSYKHANIUM-ONLINE-RULES passes all pose,
camera, shot, movement, forced-orientation and new sweep cases. The ordinary
`melee_aim` test now verifies online-mode bypass across all four common melee
hooks: valid live tracking must not replace the stock action or view component.
Focused `melee_aim` and `online_rules` CTests pass **2/2**. No runtime code change,
new live attempt or deployment in this task. Continue the todo list.

Integrated checkpoint: the full Release preset build passes, including the
recompiled continuous-recovery executable. Full offline Release CTest then
passes **108/108**, with headset tests disabled at configuration. Evidence:
`artifacts/unattended/continuous-todo-full-ctest-20260907.log`. This supersedes
the preceding 107-test full-suite baseline. LuaJIT still compiles 36 mod chunks.

## Live recovery follow-up: PC Streamer access

A different recovery step from the earlier Quest-app restart was attempted:
restart the sole PC Streamer process after persistent swapchain creation failure.
Windows rejected Stop-Process with Access is denied. The guarded sequence did
not launch another instance. No privilege workaround, headset wake/proximity
change, deployment or new Ready attempt. Live rendering remains blocked; the
user was informed and work returned to offline mission lifecycle checks.

## Continuous todo work: failed controller-read cancellation

Branch `codex/tracking-loss-input-cancel-2026-09-07` fixes another synthetic
release leak. Lua sampled its mapper as inactive after native read failure, but
the final delivery guard only rejected inactive gameplay policy; a nonzero
cancellation release could still enter the stock ephemeral action cache.
Require effective gameplay-input activity (policy plus successful native read)
after sampling/cancelling both mappers and UI requests.

The real adapter regression fails before the fix and passes afterward. It covers
nonzero errors, cleared and stale returned levels, inherited holds on recovery,
neutral rearming, normal release and unchanged keyboard cache. Native code
returns 2 for unavailable/stale transport and resets its mapper; no native ABI
or mapper change is required. Six focused CTests pass (gameplay input, Lua source
invariants, online rules, gameplay UI input, controller bindings, UI ownership),
and all 36 LuaJIT chunks compile. Full-suite baseline is 108/108 at `dd1ec4e`.
No deployment; per-hand tracking flags and worn cancellation remain separate
acceptance limits. Continue the todo list until the user instructs a stop.

## Continuous todo work: binding discontinuity cancellation

Branch `codex/binding-discontinuity-cancel-2026-09-07` extends cancellation to
remaps, observed publisher-generation changes and invalid stick axes. Remaps/
generations clear the old semantic hold and quarantine inherited controls.
Axis loss suppresses only cancelled action releases without clearing healthy
button-alias history, avoiding either a false release or repeated press.

The actual Lua adapter reproduced the remap release before the fix. Updated
mapper expectations now distinguish cancellation from ordinary physical release;
shared-alias, neutral rearming, invalid axes and observed restart checks pass.
Five focused CTests (bindings, real UI ownership seam, prompts, UI routing,
source invariants) and 36 LuaJIT chunks pass. No deployment. Full-suite baseline
remains 108/108 at `dd1ec4e`. Next investigate the separate pose-generation versus
native-button sampling order: this change covers an observed generation, not
yet a restart detected by the native reader before Lua observes its generation.

## Continuous todo work: native publisher-change status

Branch `codex/native-publisher-transition-2026-09-07` closes that sampling-order
gap. The core mapper marks an active publisher change; `dtvr_read_gameplay_input`
returns status 3 for that frame, independently of Lua's last pose observation.
Lua's effective-activity guard already cancels all nonzero statuses. Return
values 0/1/2 retain success/invalid-output/unavailable semantics; the export's
signature and output layout are unchanged. Internal cancellation releases remain
available to mapper consumers but are not delivered into Lua's action cache.

The actual DLL-export test replaces the shared writer during a held attack,
without a pose read in between, then checks once-only status, inherited-hold
quarantine, neutral rearming and normal release. Release native-capture, native
export-test and gameplay-input-test builds pass. Five focused CTests pass:
gameplay input, native capture hooks, online rules, bindings and real Lua adapter
ownership. No live deployment; full-suite baseline remains 108/108 at `dd1ec4e`.

## Continuous todo work: range difficulty evidence

Branch `codex/online-rules-difficulty-evidence-2026-09-07` records live challenge
and resistance on the first successful input frame per proving visit. Each
optional difficulty query is protected; missing/retiring/nonfinite values report
unknown without turning a completed input write into a failure. Stable frames
do not repeat the queries/log. Aim diagnostic now says dominant_hand to match
the role abstraction, with runtime policy still right-dominant.

Source follow-up distinguishes shooting-range unperceivable/invulnerability and
pickup aids from tutorial-only damage/cooldown/peril buffs and forced base
talents. Selected range difficulty affects target health; the target spawn's 2s
are duration/side, not difficulty. PSYKHANIUM-ONLINE-RULES records those limits.
Three focused CTests pass (online rules, source invariants, smart-tag ownership),
and 36 LuaJIT chunks compile. No deployment or runtime difficulty change.

## Continuous todo work: current input-handler ownership

Branch `codex/gameplay-handler-ownership-2026-09-07` restricts ordinary and
synthetic injection to the local player's current handler. The fixed hook also
requires the same handler to have been observed by pre-update. A weak identity
reference detects replacement without retaining retired player caches; its first
sample cancels input and requires neutral rearming, even without an intervening
inactive callback during loading.

The real adapter regression reproduces a foreign handler consuming shared input
before the fix. It now covers foreign/retired pre-updates, inherited holds on
replacement, foreign/unsampled fixed updates and synthetic request ownership.
The shared policy also rejects missing/retiring managers and mismatched current
handlers. Five focused CTests (context, real adapter ownership, bindings, online
rules, source invariants) and 36 LuaJIT chunks pass. No native change beyond
`6eb81f7`, deployment or live mission-transition acceptance. The historical
remote-husk teardown race remains a separate base-game condition.

## Continuous todo work: anatomical calibration recovery

Branch `codex/hand-anatomy-calibration-2026-09-07` prevents an unusable initial
finger-joint pose from poisoning the rigid glove's cached anatomical basis.
It rejects zero/nonfinite axes and collinear anatomy before normalization/cache,
then retries on a later usable pose. Authored-animation placement also waits for
calibration before importing fingers. Valid calibration and wrist offsets retain
their existing math. No handedness setting, weapon relocation or deployment.

The actual extracted solver passes 3D axis invariants for distinct authored
hands, arbitrary world/grip rotations, scales 0.94/1/1.08 and cached calibration
under later finger animation. The new test reproduced invalid cached rotation
and premature animation import before the fixes. Missing/invalid anatomy and
recovery pass. Configure with `cmake --preset windows-vs2022
-DDARKTIDEVR_ENABLE_HEADSET_TESTS=OFF`; seven focused CTests pass using
`ctest --test-dir build/windows-vs2022 -C Release --output-on-failure -R
'^(hand_anatomy|wrist_transform|equipment_hand_sync|melee_animation_owner|melee_animation_source|lua_source_compile|lua_source_invariants)$'`.
The LuaJIT gate still compiles 36 chunks. Full-suite baseline remains 108/108 at
`dd1ec4e`; the new test increases the configured inventory to 109. No claim that
this constructed failure caused an observed live alignment issue. Continue
online-rule action-family checks and the todo list while live readiness is blocked.

## Continuous todo work: stock flame action contract

Branch `codex/online-flamer-stock-contract-2026-09-07` extends the optional
`test-online-rules-stock-contract.lua` fixture with actual stock continuous/burst
flame acquisition, ray loops, hit processing and fixed-update authority. The
real VR input adapter and first-person update precede those reads. Client and
server cases retain the body/eye simulation origin, hand-directed angle, rewind
arguments, one/eight ray ownership and server-only damage/burn calls. Supplied
hits cover self/afro/duplicate filters, friendly fire, wall/shield obstruction,
buff-only targets, burst distance delay and clearing an empty preview.

The optional fixture passes using the existing three module/source arguments
documented in PSYKHANIUM-ONLINE-RULES. Engine collision, spread and final damage
are substituted; no portable source dependency, production edit, deployment or
live flame acceptance is introduced. Continue integrated offline validation and
the remaining todo list; no headset confirmation is expected while the user works.

Integrated follow-up: the full Windows x64 Release preset build passes, followed
by **109/109 offline CTests** with headset tests disabled at configuration.
Evidence: `artifacts/unattended/continuous-todo-full-ctest-109-20260907.log`.
This includes native publisher-transition cancellation, current handler ownership,
range difficulty diagnostics and the new anatomical-calibration test. LuaJIT
compiles 36 chunks. The optional source fixture remains separate and passes;
current candidates remain undeployed.

## Continuous todo work: stock Psyker target-lock contract

Branch `codex/online-target-lock-contract-2026-09-07` adds actual smart-targeting
parameters/fixed-update and Psyker smite/single-lightning module checks to the
optional stock-source fixture. The adapter's simulation pose supplies body
origin and aim; recoil/sway order and ordinary/keyword auto-aim selection remain
stock. Sticky target retention, non-sticky retargeting, strict range boundaries,
visibility-cache expiry and replay's transient-data clear/recorded-target
retention pass. The finder supplies target ranking; no engine rollback or live
visibility/damage is executed.

The portable ranged fixture now checks all three concrete lightning hooks in
online mode for both local and remote units, with live hand tracking available:
the stock component and return values remain unchanged. Three focused CTests
pass (ranged aim, online rules, smart-tag marker ownership), plus the expanded
optional source fixture. Production code is unchanged; full Release build and
109/109 CTest baseline remain `5f1eccd`. Continue the todo list with live readiness
and worn acceptance still blocked as previously recorded.

## Continuous todo work: rigid-hand spawner readiness

Branch `codex/rigid-hand-spawn-readiness-2026-09-07` waits for the stock profile
spawner's `spawned()` readiness instead of accepting early unit existence. The
spawner continues receiving initialization updates while pending. Once ready,
update no longer duplicates placement's full glove-visibility traversal; initial
visibility and placement enforcement remain. One update plus one placement per
hand now requests two traversals instead of four. No measured FPS improvement.

The regression reproduced premature readiness before the fix and passes pending
streaming, stable updates without repeated visibility calls, missing/dead units,
failed streaming quarantine and fresh replacement ownership. Configure with
headset tests disabled; seven focused CTests pass (rigid hand readiness, anatomy,
equipment sync, both melee animation fixtures, Lua source compile/invariants).
LuaJIT compiles 36 chunks; configured CTest inventory is now 110, with the last
full 109/109 baseline at `5f1eccd`. No native changes or deployment. Keep working
through the todo list and preserve the documented live/XR readiness boundary.

## Continuous todo work: rigid-hand liveness and visibility fallback

Branch `codex/rigid-hand-liveness-2026-09-07` requires both ready hand units to
remain alive before the pair can own presentation or hide source hands. If a
previously ready pair loses a unit, both proxies retire together, preventing a
surviving glove from overlapping fallback hands. The existing failed-source
quarantine prevents repeated respawn attempts until source or enable ownership
changes; disabling/re-enabling allows the same player to reacquire.

The outer presentation seam now forces visibility refresh on active/inactive
changes, including a nil proxy return, instead of waiting for the regular
60-frame visibility pass. Stable frames do not repeat the forced refresh.
Diagnostics report active/inactive explicitly, and cached proxy poses clear on
either transition. The regression reproduces stale active ownership before the
fix and executes actual liveness/slot policy, update orchestration and the main
visibility seam with mocked unit/spawner operations. It covers each missing/dead
hand, complete teardown, replacement, survivor retirement and quarantine reset.

Full Windows x64 offline CTest suite: **110/110 pass**, including all 36 LuaJIT
chunks, with headset tests disabled at configuration. Evidence:
`artifacts/unattended/continuous-todo-full-ctest-110-20260907.log`.
Native code is unchanged since the full Release build at `5f1eccd`. No deployment
or claim that this constructed unit-loss case caused a historical live crash.
Continue the remaining todo list; user has not instructed a stop.

## Continuous todo work: reticle cache ownership

Branch `codex/reticle-cache-ownership-2026-09-07` fixes negative-age freshness
after controller sequence restart and binds cached convergence/tag targets to
their controller generation, game session and live current player. A shared
getter invalidates stale data; convergence retains its existing hand-ray
fallback, and the hand-origin HUD receives no stale target. Invalid publication,
ray error, lost hand aim or missing simulation component clears cached owner
references as well. Online-mode stock forced tagging and combat origins remain.

The regression executes real publication/convergence and reproduces the old
negative-age error. It covers 0/60/61-frame boundaries, generation changes even
after sequence catch-up, player/session changes, owner death, no pose and failed
query. Actual installed targeting hooks and HUD hooks verify clearing/empty
fallback. Six focused CTests pass (reticle surfaces/cache, ranged aim, online
rules, smart-tag marker, Lua compile/invariants); 36 chunks compile. Full-suite
baseline remains 110/110 at `aadf4f3`, native build `5f1eccd`. No deployment or live
aim/transition acceptance. Continue other todo work without headset verification.

Reticle follow-up on the same task: protect the current-player lookup while
checking a cached point. A retiring manager can throw despite the cached owner
still being alive. The new fixture reproduces that exception; the getter now
clears the point and falls back. Four focused CTests pass (reticle cache, ranged
aim, smart-tag marker, 36-chunk Lua compile). No native/deployment change.

## Continuous todo work: stock blocking contract

Branch `codex/online-block-stock-contract-2026-09-07` runs actual stock Block
eligibility and cost code after the VR cache and stock first-person update.
Constructed attack positions verify simulation-facing inner/outer limits, block
cost groups and multipliers, ranged permission, server-owned revive auto-block,
Psyker warp-charge cap/excess stamina cost, break stun immunity and outcome
notifications. Stamina depletion, stun and RPC endpoints are sinks; engine
collision/live incoming damage is not exercised. The fixture needed vector
subtraction added to its math substitute; no production block fix was required.

The existing portable block-hook test now explicitly declines pose overrides
with a support-hand pose still available. Three focused CTests (block direction,
online rules, ranged aim) and the optional source fixture pass. Documentation
makes the one-direction limit explicit: current online-rules blocking uses the
dominant-hand simulation direction, not an independently oriented support shield.
No production code/deployment change; full-suite baseline remains 110/110 at
`aadf4f3`, native build `5f1eccd`. Continue the user's todo list until instructed
to stop, with worn verification pending while they are at work.

## Continuous todo work: queued UI request ownership

Branch `codex/ui-request-owner-2026-09-07` binds queued controller tag, inventory
and menu requests to the local player at sampling time. A changed or unavailable
owner cancels the request; protected owner lookup handles a retiring manager.
Tag cancellation applies across cached HUD instances and cannot revive when an
old player returns. Stock keyboard input, modal gates and return values remain.
The regression reproduced a cached tag crossing a player replacement before the
fix, then covers pending requests, lookup failure/recovery and fresh input.
The shared menu fixture now supplies a stable player instead of inventing a new
one on each lookup. Six focused CTests pass (gameplay UI input/ownership, shared
menu input/injector, Lua compile/invariants); all 36 chunks compile. Full-suite
baseline remains 110/110 at `aadf4f3`, native build `5f1eccd`. No deployment.

The broader hint investigation found no event callback formatting gap in the
three stock inventory onboarding hints: their event registration lists are
empty. No speculative event wrapper or talent-specific patch was added. The
communication wheel remains without a VR action: its held input, selection and
HUD ownership need a complete route before advertising a binding. Continue the
mission interaction review and remaining todo while headset rendering is blocked.

## Continuous todo work: stock interaction contract

Branch `codex/online-interaction-stock-contract-2026-09-07` extends the optional
stock-source fixture with actual acquisition, ongoing spatial validity,
interaction state/timer and revive completion methods. The current VR-authored
stock first-person component supplies query origin/direction. Supplied collisions
cover direct/fallback targets, holding, exact completion time, release and
obstruction/invalid/dead/missing-target cancellation, denied starts and infinite
UI completion. Actual revive stop mutates assisted/knocked-down inputs and calls
buff/stat endpoints only on server success. Physics, interactee service and event
endpoints are substitutes; no real mission or geometry was exercised.

The portable installed interaction hooks now also decline hand overrides while
retaining the stock component and multi-value return. The optional stock fixture
and focused melee/online-rules/gameplay-ownership CTests pass. Production code is
unchanged; full-suite baseline 110/110 at `aadf4f3`, native build `5f1eccd`.
Continue the todo; no deployment, live revive, rescue or worn acceptance claimed.

## Continuous todo work: GPU timing workload boundaries

Branch `codex/ngx-timing-workload-2026-09-07` labels NGX GPU averages with observed
feature lifetime and per-eye dimensions. A changed key flushes the prior partial
group, preventing the old 120-sample aggregation from mixing feature/extent
changes. Zero/unknown keys are skipped; normal bounded query/fence behavior and
120-sample reporting remain. Direct and compute D3D12 WARP fixtures independently
change lifetime, width and height and verify six 60-sample boundary rows plus two
120-sample rows across both eyes. Initial MSVC build rejected the fixture's
deprecated scanner; it now uses bounded `sscanf_s`. Release profiler/native DLL
builds and four focused CTests pass (both profiler queues, native hooks, generated
frame state). This records workload identity, not an FPS improvement or blur fix.
Full-suite baseline remains 110/110 at `aadf4f3`; native sources have now advanced
beyond the prior full Release build at `5f1eccd`. No deployment; continue the todo.

Integration checkpoint `df99611`: full Windows x64 Release preset build and
**110/110 offline CTests pass**, with headset tests still disabled. Evidence:
`artifacts/unattended/continuous-todo-full-build-df99611-20260907.log` and
`artifacts/unattended/continuous-todo-full-ctest-df99611-20260907.log`. This is the
new build/suite baseline; no live checks were performed by that run.

## Continuous todo work: Quest watcher cleanup

Branch `codex/quest-watcher-cleanup-2026-09-07` restores normal proximity
automation when the reconnect watcher exits. It remembers every authorized
Quest override attempt, including an ambiguous failed broadcast and a later
disconnect. Cleanup attempts every remembered device; a restore failure is
logged and returns failure after the other devices have been handled. Ordinary
loop faults retain their original error when cleanup succeeds. The isolated
fixture also reproduced startup failure when the ADB fallback pipeline collapsed
to a scalar/null under Windows PowerShell; fallback discovery now preserves an
array before appending a PATH client.

The actual watcher and proximity scripts run against an isolated fake ADB client
with simulated polling/time, covering normal exit, disconnect, failed apply,
loop failure and one failed restore among two devices. No real ADB invocation,
proximity change, wait or headset launch occurs in this test. Two focused CTests
pass (watcher cleanup and XR readiness); the inventory is now 111 tests, while
the last full suite/build remains the 110-test `df99611` checkpoint. Continue
offline work; this tool fix does not resolve the current VDXR renderability fault.

## Continuous todo work: unchanged controller samples

Branch `codex/controller-idle-fastpath-2026-09-07` skips ephemeral-action routing
when a valid controller sample has no press/release edge. Native/semantic
sampling, UI cancellation, owner handling and turning still occur first; held
inputs, movement and online aim continue in the separate fixed-frame hook.
This avoids two diagnostic tables and a binding scan on those samples. Six
existing focused CTests pass (controller bindings, gameplay UI input/ownership,
online rules, Lua compile/invariants); 36 chunks compile. No added test for the
simple early return and no measured FPS claim. Full build/suite baseline remains
`df99611` (110 tests); the newer watcher test passes separately. Undeployed.

## Continuous todo work: stock air movement and sliding

Branch `codex/online-air-slide-contract-2026-09-07` executes actual stock air
steering and jumping/falling updates after the VR cache and first-person update.
108 combinations of state, aim heading, input direction and starting velocity
preserve baseline air acceleration/drag and jump gravity, with weapon/player
speed modifiers and a shared recoil offset. Sprint-jump thresholds and server
fall-damage-check dispatch remain. A missing stuck-recovery sink was added to
the initial fixture; no production fix was needed.

Actual slide entry confirms the facing limitation: sideways/backward hand aim
can prevent a slide despite forward world velocity. Once sliding, ordinary and
sprint friction follow existing world velocity rather than rotating with aim.
Transitions, collisions, damage and stuck recovery are substituted. The optional
stock fixture passes; no live locomotion/comfort claim or production change.
The block-selection review also found stock deliberately preserves blocking into
some attacks, so no simplistic support-hand switch was added. Full build/suite
baseline stays `df99611`; continue the user's todo until instructed to stop.

## Continuous todo work: desktop wheel target

Branch `codex/menu-desktop-event-ownership-2026-09-07` fixes a reproduced mismatch
in the common menu adapter: stock desktop wheel deltas were retained while the
cursor still followed an unrelated controller ray. A wheel event now snapshots
the foreground desktop's physical cursor through the existing mirror reader,
maps it to the UI canvas and retains that point across the frame's service
reads. Active XR press/hold/release and XR scrolling keep their target. Invalid,
off-window, background or failing desktop reads retain the existing route.
The mirror reader is shared with the HUD panel; no native ABI change.

Five focused CTests pass (menu input, gameplay UI, HUD panel, Lua
compile/invariants), including both shared service entry points, coordinate
mapping, immutable repeated reads and gesture priority; all 36 chunks compile.
The integration fixture first needed to drain the preceding XR release before
expecting desktop ownership. This addresses the source-level wheel mismatch,
not proof of the historical live scroll/drag cause. Desktop drag release and
possible duplicate mouse-edge transport remain to investigate. Undeployed;
continue the todo, with full build/suite baseline still `df99611`.

Integration checkpoint `6c79aec`: **111/111 offline CTests pass**, including
watcher cleanup and the desktop-wheel candidate. Native code is unchanged from
the full Release build at `df99611`. Evidence:
`artifacts/unattended/continuous-todo-full-ctest-6c79aec-20260907.log`.

## Continuous todo work: desktop mouse phases and duplicate transport

Branch `codex/menu-mouse-gesture-2026-09-07` extends the physical desktop cursor
snapshot to stock left/right/middle press, hold and release. The first mouse
event and release frame no longer need a later XR-publisher coordinate sample.
Active XR gestures retain the existing precedence. The native harness no longer
ORs the desktop left-button level into the XR primary edge state machine: stock
already delivers that mouse event, and the second asynchronous route could
replay it. Controller and explicit named-test edges, desktop fallback/held
coordinate selection and the transport ABI remain.

The Lua regression reproduced a mouse press using the unrelated controller
point before the fix. All nine mouse phases and an installed-service drag check
now retain the immediate desktop point, one stock press/release and subsequent
controller cursor return. This uses an independent simulated XR input stream;
it is not live end-to-end timing evidence. Release XR harness builds and six
focused CTests pass (menu, HUD, panel pointer, injector, Lua compile/invariants),
with 36 chunks compiling. The Lua/harness pair remains undeployed; the historical
live scrollbar failure is not declared resolved. Full-suite baseline remains
111/111 at `6c79aec`; full Release baseline `df99611`, newer harness built here.
Continue the todo without requesting worn verification while the user is away.

Follow-up on the same branch reproduces a desktop drag/release crossing the
window edge and jumping to the controller cursor. Finite off-window coordinates
now map outside the UI canvas, preserving stock drag and hit-test behavior.
Invalid dimensions, background windows and failing reads still fall back as
before. The new boundary regression and all six focused checks above pass;
36 Lua chunks compile. This remains an undeployed candidate.

## Continuous todo work: recorded objective-device input

Branch `codex/objective-input-stock-contract-2026-09-07` extends the optional
stock input-history fixture through the actual minigame input method. Both
client and server readers consume eleven recorded frames containing primary,
interact and jump holds/releases, alternate cancellation, stick quadrants/zero,
stock dodge arbitration, weapon-action blocking and loss of the wielded device.
Changing live hand aim does not alter the device's stock view or axis columns.
The first fixture run exposed a retained sender frame from the preceding test;
resetting the independent pipeline's sent-frame marker fixes that fixture setup.
No production change was required by these cases.

Optional stock fixture passes both with and without the VR module arguments.
Four focused CTests pass (online rules, controller bindings, gameplay ownership,
scanner stick reference). Device outcomes, animations and weapon execution are
sinks; no real objective, network serialization or headset acceptance. Continue
offline todo work while renderability remains blocked. Full suite remains
111/111 at `6c79aec`; full Release build `df99611`, newer XR harness `f201a9a`.

## Continuous todo work: scanner transition lookup

Branch `codex/scanner-transition-lookup-2026-09-07` protects the complete current
player/state lookup used by optional hand-relative movement. The existing
protected state-name query did not cover obtaining the player or extension;
a retiring lookup could throw out of fixed input caching. Both failures are
reproduced in the real movement-seam fixture and now retain its existing
missing-state locomotion fallback. Valid minigame axes stay direct and valid
walking axes retain hand-relative rotation. No new input admission policy.

Five focused CTests pass (scanner stick, online rules, gameplay ownership,
Lua compile/invariants); all 36 chunks compile. Undeployed, with no live
transition acceptance. Continue the todo while the user is away.

## Continuous todo work: character input ownership

Branch `codex/character-input-owner-2026-09-07` extends the mapper's weak owner
record from the input handler to its live local character unit. Actual stock
`HumanGameplay.pre_update` replaces unit/orientation components without creating
a new input handler. The real adapter regression reproduced a held attack
surviving that replacement. Replacement now drains input and requires neutral
rearming, and a missing/non-live unit remains inactive. A changed unit between
pre-update and fixed caching cannot inherit the old sample. Protected lookup
retains strict current-player/current-handler ownership and stock caches.

Six focused checks and the **full 111/111 offline CTest suite pass**, with all
36 Lua chunks compiling. Evidence:
`artifacts/unattended/continuous-todo-character-owner-ctest-20260907.log`.
No native code changed; full Release baseline remains `df99611`, with the newer
XR harness built at `f201a9a`. Unit liveness is engine object liveness, not proof
of health-state/spectator gameplay acceptance. This remains undeployed; continue
the todo without waiting for worn verification.

## Continuous todo work: movement table construction

Branch `codex/movement-cache-allocation-2026-09-07` removes three temporary
table constructions from the ordinary fixed movement merge and two scratch
arrays from online-rules movement conversion. Scalar locals retain neutral
keyboard/gamepad channels, component clamping, partial action maps, held-action
routing and diagnostics. Online conversion still validates all packed values
before writing movement and aim together. No live allocation/FPS claim.

The real fixed-cache fixture passes before and after the refactor with neutral
overlapping keyboard channels, mixed opposing/saturated stick input, untouched
older entries, missing channels, held attacks and UI cancellation. Six focused
CTests pass, all 36 chunks compile, and both optional stock input/rules fixtures
pass (including recorded objective-device inputs). Full suite remains 111/111
at `968df68`; full Release baseline `df99611`, newer XR harness `f201a9a`.
Undeployed; continue the todo while the user is away.

## Continuous todo work: stock shared menu hints

Branch `codex/menu-hint-stock-contract-2026-09-07` adds optional actual-stock
formatter and input-legend execution to the menu hint fixture. Alias lookup,
hold/release wording, localization context, tint, patterns, suffixes, width
invalidation and clickable-callback ownership pass; no callback is activated.
Three focused CTests pass. No production change or talent-specific patch.

The refreshed hint inventory is 138 calls/47 files, with 108 dynamic action
expressions and four raw-key formatters. Its two user acceptance cases remain
pending. Gamepad-only hidden labels, raw chat keys and unsupported spectator
cycling are not relabelled as controller routes. Current evidence is
`artifacts/unattended/ui-binding-hint-audit-current-20260907.json` and the
optional command in INPUT-REVISION-AUDIT. Localized/device text is substituted;
no rendered label/readability acceptance. Continue the todo; full-suite baseline
111/111 at `968df68`, newer movement changes have focused passing checks.

## Continuous todo work: stock projectile spawning

Branch `codex/projectile-stock-spawn-2026-09-07` extends the optional stock-rules
fixture through actual projectile firing and current/cached spawn-parameter
readers after the existing shot-preparation test. Eight client/server,
immediate/cached and explicit/default combinations preserve prepared origin and
direction, cached ballistic values where stock chooses them, projectile/weapon
metadata, owner/critical/side fields and server-only spawning. Optional proc
metadata and the no-proc-table branch pass. Trajectory calculation and final
proc/spawn endpoints are sinks; no live collision, damage or server acceptance.

The optional stock-rules fixture passes. No production change was needed.
The three most recent saved console logs did not identify the user's purchased
gun templates; the exact loadout remains unknown. Existing requested weapon
inventory diagnostics were reviewed, not armed or run. Continue the todo with
full-suite baseline 111/111 at `968df68`; no live launch or deployment.

## Continuous todo work: stock replay dispatch

Branch `codex/stock-replay-dispatch-2026-09-07` executes actual extension-manager,
holder and base-system correction/replay dispatch against the recorded VR input
fixture. Three old frames run in order, with correction notification first and
the stock input reader before the consuming simulation. Old action, movement
and aim stay paired while current hand lookup deliberately throws if read.
No capture or packet send occurs. A subsequent empty-unit replay verifies that
the stock temporary maps/lists do not retain the previous unit's systems.

The expanded optional input fixture passes; no production change. Correction
component data and the simulation consumer are supplied, so engine rollback
and real correction convergence remain untested. This is additional source
orchestration evidence, not remote mission admission. Continue the todo while
the user is away; full-suite/build baselines and live blocker are unchanged.

## Continuous todo work: stock correction boundary

Branch `codex/stock-correction-boundary-2026-09-07` connects actual stock
unit-data correction and component copying to the replay fixture, with stock
input-handler acknowledgement/panic methods. A supplied number/boolean/array
schema covers mismatch restoration, next-ring copy, action notification,
resimulating lifetime, matching state, duplicate/old snapshots and future/expired
snapshot rejection before component reads. In-window recovery clears the stock
panic state. The optional stock input fixture passes with no tracking recapture.

No production change. Game-object decoding, schema, clock effects, telemetry
and the simulation consumer are fixtures. Engine vector/quaternion userdata
restoration and live convergence remain unverified. Continue offline work;
full-suite baseline 111/111 at `968df68`, native build baselines unchanged.

## Continuous todo work: Guardian preference recovery

Branch `codex/quest-boundary-recovery-2026-09-07` records a verified ADB
Guardian pause/resume route from the installed SideQuest implementation, alongside
Meta's documented MQDH development Boundary switch. Guardian's own logs confirm
the preference changing and restoration. The older system property query stays
blank and cannot verify this route. See QUEST-PASSTHROUGH-RECOVERY for the command.

The immediate Ready attempt ran before pause completion and saw no HMD. A settled
15-second attempt with logged Guardian pause reached session creation, then
failed with the existing VDXR swapchain error `-7000`. Guardian was restored with
logged `1 -> 0`, and proximity Enable/Status ran in `finally`. No deployment or
Darktide launch; double-tap cause and tracking recovery remain unproven. Continue
offline work; do not repeatedly retry the same runtime failure without new evidence.

## Continuous todo work: HUD editor request ownership

Branch `codex/hud-editor-request-owner-2026-09-07` ties a queued editor request to
the HUD that accepted it. Menu-close delivery rechecks display readiness and
both retained/current-update ownership, cancelling across HUD replacement,
foreign update or display loss. The request cannot revive when the old owner
returns. Existing second-click cancellation and ordinary menu-close delivery
remain intact.

The real module fixture reproduced editor opening after display readiness was
lost. Four focused CTests pass after the fix, including HUD routing/options and
Lua compile/invariants; all 36 chunks compile. The replacement-before-draw case
also runs the actual registered HUD update hook. Undeployed; live menu/editor
transition and saved-position acceptance remain pending. Continue the todo.

## Continuous todo work: deployable placement contracts

Branch `codex/stock-deployable-placement-2026-09-07` extends the optional
stock-rules fixture through actual deployable aim, base action and pickup spawn
methods. Simulated pose feeds forward/downward/forced rays; stock slope and
registered-attachment checks remain. Cached placement avoids live pose reads,
retry defers spawning, ammo gates retain stock timing, and only the server
spawns pickups. Owner/session metadata and drop/training callbacks pass.

The optional stock-rules command passes. No production change. Ray responses,
fixed-time rounding and final service endpoints are fixtures; real geometry,
item consumption and remote acceptance remain pending. Continue the todo with
the existing full-suite/build baselines and unresolved VDXR rendering blocker.

## Continuous todo work: teammate supply transfer

Branch `codex/stock-pocketable-transfer-2026-09-07` executes stock ally target
retention/cancellation, give action and recipient-slot validation in the optional
stock-rules fixture. Transfer timing rechecks recipient liveness, human ownership
and free slot before removing the item; server-only equip/assist/effect/voice
calls remain. Missing definitions/targets and replay skip transfer. No new
binding is needed: stock shared pocketables use the existing weapon-special hold.

The optional stock-rules fixture passes. Smart-targeting results, fixed-time
rounding and final inventory/notification endpoints are supplied. No production
change or live teammate acceptance; continue the todo while the user is away.

## Continuous todo work: bounded rendering preflight

Branch `codex/xr-preflight-timeout-2026-09-07` bounds the Ready smoke process at
90 seconds. Both output pipes drain asynchronously. Timeout terminates only the
child process started by that invocation, records timeout/completeness fields,
and cannot pass because of an earlier `result=pass` line. Ordinary nonzero exit
remains a failure. The helper opens no console window and does not restart VD.

Real isolated child-process tests cover output beyond pipe capacity on stdout
and stderr, nonzero exit, a stalled process after an early pass marker, child
termination and the actual preflight result-classification block. Five focused
checks and the **full 112/112 offline CTest suite pass** (14.31 seconds), including
all 36 Lua chunks. Evidence:
`artifacts/unattended/continuous-todo-xr-timeout-ctest-20260907.log`.
No headset was awakened for these tests; the runtime blocker remains. Continue
the todo until instructed to stop.

## Continuous todo work: false-held release boundary

Branch `codex/stock-held-release-boundary-2026-09-07` confirms the existing
cancellation caveat by executing stock melee/pocketable release elements after
a real mapper remap. Holds and explicit release edges clear, but stock parser
elements can complete on `held=false`. Comments now describe edge suppression
precisely; runtime behavior is unchanged. No universal charge-cancellation claim,
forced holster or client-only action reset. Actual hierarchy/weapon outcomes
remain untested by this element-level fixture.

The optional stock-input fixture passes. This refines the online/transition
acceptance boundary and does not admit remote missions. Continue the todo;
full offline suite remains 112/112 at `124361b`, with native build baselines
unchanged and later changes limited to this optional fixture/comments/docs.

## Continuous todo work: stock input-service gate

Branch `codex/stock-null-input-gate-2026-09-07` fixes controller admission when
stock supplies a null input service independently of ordinary UI ownership
(cinematic/ImGui paths in HumanGameplay). The registered pre-update hook forwards
its actual service; real controller delivery and the synthetic fire probe both
require a protected `is_null_service() == false` result. Missing/retiring services
block delivery, and controller cancellation/neutral rearming remain in place.

The adapter fixture reproduced stock-disabled input admitting controller actions.
Six focused CTests pass, including real registered-hook forwarding and protected
service queries; all 36 Lua chunks compile. This also prevents online aim capture
through its existing gameplay-active gate. Undeployed; the full-suite baseline
remains 112/112 at `124361b`. Continue the todo with no new live preflight attempt.

## Continuous todo work: swapchain failure evidence

Branch `codex/xr-swapchain-failure-evidence-2026-09-07`, implementation `03d60d1`,
adds failure-only XR projection texture request/device/debug-queue logging. The
Release harness builds; help, D3D12 smoke/resize and bounded-process checks pass.
This is the newest harness build, superseding `f201a9a`; full native build
baseline remains `df99611`.

One settled Ready attempt with verified Guardian pause collected the new fields:
first eye, recommended 2496x2688, format 29, one sample/layer/face/mip, usage 33,
application device removal reason 0 and zero D3D12 debug messages. VDXR still
failed creating its texture with `-7000`. The smoke exited 1 without timeout and
captured complete output. Guardian restored with logged `1 -> 0`; proximity
Enable/Status ran in `finally`. No Darktide launch/deployment or texture fallback.
See QUEST-PASSTHROUGH-RECOVERY; the runtime's internal cause remains unknown.
Continue useful offline work instead of repeating unchanged smoke attempts.

## Continuous todo work: cached catalogue and shotgun batches

Branch `codex/stock-shotgun-pellets-2026-09-07` reads the local game's HTTP
cache read-only. It contains a general item catalogue (version 135417), not an
owned-inventory response. Thirty non-empty ranged templates are tagged for
Psyker and all thirty have matching source files in the audited snapshot.
Direct action kinds identify 22 hitscan, four pellet and four staff templates;
this is not a list of the user's purchases or proof of current feature access.
Ignored derived evidence: `artifacts/unattended/psyker-cached-catalogue-20260907.json`.
No headers, connection information, account identifiers or full catalogue were
copied into Git. The actual owned gun models remain unknown.

The optional stock-rules fixture now executes shotgun shooting, count/state
progression and special-shell selection. Constructed 4/4/1 and 2/2/1 pellet
batches preserve grouped aim, all shell parameters, rewind/filter arguments and
final processing/proc metadata. Spread/collision/damage endpoints are supplied;
no live pellet distribution or damage acceptance. The fixture passes; no
production change. Continue the todo with the existing suite/build baselines.

## Continuous todo work: hitscan effects and hit ordering

Branch `codex/stock-hitscan-effects-2026-09-07` extends the optional stock-rules
fixture through actual hitscan shooting after VR input, simulated pose and stock
shot preparation. Twenty constructed cases cross local/remote and client/server
ownership with default or combined collision tests, empty hits, power fallback,
charge thresholds, optional proc/chain dispatch and effect endpoints. Combined
ray/sphere results sort by both supported distance layouts before processing;
shot-result fields overwrite stale values. Stock origin, charge and prediction
arguments reach the damage sink unchanged. The fixture passes. Engine rotation,
collision and damage are supplied, so this does not establish physical impacts,
network damage or all owned loadouts. No production change or new live attempt.

## Continuous todo work: authoritative status refresh

Branch `codex/current-status-refresh-2026-09-07` updates CURRENT-STATUS and the
ordered todo with the current validation/build baselines, Guardian restoration,
texture failure, input ownership and catalogue/stock-contract scope. Historical
entries remain historical; worn and remote-server acceptance remain pending.
Draft review #2 now includes changes through `3f1bfbb`. Continue the todo.

## Continuous todo work: fixed-frame input service ownership

Branch `codex/fixed-input-service-owner-2026-09-07` closes the corresponding
fixed-frame gap after `9f254d0`. Stock selects its service for each fixed call,
so a null service can follow an earlier accepted render sample. The actual-hook
regression reproduced movement merging in that case. The hook now cancels
mapper/UI/synthetic state before touching controller history or online aim.
Null, missing and retiring services preserve stock cache contents; later valid
fixed calls cannot restore held input without a new neutral render sample.
Six focused CTests pass, including 36-chunk compilation. Undeployed; full-suite
and native build baselines are unchanged. No universal charged-action
cancellation claim: stock held=false rules still apply. Continue the todo.

## Continuous todo work: offline graphics isolation

After `596c459`, the integrated suite exposed a test-configuration gap: although
headset tests were disabled, the two ordinary D3D12 smoke tests constructed the
OpenXR probe by default. Both unexpectedly created a headset session and failed
at the known texture boundary; 110/112 passed. Sessions were destroyed and no
Guardian/proximity settings or game deployment were performed by those tests.
Earlier 112/112 results were state-dependent and did not prove this isolation.
Failed evidence: `artifacts/unattended/continuous-todo-fixed-input-ctest-20260907.log`.

Branch `codex/offline-graphics-test-isolation-2026-09-07`, implementation
`e2aa82a`, adds explicit `--no-openxr` before runtime discovery and uses it in
both desktop smoke tests. XR requests conflict with this mode before discovery
or device construction. Twelve real process cases cover both argument orders;
the smoke tests reject unexpected discovery/session markers. Normal launch and
Ready defaults are unchanged. The Release harness builds and the full suite
passes **113/113 in 14.84 seconds**, including all 36 Lua chunks. Evidence:
`artifacts/unattended/continuous-todo-offline-isolation-ctest-20260907.log`.
This supersedes the integrated suite and harness baselines, not the full native
producer build at `df99611`. No new live recovery attempt. Continue the todo.

## Continuous todo work: exact VDXR backend error boundary

Branch `codex/vdxr-last-error-diagnostic-2026-09-07`, implementation `4298262`,
adds a failure-only query of the already loaded Virtual Desktop backend's
thread-local last-error text. Exact installed VDXR source confirms its failing
OVR call uses an internal D3D11 device; our D3D12 diagnostics cannot inspect that
device. The Release harness builds and four focused offline checks pass. This
is the newest harness build; full suite remains 113/113 at `e2aa82a`.

A new bounded Ready attempt at 13:15 collected empty backend error information
and the same first-eye texture failure. Guardian and proximity restored, no
game/deployment. The source also explains the absent optional accessibility
file's warning; it is not a proven corruption to repair. Exact sources, limits
and evidence paths are in QUEST-PASSTHROUGH-RECOVERY. Continue offline work.

## Continuous todo work: launcher cleanup continuation

Branch `codex/launcher-cleanup-continuation-2026-09-07` fixes sequential cleanup
in `start-darktide-vr.ps1`. A failed early file restoration previously skipped
all later flags, run-owned game cleanup and Psykhanium request retirement. Each
independent cleanup step now runs despite earlier errors; billboard flag and
binary restoration are separate steps. The startup helper handle disposes in
its own `finally`. Cleanup errors aggregate after all steps. An existing launch
exception remains primary and cleanup errors are warnings; an otherwise
successful launch fails if cleanup did not complete.

The actual finalizer fixture reproduces the skipped flag before the fix. It
covers normal completion, one/multiple cleanup failures, original-error
preservation, later request retirement and preservation of pre-existing or
wrong-path game processes. Eight focused CTests pass in 5.95 seconds, with
file/process endpoints mocked; no installation, process kill or live XR run.
The configured suite now has 114 tests; the latest full baseline remains
113/113 at `e2aa82a`. Harness remains `4298262`. Continue the todo.

## Continuous todo work: alternate-library shortcut path

Branch `codex/launcher-game-root-forwarding-2026-09-07` adds optional GameRoot
forwarding to the ordinary launch wrapper and shortcut generator. A supplied
shortcut path resolves literally and must contain `binaries/Darktide.exe`; it
is quoted in the shortcut arguments. Omitted GameRoot preserves the existing
start-script default, and ordinary launch/authentication settings remain.
Both edited PowerShell scripts parse and the diff check passes. No shortcut was
installed and no game files changed. This closes a development setup gap; it
does not provide a clean installer or complete portable-release acceptance.

## Continuous todo work: stock ledge and vault ownership

Branch `codex/stock-vaulting-contract-2026-09-07` extends the optional stock-rules
fixture through actual first-person ledge dispatch, ledge discovery entry and
vault admission. Three yaw headings, grounded/airborne offsets, absent/present
collisions and significant obstacles retain stock direction/filter/flag rules.
Resimulation retains existing ledge results without another physics query.
Supplied ledges cover reverse selection, height/distance boundaries, air limits,
zero/wrong-direction movement and the luggable restriction. The complete
optional stock-rules fixture passes with the pinned LuaJIT validator.

Finding: ledge discovery uses recorded simulation aim before recoil, so the
online-rules candidate searches toward the hand even when walking remains
head-relative. This is an explicit traversal limitation, not a client-only
direction change to make silently. Collision responses, ring indices and
yaw-only math are substitutes; no real geometry, pitched traversal, climbing or
live server acceptance. No production code or deployment changed. The offline
full-suite baseline and harness build remain unchanged. Continue the todo.

## Continuous todo work: automatic gameplay stereo evidence

Branch `codex/unattended-stereo-evidence-2026-09-07` adds a launcher delivery
requirement for `AutoEnterHub` and `EnterPsykhanium`; direct runner callers can
select `RequireSharedStereo`. The viewer's ordinary success can mean only flat
fallback, so these runs now also require its completed shared-eye presentation
summary with nonzero fresh shared pairs and submitted frames. Missing,
duplicate, invalid or zero summaries fail. Live progress lines and reused-frame
counts cannot substitute. Nonzero harness exit and abnormal game exit remain
the primary failures; ordinary manual/menu-only launches retain their behavior.

Eight focused offline CTests pass in 3.08 seconds, including the real start
argument expression and evidence parser. All three edited production scripts
parse successfully. Configured suite count is now 115; full baseline remains
113/113 at `e2aa82a`, harness `4298262`. No game, deployment or headset action.
This verifies delivery counters only: fresh Lua initialization must still be
checked in the current game log, and worn visual acceptance is pending.
Continue the todo; no stop instruction has been received.

## Continuous todo work: spectator consumer audit

Branch `codex/spectator-input-ownership-audit-2026-09-07` records the actual
direct `spectate_next` consumer and stock death/hogtied/rescue/safe-zone camera
ownership. No VR route exists yet, and fixed combat-cache delivery alone would
not reach it. A separate scoped local-player route must work when the character
is unavailable while retaining UI/null-service/cinematic exclusion. The first-
person observer root also follows the target unit's interpolated aim; ordinary
local HMD independence does not cover that camera branch. Source references
and acceptance gaps are in MISSION-INTERACTION-AUDIT. Documentation only, no new
tests or live actions; runtime/build validation baselines remain unchanged.

## Continuous todo work: melee probe reference-history ownership

Branch `codex/melee-probe-reference-history-2026-09-07` fixes the diagnostic
probe's trajectory key, which previously changed for weapons/actions but not
bridge replacement or headset recenter. It now also observes controller
transport generation, recenter generation and the resolved physical hand.
Stable samples retain history; changed references start a fresh trajectory
without replacing the simulation tick owner. No cooldown or damage path changes.

The actual live-adapter regression fails before the fix on publisher replacement
and passes afterward, including stable/recenter/physical-hand cases. Seven
focused CTests pass in 0.82 seconds: live probe, diagnostic orchestration,
simulation, sweep planning, hand roles, Lua source invariants and all 36 chunks
through the pinned compiler. Existing orchestration coverage confirms changed
keys do not sweep across the preceding trajectory. No deployment/headset work;
full suite remains 113/113 at `e2aa82a`, configured count 115, harness `4298262`.
The non-damaging probe remains opt-in and contact acceptance remains with the
user. Continue the todo.

## Continuous todo work: melee probe correction recovery

Branch `codex/melee-probe-correction-history-2026-09-07` closes the corresponding
diagnostic replay gap. Skipping a replay query previously retained the preceding
trajectory, allowing the next live sample to sweep across a correction. Replay
now clears only the old pose; the simulation ledger remains intact. The first
recovered tick uses a fresh pose, and repeating that tick still cannot query.
The regression fails before the fix and passes after it. Six focused CTests,
including all 36 chunks through LuaJIT, pass in 0.78 seconds. No damage path,
network behavior, deployment or headset action changed. Continue offline work;
the full-suite and harness baselines remain unchanged.

## Continuous todo work: melee probe geometry recovery

Branch `codex/melee-probe-volume-recovery-2026-09-07` fixes permanent waiting
after invalid geometry recovers within the same named attack. The regression
reproduces the missed recovery before the fix. Valid recovery now restores the
volume, clears the old reason and starts fresh trajectory history; stable
geometry retains that history. Invalid volumes still perform no queries. Five
focused CTests pass in 0.77 seconds, including the 36-chunk LuaJIT gate.
No physical damage, deployment or live acceptance change; continue the todo.

## Continuous todo work: Windows runtime event evidence

Branch `codex/quest-event-log-check-2026-09-07` records read-only Windows event
queries around the 13:15 Ready failure. The 13:10–13:20 Application/System
queries completed, with no matching runtime/graphics events across all levels.
This supplies no new root cause. The current token is not elevated; the official
WPR trace procedure remains unstarted. No XR session or device setting changed.
Continue offline work rather than repeating an unchanged failing Ready attempt.

## Continuous todo work: actual Quest double-tap event gate

Branch `codex/quest-shortcut-settings-audit-2026-09-07` traces the installed shell
APK's actual double-tap handler. Standard ADB settings only surfaced an Android
wake gesture; the matching FUSE property is unrelated storage configuration.
The shell instead reads `passthrough_on_demand_enabled` from Meta's preference
service before forwarding sensor events. A separate feature/config gate can
re-enable that preference under its setup conditions, so it is not a verified
persistent-disable recipe. The preference service denied ADB's diagnostic dump;
no identity/root workaround or preference change was attempted. Exact software
version/hash, method evidence and primary Android links are recorded in
QUEST-PASSTHROUGH-RECOVERY. APK/disassembly are ignored local inspection artifacts.
Read-only inventory/inspection only; no XR session or device setting change.
Rendering and the suspected accidental trigger remain unresolved. Continue work.

## Continuous todo work: retiring game-mode lookup

Branch `codex/game-mode-lookup-retirement-2026-09-07` protects method lookup as
well as invocation in the main game-mode predicate. A retiring proxy previously
raised before the existing call guard. The actual main predicate regression
reproduces that failure and now passes for missing/invalid/throwing owners,
non-string results, inherited receivers and mode changes. Six focused CTests
pass in 0.82 seconds: gameplay context, ranged aim, online rules, gameplay UI
ownership, source invariants and the 36-chunk LuaJIT gate. No deployment or live
transition acceptance; full offline baseline remains 113/113 at `e2aa82a` with
115 tests configured. Continue the todo while live rendering remains blocked.

## Continuous todo work: actual stock spectator lifecycle

Branch `codex/stock-spectator-contract-2026-09-07` adds an optional source
contract for actual local service selection, camera update, human roster
selection and observer aim. Normal/hogtied/rescue/death/safe-zone transitions,
unavailable/removed owners, lost targets, UI/ImGui and cinematics pass. Stock
selection excludes bots; safe-zone death does not continuously consume cycle
input. See MISSION-INTERACTION-AUDIT for the command and fixture limits.
No production change, deployment or visual acceptance. The existing combat
mapper resets without a live character, so a spectator route needs separately
admitted sampling rather than reusing its cleared held output. Continue work.

## Continuous todo work: scoped spectator controller route

Branch `codex/spectator-controller-route-2026-09-07` implements camera-only
cycling using the jump binding (A by default), independent native input state,
fresh sample generation/axes and matching cached hints. Current local
camera/player/service ownership, observer/dead mode, existing local-authority
policy and neutral rearming are required; no character object is required.
Only the stock camera call receives the extra action. Combat holds/cancellation
and stock rescue/death/target/camera-orientation rules remain independent.

Validation on Windows x64: full Release build succeeds; CTest passes 116/116 in
15.52 seconds with headset tests OFF and desktop tests explicitly skipping XR.
The pinned gate compiles all 37 Lua chunks. Actual native exports verify camera
and combat edge independence, cancellation/rearming, publisher replacement,
sample metadata and stale input rejection. Portable Lua covers foreign/retiring
owners, UI/null services, mode/service changes, remaps/directional controls,
hint refresh, stock errors and old-DLL fallback. The optional stock spectator
contract with all three module paths also passes real VR-driven cycling and
stock UI/rescue transitions. Log: ignored
`artifacts/unattended/spectator-route-ctest-20260907.log`.

This paired native/Lua candidate remains undeployed. Rendering remains blocked
at the existing first-eye failure; no new Ready attempt or device setting change.
Fresh stereo initialization and nonzero shared_ready will still be required
after future deployment. Observer comfort, live input and mission lifecycle
are pending the user; continue the todo without claiming worn acceptance.

## Continuous todo work: generated health configuration boundaries

Branch `codex/generated-health-session-boundaries-2026-09-07` fixes timing and
focus history spanning an explicit generated-bridge disable/re-enable. Each
transition now resets its health window and is logged; repeated configuration
preserves the current window. Health also rechecks enablement under its lock.
The actual native regression fails before the fix and passes after it, checking
a disabled interval longer than the reporting period and clean resumed timing.

Release native DLL, ring and continuous-recovery targets build. Seven focused
CTests pass in 2.87 seconds: native health session, health analyzer, original
ring/UI ring, continuous recovery, native hooks and generated frame state.
The suite now has 117 configured tests; last full pass remains 116/116 at
`2790e7d`. No Lua change (37-chunk baseline), deployment, XR or device setting
change. Explicit bridge configuration does not identify the game's FG setting;
this is measurement correctness, not a measured performance fix. Continue work.

## Continuous todo work: health counter regression

Branch `codex/generated-health-counter-regression-2026-09-07` prevents unsigned
FPS subtraction after a surface/fence publication counter drops below its window
baseline. The reporter starts a fresh window and emits a timing boundary; the
Python summary counts it and breaks generation-counter continuity. Actual native
and analyzer regressions reproduce both old failures. Native DLL/ring/recovery
targets build; seven focused checks pass in 3.92 seconds. Full baseline remains
116/116 at `2790e7d`, configured count 117. No live resize, deployment, headset
action or measured performance claim. Continue the todo.

## Continuous todo work: live tracking for melee queries

Branch `codex/melee-live-tracking-gate-2026-09-07` fixes the diagnostic probe
using held IK availability as contact authority. The actual adapter regression
reproduces a stale pose after live grip tracking becomes false. Query admission
now requires the resolved physical hand's live tracking flag as well as its
usable pose; false/missing tracking never reads that held target. Recovery and
physical-hand changes pass while IK retention is untouched. Six focused CTests
pass in 0.82 seconds, including all 37 Lua chunks and existing invalid-tracking
history/query tests. No damage, native change, deployment or worn acceptance.
Last full suite remains 116/116 at `2790e7d`; latest native build `01617d6` and
configured count 117. Continue the todo.

## Continuous todo work: actual stock melee timing boundaries

Branch `codex/stock-melee-timing-contract-2026-09-07` adds an optional actual
ActionHandler timing/chain contract. Sixteen threshold cases pass, along with
additive buffs, handling, stock gameplay caps and conditional admission checks.
Engine network bounds, routes, inversion membership and availability endpoints
are supplied fixtures; see MELEE-TIMING-AUDIT for the command and limits. No
production/native change or deployment; continue the todo. Runtime Lua remains
`42d4d53`, native build `01617d6`, full suite 116/116 at `2790e7d`, configured 117.

## Continuous todo work: rejected-step melee trajectory recovery

Branch `codex/melee-invalid-step-history-2026-09-07` clears diagnostic trajectory
history after nonadvancing time, malformed steps or malformed requests. The
actual orchestration regression reproduced an old trajectory across a rejected
clock sample. Recovery now starts fresh, while ordinary duplicate ticks preserve
history and the simulation tick ledger remains intact. Six focused CTests pass
in 0.80 seconds, including all 37 Lua chunks. No damage/native change, deployment
or live acceptance. Continue the todo; full/native baselines remain unchanged.

## Continuous todo work: Steam game-folder discovery

Branch `codex/steam-game-root-discovery-2026-09-07` removes the machine-specific
default from the ordinary start script and development sync. A read-only helper
uses Steam registry roots, modern/legacy library lists and the Darktide manifest;
explicit GameRoot takes priority. It rejects malformed metadata/invalid folders,
deduplicates paths, ignores stale installations without the executable and
requires a choice when several valid copies exist. Shortcut defaults inherit
discovery; other standalone diagnostics retain their own parameters.

Windows PowerShell 5 fixtures cover modern/legacy libraries, spaces/apostrophes,
explicit selection, ambiguity, stale metadata, invalid app identity, traversal,
duplicate keys and malformed grammar. Read-only real discovery locates the
existing installation. Ten focused launcher/source CTests pass in 3.67 seconds;
the final absolute-library-path restriction also passes the discovery fixture.
Early-failure testing uses an inert fixture executable and still cannot arm a
range launch before prerequisites pass. Fixture cleanup is confined to its newly
created artifacts/tests subtree. No shortcut creation, deployment, game launch,
headset action or clean installation occurred.

Configured count is now 118; full baseline remains 116/116 at `2790e7d`, latest
native build `01617d6`, runtime Lua `2d44cdc` (37 chunks). Continue the todo.

## Continuous todo work: melee probe owner collection

Branch `codex/melee-probe-owner-release-2026-09-07` removes the strong cached
weapon/action references that could retain a retired extension through stock
ActionWeaponBase's back-reference. The pinned LuaJIT regression reproduced that
weak-key/value cycle. Weak context values now allow both objects to collect;
explicit weapon-presence state also clears a cached volume when an empty slot's
weak reference has already disappeared. That recovery edge has its own failing
then passing regression. Six focused CTests pass in 0.81 seconds, including all
37 chunks. No damage/native change, deployment or live memory/visual claim.
Full baseline remains 116/116 at `2790e7d`, configured count 118. Continue work.

## Continuous todo work: portable readiness game selection

Branch `codex/preflight-steam-discovery-2026-09-07` applies the existing Steam
discovery helper to the required readiness preflight. Explicit GameRoot still
takes priority; resolution and executable validation precede any device access.
PowerShell parsing, the discovery and source-invariant CTests, and the seven-case
readiness fixture pass. No live preflight, headset change or deployment was run.
The other weak-key caches inspected did not show the melee probe's owner cycle;
no speculative cache changes were made. Continue the todo.

## Integrated validation at 15:22 Brisbane

Full Windows x64 Release build and all 118 configured CTests pass through
`5ffb1a7` in 18.49 seconds. This integrates the native health boundaries, melee
tracking/history/collection fixes and Steam discovery with the spectator baseline.
Headset tests remain OFF; desktop graphics tests explicitly skip OpenXR.
Evidence: `artifacts/unattended/integrated-118-ctest-20260907.log`. This supersedes
the previous 116-test full baseline; no deployment or live readiness was run.
Runtime Lua remains `5906ba9`, native source `01617d6`, XR harness source
`4298262`. Continue working until instructed to stop.

## Continuous todo work: optional menu renderer error cleanup

Branch `codex/menu-renderer-error-retirement-2026-09-07` restores temporary
crafting/system view renderers and begin/end pass fields after stock or diagnostic
errors, then propagates the original error. Failed queue setup remains retryable
in the same UI frame. The actual-hook regressions fail before the fix and pass
afterward, including nesting and bypass. Five focused CTests pass in 0.83 seconds
with 37 Lua chunks. Configured count is now 119; the last full baseline remains
118/118 at `5ffb1a7`. No native change, deployment, live recovery or visual claim.
Continue the todo; normal proximity remains restored.
