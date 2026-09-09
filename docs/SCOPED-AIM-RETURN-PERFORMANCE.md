# Scoped aim return allocation

9 September 2026. The controller-aim module's private pose scope previously
packed every protected stock-call result into a table, restored the original
component, then unpacked the results. A small variadic completion function now
restores the component and forwards the protected call's values directly.
The proxy, component read-through, stock invocation and other result-packing
sites are unchanged. No tracking, aiming or gameplay rule changes are intended.

The explicit offline benchmark loads the actual module prefix before its install
function and returns the private helper. It does not install game hooks. Its
checks cover five results including leading/interior/trailing nils, zero results,
error-object identity, nested restoration, inherited component fields and bypass
when pose/component data is absent. These are preservation checks for the changed
scope, not additional basic-gameplay acceptance.

Five alternating baseline/candidate trials run 100,000 calls each after 3,000
warm-up calls. The stock-call double checks the scoped fields and returns five
values. Allocation measurements pause garbage collection; they are temporary
heap growth, not retained memory or an observed game memory leak.

| Mode | Baseline median | Candidate median | Heap growth baseline / candidate |
| --- | ---: | ---: | ---: |
| Pinned LuaJIT, default JIT enabled | 40.9382 ms | 26.2258 ms | 50,000.0938 / 31,250.0938 KiB |
| Same executable, `-joff` | 37.7154 ms | 24.6287 ms | 50,000.0938 / 31,250.0938 KiB |

Default-mode timings do not prove that LuaJIT compiled this particular scope;
the proxy allocation, protected call and validation double remain in the timed
path. Baseline is the module at `2f0939e`. All 69 mod Lua chunks compile with the
pinned gate. No game frame-time, worn visual or live hook acceptance is claimed.
This source change is not in the staged three-module Lua performance package.

Validation on Windows x64:

```powershell
& build/dependencies/luajit/src/luajit.exe tools/stereo/benchmark-scoped-aim-returns.lua BASELINE.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_aim.lua
& build/dependencies/luajit/src/luajit.exe -joff tools/stereo/benchmark-scoped-aim-returns.lua BASELINE.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_aim.lua
& tools/stereo/test-darktide-lua-source.ps1
git diff --check
```

Local receipts: `artifacts/unattended/scoped-aim-return-{benchmark,interpreter,lua-gate}-20260909.log`.
