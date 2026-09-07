# Stock melee input and sweep contracts

8 September 2026. Physical melee is paused while server-side stock melee is
established. These optional checks execute cached stock Lua with fixtures;
they neither modify nor launch the game.

`tests/tooling/test-melee-parser-stock-contract.lua` loads the entire stock
ActionInputParser, formatter and input hierarchy, then drives them with actual
VR controller-binding output. The default, fast, mid and slow shared melee
input setups pass light release, held heavy and automatic heavy completion.
The default setup also passes block, push, push follow-up, cancellation and
release-to-base cases. The hold runs cross the parser's 60-frame ring boundary.

Two release cases differ. Releasing immediately after push follow-up returns
the hierarchy to base without queuing the `dont_queue` release as an action.
Keeping block held can instead queue block on the next update; releasing later
then produces `block_release`. This is observed stock parser behavior, not a
VR cancellation fix or proof that the action handler admits every queued action.

The parser is real; class construction, engine services, 10 ms fixed ticks,
unrelated common-action inputs and immediate action consumption are fixtures.
Weapon-specific overrides, forcesword special hierarchy, stock action admission,
network serialization and authoritative damage remain outside this check.
Existing separate transport tests cover recorded input send/receive/replay;
these results must not be described as a new end-to-end server test.

`tests/tooling/test-melee-reference-stock-contract.lua` executes the stock sweep
update. It verifies pre-window reference refresh, previous/current aim sampling,
the first and final damage-window frames, one exit/proc dispatch and suppression
after abort. Pose values and authored-spline/physics sinks are supplied. Moving
aim during an attack can change its sweep, so the local guide is a snapshot of
the path for the current aim rather than a latched future trajectory.

Both pass against cached source snapshot
`0f0cb45991e9305ef4a7b925370792d7d6035f95` with the pinned LuaJIT:

```powershell
& build/dependencies/luajit/src/luajit.exe tests/tooling/test-melee-parser-stock-contract.lua _downloads/Darktide-Source-Code mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_bindings.lua
& build/dependencies/luajit/src/luajit.exe tests/tooling/test-melee-reference-stock-contract.lua _downloads/Darktide-Source-Code
```

For the next worn check use the focused [first-swing preview candidate](STOCK-MELEE-PREVIEW.md)
in PR #11. Visibility and local swing correspondence do not establish server
damage. Preserve the current remote-mission gate until authoritative behavior,
prediction/replay and the required mission checks have been established.
