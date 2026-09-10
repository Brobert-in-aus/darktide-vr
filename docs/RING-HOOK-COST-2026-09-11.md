# CPU hook costs after native ring delivery

The descriptor-copy and native-ring candidate delivers about 89.5 native FPS
at DLSS Quality, versus the accepted control's 76.47 FPS. Its original-frame
transport makes a live comparison of earlier CPU hook savings useful.

Focused source `a99b8ce` applies the existing `8b3697a` change to ring source
`10550a4`. It reserves the menu diagnostic budget before preparing payloads,
matches short resource names without heap allocations, and copies only fixed
command-recording state rather than diagnostic pass maps. The ring algorithm,
actual DirectX calls, Lua, viewer and graphics settings are unchanged.

Focused branch: `codex/focused-ring-hook-cost-2026-09-11`.
DLL SHA-256:
`DAA51105678FAA435D97180DB3A54D3605B0B419BCBB7217A65715B082520901`.
Build: `build/focused-descriptor-demand`. The earlier ring DLL is preserved as
`artifacts/native-baselines/D4AB131A-native-original-ring.dll` for reversal.

Windows x64 Release compilation and four checks pass: `native_capture_hooks`,
`bounded_diagnostic`, `resource_name_match`, `command_recording_snapshot`
(0.94 seconds total). The initial build command also requested a ring test
target absent from this older focused tree, after successfully building the
DLL; the dedicated root ring tests remain the previously recorded validation.
The first smoke-test invocation lacked its executable; building that target
and rerunning all four checks passed. Receipts:
`artifacts/unattended/ring-hook-cost-{build,tests-build,smoke-build,tests}-20260911.log`.

The Quality mission comparison delivered 89.58637 native FPS, with no generated
frames or repeats, zero pose mismatches, clean exit and restored files. The
preceding ring-only Quality trials delivered 89.56705 and 89.34302 FPS. This
does not demonstrate a live gain from these extra changes; keep them separate
from the repeated descriptor/ring improvement. There were 27 valid GPU activity
samples and two missing, with no observed busy Streamer sample (incomplete
engine coverage remains unknown). Evidence:
`artifacts/unattended/synthetic-descriptor-demand-ring-hooks-a-20260911`.

The preserved combined DLL is now
`artifacts/native-baselines/DAA51105-ring-hook-cost.dll`. The build directory
may be reused for subsequent focused diagnostics; use the hash-pinned artifact
when repeating this comparison.
