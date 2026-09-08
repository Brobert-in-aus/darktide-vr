# Owned communication-wheel context

## Coordinating adapter

The unloaded `darktidevr_communication_wheel.lua` now connects gesture, context
and navigation ownership around the stock HUD methods. Its future caller must
sample a physical hold before both gameplay stick consumers, supply exact local
owner/generation/routing checks, and register callbacks through the game's
physics-safe queue. No main-module loading or binding is installed yet.

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
not worn selection or live input integration.

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-communication-wheel.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe artifacts/vendor/Darktide-Source-Code
```

## Context primitive

The unloaded `darktidevr_communication_context.lua` isolates a future VR hold
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

The future integration must establish one gesture/stick claim before turning
and virtual action sampling, route only its held presentation through private
navigation vectors, freeze the last selection on release, and cancel on routing
loss or owner replacement. These pieces remain unloaded. Keyboard/gamepad
coexistence and worn selection/cursor behavior still require acceptance.

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
