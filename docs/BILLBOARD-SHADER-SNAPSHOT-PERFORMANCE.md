# Coherent single-shader diagnostic snapshots

The diagnostic report previously read each of eight shader ranks three times:
low hash, high hash and count. Every read copied and sorted the counter map,
and concurrent ranking changes could combine unrelated halves/counts.

The new optional `dtvr_copy_billboard_candidate_shaders` export copies all
records under the counter lock, releases it, and ranks only the requested prefix.
Each 16-byte sample contains both hash halves and its count. Lua resolves this
optional export once during native setup and reuses an eight-sample FFI buffer.
The log text remains unchanged. Older DLLs retain the existing ranked-read
fallback; coherence improvements apply when the bulk export is available.
No shader substitution, transform, draw or game input behaviour changes.

Five alternating Windows x64 Release trials, 1,000 diagnostic reports:

| Candidate shaders | Legacy 24-read median | Bulk snapshot median |
| --- | ---: | ---: |
| 8 | 1.4684 ms | 0.0497 ms |
| 32 | 4.7526 ms | 0.1977 ms |
| 128 | 31.3208 ms | 0.4785 ms |
| 1,024 | 302.3780 ms | 4.6740 ms |

The benchmark models the existing native ranked-read algorithm and the new
snapshot helper, including locks/copies/ranking/packing. It excludes FFI calls
and log formatting; candidate populations are constructed. No game frame-time
or actual polling-cost claim is made.

Validation covers empty/full/truncated capacity, ties, complete high/low hashes,
count packing and ownership after source mutation. Native export checks reject
null/zero/oversized requests and preserve empty output. Native DLL and affected
executables build; two focused CTests pass in 3.26 seconds. All 69 mod Lua chunks
compile. An explicit pinned LuaJIT FFI check loads copied accepted/candidate DLLs
without installing hooks, verifies the 16-byte layout and confirms legacy-symbol
fallback versus new export availability. Its source also passes the syntax gate.

No deployment. This native/Lua change is outside both staged performance payloads.
Receipts under ignored `artifacts/unattended/`:
`billboard-shader-snapshot-{build,benchmark,tests,lua-gate-final}-20260909.log`,
`billboard-shader-snapshot-ffi-{legacy,candidate,syntax}-20260909.log`, and
`billboard-shader-snapshot-ffi-hashes-20260909.json`.
