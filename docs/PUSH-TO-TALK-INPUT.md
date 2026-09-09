# Scoped push-to-talk input candidate

## Integrated physical binding

Main now loads `darktidevr_push_to_talk.lua` and feeds it the mapped held action
after gameplay binding sampling. **Hold push-to-talk** starts unassigned and
accepts physical buttons only in the normal combat/hub profiles. Prompts read
the same assignments. The source candidate remains undeployed; no installed
setting or microphone operation changed.

The coordinator scopes the hold to a fresh sample, local handler/unit, current
binding revision, world/mode and native input/recenter generation. Ordinary UI,
ImGui, native input loss, null chat/gameplay services, remaps and disable/unload
cancel it. Observed routing loss stays cancelled through recovery until a
released semantic sample arrives; a regression caught a briefly blocked hold
reviving without that release. Keyboard PTT remains independent. This route uses
the existing VR gameplay eligibility and does not provide menu-wide voice input.

Four focused PTT/binding/prompt/production-input CTests pass in 0.13 seconds;
all 69 Lua chunks compile. The real production seam is exercised through loading,
mapped holds, release, remap/reconnect, UI/ImGui and cached/fixed null-service
cancellation. The optional cached stock update still passes with all microphone
operations mocked. Live acceptance remains: choose a free physical button,
confirm the game's selected voice mode, and check hold/release and cancellation
after fresh Ready and deliberate deployment. Text entry remains separate.

## Stock input primitive

Eligibility probes now protect method lookup and null-service queries. A retiring
proxy previously threw before the stock update began, including in voice modes
that did not need PTT input. Failed probes now skip injection and leave stock
update/cleanup in control. The adapter still propagates errors raised by the
stock update itself and restores its cached service after scoped injection.

The regression failed before this guard. Three PTT/binding/production-input
checks pass in 0.06 seconds and all 69 Lua chunks compile. Actual cached
ChatManager fixtures cover retiring lookup/query in muted, voice-activated and
PTT modes; stock PTT mute cleanup still runs. Every microphone operation is
mocked. Port this follow-up to the focused communication candidate before trial.

Stock `ChatManager.init` retains an Ingame input service. Its update queries
both `has("voip_push_to_talk")` and the held value. Only push-to-talk voice mode
uses that input to request mute/unmute; the update preserves muted and
voice-activated modes. On Windows, the missing-setting fallback is stock
push-to-talk. These are cached-source findings, not current account settings.

`darktidevr_push_to_talk_input.lua` supplies
`Talk.with_input(manager, held, is_current, update, ...)`. It temporarily wraps
that cached service during one callback, contributing true only for an explicit
hold whose owner/sample predicate remains true. It preserves existing `has`
support, null services, unrelated actions and stock keyboard input. It does not
change voice mode or invoke microphone, channel or communication APIs itself.

The proxy expires on return/error and checks service ownership on each query.
A later update cannot revive a retained proxy. Nested updates suspend outer
injection, including unheld updates and failures. Service replacements made by
the real update are preserved. Sparse return values and callback errors pass
through after scope restoration.

The primitive's caller must supply a fresh,
released-before-activation binding sample and a predicate for its exact local
owner, input generation and routing eligibility. It must cancel holds on remap,
tracking loss and owner changes while retaining independent keyboard behavior.
Do not bypass the stock voice-mode choice, invent support for an absent alias,
or infer microphone operation from a synthetic input counter.

Text chat is separate: `show_chat` is a pressed View action consumed by
`ConstantElementChat._handle_keyboard_input` to begin writing. Active chat then
uses its own editing/send/back routes. Merely exposing `show_chat` is not complete
controller text entry. The saved keyboard override in the mission audit remains
the reference; do not assume Enter opens chat or synthesize message submission.

Validation, 9 September: three focused CTests
(`push_to_talk_input|gameplay_ui_input|communication_context`) pass in 0.06 seconds;
65 Lua chunks compile with pinned LuaJIT. An optional fixture executes the actual
cached stock voice-setting helper and `ChatManager.update`, with microphone
operations mocked. It covers hold/release, unchanged state, routing loss, keyboard
coexistence, muted/voice-activated modes and Windows fallback. No game, microphone,
voice channel or network operation ran. Installed files/settings are unchanged.

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-push-to-talk-input.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_push_to_talk_input.lua artifacts/vendor/Darktide-Source-Code
tools/stereo/test-darktide-lua-source.ps1
```
