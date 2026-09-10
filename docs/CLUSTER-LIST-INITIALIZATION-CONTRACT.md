# Clustered-light list initialization

The installed renderer config declares a 30×17×64 cluster grid, 500 maximum
lights and a 4,194,304-word normal linked list (16 MiB), cleared to all ones.
This is separate from the 64,000-word ray-tracing list. The grid and light limit
alone permit 16,320,000 memberships, so they do not rule out list overflow.

The 891 decoded renderer-library containers contain two bindings that write
the normal `cluster_linked_list`: `cf61cfd5…def36e` and `795d7b14…5b8e1b`.
Both reserve contiguous ranges from `cluster_counter`, exchange a cluster head
with the allocation index masked to 22 bits, and store a packed previous-head
index plus light index at the **unmasked** allocation address. Their depth-range
loops write each reserved entry. The compaction reader `57eaa35d…894984` follows
at most 32 nodes; the visualization reader `e11081ee…21f92` also follows masked
links. This inventory covers the decoded libraries, not every possible live
resource alias or material program.

## Conditional equivalence

For a counter starting at zero with N contiguous allocations, after every
reserved node store completes, all indices in `[0, min(N, capacity))` are freshly
written. If N is below capacity, every published head and link refers to this
prefix or the sentinel. If N reaches capacity, the entire backing list is freshly
written, including the indices to which overflowing heads wrap. Thus overflow
does not by itself make old list contents reachable. It can still cause stock
truncation, cycles and missing lights; this argument does not fix those defects.

This assumes no integer counter/address wrap, no abandoned allocations, cleared
heads and counters, valid input ranges, completed stores before reading, and no
other reader of untouched storage. Microsoft's [raw-store semantics](https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/store-raw--sm5---asm-)
describe discarded out-of-bounds UAV components; the model uses that behavior.
The isolated DXIL fixture below checks that assumption on the local GPU.

`tests/tooling/test-cluster-list-initialization.py` exercises 768 seeded cases,
including interleaved range writers, deferred/reversed store completion, empty
lists, sentinel boundaries and multiple capacity wraps. Random prior contents
produce the same bounded traversal as a full clear. Three negative cases show
that missing writes, a non-reset counter and retained cluster heads break the
contract. This is a model of the decoded operations, not a test of game rendering.

## Hardware fixture

`darktidevr-cluster-list-benchmark` loads a caller-supplied decoded writer and
creates its actual four UAV bindings, dimensions constant buffer and either
texture-array or raw-buffer light bounds. It uses 1, 128, 129 and 500 lights
covering all clusters, for 32,640, 4,177,920, 4,210,560 and 16,320,000 allocated
nodes. The middle cases straddle the 4,194,304-node capacity.

Every trial poisons the list before selecting full clear or retained contents.
Readback verifies all head indices, exact per-cluster counts, the allocation
counter, every node in the initialized prefix, and every untouched tail word.
The poison's light index exceeds the fixture's light range, so passing the
prefix check establishes fresh writes. Atomic insertion order can differ
between runs; this checks initialization invariants rather than pretending the
entire arrays must match byte for byte. Explicit UAV barriers precede consumers.

Both original writers passed all 16 trials with the D3D12 debug layer enabled
and no warnings after correcting the fixture's initial buffer transitions.
Both then passed 16 trials without the debug layer on the RTX 4090. The texture
writer is `cf61cfd5723e79e213ff5f53c4d97f844f5e5e0b394f941ddac8d1dcb0def36e`;
the raw-buffer writer is
`795d7b14b48fa01b387dce1921846c0e3b661350b4fb92ea19fa12b41a5b8e1b`.
These hashes were verified before loading the local files.

Build the manual target with CMake, then run it with the decoded shader path;
add `--buffer-input` for the second writer and `--debug` for validation. Assets
are not bundled. The test is intentionally outside default CTest execution.
The Python contract model is registered as `cluster_list_initialization`.

Without the debug layer, the isolated clear plus following barrier measured
11.264 microseconds in 15 of 16 samples and 12.288 in one. The corresponding
barrier-only interval measured 0–1.024 microseconds. Writer execution contained
outliers, so no combined-dispatch speedup or game FPS improvement is claimed.
This is a small, measurable candidate, not a reason to prioritize it over the
larger stereo delivery work. Local logs are `cluster-list-*-20260910.log` under
`artifacts/unattended`; no game process was involved.

## Remaining work

Attribute the live clear, shader bindings and barriers to the exact resource.
Removing an
engine clear must retain required UAV/alias ordering; changing a config boolean
does not establish this. The fixture does not prove the full renderer's alias
lifetimes, every dispatch mode or visual equivalence. No game clear or renderer
setting has been changed.
