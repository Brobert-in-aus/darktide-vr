# HUD options checkpoint — 6 September 2026

Three DMF numeric controls now adjust the active VR HUD without restarting:

| Control | Default | Range | Effect |
| --- | --- | --- | --- |
| HUD size | 100% | 50–150% | Uniform panel scale, relative to 0.63 |
| HUD distance | 2 m | 0.75–4 m | Position and physical dimensions change together to retain apparent size |
| HUD text and icon size | 100% | 50–150% | Fixed element scale, relative to 2.08 |

Invalid/non-finite saved values fall back safely; finite values are bounded.
Existing setting callbacks are preserved. Only internal-scale changes request
a one-time fixed-element refresh; spatial markers, capture resources and saved
Custom HUD positions remain independent.

Validation on Windows x64:

```powershell
ctest --test-dir build/windows-vs2022 -C Release --output-on-failure -R '^(hud_panel|hud_options|menu_input|lua_source_compile)$'
```

All four tests passed, including the pinned 27-chunk LuaJIT gate. The new fixture
covers defaults, angular size, bounds, callback chaining, idempotence, resource
identity, fixed-only refresh, saved layout preservation and DMF label formatting.
Live Mod Options showed all three labels and defaults; a desktop click changed
size to 110%, reopening retained it, and it was restored to 100%. This verifies
same-session persistence, not a non-default value across a full game restart.
DMF formats control labels but displays tooltip descriptions directly; percent
escaping is required in the labels. A doubled-percent tooltip seen during the
live check was replaced with plain wording and the test gate passed again.

Live log: `artifacts/unattended/hud-options-verified-20260906.log` (ignored).
Private range initialization created the HUD target at the runtime-derived
2496×1404 size and reported a 2.000 m surface, 1.897 m wide and 1.276 m high.
The harness reached `shared_ready=1447`, with fresh pairs at about 45 FPS,
zero pose mismatches and zero fallback frames in that interval.
Worn acceptance of altered values and detailed layout fit remain user checks.
