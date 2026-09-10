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

Matched simulator baseline/candidate trials use Quality DLSS,
2496x2688 per eye, 13 workers, Reflex On, HUD/menu enabled, 120 Hz runtime,
stationary `cm_archives` mission start, optional diagnostics disabled. Start with
native rendering, then test frame generation. Physical Ready failed; the Quest
is in standby for an explicit idle-encoding simulator control. Record observed
Streamer activity and missing counter samples for each trial. This does not
replace physical/worn acceptance or prove visual parity from counters.

Native A/B/A results, after ten seconds of warm-up:

| Selection | Viewer distinct FPS | Game Present rate | Published-pair rate |
| --- | ---: | ---: | ---: |
| Accepted A2 | 74.85 | 75.00 | 74.84 |
| Candidate B1 | 53.38 | 92.83 | 53.30 |
| Accepted A3 | 74.33 | 74.44 | 74.33 |

Game/producer rates use first-to-last `native_observer` counter deltas after the
same ten-second warm-up. Their endpoints differ slightly from viewer intervals.
The candidate increases observed game presentations by about 24%, but delivered
stereo becomes worse. **Do not promote it as a standalone performance fix.**
All three runs exited cleanly, restored files and reported zero pose mismatches.
Streamer busy samples were zero; A2/A3 had 27 valid GPU samples plus one missing,
and B1 had 28 valid samples. Camera position, orientation and FOV matched within
the logged numeric precision. No capture failure was found in B1's game log.

The native producer has a single shared eye-pair slot. At eye zero it drops the
entire pair while `consumed < ready`, returning success without publication.
This is a plausible explanation for the Present/publication divergence, not yet
a direct count of rejected pairs. A candidate control capped at 72 FPS completed
at 71.75 delivered FPS, zero pose mismatches, clean exit and restored files.
All 28 GPU samples were valid, with no busy Streamer engine observed. This
supports a pacing/handoff limit rather than a simple rendering slowdown.
Frame-generation transport
already has a separate original-frame ring and should be measured independently.

The first A1 run was excluded because the runner could not recover the process
exit code. See [exit-status recovery](SIMULATOR-EXIT-STATUS-2026-09-11.md).
Local mission evidence: `artifacts/unattended/synthetic-descriptor-demand-{a2,b1,a3}-20260911`.
