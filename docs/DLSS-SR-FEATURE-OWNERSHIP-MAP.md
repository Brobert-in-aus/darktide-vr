# SR feature selection in the installed engine

This read-only map uses Darktide executable SHA-256
`6fce8db87a77a412b22ef9f33f74fa16ef85126cc0fbb24187d78b85fc7a19d3`.
Addresses are RVAs for that exact build. They are inspection evidence, not
approved hook locations or inferred callable engine ABIs.

The renderer function with primary unwind owner `7cb490` contains the
`slDLSSSetOptions` and `slEvaluateFeature(DLSS)` labels. At `7cde27`, the selected
record's address plus eight becomes the viewport pointer passed to the options
call at `7cde84`. The evaluation path reloads the same indexed record at
`7cdeb9`, adds eight, and writes that pointer into a one-element input array.
It passes feature zero, the current frame token, one input and its command
buffer to the indirect call at `7cdeda`.

That instruction resolves to import slot `e969d8`, which the PE import table
names `sl.interposer.dll!slEvaluateFeature`. Feature zero is DLSS SR in the
pinned [Streamline core types](https://github.com/NVIDIA-RTX/Streamline/blob/v2.7.30/include/sl_core_types.h).
The [core API declaration](https://github.com/NVIDIA-RTX/Streamline/blob/v2.7.30/include/sl_core_api.h)
matches the observed five arguments. Thus the engine has a concrete SR viewport
identity available at the API boundary, independent of the pending capture-tag
queue. This does not yet map its numeric viewport to a physical eye or show
that a nested NGX evaluation executes synchronously on the same thread.

A bounded observer can test that last link by retaining only the viewport,
frame token and command buffer for the duration of the SR API call, then
recording whether sampled NGX SR evaluations see that same context. It must
restore prior context on nested calls and leave other features unlabelled.
Absence of a synchronous match must remain unknown. Actual camera/eye linkage
is a separate validation step; do not assign eyes from alternating call order.

Reproduce the label map with `tools/renderer_probe/map-engine-render-scopes.py`,
the executable, its required `--expected-sha256`, an artifact `--output` and
`--scope-family dlss`. The default render family is unchanged. The map follows
chained unwind ownership and reports its linear-disassembly limitations.
Local evidence is `artifacts/unattended/engine-dlss-ownership-20260910.json` and
`engine-sr-functions-20260910.txt`. No process memory or rendering was modified.
