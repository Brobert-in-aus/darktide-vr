# Resource-name matching CPU cost

9 September 2026, offline native candidate, undeployed.

Eye/menu routing repeatedly read a D3D12 resource's debug name via a size query,
allocated wide buffer, UTF-8 sizing/conversion and allocated string. The known
routing identifiers are short ASCII hashes. Their matcher now reads directly
into a stack buffer and compares a string view. No pointer cache is introduced:
renaming an object is visible on the next query. Wide names still take precedence;
an empty wide name falls through to the ANSI name. ANSI trailing zero bytes are
trimmed, while embedded zeros remain significant. Long or non-ASCII names retain
the existing reader. Diagnostic text uses the existing reader too.

All four eye-final/index, eye-output and menu matching helpers use this path.
It does not change eligible resource names, dimensions, render barriers or copies.

## Validation and measurement

Windows x64 Release native capture and the new matcher executable build in
`build/xr-frame-stage-timing`. Two focused CTests pass in 0.34 seconds:
`bounded_diagnostic` and `resource_name_match`.

The matcher check creates a real D3D12 WARP resource and compares against the
previous reader, retained verbatim in the fixture. It covers missing/null names,
ANSI and wide hashes, wide precedence, rename visibility, empty-wide fallback,
embedded/trailing zeros, 64/65-character wide bounds, long ANSI and non-ASCII
fallback. The short-name benchmark takes no slow fallback.

Five alternating-order trials of 200,000 wide-name queries measured old
17.3765-17.6203 ms (median 17.3987), new 4.9257-5.0162 ms (median 4.9313).
This measures real WARP object's CPU metadata queries, not GPU execution, real
game hook frequency, hardware-driver cost or in-game FPS. No timing threshold
is asserted. The helper's fast path makes one private-data query and allocates
no heap buffer; the actual game may also present missing or nonmatching names.

```powershell
cmake --build build/xr-frame-stage-timing --config Release --target darktidevr_native_capture darktidevr-resource-name-match-tests
build/xr-frame-stage-timing/tests/streamline_stereo_inputs/Release/darktidevr-resource-name-match-tests.exe
ctest --test-dir build/xr-frame-stage-timing -C Release -R 'resource_name_match|bounded_diagnostic' --output-on-failure
```

Use the Visual Studio 2022 Community bundled CMake/CTest here. Receipts in
`artifacts/unattended`: `resource-name-build-20260909.log`,
`resource-name-build-final-20260909.log`, `resource-name-benchmark-20260909.log`,
and `resource-name-tests-20260909.log`.

No installation, graphics or headset change. A later focused native candidate
must preserve the accepted mixed baseline and pass Ready before deployment.
