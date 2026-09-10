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

## Stationary SoloPlay results, 10 September 2026

Matching 120-second mission-start trials use cm_archives difficulty 3, simulator
120 Hz, DLSS Quality, Reflex On, FG Off, unlimited cap, and 13 configured
workers (six effective in the separately observed engine pool). The native
diagnostic-cleanup build is unchanged. Analysis excludes the first ten seconds.

| Mesh streaming | Distinct native FPS | GPU busy | Board power | Board memory |
| --- | ---: | ---: | ---: | ---: |
| Disabled A | 79.08 | 66.04% | 280.65 W | 9,212 MiB |
| Normal matching control | 74.76 | 62.76% | 270.12 W | 7,436 MiB |
| Disabled B | 79.88 | 66.69% | 282.08 W | 9,225 MiB |

Both disabled runs improve native throughput by approximately 6–7% against the
matching control, using about 1.7 GiB more board memory. This is a repeatable
lead in one stationary scene, not evidence about traversal stalls, combat,
visual equivalence, or smaller GPUs. Keep the accepted streaming setting.
All three runs exit cleanly and report exact file restoration.

Local evidence: `synthetic-solo-mesh-disabled-a-20260910`,
`synthetic-solo-mesh-default-a-20260910`, and
`synthetic-solo-mesh-disabled-b-20260910` under `artifacts/unattended`, with
matching `solo-mesh-*-gpu-20260910.csv` telemetry. These machine-local captures
are excluded from Git.

## Budget override boundary

On engine SHA-256
`6fce8db87a77a412b22ef9f33f74fa16ef85126cc0fbb24187d78b85fc7a19d3`,
startup owner `285ee0` reads the user settings object at application `+148`
for `mesh_streamer_settings.disable` (`2871ac` onward), overriding the
application-settings default. The constructor at `2ccf30` reads budget,
eviction and limits from the separate application-settings object at `+140`
(`2cdcc4` onward), choosing its `win32` section when present. The budget accepts
float or integer values and converts milliseconds to seconds before storage.

This inspected path does not establish a user-settings override for the numeric
budget. Do not add a purported user-budget benchmark variable based only on the
shared section name. Captures are in `mesh-streamer-settings-parser-20260910.txt`,
`mesh-streamer-parser-labels-20260910.txt`, and
`mesh-streamer-user-config-20260910.txt` under the local artifact directory.
