# Command recording snapshot CPU cost

9 September 2026, offline native candidate, undeployed.

Six rendering/diagnostic helpers copied an entire `CommandTrace` under the trace
mutex even though they used only fixed recording state. That also cloned its
unordered map of diagnostic pass counters. The map can grow during a recording;
copy cost and allocation count therefore depended on unrelated diagnostic data.

Fixed fields now live in a trivially copyable `CommandRecordingSnapshot` base.
The six callers snapshot that base under the existing mutex. The live trace
retains and updates its pass map. Full trace copies are deleted at compile time;
move/reset remain supported. Hashing and cluster-binding readers accept the
fixed snapshot. There is no retained reference to mutable recording state.

Affected paths: cluster-light FOV patch collection, cluster submission history,
world UI replay, the disabled menu-consumer probe, cluster dispatch diagnostics,
and stock menu redirection. Their existing enable/eligibility gates are unchanged.

## Validation and measurement

Windows x64 Release native builds, including the copy-deletion guard. Four CTests
pass in 0.66 seconds: `command_recording_snapshot`, `resource_name_match`,
`bounded_diagnostic`, `billboard_draw_readback`. The snapshot check verifies no
diagnostic value copies, retained fixed fields and independence after source
mutation/clearing. A static assertion enforces trivial copyability.

The isolated benchmark uses the production snapshot plus a constructed unordered
map of 16-counter diagnostic values. Five alternating-order trials per condition,
10,000 fresh copies each:

| Constructed map entries | Old median | Snapshot median |
| --- | ---: | ---: |
| 0 | 0.8794 ms | 0.2669 ms |
| 128 | 39.6368 ms | 0.2621 ms |

The map workload is constructed, not a captured game distribution or the exact
native PassCounts layout. This measures the eliminated map-copy mechanism and
includes object destruction. It is not an in-game FPS estimate or hardware GPU
measurement. Timing is informational and never a test threshold.

```powershell
cmake --build build/xr-frame-stage-timing --config Release --target darktidevr_native_capture darktidevr-command-recording-snapshot-tests
build/xr-frame-stage-timing/tests/streamline_stereo_inputs/Release/darktidevr-command-recording-snapshot-tests.exe
ctest --test-dir build/xr-frame-stage-timing -C Release -R 'command_recording_snapshot|resource_name_match|bounded_diagnostic|billboard_draw_readback' --output-on-failure
```

Use Visual Studio 2022 Community bundled CMake/CTest here. Receipts under
`artifacts/unattended`: `command-snapshot-build-20260909.log`,
`command-snapshot-build-final-20260909.log`, `command-snapshot-test-build-20260909.log`,
`command-snapshot-benchmark-20260909.log`, `command-snapshot-tests-20260909.log`.
No deployment, game interaction, graphics or headset change. A later focused
native trial must retain the mixed baseline and pass Ready before deployment.
