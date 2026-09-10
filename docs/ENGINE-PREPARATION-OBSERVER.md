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
The first mission capture completed at
`artifacts/unattended/synthetic-descriptor-demand-engine-preparation-20260911`.
The wrapper preserves both flag locations and uses the normal transactional
benchmark launcher with Quality, 2496x2688, 13 workers, HUD/menu on and FG off.
Physical readiness remains unavailable; this is an authorised simulator trial.

## Mission results and sample spread

The initial dynamic stream filled all 4,096 records during one Present ID:
0.3434 milliseconds elapsed across seven contexts. Its mean duration was
0.045 microseconds, with median zero and p95 0.1 microseconds. These tiny
durations are near the QPC tick granularity, and the single-frame burst does
not establish representative cost across gameplay.

Root `2ca1435` / focused `43ba098` samples every 64th dynamic invocation per
thread, without a shared counter write on unsampled calls. The header records
`stride=64`; old captures remain readable. Linked updates retain stride one.
Forwarding/stride-bound checks and reader checks pass; the focused native smoke
test also passes. DLL SHA-256:
`52FAB41DFC27C977AC89BEEAAC78BA48F6506301AFC4648FB53798E7710E42E7`.
The earlier DLL is preserved as `artifacts/native-baselines/3B57E255-engine-preparation.dll`.

The second dynamic capture spans Present IDs 2547–2573, 0.2855 seconds and
197 contexts. Mean is 0.053 microseconds, median zero, p95 0.1 and maximum 0.4.
Periodic sampling is not random sampling or complete call accounting. It
supports treating this as a small per-call operation, not a new dominant cost.

Linked-update means were 14.323 and 14.439 microseconds; medians 0.200 and 0.150,
and p95 69.9 and 72.5. Each 512-record stream covers about 40 Present IDs and
seven contexts; list counts range from zero to 1,326/1,330. Counts remain equal
before/after in 512/512 and 511/512 calls. This does not establish unchanged
transforms and does not justify skipping a second-eye update.

Both runs exit cleanly, restore files and report zero pose mismatches. Their
diagnostic native rates are 88.95 and 88.63 FPS. GPU activity records: 32 valid
plus two missing, then 27 valid plus one missing; no observed busy Streamer
samples. Evidence suffixes: `engine-preparation` and `engine-preparation-stride`
under `artifacts/unattended/synthetic-descriptor-demand-*-20260911`.
