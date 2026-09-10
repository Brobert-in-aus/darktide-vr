# Particle simulation and stereo ownership

11 September 2026. Read-only investigation of Darktide 1.3.770.210, SHA-256
`6FCE8DB87A77A412B22EF9F33F74FA16EF85126CC0FBB24187D78B85FC7A19D3`.
Addresses below are RVAs for that executable only, not approved hook sites.

The [bounded command capture](ENGINE-DISPATCH-BUNDLE-COMMANDS.md) identifies
GPU particle emission and simulation among sampled category-2 compute commands.
Static tracing finds an update-needed flag, but no once-per-view consumption of
that flag in the regular particle builder. This is a lead for repeated work,
not proof of duplicate GPU simulation or a safe optimisation.

## Update and render paths

| Function | Evidence and role |
| --- | --- |
| `46b380` | `ParticleSystem` update-side owner; calls `561e00` at `46beea` |
| `561e00` | Writes particle object byte `+514`; advances ping-pong/frame counters when set |
| `46cfc0` | `ParticleSystem` rendering owner; regular and shadow branches |
| `563770` | `GPUVisualizer::render`; builds emit/sim/render batches |
| `564e80` | Constructs each kernel command and its parameter bindings |
| `560b10` | Resolves particle resource/constant parameter locations and writes handles |

`561e00` sets byte `+514` at `5626fc` following a floating-point comparison
and a `+510 < 10` counter check. A later emission path sets it at `5633e0`.
When set, counters at `+510`, `+4e4` and `+4e8` advance at `563483–563491`.
The exact semantic names of those counters and compared values remain inferred.

`563770` reads `+514` into R15B at entry. That value gates both the emit and sim
calls at `563e9b` and `563ebe`, plus later auxiliary work. It does not clear the
flag. The render batch has a separate low-bit control from a caller argument.
The `+4e4` parity selects the two buffers at object `+50` and `+58`.

The containing `46cfc0` function takes a regular path to `563770` at `46df7b`,
or a separately labelled `GPUVisualizer::render_shadows` path. Its callers
are `37a340` and `414430`; the latter supplies the shadow selector as one.
These callers and their parameter roles were followed through chained unwind
records, rather than treating fragments as standalone function entries.

## Why a blanket second-eye skip is premature

The regular builder updates matrix-derived constants in object `+138`, using
the input transform and view matrices. Helper `564e80` also constructs bindings
using view-dependent matrix addresses. This includes rendering work as well as
the candidate shared simulation. Skipping the function would remove required
second-eye rendering and parameter preparation.

Buffer helper `560b10` builds a temporary hash lookup from kernel parameter
metadata, then resolves resource handles and constants. Static initializer
references identify names including `rw_particle_data_raw`,
`r_particle_data_raw`, `rw_counterbuffer`, `rw_indirect_args`,
`rw_render_indirect_args`, `r_external_emit_data_buffer`, and
`c_particle_system_per_frame`. These names and ping-pong selection make buffer
identity/lifetime a useful next diagnostic. They do not establish identical
inputs, command ordering or output ownership across the two eyes.

The 1,000-sample identity capture observed primary owners `563770` twice,
`564e80` once and `560b10` once on the Present thread. These sparse samples do
not measure their CPU cost, worker cost or call frequency. The temporary lookup
could be investigated for cached parameter offsets, but has no demonstrated
performance benefit and requires layout-lifetime/invalidation evidence.

## Next evidence required

- Count regular emit/sim submissions by particle object, update serial and eye;
  distinguish repeated rendering from a new simulation update.
- Compare input/output buffer handles, per-frame constants and ordering for
  matching submissions. Identify view-dependent shader inputs before sharing.
- Measure command preparation and GPU cost with a bounded diagnostic. Keep
  diagnostic throughput separate from clean-launch comparisons.
- Only then isolate a candidate sharing/caching change and test matched Quality
  DLSS, high-resolution native and FG controls. Particle motion, collisions and
  per-eye appearance would require targeted acceptance if behaviour changes.

No engine behaviour, installed files or accepted defaults changed in this task.

## Reproduction and validation

The existing exact-hash static mapper now accepts `--scope-family particles`.
With pefile 2024.8.26 and capstone 5.0.9 available:

```powershell
python tools/renderer_probe/map-engine-render-scopes.py <Darktide.exe> `
  --expected-sha256 6FCE8DB87A77A412B22EF9F33F74FA16EF85126CC0FBB24187D78B85FC7A19D3 `
  --scope-family particles --output <report.json>
python tests/tooling/test-engine-unwind-ownership.py
```

The Windows run found seven label references in four unwind ranges, resolving
three primary functions; five unwind tests passed. The three hash initializer
references have no unwind records and remain explicitly unowned. The mapper
retains its existing hash gate and refusal to overwrite the executable.

Local ignored evidence under `artifacts/unattended`:
`engine-particle-scopes-20260911.json`, `engine-particle-update-20260911.txt`,
`engine-particle-batch-construction-20260911.txt`,
`engine-particle-batch-caller-20260911.txt`,
`engine-particle-kernel-builder-20260911.txt`, and
`engine-particle-buffer-bindings-20260911.txt`.
