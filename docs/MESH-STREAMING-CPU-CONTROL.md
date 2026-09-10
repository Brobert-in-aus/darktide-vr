# Mesh-streaming CPU control

In the saved 1,000-sample render-thread capture, 29 clock-query stack samples
returned to engine RVA `2c0f5e`, inside primary owner `2c0a20`, labelled
`mesh_streamer::update`. Inspection shows a time-budget check after each item.
This supplies a maintenance-work lead; sample counts are not CPU-time shares.

Fatshark's [engine developer confirms](https://forums.fatsharkgames.com/t/mesh-streaming-not-working-correctly/83361/7)
the restart-only user override `mesh_streamer_settings = { disable = true }`.
The project already has a standalone diagnostic for this setting. The benchmark
now accepts `-MeshStreaming Disabled`, defaulting to Preserve, using the same
override inside its exact settings-backup transaction. It rejects missing,
nested or ambiguous sections and preserves unrelated fields.

This diagnostic can change mesh residency and memory use. It is not a proposal
to disable streaming by default, nor a worn visual-acceptance test. The optional
`memory.used [MiB]` telemetry column is now summarized with the existing workload
window and unknown-interval rules. Older telemetry without that column remains
valid. Board memory totals include other processes.

Validation commands:

```powershell
& tests/tooling/test-synthetic-framegen-settings.ps1
python tests/tooling/test-synthetic-gpu-load.py
```

Settings checks pass for inherited/false/true overrides and malformed/duplicate
rejection. All three GPU-reader tests pass, including optional memory units and
backward compatibility. The benchmark runner parses successfully.
