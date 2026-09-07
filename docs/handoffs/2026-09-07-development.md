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
