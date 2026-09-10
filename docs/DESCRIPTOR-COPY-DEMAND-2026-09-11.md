# Descriptor-copy metadata demand

The compute stage observer identified descriptor binding as the largest sampled
binding stage. The engine allocator initializes each descriptor with a separate
`CopyDescriptorsSimple` before its caller overwrites the range using
`CopyDescriptors`. Our hooks add global-mutex and hash-map work to both APIs.

Clean launches install those copy hooks for stock-menu render-target metadata,
but do not install CBV/SRV/UAV metadata writers. Shader descriptor copies thus
perform bookkeeping against entries that cannot have been populated. This is
independent of whether an interactive menu is currently open.

## Candidate

Commit `2ad852f` checks the installed creation-hook pointers by heap type after
forwarding the original DirectX call. Untracked heap types return before querying
the descriptor increment, taking `descriptor_mutex` or accessing the map.
RTV copies remain tracked for stock menus. Diagnostic/cluster shader tracking and
diagnostic depth tracking remain active when their creation hooks are installed.
No sampler metadata writer exists. Unknown heap types retain the old path.

Creation hooks are selected before the single `MH_EnableHook` call. Runtime menu
toggles do not disable metadata propagation; menus opened later still have the
render-target history. The candidate changes no engine allocator, actual copy,
resource state, command ordering or descriptor contents.

Focused branch `codex/focused-descriptor-demand-2026-09-11`, commit `87ed0d0`,
contains only this change on accepted native `23345e5`. DLL SHA-256:
`3AFEB3AF0756CC39570C8161D8435F3BF5875C645FC80044FAB87B41A65B9E28`.
Do not deploy the accumulated root development DLL.

## Isolated copy workload

`darktidevr-descriptor-copy-performance` uses real D3D12 descriptor heaps with
valid null SRVs, separate source/destination heaps per worker, and synchronized
worker starts. Each worker records 10,000 batches of 16 descriptors. It measures
range copies alone and the engine-like sequence of 16 single-descriptor default
fills followed by a range copy. No GPU work or game process is launched.

Two baseline/candidate rounds used copied DLLs and separate TEMP directories.
Baseline SHA-256 was the accepted `FCCDD0DE...` build. Eight-worker wall times:

| Mode/workload | Baseline rounds (ms) | Candidate rounds (ms) |
| --- | --- | --- |
| Clean, range copy | 20.818 / 20.364 | 2.049 / 1.946 |
| Clean, default fills + range | 216.789 / 217.758 | 3.725 / 3.766 |
| Diagnostic, default fills + range | 238.212 / 239.163 | 235.496 / 239.269 |
| Unhooked, default fills + range | 3.684 / 3.715 | 3.752 / 3.799 |

The candidate removes most overhead in this deliberately concentrated workload.
These ratios are not game FPS projections. Diagnostic cost remains, as expected
because its shader metadata is populated and required.

Validation: Windows x64 Release builds passed for root and focused native DLLs
and the workload executable. `ctest --test-dir build/xr-window-capture-demand
-C Release -R '^native_capture_hooks$' --output-on-failure` passed after building
the test target. Evidence: `artifacts/unattended/descriptor-copy-offline-20260911`.

## Mission comparison

Matched simulator baseline/candidate trials are in progress: Quality DLSS,
2496x2688 per eye, 13 workers, Reflex On, HUD/menu enabled, 120 Hz runtime,
stationary `cm_archives` mission start, optional diagnostics disabled. Start with
native rendering, then test frame generation. Physical Ready failed; the Quest
is in standby for an explicit idle-encoding simulator control. Record observed
Streamer activity and missing counter samples for each trial. This does not
replace physical/worn acceptance or prove visual parity from counters.
