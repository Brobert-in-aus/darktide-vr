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
passed. Focused simulator capture is pending; no visual or performance claim.
