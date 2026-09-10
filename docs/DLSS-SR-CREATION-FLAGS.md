# Observe DLSS SR creation conventions

The earlier SR capture recorded evaluation inputs but not the flags supplied
when its features were created. Those flags declare low-resolution/jittered
motion vectors, depth inversion, HDR and exposure behavior. Frame-generation
constants cannot substitute for this SR-specific evidence.

With the existing optional `observe_sr_inputs` probe enabled, query the signed
integer `DLSS.Feature.Create.Flags` immediately before SR `CreateFeature`.
Verify its typed getter against the pinned runtime first. Cache only the query
status and scalar in the successful feature's existing lifetime registry.
Release or ambiguous duplicate creation clears the observation along with the
identity. No parameter pointer is retained and no parameter is written.

Creation queries have a separate 128-attempt process limit because features can
be created before the stereo capture gate opens. Queries also stop after the
64-evaluation SR budget is exhausted. The later sampled evaluations repeat the
cached flags as a schema-4 scalar, tying them to the resource record's lifetime.
They do not reread a potentially changed evaluation parameter object.

The reader accepts schemas 1–4. Older, omitted, failed or unverified creation
observations remain unknown. Known bits are decoded against the pinned NGX
definitions; the invalid bit and uninterpreted bits remain explicit. Conflicting
creation observations within one feature lifetime reject the trace. A valid
query does not prove that the declared conventions match the pixels.

## Validation

Windows x64 Release native build passed. Five focused checks passed in 0.65 s:
native capture, feature registry, SR formatter/budget, pinned official NGX ABI
and bounded diagnostics. Eleven parser checks passed with the native formatter,
including unavailable flags, reserved/invalid bits, lifetime inconsistency and
older-schema rejection of the new field. Reprocessing the actual schema-2
capture preserves all 64 complete evaluations with unknown creation flags.

Commands use `build/xr-frame-stage-timing`: build `darktidevr_native_capture`,
`darktidevr-ngx-feature-registry-tests`, `darktidevr-ngx-sr-observation-tests`,
`darktidevr-ngx-abi-reference` and `darktidevr-native-capture-tests`; run CTest
filter `^(ngx_abi_reference|ngx_sr_observation|ngx_feature_registry|native_capture_hooks|bounded_diagnostic)$`;
run `test_ngx_sr_probe.py --native` with the built SR observation executable.
Build receipts are `artifacts/unattended/dlss-sr-creation-flags-*-20260910.log`.

Built only. No Lua, game settings or accepted installation changes, and no basic
gameplay checks. A focused baseline build and successful Ready preflight remain
required for a new capture. This supplies evidence for DLSS implementation work;
it makes no quality or performance claim.

## Simulator observation

A 30-second simulator trial subsequently used focused native `16e656f` (SR
baseline `601e100` plus the FG completion resolver), DLL SHA-256
`2B13DC61D70B7C8F345B89BB6C499304B5A67DB21C282FBBAD262BF93A0E9750`.
The strict reader accepted all 64 schema-4 evaluations with complete scalar and
context records. Lifetimes 2 and 3 each contributed 32 observations. Every
creation flags query succeeded with value 99 (`0x63`): HDR, low-resolution
motion vectors, sharpening and automatic exposure enabled; jittered motion,
inverted depth and alpha upscaling disabled. No unknown or invalid bits appeared.

Colour/depth/motion were 1408x1536, output 2112x2304. Motion scale was
(-1408,-1536), pre-exposure one and all sampled reset values zero. Transparency,
exposure and bias-current-colour inputs were successful null queries. These are
the SR feature's own declared conventions, not values inferred from FG. They
still require comparison with the actual input pixels before alleging or fixing
a convention mismatch.

The run submitted 1,286 fresh and 1,268 generated stereo pairs, reported zero
pose mismatches and exited cleanly. All saved files were restored, including
both accepted native DLLs; installed Lua was unchanged. Windows Release build,
five focused native tests and all eleven parser tests (including native output)
passed. Evidence: `artifacts/unattended/synthetic-sr-conventions-20260910`.
This was a simulator diagnostic; physical-runtime performance and visual
acceptance are not established.
