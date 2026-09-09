# Offline native hook comparison

9 September 2026. This benchmark compares the accepted native DLL against the
focused three-optimisation payload through their actual Direct3D12 hooks.
It records command lists only: no queue execution, Present, OpenXR session,
image capture or game process. It does not measure GPU work or live FPS.

Accepted source `23345e5`, DLL SHA-256:
`FCCDD0DE699F9D50D2BD316792829D4EE5700843D925D194BE4DF1F3EEB02369`.
Candidate source `8b3697a`, PR #189, DLL SHA-256:
`63592118307969E087F7EBC849BB011291C4C75708591C5092966F001A74235B`.
The later buffer-cache and pose-math changes are outside this comparison.

## Method

The Windows x64 Release executable loads one copied DLL, enables diagnostic
hooks and installs them in its own process. It uses the default D3D12 adapter
and a two-transition render-target/shader-resource pair with an unrelated short
ASCII resource name. Each workload warms up for 5,000 pairs, then times recording
20,000 pairs (40,000 barriers). Warm-up exhausts the menu log before timing.
Command lists are closed and reset without submission between workloads.

The runner launches five fresh processes per version in alternating order.
Each has a new working directory and TEMP/TMP, copied hash-checked DLL, isolated
shared transports, and no inherited DARKTIDEVR overrides. Each process has a
60-second deadline; the runner restores its environment and retains logs.
Sources and benchmark executable are checked for changes across the comparison.
An existing output directory is refused. This is an explicit benchmark, not an
automatic CTest or a launcher for Darktide.

Three resource dimensions select distinct paths in the pinned sources:
2112x1188 exercises exhausted menu logging; 1920x2160 matches the default input
extent and exercises nonmatching eye-name checks; 1920x1080 is a control which
matches neither. RGBA16F does not match the uninitialised camera output format,
so no anonymous output is learned. The command-snapshot optimisation is not
exercised by these barrier-only workloads.

## Expanded comparison

The repeatability update records the selected adapter vendor/device and driver
version, requiring identical identity across runs. The runner accepts an odd
`-Trials` count from 3 to 31 (default 5), computes its median from that count,
and saves schema 2 with the trial count and adapter identity.

A 15-trial-per-version comparison selects vendor 4318/device 9860, hardware
adapter, driver integer 9007199255790656. Local Windows device inventory maps these IDs to NVIDIA GeForce RTX 4090, driver 32.0.16.1088. All 30 processes retain 4,096 matching
normalized diagnostic lines, with the same digest shown below. Milliseconds
per 40,000 recorded barriers:

| Workload | Accepted median (min-max) | Candidate median (min-max) |
| --- | ---: | ---: |
| Exhausted menu log | 11.0243 (10.5315-11.9635) | 5.1497 (5.0400-5.9920) |
| Short name matching | 11.0891 (10.7104-15.6105) | 7.0136 (6.8307-10.0426) |
| Control | 5.1804 (4.9660-6.9289) | 5.1031 (4.9990-5.5423) |

The targeted paths remain faster. Control medians differ by 0.0773 ms with
overlapping ranges; the earlier small control slowdown does not recur here.
This is still command-recording CPU time, with no GPU submission or game FPS
measurement. Both installed DLL hashes remain unchanged.

Receipt: `artifacts/unattended/native-hook-comparison-15-trials-20260909/comparison.json`.
Build receipt: `artifacts/unattended/hook-performance-repeatability-build-20260909.log`.
Benchmark executable SHA-256:
`4B338F71188B2AE0D96EFAE9FFB5967B6240A2CBDA18D283F3313E5321C3449C`.

## Earlier five-trial results

System CPU: AMD Ryzen 7 9800X3D. Windows default D3D12 adapter selection is used;
its identity was not recorded by this version of the executable. No power,
graphics, runtime or driver setting was changed for the comparison.

Final verified run, milliseconds per 40,000 recorded barriers:

| Workload | Accepted median (min-max) | Candidate median (min-max) |
| --- | ---: | ---: |
| Exhausted menu log | 11.3766 (10.7169-22.5319) | 5.6263 (5.2900-5.9714) |
| Short name matching | 10.9198 (10.7404-17.9344) | 6.9455 (6.7413-8.8562) |
| Control | 5.0514 (4.9840-5.1365) | 5.3798 (5.1521-6.0781) |

The two targeted paths improve in this recording workload. The control is
slightly slower in the final run; an earlier complete run measured medians
5.17/5.15 ms. There are outliers and scheduling/driver variability, so these
results do not establish a general speedup or a statistically characterised
regression in unaffected work. They do not quantify game hook frequency or fix
the sustained VDXR submission delay.

Every process retained exactly 4,096 menu diagnostic lines. After normalising
only command-list/resource pointer addresses, all ten logs have the same SHA-256:
`5DC7F855F6BF4DAD70E4A40514BFB79ABE1F9FFE65FB09C3B30BD16D0DF20005`.
Thus the saving does not come from omitting the admitted diagnostic payloads.

Final receipt: `artifacts/unattended/native-hook-comparison-verified-20260909/comparison.json`.
Per-process DLLs, stdout/stderr and diagnostic logs are retained alongside it.
Earlier complete run: `native-hook-comparison-final-20260909/comparison.json`.
The first exploratory run used 1920x1080 for workload 1 and did not exercise the
name matcher; do not attribute its workload 1 to name matching.

## Repeat

Build `darktidevr-hook-performance` in the isolated Release build. Run
`tools/stereo/compare-native-hook-performance.ps1` with `-Executable`, `-Baseline`,
`-Candidate`, `-BaselineHash`, `-CandidateHash` and a new `-OutputDirectory`.
Paths may point to the installed baseline for reading; only copied DLLs are loaded.
Build receipts: `hook-performance-build-20260909.log` and
`hook-performance-build-final-20260909.log` under `artifacts/unattended`.
No new CTest was registered. Both actual installed native copies remain unchanged.
The focused candidate stays staged and requires Ready before real deployment.

## Actual Map/Unmap hook measurement

The explicit hook benchmark now supports `DLL --mapping` and
`DLL --mapping-control`. Both load the same copied DLL and create 1,024 upload
buffers on the same adapter; control leaves native hooks uninstalled. Each of
three workloads warms 1,000 Map/Unmap pairs, then times 10,000 pairs. The hook
case requires exact deltas of 10,000 maps, matched resources and unmaps; control
requires all three deltas to remain zero. Buffers are mapped without CPU reads
or writes. There is no command queue execution, Present, XR session or game.
Default barrier-recording mode remains unchanged.

`measure-native-map-hooks.ps1` checks the DLL hash, creates fresh process/temp
isolation, alternates hooked/control order, checks adapter/driver identity and
completion/counter evidence, preserves input hashes and reports every trial.
Use explicit `-Executable`, `-Library`, `-LibraryHash`, `-OutputDirectory` and
optional odd `-Trials` (default five). It does not install a game payload.

Five fresh processes per mode using focused native `8b3697a`, DLL hash
`63592118307969E087F7EBC849BB011291C4C75708591C5092966F001A74235B`, report these
median milliseconds per 10,000 pairs:

| Buffer distribution | Unhooked control | Hooked |
| --- | ---: | ---: |
| Repeated 16 early allocations | 0.4725 | 11.2978 |
| Newest allocation | 0.4714 | 3.1865 |
| Cycle all 1,024 allocations | 0.8311 | 7.1080 |

These results include driver Map/Unmap, stack capture, counters, locking and
resource-pointer reverse scans. They do not isolate any one component's exact
cost. The larger early-allocation cost supports reviewing the pointer scans;
the existing GPU-address caches do not accelerate those scans. Real game map
frequency and allocation distribution remain unmeasured, so no frame-time
improvement is claimed.

Windows x64 Release benchmark builds. All ten measurement processes pass their
counter and completion checks on adapter vendor 4318/device 9860/software 0,
driver integer 9007199255790656. Executable SHA256:
`1DC64B8F57E6A7B590FA47D11CFF8C356B9A0DE7BA93943ABE9A4FB7928B87AD`.
Receipts: `artifacts/unattended/native-map-benchmark-build-20260909.log` and
`artifacts/unattended/native-map-hook-measurement-20260909/comparison.json`.
No runtime code, accepted installation or staged payload was changed.

### Retained focused pointer-cache candidate

Focused candidate `28a5500` (PR #220), based on `516f935`, adds a 64-entry
resource-pointer cache for Map, Unmap and staging updates. Exact keys retain
indices into current metadata and expire on registration/destruction. Unmap
retains the filtered reverse-scan fallback when the newest identity does not
match the current mapping/subresource. Counters and stack capture are unchanged.

Five hooked and five unhooked processes per DLL run in successive baseline and
candidate batches, alternating hooked/control order within each batch. Hooked
medians per 10,000 Map/Unmap pairs are 11.2433 to 3.7986 ms for early allocations,
3.1519 to 3.1274 ms for newest, and 7.2709 to 5.2627 ms cycling all allocations.
Newest ranges overlap; early/cycling ranges do not. All 20 processes pass exact
map/match/unmap counts with unchanged adapter/driver identity. This measures
constructed mapping workloads, not game frame time or upload-staging speed.
Receipts: `native-map-buffer-baseline-20260909/comparison.json` and
`native-map-pointer-candidate-20260909/comparison.json` under
`artifacts/unattended`.

The same three-file runtime/test delta now applies cleanly to main development.
Its native DLL and affected executables rebuild; native hooks and buffer lookup
pass 2/2 in 2.46 seconds, headset tests OFF. Main integration receipts:
`resource-pointer-main-build-20260909.log` and
`resource-pointer-main-tests-20260909.log`. The measured DLL remains the focused
candidate, not the accumulated main binary. Neither is deployed; staged payloads
remain unchanged.

## Hook activation and production upload path

The accepted `23345e5` and current source install Map/Unmap hooks only when
broad diagnostic hooks or cluster tracing are requested. The mapping benchmark
explicitly enables diagnostics. Its measured gains therefore apply to those
instrumented modes, not automatically to a normal production session.
The upload-staging hook is also eligible for the separately requested cluster
light-visibility fix, after its engine signature check. The resource-pointer
cache serves that call site too, but the Map benchmark does not measure it.

A read-only saved-flag audit at 17:08 Brisbane finds diagnostic hooks, cluster
trace, vertex dump and draw census not requested. Performance/profile-pass files
are present but do not contain the accepted enabled token. The cluster lighting
fix presence flag is set. Source-defined paths and their presence/text grammar
were checked separately; this is saved request state, not live activation or
Ready certification. Receipt: `artifacts/unattended/performance-hook-flags-20260909.json`.
No flags were written.

The upload-flush source now checks `cluster_trace_log` before locking
`cluster_constant_copy_mutex` and querying ring membership. Both resulting
booleans feed trace-only branches. Snapshot collection, registry/staging metadata
updates, lighting-patch locking and writes, and the original flush call stay
unchanged. With tracing inactive, one mutex acquisition and membership lookup
are avoided per valid upload snapshot. With tracing active at this gate the
same membership query runs. No timing or game FPS claim is made for this small
source-level change; trace arming across an in-flight callback is not a measured
acceptance case.

Windows x64 Release native DLL builds, and the existing native hook check passes
1/1 in 0.43 seconds, headset tests OFF. That isolated check does not invoke the
version-gated engine upload-flush target; dependency inspection establishes the
trace-only scope, while live acceptance remains outstanding. Receipts:
`artifacts/unattended/upload-trace-lock-build-20260909.log` and
`upload-trace-lock-tests-20260909.log`. The independent focused extension
`24687ff` now includes this guard and is staged separately; the measured map
build `28a5500` remains preserved as its earlier comparison baseline.
# Interleaved mapping comparison at session close

9 September: the runner now accepts optional `-ComparisonLibrary` and
`-ComparisonLibraryHash` together. It alternates library and hook/control order
each trial, retains fresh isolated processes, verifies both source/copy hashes
and adapter identity, and emits schema 2 with a library label per observation.
Single-library invocation retains schema 1; a three-trial invocation passes.

Five interleaved trials compare focused buffer `516f935` with preserved pointer
candidate `28a5500` (20 processes, 60 workload observations):

| 10,000 Map/Unmap pairs, hooks enabled | Baseline median | Candidate median |
| --- | ---: | ---: |
| Repeated first 16 resources | 11.2929 ms | 3.6309 ms |
| Newest resource | 3.1737 ms | 3.7194 ms |
| Cycle all 1,024 resources | 7.4291 ms | 5.4128 ms |

The newest-resource result is **17.2% slower** in this run; its ranges narrowly
overlap (3.0693–3.2804 versus 3.2642–3.8605 ms). Earlier successive batches showed
similar newest-resource medians. Keep this unresolved tradeoff visible: the
cache is not an across-the-board timing win. Early/cycling ranges remain
separated. Control medians are 0.6820/0.4755, 0.5016/0.4729 and 0.7932/0.7854 ms
(baseline/candidate), with overlapping ranges and notable early-control noise.
Actual game distribution and frame-time impact remain unmeasured. These hooks
are diagnostic-mode paths, and no GPU work, game or XR session ran.

All counter/completion checks pass. DLL hashes remain those recorded for
`516f935` and `28a5500`; executable hash is
`1DC64B8F57E6A7B590FA47D11CFF8C356B9A0DE7BA93943ABE9A4FB7928B87AD`.
Receipts: `artifacts/unattended/native-map-interleaved-20260909/comparison.json`
and `native-map-single-interface-20260909/comparison.json`. No staged bytes change.
