# Bounded cascade-stage observation

11 September 2026. This diagnostic follows the
[shadow reuse contract](STEREO-SHADOW-REUSE-CONTRACT.md). It measures the CPU
function at engine RVA `419910`; it does not skip shadows or change GPU work.

The exact supported executable is SHA-256
`6FCE8DB87A77A412B22EF9F33F74FA16EF85126CC0FBB24187D78B85FC7A19D3`.
The full chained function and caller at `418156` establish six pointer arguments:
four in the normal integer registers and two on the stack. The fifth points to
the normalized light direction prepared by `417f50`; the sixth is a render
context. The caller immediately overwrites RAX, and the callee ends with scope
cleanup. The observer forwards all six arguments through the original void call.
A fresh byte scan found that direct call and no absolute pointer to the entry;
this is not a complete proof about possible indirect calls. Installation requires
the exact executable hash and all 20 entry bytes before creating the hook.

Arm `[probe] enabled=1, capture=0` in `darktidevr_cascade_stage.flag` beside the
native DLL before launch. Set `capture=1` only after the workload settles. No
enabled flag means no hook. Admission requires nonzero Present and gameplay
generation, is limited to 256 calls per process, and excludes same-thread
reentry. After exhaustion the hook forwards without further observations.

Each record keeps thread, Present, generation, six argument identities, QPC
begin/end and three bounded snapshots: 48 settings bytes from argument one,
12 light-direction bytes from argument five, and 24 uninterpreted view bytes
at argument six +50. Reads are guarded and happen before timing. Failed reads
are unknown, never matching zero-filled evidence. No resources are retained,
read back or rebound. Original arguments and Windows error state are preserved.

The result is CPU wall time including nested work and waits, not GPU shadow
cost or a sum that can be subtracted from frame time. Present/generation tags
are observations, not established eye identity. Matching sampled inputs omit
the complete cascade transforms, settings, world updates and transient-resource
lifetime. They do not authorize reusing pixels, constants or a whole stage.

The strict reader requires the full header, 256 unique indexed records and
completion marker, validates native ranges and read-validity consistency, and
reports nonfinite light vectors separately. Partial captures are rejected.

## Offline validation

Windows x64 Release native build passes. `cascade_stage_forwarding` and
`native_capture_hooks` pass 2/2 in 0.49 seconds. The forwarding test checks all
six pointer arguments, both Windows error states, disabled/non-world gates,
reentry, unreadable memory, concurrent admission and exact exhaustion. It makes
518 original mock calls while admitting exactly 256 records. Four reader tests
pass, including the actual native formatter and malformed/incomplete captures.

```
cmake --build build/xr-window-capture-demand --config Release --target darktidevr_native_capture darktidevr-cascade-stage-forwarding-tests
ctest --test-dir build/xr-window-capture-demand -C Release -R '^(cascade_stage_forwarding|native_capture_hooks|cascade_stage_reader)$' --output-on-failure
python tests/tooling/test-cascade-stage.py --native build/xr-window-capture-demand/tests/native_capture/Release/darktidevr-cascade-stage-forwarding-tests.exe
```

Static receipt: ignored `artifacts/unattended/cascade-entry-contract-20260911.json`.
Live timing, complete reuse inputs and worn acceptance remain unestablished.
Use a focused native build for any authorized diagnostic; do not deploy the
accumulated native development DLL.
