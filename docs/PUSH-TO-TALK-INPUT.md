# Scoped push-to-talk input candidate

Stock `ChatManager.init` retains an Ingame input service. Its update queries
both `has("voip_push_to_talk")` and the held value. Only push-to-talk voice mode
uses that input to request mute/unmute; the update preserves muted and
voice-activated modes. On Windows, the missing-setting fallback is stock
push-to-talk. These are cached-source findings, not current account settings.

The unloaded `darktidevr_push_to_talk_input.lua` supplies
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

This is not a usable Quest binding yet. The future caller must supply a fresh,
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
