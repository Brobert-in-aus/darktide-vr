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
extra reads occur at an admitted wait; failed reads remain absent. No GPU
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

The branch-flag follow-up is pending. Local static evidence is under `artifacts/unattended`:
`engine-bundle-writer-5c6bf0-20260911.txt`,
`engine-bundle-writer-5c63c1-20260911.txt`,
`engine-bundle-writer-5c65c4-20260911.txt`,
`engine-category-7d0040-20260911.txt`, and
`engine-dispatch-strings-20260911.txt`.
Live evidence: `synthetic-dispatch-bundles-20260911/thread-residency/`.
