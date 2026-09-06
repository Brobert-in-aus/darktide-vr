# Development continuation: 7 September 2026

The user resumed development and requested continued work until told to stop.
They are at work all day and cannot provide in-headset verification. Continue
automated checks and offline work; keep worn checks pending without waiting for
immediate feedback. The task has an active 20-minute heartbeat. Automation state
and device identifiers remain outside Git.

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
