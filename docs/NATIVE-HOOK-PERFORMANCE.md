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

## Recorded results

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
