# Decode the installed engine's packed shaders

The shader-library groups have a second Oodle compression layer. Earlier scans
correctly rejected their embedded `DXBC` markers as invalid standalone
containers; decoding the enclosing records now exposes valid containers.
This enables offline inspection of the engine's lighting and motion code.

## Observed format and tool

`tools/renderer_probe/decode-packed-shader-groups.py` recognizes this observed
envelope in already-extracted groups:

```text
u32 compressed_length
Oodle block beginning 8c 06, exactly compressed_length bytes
u32 tag = 5
u32 decoded_length
```

The tool bounds both lengths, caps each decoded record at 16 MiB, verifies the
explicitly supplied Oodle DLL hash before loading it, enables the decoder's
fuzz-safe mode, and requires an exact output size plus a complete bounds-checked
DXBC container. It writes a new output directory with source hashes, record
offsets and content-addressed containers. Decoder failure rejects the operation;
it is not silently treated as an absent shader.

Only this envelope is recognized. The tool does not claim to decode the entire
group format, resolve individual shader permutations or provide a repacker.
Game assets and extracted shaders must remain outside Git.

## Installed-asset result, 10 September

Fresh extraction of the renderer bundle produced 44 groups, 17,972,979 bytes.
There were 1,904 matching records and 891 unique decoded containers. Every
container passed the existing structural bounds checker and Microsoft's DXC
`-dumpbin` successfully read all 891. Four isolated decoder tests cover envelope
bounds, truncated input, unknown tags, invalid decoded chunks, wrong output
lengths and propagated decompression failures.

All 44 group name hashes match the 44 `shader_libraries` paths in the freshly
verified renderer configuration using the extractor's MurmurHash64A algorithm.
This identifies libraries, not individual entry-point names or live PSO use.
The clustered-shading library contains 18 unique decoded programs.

Oodle DLL SHA-256 used:
`8595A4795F1E0C7F548598F3E2AA528B6BE5456C6D934C665182EAECB04156C0`.
The library is the installed game's `binaries/oo2core_9_win64.dll`.
DXC is Windows SDK `10.0.26100.0/x64/dxc.exe`.

Run the decoder with extracted input/output directories and explicit `--oodle`
and `--oodle-sha256` arguments. Run its isolated tests with
`python tests/tooling/test-packed-shader-groups.py`. No game or headset is needed.

## First performance lead and boundary

The config clears a 4,194,304-element `cluster_linked_list`. In decoded program
`cf61cfd5723e79e213ff5f53c4d97f844f5e5e0b394f941ddac8d1dcb0def36e`,
the writer allocates from a counter, exchanges a cluster head masked to 22 bits,
and writes a packed previous-node index plus light index. The consumer
`57eaa35da0d7264e8e7d084a755223b7d5e3fe8d1b1dc74eb52061efd6894984`
checks the head sentinel and follows packed links in bounded groups.

This makes redundant list clearing a concrete investigation, not an accepted
optimisation. The inspected writer masks the published index but addresses its
store with the unmasked allocation index. Capacity overflow, other writers,
resource aliases and dispatch ordering must be resolved before concluding that
all reachable nodes are freshly written. Removing the clear could change
overflow behavior even if ordinary frames appear correct. No clear, shader or
engine setting was changed, and no performance gain is claimed.

The subsequent [initialization contract](CLUSTER-LIST-INITIALIZATION-CONTRACT.md)
identifies both normal-list writers and verifies fresh-prefix behavior on the
GPU, including overflow, with poisoned prior contents. The isolated clear costs
about 11–12 microseconds; live resource aliases and ordering remain unverified.

Ignored evidence under `artifacts/unattended`: `engine-shader-groups-20260910`,
`decoded-engine-shaders-20260910/manifest.json`,
`engine-shader-library-names-20260910.json`, and
`engine-shader-disassembly-20260910`. This is offline development only.
