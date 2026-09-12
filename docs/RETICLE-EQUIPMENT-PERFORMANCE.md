# Reticle equipment lookup allocation

9 September 2026. Each candidate hit in the hand-origin reticle ray checks
whether its unit belongs to the player's visual equipment. The lookup previously
allocated a two-entry attachment-set table for every visited equipment slot.
It now visits the first- and third-person attachment sets directly through one
helper. Missing equipment returns false without allocating an empty table.
No equipment identity is cached: each lookup reads the current loadout tables.
Raycast parameters, hit selection and convergence output are unchanged.

The explicit offline benchmark loads the actual private lookup from the module
prefix before installation. Engine extension lookup is a double; no game hooks,
physics, tracking or rendering run. It compares owner/first-person identity,
all direct and attachment units in six slots, absent extension/equipment/first
attachment set, ignored non-table slots, and removal/replacement of an attachment.
The six-slot numerical workload is illustrative, not a captured player loadout.

Five alternating trials each run 100,000 lookups after 3,000 warm-up calls:

| Workload | Default LuaJIT baseline / candidate median | Interpreter baseline / candidate median |
| --- | ---: | ---: |
| No matching unit | 60.0733 / 42.5600 ms | 111.9471 / 105.3590 ms |
| Attachment in sixth slot | 58.6412 / 43.3264 ms | 99.0197 / 98.8175 ms |

Typical temporary heap growth drops from 51,562.5938 to 0.0938 KiB for either
six-slot workload with collection paused. First default-mode trials include small
extra JIT allocations. Interpreter timing ranges overlap, so those results do
not establish a consistent interpreter speed gain. The unchanged owner fast
path is also recorded as a control; the JIT can fold its constant comparison,
so its sub-millisecond timing is not a meaningful engine-call estimate.

Baseline is `1a7053e`. The exact identity comparisons pass and all 69 Lua chunks
compile. This is an allocation reduction in source, not a game FPS measurement,
gameplay acceptance or fix for sustained VDXR slowdown. It is outside the staged
Lua performance package and the accepted installation is unchanged.

Validation on Windows x64:

```powershell
& build/dependencies/luajit/src/luajit.exe tools/stereo/benchmark-reticle-equipment.lua BASELINE.lua mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_aim.lua
& build/dependencies/luajit/src/luajit.exe -joff tools/stereo/benchmark-reticle-equipment.lua BASELINE.lua mods/darktidevr/scripts/mods/darktidevr/darktidevr_controller_aim.lua
& tools/stereo/test-darktide-lua-source.ps1
git diff --check
```

Local receipts: `artifacts/unattended/reticle-equipment-{benchmark,interpreter,lua-gate}-20260909.log`.
