# Command types behind dispatch categories

Read-only inspection of engine SHA-256
`6FCE8DB87A77A412B22EF9F33F74FA16EF85126CC0FBB24187D78B85FC7A19D3`
narrows the [category-cost lead](ENGINE-DISPATCH-CATEGORY-COSTS.md). Addresses
below are build-specific RVAs, with chained unwind fragments resolved to their
primary functions. No engine instructions or data are changed.

## Static links

`5c6bf0` appends a 32-byte descriptor to a command owner's array at `+68/+70`.
It explicitly sets descriptor flags to `0x20` (`5c6c22`) and writes command
opcode `0x23` (`5c6d4a`). The descriptor carries a sort key, command-buffer
owner, start offset and loop extent. The command header separately carries its
opcode, allocation size and payload offset.

The dispatcher sorts those descriptors, then `7cb490` chooses a cost category
from descriptor `+18`: sign bit first (3), then `0x20` (2), then `0x4` (1), else
0. Its opcode table at `7d0264` routes `0x23` to `7cb6ac`. This is a common
kernel-command path with several branches, not a single draw operation:

- Payload `+1c` bit 0 selects `7c8410`, which can issue compute Dispatch or
  ExecuteIndirect. Bit 1 selects its alternate command queue.
- Otherwise descriptor bit `0x20` and payload bit 2 together select `7b0c90`.
  It queries ID3D12GraphicsCommandList4 (IID
  `8754318e-d3a9-4541-98cf-645b50dc4874`) and uses SetPipelineState1 and
  DispatchRays/ExecuteIndirect. Without payload bit 2 it uses the compute path.
- Without descriptor bit `0x20`, the descriptor sign bit can select `7a4230`,
  identified by embedded function/assertion strings as
  `D3D12Instancer::insert_instance`; otherwise it uses a direct draw path.

The initially investigated instancer call is therefore **not** evidence of
category-2 instancing cost. Actual payload flags are needed to distinguish its
compute and ray branches. Local Windows SDK 10.0.26100.0 d3d12.h confirms the
queried interface and vtable offsets e8 (SetComputeRootSignature), 1d8
(ExecuteIndirect), 258 (SetPipelineState1) and 260 (DispatchRays).

Two other descriptor builders, primary functions `5c6380` and `5c6580`, derive
the `0x20` descriptor bit from the sign bit of an upstream record's flags.
The latter can also set the descriptor sign bit, which takes category-3
precedence. These paths are another reason not to equate category 2 with one
opcode, shader or rendering pass without live evidence.

## Bounded live observation

The existing exact-build dispatch-wait sampler now reads eight evenly spaced
positions in the sorted descriptor array at dispatcher RBP−30. It follows each
descriptor's owner only far enough to validate the buffer bounds and read the
first command header, plus the one branch flag word for opcode 23. At most 32
reads plus the descriptor-array pointer occur at an admitted wait in the branch-flag version; failed reads remain absent. No GPU
resources or target state are modified. Other workers continue running, so
these are sequential observations. A candidate branch is not proof that its
GPU command executed successfully.

The loop checks command **starts** against its descriptor end. A final command
can extend beyond that end: `5c6bf0` stores a payload-based extent but the command
allocation also includes its header/alignment. Validation therefore bounds the
full first command by its owning buffer, not by the descriptor extent alone.

The reader reports category, raw flags and first opcode together. Evenly spaced
positions in a sorted array are not random workload samples; repeated waits do
not establish per-frame counts, CPU-time shares or the slowest executing job.
This probe is intended to identify the kinds of work present before selecting
a more focused optimisation.

## Validation

Windows x64 Release sampler build, `dispatch_bundle_probe` and
`thread_residency_self` pass. The latter retains the existing checks that a
pre-existing suspend count is preserved. Four reader tests cover precedence,
unknown records, older captures and invalid positions/fields. The previous
1,000-sample chunk capture still parses with its original 79 valid partitions
and no invented bundle observations.

The first mission capture returned 584 valid first-command observations at 73
waits. All 88 category-2 observations had opcode 23; categories 1 and 3 also used
that opcode. This initial sampler did not read payload flags, so route attribution
remains unknown in its report. Mean pause was 56.99 microseconds, maximum 379.2.
The initially attempted capture preceded Present profiler admission and was
rejected without suspending a thread; a later retry completed all 1,000 samples.
The mission exited cleanly, reported zero pose mismatches and restored files.
Its background sampler collected 31 valid and three unavailable records. No
sampled Streamer engine exceeded 0.1%; coverage is explicitly incomplete.

The branch-flag follow-up (sampler SHA-256
`E3ADB0622FFC9C89DE7111F9E945BA4FC1ABFDBE9F78C1B86E6A9CAF9BC22FDA`)
completed 1,000 samples and 704 valid descriptor observations at 88 waits:

| Category | Sampled first-command route | Observations |
| --- | --- | ---: |
| 2 | Opcode 23, payload flags 1: compute on graphics queue | 121 |
| 3 | Opcode 23, payload flags 0: instancer candidate | 266 |
| 1 | Opcode 23, payload flags 0: direct draw candidate | 40 |
| 0 | Other first opcodes; no kernel-route claim | 277 |

All sampled category-2 entries used the compute branch, not the ray branch.
Neither ray dispatch nor the alternate compute queue was selected by these
sampled first commands. This is not an exhaustive census of every command or
proof of disabled ray tracing throughout the game. The next useful target is
compute-command preparation/binding within `7c8410`, and the identity of those
compute kernels, before changing queue policy or sharing work between eyes.

Mean pause was 57.73 microseconds, maximum 682.2. The 60-second mission diagnostic
used the saved higher resolution, native rendering with Quality DLSS, accepted
Lua, focused Present-CPU DLL E87B739 and benchmark viewer 216E3F76. Exit was
clean, pose mismatches were zero, saved files restored, and normal proximity
handling was restored. Background GPU recording returned 21 valid and one
unavailable sample; no sampled Streamer engine exceeded the threshold. This is
instrumented evidence, not an uninstrumented FPS comparison.

Local static evidence is under `artifacts/unattended`:
`engine-bundle-writer-5c6bf0-20260911.txt`,
`engine-bundle-writer-5c63c1-20260911.txt`,
`engine-bundle-writer-5c65c4-20260911.txt`,
`engine-category-7d0040-20260911.txt`, and
`engine-dispatch-strings-20260911.txt`.
Live evidence: `synthetic-dispatch-bundles-20260911/thread-residency/`.
Follow-up: `synthetic-dispatch-routes-20260911/thread-residency/`.

## Compute identities — 11 September follow-up

The identity extension reads a further 32 bytes at opcode-23 payload +58:
resource tag (64 bits), object and batch tags (32 bits each), three uninterpreted
words, and the runtime kernel handle at +74. These are the fields consumed by
the engine diagnostics and compute lookup. It does not follow that handle or
read shader resources. The bound is now 40 reads plus the array pointer per
admitted wait. Older captures retain unknown identities.

`synthetic-dispatch-identities-20260911/thread-residency/` completed 1,000 samples,
with 736 valid descriptors at 92 admitted waits. Mean pause was 58.74 microseconds,
maximum 441.9. The sampler SHA-256 was
`0C23557AA4A800F8139E1287CF26408E47B25AECB85F7B1E5A8068BB2BF8B077`.
Category-2 compute observations contained 20 distinct resource tags. The two
batch tags resolve as follows, retaining the engine's spelling:

| Batch tag | Engine label |
| --- | --- |
| `2765d852` | `gpu_visalizer_sim` |
| `372353f4` | `gpu_visalizer_emit` |

The identification uses Stingray's upper 32 bits of MurmurHash64A with seed zero,
checked against 44 independently known shader-library path hashes. A search of
243,172 local executable/source candidate tokens found these two matching batch
labels, but no names for the 20 resource tags. A hash match alone is not a unique
name guarantee; the static references provide additional evidence: initializers
at RVA 19ef20/19efa0 store emit/sim hashes at 12dc7f0/12dc7dc, and the particle
batch builder at 563770 consumes those globals at 563df2/563e20. All RVAs refer
to the exact executable hash specified above in this document.

This identifies sampled particle emission/simulation work, not its time share
or a duplicate-per-eye count. Builder 563770 gates the two batches on object
byte +514; its caller at 46df7b also selects between paths. Establishing the
lifetime of that flag and how the caller runs across views is the next step.
No simulation suppression or queue-policy change is justified yet.

The mission used Quality DLSS, FG off, unlimited native cap, saved 2496x2688
per-eye resolution, 120 Hz, HUD/menu on, preview/debug off and the focused
Present CPU profiler. It exited cleanly, restored saved files, and recorded
zero pose mismatches. Physical readiness was unavailable; this was the
authorized simulator fallback. GPU recording returned 21 valid and one
unavailable sample with no sampled Streamer engine above the busy threshold;
coverage remains incomplete. Normal proximity handling was restored.

Validation: Windows x64 Release build; CTest `dispatch_bundle_probe` and
`thread_residency_self` (2/2); five bundle-reader tests and the unwind-index
regression passed. Local supporting records include
`dispatch-identity-name-candidates-20260911.json`,
`engine-particle-batch-construction-20260911.txt` and
`engine-particle-batch-caller-20260911.txt` under `artifacts/unattended`.
