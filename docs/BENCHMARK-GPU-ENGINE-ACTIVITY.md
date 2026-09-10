# Background GPU activity in simulator benchmarks

The [11 September frame-production investigation](FRAME-PRODUCTION-2026-09-11.md)
found substantially different simulator throughput when Virtual Desktop desktop
encoding was active. A sleeping-headset intervention removed the observed
encoder activity; waking the headset did not restore it. Record activity directly
instead of inferring it from headset power state.

`run-synthetic-framegen-benchmark.ps1 -ObserveGpuEngineActivity` now starts a
bounded background sampler before the consumer. It records Windows GPU Engine
counters for Darktide, VirtualDesktop.Streamer, VirtualDesktop.Service and the
viewer every five seconds. The record includes UTC time, process identity,
individual engine instance/type, percentage and counter validity. It never
changes streaming settings or stops a measured process.

The runner stops and removes its own sampling job during cleanup. The sampler
also has an independent lifetime bound. Records flush as they are written to
`gpu-engine-activity.jsonl`; job errors go to `gpu-engine-activity-job.log`.
Unsupported/localised counter paths and collection errors remain unavailable,
not zero utilisation. Sampling is opt-in and should be matched between controls.
`capture_ms` is elapsed collection time, including the counter sampling interval,
not CPU time consumed by the sampler.

`analyze-synthetic-framegen.py` includes these observations in `summary.json`.
It retains each engine's maximum and busy-sample count separately: two encoders
at 43% do **not** mean 86% board utilisation. A process can be absent, have no
reported engines above 0.1%, show activity, or have incomplete counter coverage.
The report covers the whole recorded run including loading; it is not aligned
automatically to the selected FPS warmup window. Inspect timestamps/raw records
before attributing a steady-state difference. Sampling gaps cannot rule out
activity between observations.

## Validation, 11 September 2026

Eight frame-generation analysis tests pass, including separate encoder values,
unavailable versus idle data, malformed percentages and process identity checks.
Both PowerShell scripts parse and `git diff --check` passes. A six-second
standalone Windows counter capture succeeded. A separate background-job check
collected a real sample, observed its stop file and completed cleanly, after
which the owning job was removed. No game or headset was needed for these checks.

Local evidence: `artifacts/unattended/gpu-engine-sampler-offline-20260911.jsonl`
and `gpu-engine-job-check-20260911.jsonl`. The integrated game-run option is
ready for the next substantive benchmark; no additional gameplay smoke run was
performed solely to test this recorder.
