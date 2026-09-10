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
