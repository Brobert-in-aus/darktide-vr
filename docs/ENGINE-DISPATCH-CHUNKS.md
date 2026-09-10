# Observed weighted dispatch partitions

Read-only inspection of the verified dispatcher shows a nominal partition count
derived from workers plus the assisting caller and a 64-bundle minimum batch.
For weighted splitting, the budget is historical aggregate cost divided by
historical bundle count, scaled to the current bundle count and divided by the
nominal partition count (`7aa8ef`–`7aa953`). Category estimates are accumulated
until this budget is exceeded. The splitter can therefore produce fewer chunks
than the nominal count; it also bounds extra chunks before appending a tail.

The bounded sampler reads the existing chunk count and at most 32 boundary
entries at the exact verified dispatcher wait. The dispatcher prolog establishes
RBP=RSP+0x100; count and boundary-array fields at RSP+0x64/+0x68/+0x70 remain
live until cleanup after that wait. Failed reads are absent. The reader requires
matching counts, a zero first boundary, strictly increasing starts and coverage
ending at the known weighted bundle count. Bundle sizes are not draw counts or
CPU costs.

## Mission observation, 10 September

The 1,000-sample stationary SoloPlay native-rendering capture returned 79 valid
partitions. Every observation had six workers and weighted splitting enabled.

| Chunks | Observations |
| ---: | ---: |
| 5 | 1 |
| 6 | 31 |
| 7 | 10 |
| 8 | 19 |
| 9 | 16 |
| 10 | 2 |

The current workload held 4,629–5,627 bundles and individual chunks ranged from
18 to 1,780 bundles. For example, one six-chunk partition was
`1477, 992, 242, 712, 977, 485`. These are repeated wait observations, not an
unbiased distribution across frames. The worker/assisting-caller capacity is
seven, so 32 observations had fewer chunks than that capacity. This is a lead
for scheduling work, not proof that increasing chunks helps: weighted costs,
command-list setup and dependencies still matter.

Windows x64 Release sampler build and the isolated suspension checks pass.
The reader still accepts the preceding paired capture without chunk fields.
Mean pause was 60.99 microseconds; maximum was 3,163.9 microseconds, so this run
must not be used as an uninstrumented performance comparison. All 1,000 samples
completed; mission exit, zero pose mismatches and exact restoration passed.

Ignored evidence: `synthetic-solo-dispatch-chunks-a-20260910/thread-residency`
and `engine-dispatch-splitter-20260910.txt`. No engine state is modified.
