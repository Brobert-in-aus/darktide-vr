# Bounded SR native command identity

The 10 September schema-5 capture associated SR feature lifetimes with nested
Streamline viewports, but all 64 raw command-pointer comparisons failed. A
wrapper/native distinction could explain this without a rendering error.

Streamline's [pinned v2.7.30 programming guide, section 5.3](https://github.com/NVIDIA-RTX/Streamline/blob/v2.7.30/docs/ProgrammingGuide.md#53-how-to-check-if-sl-proxies-are-used)
documents QueryInterface with GUID ADEC44E2-61F0-45C3-AD9F-1B37379284FF to obtain
the native interface from a proxy, including graphics command lists. This avoids
calling the non-thread-safe slGetNativeInterface API or reading private fields.

Schema 6 adds one NGX_SR_COMMAND_IDENTITY record to each admitted SR sample.
The query runs only inside a live, verified Streamline SR scope and the existing
64-sample budget. Its temporary COM reference is released before returning;
only the numeric identity and HRESULT are recorded. No rendering arguments,
resource states, history, motion vectors or GPU waits change. Disabled and
exhausted observation paths do not query the interface.

The strict reader retains schemas 1–5. `synchronous_native_command_match` is
true/false only when the query produced a native identity and the matching NGX
record exists; unsupported, missing and null results are unknown (`null`). It
rejects failed queries carrying an identity and queries without live context.
Raw pointer comparison remains separate. Neither comparison establishes GPU
completion, image correctness, HUD attribution or physical eye ownership.

## Validation, 11 September 2026

Windows x64 Release native DLL and focused tests built successfully using the
existing `build/xr-window-capture-demand` build directory. This accumulated
native build is **not a deployment candidate**; simulator deployment must use
the focused SR baseline in its own worktree.

Commands:

```powershell
cmake --build build/xr-window-capture-demand --config Release --target darktidevr_native_capture darktidevr-streamline-native-identity-tests darktidevr-ngx-sr-observation-tests
ctest --test-dir build/xr-window-capture-demand -C Release -R '^(ngx_sr_observation|streamline_native_identity)$' --output-on-failure
python tests/streamline_stereo_inputs/test_ngx_sr_probe.py --native build/xr-window-capture-demand/tests/streamline_stereo_inputs/Release/darktidevr-ngx-sr-observation-tests.exe
```

Both native tests and all 13 reader tests passed. Coverage includes unsupported
queries, malformed null success, malformed failure with a returned reference,
balanced reference counts, actual native record formatting, mismatches,
unknowns, duplicate records and rejected attribution claims. `git diff --check`
passed.

## Focused simulator result

Focused commit `e54ee36` extends `c58b94e` with this diagnostic only. Native DLL
SHA-256 `DA2E51BDBCC3FC0ABBE68B9AEBFC818995DE36A248FEED9FF85E32F033CE6219`.
Five focused native tests and all 13 reader tests passed. Two test executables
were initially missing; after building those targets the five-test run passed.

Physical Ready failed with rendering unavailable, so the authorised isolated
simulator fallback was used with saved 2496×2688 eye dimensions, Quality DLSS,
FG on, 120 Hz/cap, workers 13, Reflex on, HUD/menu on and preview/debug off.
The closed-game SoloPlay launch entered cm_archives at difficulty 3. The capture
lasted 30 seconds after readiness; it is diagnostic, not a matched performance
comparison against the FB244186 baseline.

All 64 admitted SR evaluations completed successfully. Every special query
returned S_OK and a native address identical to that evaluation's NGX command
list. All 64 raw Streamline/NGX address comparisons still differed. Thus the
earlier mismatch is explained by the Streamline proxy for this sampled path.
Lifetime 2 remained in viewport 1460506473 and lifetime 3 in viewport 277090740,
32 observations each. Viewport IDs are run-local, not persistent eye numbers.

The existing camera-coherence analyzer found 14 paired records from present
2164 onward. Assigning those viewports to eyes 0 and 1 respectively produced
64 mm separation within 5 micrometres, corrected orientation differences below
0.000006 degrees and baseline alignment within 0.000010 degrees. Swapping the
assignment produced about 28 degrees of corrected forward disagreement. This
extends the metadata chain; it still does not inspect GPU history or pixels.

The consumer delivered 1,729 fresh and 1,723 generated submissions with zero
reported pose mismatches and clean exit. Exact restoration passed, the simulator
DLL was restored, and normal proximity handling was restored. Accepted native,
Lua and viewer defaults were not promoted or replaced permanently.

Evidence: `artifacts/unattended/synthetic-sr-native-identity-20260911/`, including
`sr-report.json`, `camera-coherence.json`, original logs and `restoration.json`.
Physical readiness receipt: `sr-native-identity-ready-20260911.json`.
The remaining HUD blur investigation needs resource/pixel or worn evidence;
this result gives no reason to change eye history, jitter or reset policy.
