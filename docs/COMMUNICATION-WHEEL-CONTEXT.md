# Owned communication-wheel context

## Coordinating adapter

`darktidevr_communication_wheel.lua` connects gesture, context and navigation
ownership around the stock HUD methods. Main now loads it through
`darktidevr_communication_input.lua`, which samples the physical hold before
turning and virtual stick actions and supplies the same claim to both. The
adapter registers intentional releases through the game's physics-safe queue.
This source candidate is not deployed to the accepted installed build.

The new **Hold communication wheel** action starts unassigned. Combat and hub
profiles share the normal binding system, including physical aliases; navigation
axes cannot bind the wheel itself. Invalid saved or legacy axis assignments are
ignored at resolution. Prompts report only usable physical assignments. Preparing
the profile before gesture sampling keeps its owner revision consistent with the
following gameplay sample. Remaps, local handler/unit replacement, world/mode,
transport/recenter generation, tracking loss and blocked input invalidate old
deferred ownership. Mod disable/unload and fixed-update null input cancel it.
The deferred guard also checks ImGui ownership independently of normal UI.
A reproduced regression admitted a release when ImGui opened after sampling;
active or retiring ImGui managers now invalidate it. Six focused communication
and production-input checks pass in 0.10 seconds; all 68 chunks compile.

Deferred release now also protects both lookup and execution of the HUD input's
null-service queries. A retiring proxy previously threw before cancellation,
leaving the owned release queued. Query, lookup and null-proxy failures now
cancel without firing a communication effect or leaving the wheel context owned.
The regression failed before the fix. Six communication/production-input CTests
pass in 0.11 seconds, all 69 chunks compile, and the actual cached stock wheel
callback fixture passes with every communication effect mocked. This follow-up
must be ported to focused communication PR #129 before its live trial.

The button remains available to any other actions deliberately assigned to it.
For an initial worn trial, choose a free button to isolate wheel behavior, then
check deliberate aliases separately. No default mapping or installed settings
were changed by this development session.

The adapter admits only an idle local HUD, freezes selection on release, and
consumes the release token once at deferred execution. It rechecks ownership,
context and null input there; a regression caught input becoming blocked between
queueing and execution. Pending short taps retain ownership until they mature or
are cancelled. Closing retains the stick claim until neutral. Destroy, routing
loss and callback/update errors retire owned state and restore stock context.
Unscoped reentrant calls cannot advance the private wheel. Idle keyboard input
remains stock-owned; during a VR gesture its wheel hold is exclusive, while
unrelated service inputs and methods still forward to stock.

Validation: five focused CTests (`communication_|exclusive_gameplay_stick`) pass
in 0.08 seconds and all 67 Lua chunks compile. The optional cached-source run
executes the game's handle, close and release callback methods with all
communication effects mocked. This establishes offline lifecycle behavior,
not worn selection or live acceptance. The subsequent input fixture also covers
physical-only bindings, profile preparation, stale ownership, neutral rearm and
the same claim reaching the real turning/binding modules.

Integrated validation: the full offline suite passed 175/176 in 55.51 seconds;
the previous gameplay fixture lacked the new module loader. The extended fixture
loads the actual adapter and checks production call ordering, directional attack
suppression and neutral rearm. All five affected input checks pass after that
fixture update (0.14 seconds). All 68 source chunks compile. No installed Lua,
native binary, settings, headset or game state changed.

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-communication-wheel.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe artifacts/vendor/Darktide-Source-Code
```

## Context primitive

`darktidevr_communication_context.lua` isolates a VR hold
from stock pending taps and deferred release state. It does not add a binding,
hook the HUD or invoke any tag, voice or chat API.

`Context.acquire(hud, revoke)` accepts only an idle, living HUD with no active
wheel, close delay, wheel start, pending location tap or active tagging input.
It rejects a second claim even before stock has processed the first hold. It
temporarily installs a private wheel context, clears entry hover and replaces
hover-grace data so a new hold cannot inherit a prior route's selection.

The returned handle exposes:

- `current()` for checking the original HUD/context before a deferred callback.
- `finish()` to restore the prior stock context only after start, pending tap,
  wheel-active and close-delay state have all cleared.
- `cancel()` to retire ownership, invoke the supplied gesture revocation,
  clear every member of the owned context and invoke stock wheel closure.
  Cancellation restores the prior context only if it still owns the HUD field.
  Replaced contexts are preserved; destroyed HUDs skip engine cleanup. Repeated
  cancellation does nothing. Revocation and closure errors both survive, and
  retirement/restoration still run before the error propagates.

The caller must supply the gesture's real cancellation function and guard each
deferred release with both `current()` and `gesture.take_release(token)` at
execution time. Retaining an unguarded stock callback is unsafe. Callers must
not admit a new gesture while another input route owns the HUD; these structural
checks cannot infer input routing. An intentional release may create a delayed
tap: retain ownership until it executes or cancellation clears it. A cleanup
error requires caller recovery; this module does not retry engine callbacks.

The integrated candidate establishes one gesture/stick claim before turning
and virtual action sampling, routes held presentation through private navigation
vectors, freezes selection on release, and cancels on routing/owner loss.
Keyboard/gamepad coexistence and worn selection/cursor behavior still require
live acceptance after fresh Ready and deliberate focused deployment. Check
opening, selection in every sector, intentional release, cancellation without a
command, cursor cleanup, pending short taps and neutral return to turning.

Validation, 9 September: four focused CTests (`communication_|exclusive_gameplay_stick`)
pass in 0.06 seconds and all 64 Lua chunks compile with the pinned LuaJIT gate.
An optional cached-source fixture executes stock `_on_wheel_closed` and
`_handle_com_wheel` with the real gesture token state: cancellation closes once,
leaves no delayed tag and rejects duplicate deferred releases. Communication
side effects are mocked; no game, headset, network, voice or chat was invoked.

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-communication-context.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_communication_context.lua artifacts/vendor/Darktide-Source-Code
tools/stereo/test-darktide-lua-source.ps1
```
