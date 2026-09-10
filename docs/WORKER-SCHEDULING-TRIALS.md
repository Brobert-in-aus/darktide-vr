# Worker-count control for the CPU-bound mission workload

The benchmark machine has an eight-core, sixteen-thread Ryzen 7 9800X3D. The
saved game setting requests 13 workers. A thread making presentation calls
uses nearly one logical core while the native-only mission workload leaves
substantial GPU idle time. That motivates a scheduling comparison; it does
not prove that the existing worker setting is wrong.

`-WorkerThreads 8` changes only the active top-level `max_worker_threads` value.
The detected-user cache and other settings remain intact. Zero means preserve
the current value. The runner records the requested setting and restores the
entire settings file after the run. Tests reject missing or duplicate active
fields and verify cache preservation. This records configuration, not an
engine API confirmation of the number of running workers.

Compare eight and thirteen workers with FG off, Unlimited, 120 Hz,
2112x2304 eyes, DLSS Quality and the same stationary cm_archives difficulty-3
workload. Use native `FB244186...` and simulator `3C3F41C...` throughout this
comparison. CPU/GPU profiler flags are disabled. Repeated comparisons are
needed before changing a recommendation; no permanent worker setting is
installed by these trials.

The eight-worker trial delivered 74.90 native pairs/s over 112.15 analyzed
seconds; thirteen delivered 74.19 over 111.60 seconds. Their 110-second board
windows averaged 62.59% / 62.13% busy time and 270.43 / 268.40 W respectively,
with complete coverage. Both had no generated frames, repeats or pose
mismatches and passed shutdown/restoration. The difference is below 1% in one
trial per setting, so no worker-count recommendation is changed. The saved
thirteen-worker setting remains restored.
## Later engine-count observation

Read-only engine mapping and a bounded live diagnostic subsequently found six
workers in the relevant pool with the configured value of 13. Initialization
also applies a CPU-derived bound and an upper clamp of 12. The earlier 8/13
rows describe requested settings and must not be interpreted as proof of two
different effective pools. See [dispatcher layout](ENGINE-DISPATCH-JOB-LAYOUT.md).
