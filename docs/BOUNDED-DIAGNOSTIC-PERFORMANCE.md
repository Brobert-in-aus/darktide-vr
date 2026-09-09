# Exhausted menu diagnostics: CPU optimisation

9 September 2026, offline candidate; not deployed.

After the menu resource log reached its 4,096-entry budget, later calls still
incremented a shared atomic counter and evaluated arguments before rejection,
including resource debug-name lookups and temporary strings in the barrier hook.

All 24 calls now reserve an entry before evaluating diagnostic arguments.
Saturation uses a relaxed atomic load instead of a read-modify-write. Admission
uses compare/exchange for an exact concurrent 4,096-attempt cap. The menu-only
resource description and consumer descriptor snapshot also move inside admission.
Names used for routing remain unchanged. File format, path, locking and writing
are unchanged; failed writes still consume an attempted entry. Concurrent
reservations need not be written in reservation order.

## Offline validation

Windows x64 Release native capture builds in `build/xr-frame-stage-timing`.
`bounded_diagnostic` and `diagnostic_append_log` pass, 2/2 in 0.27 seconds.
Eight concurrent callers prepare exactly 4,096 payloads, then none after
saturation; a zero budget prepares none.

Five alternating-order benchmark trials compare four million exhausted attempts
across eight threads. Old counter: 26.5905-27.4281 ms, median 27.1734 ms.
New production gate: 0.7103-0.8680 ms, median 0.7815 ms. This isolates admission
contention, including thread launch/join. It excludes resource-name work and
does not measure real hook frequency or establish an in-game FPS improvement.
Timing is informational, not a pass threshold.

```powershell
cmake --build build/xr-frame-stage-timing --config Release --target darktidevr_native_capture darktidevr-bounded-diagnostic-tests
build/xr-frame-stage-timing/tests/streamline_stereo_inputs/Release/darktidevr-bounded-diagnostic-tests.exe
ctest --test-dir build/xr-frame-stage-timing -C Release -R 'bounded_diagnostic|diagnostic_append_log' --output-on-failure
```

CMake/CTest are the Visual Studio 2022 Community bundled executables here.
Receipts under `artifacts/unattended`: `bounded-diagnostic-build-20260909.log`,
`bounded-diagnostic-build-final-20260909.log`,
`bounded-diagnostic-benchmark-20260909.log`, and
`bounded-diagnostic-tests-20260909.log`.

Accepted installation, graphics settings and headset state were unchanged.
A focused deployment requires Ready and can measure real-session CPU cost.
Basic gameplay verification is not needed to continue offline optimisation.
