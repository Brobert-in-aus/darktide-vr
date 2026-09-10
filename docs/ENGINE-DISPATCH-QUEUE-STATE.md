# Work queues during the dispatch wait

The exact-build layout observer now reads the two pool queue counts while the
render caller is paused at its verified dispatch wait. `6f7690` assists from
the queues at pool `+110` and `+e8`; `6f7820` reads their counts at queue `+1c`.
The worker loop independently confirms the resulting pool offsets `+12c` and
`+104`. These are shared pool queues, not queues exclusive to this dispatch.

Workers keep running during the two bounded reads. Values are sequential
observations, not a coherent snapshot of all jobs or workers. A zero queue does
not mean all dispatched jobs have completed; jobs may already be executing.
The reader rejects implausible depths and preserves older receipt support.

The 1,000-sample mission capture produced 103 queue observations at the dispatch
wait. Both depths were zero in 88 observations. Queue A was nonzero in 15,
ranging from 1 to 243; queue B was zero throughout. Thus the observed wait is
usually not accompanied by a backlog in these queues. Investigate completion
of already-dispatched work and dependencies before increasing worker count.
This does not identify which executing job is last or prove an idle worker
overlapped a render wait.

Mean debugger pause was 56.16 microseconds and maximum 721.9. The capture is
diagnostic, not an uninstrumented performance comparison. Windows x64 native
build and `thread_residency_self` pass, and the reader processes older category
captures without queue fields. Evidence under ignored `artifacts/unattended`:
`synthetic-solo-dispatch-queues-a-20260910/thread-residency` and
`dispatch-queues-summary-20260910.json`.
The simulator benchmark exited cleanly and exact file restoration passed.
