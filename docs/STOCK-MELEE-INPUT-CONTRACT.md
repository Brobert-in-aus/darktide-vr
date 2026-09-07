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
Each case now runs a second full parser fed by the actual stock client buffering,
send and authoritative receive methods through an in-memory RPC sink. The client
input ring is deliberately four frames wide; duplicate packets are delivered.
Both parsers agree on the next action, automatic-completion state and hierarchy
on every tick. An intentionally false received primary hold is detected as a
divergence, confirming that the fixture cannot substitute current local input
when a recorded receiving value is false.

Two release cases differ. Releasing immediately after push follow-up returns
the hierarchy to base without queuing the `dont_queue` release as an action.
Keeping block held can instead queue block on the next update; releasing later
then produces `block_release`. This is observed stock parser behavior, not a
VR cancellation fix or proof that the action handler admits every queued action.

The parser is real; class construction, engine services, 10 ms fixed ticks,
unrelated common-action inputs and immediate action consumption are fixtures.
The three force-sword variants also execute their actual input overrides. Light
release, held heavy, an 80-tick quell hold/release and push-follow-up releases
agree across both parsers. Releasing only alternate preserves the target hold;
releasing primary selects `find_target_release`, including when both are released.
The stock hierarchy gives that input priority over the raw-release `fling_target`.
Actual target finding, conditional action-state fling, peril reduction, stock
action admission, engine network serialization and authoritative damage remain
outside this check. Other weapon-specific overrides remain untested.
Existing separate transport tests cover correction/replay. The new combined
transport/parser fixture is not a live or end-to-end damage/server test.

`tests/tooling/test-melee-reference-stock-contract.lua` executes the stock sweep
update. It verifies pre-window reference refresh, previous/current aim sampling,
the first and final damage-window frames, one exit/proc dispatch and suppression
after abort. Pose values and authored-spline/physics sinks are supplied. Moving
aim during an attack can change its sweep, so the local guide is a snapshot of
the path for the current aim rather than a latched future trajectory.

`tests/tooling/test-melee-authority-stock-contract.lua` executes the stock final
attack dispatcher with `attack_type=melee`. A supplied positive calculated result
can be returned on the client while the health mutation sink remains uncalled.
Only the allowed server path invokes that sink and returns its supplied actual
damage value. Blocking, ally protection and assisted/hogtied skips also pass;
the block-state write remains server-owned. Damage calculation and health math
are fixtures, so this establishes dispatch ownership, not live damage amounts.

All three pass against cached source snapshot
`0f0cb45991e9305ef4a7b925370792d7d6035f95` with the pinned LuaJIT:

```powershell
& build/dependencies/luajit/src/luajit.exe tests/tooling/test-melee-parser-stock-contract.lua _downloads/Darktide-Source-Code mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_bindings.lua
& build/dependencies/luajit/src/luajit.exe tests/tooling/test-melee-reference-stock-contract.lua _downloads/Darktide-Source-Code
& build/dependencies/luajit/src/luajit.exe tests/tooling/test-melee-authority-stock-contract.lua _downloads/Darktide-Source-Code
```

For the next worn check use the focused [first-swing preview candidate](STOCK-MELEE-PREVIEW.md)
in PR #11. Visibility and local swing correspondence do not establish server
damage. Preserve the current remote-mission gate until authoritative behavior,
prediction/replay and the required mission checks have been established.
