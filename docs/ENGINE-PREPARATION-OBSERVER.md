# Dynamic-resource and linked-transform observations

The [post-ring residency capture](RING-CPU-DIAGNOSIS-2026-09-11.md) identifies
engine preparation after the descriptor lock saving. This observer measures two
remaining leads without changing engine work:

- `796370`, identified by an embedded assertion as
  `stingray::d3d12_resource_context::update_dynamic`: three pointer arguments,
  void return. Four direct call sites discard the return register. Capture the
  first 24 descriptor bytes and time 4,096 calls.
- `398870`, containing the `update_links` profiling label: one context argument,
  void return. Its direct caller overwrites RAX after return. Capture the count
  at context `+d30` before/after and time 512 calls. The count describes list
  length; equality does not establish that linked transforms were unchanged.

All RVAs and signatures are gated to engine SHA-256
`6FCE8DB87A77A412B22EF9F33F74FA16EF85126CC0FBB24187D78B85FC7A19D3`.
Each hook has its own bounded stream. Arming uses
`darktidevr_engine_preparation.flag` beside the loaded DLL: `[probe] enabled=1`
before launch, then `capture=1` only after the mission settles. No file or flag
means no hook installation. Exhausted hooks forward directly. Diagnostic reads
are guarded, and failed reads remain unknown. Original arguments and Windows
error state are preserved. No target resource, transform, descriptor or wait is
modified by the observer.

Records include thread, Present ID, context identity and QPC duration. These
are instrumented function wall times, including nested work and possible waits.
Streams have different sample windows and partial boundary frames. Worker
durations overlap; their sum is not a frame-time share. Repeated context/Present
IDs do not prove repeated work or identify the stereo eye. Do not skip engine
updates from these counters alone.

Root source `5eb2c16`; focused `fd8def7`, `535ef1e` on ring source `10550a4`.
Focused DLL SHA-256:
`3B57E255710740E9683E1DB9B2FEA5BDFDC688BC23F672FBD228898829D15868`.
Build location: `build/focused-descriptor-demand`. The focused port initially
missed `guarded_copy.h`; adding the unchanged dependency corrected compilation.
Windows x64 Release root/focused builds pass; `engine_preparation_forwarding`
and `native_capture_hooks` pass in both (0.53/0.50 seconds). Three Python reader
checks pass for complete records, timing/order rejection and unknown reads.

```
cmake --build build/xr-window-capture-demand --config Release --target darktidevr_native_capture darktidevr-engine-preparation-forwarding-tests
ctest --test-dir build/xr-window-capture-demand -C Release -R '^(engine_preparation_forwarding|native_capture_hooks)$' --output-on-failure
python tests/tooling/test-engine-preparation.py
```

Build receipts are `artifacts/unattended/{focused-,}engine-preparation-*-20260911.log`.
The first mission capture is in progress at
`artifacts/unattended/synthetic-descriptor-demand-engine-preparation-20260911`.
The wrapper preserves both flag locations and uses the normal transactional
benchmark launcher with Quality, 2496x2688, 13 workers, HUD/menu on and FG off.
Physical readiness remains unavailable; this is an authorised simulator trial.
