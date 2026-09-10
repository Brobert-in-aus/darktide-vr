# Engine render-thread residency

The native-only mission stays near 74 FPS when DLSS input resolution is reduced.
The Present caller is busy, distinct from the Lua render caller, and selected
existing D3D12 hooks explain only about 0.75 ms per frame. The next diagnostic
locates instruction pointers on that thread and follows the dominant wait.

## Capture and interpretation

`capture-thread-residency.ps1` requires an active, ready isolated benchmark,
an exact executable hash/path/lifetime, and one thread identified by that run's
Present CPU log. A separate x64 helper captures at most 2,000 samples, with
a 30-second deadline. It briefly suspends the thread, reads its context and a
256-byte stack excerpt, and immediately undoes its one suspension increment.
No allocation, file I/O, waiting or target locks occur while it is suspended.
Pre-existing suspension is restored and rejected. Permissions are not modified.

This follows Microsoft's contracts for [GetThreadContext](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getthreadcontext),
[SuspendThread](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-suspendthread)
and [ReadProcessMemory](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-readprocessmemory).
The technique perturbs execution and samples residency, including waits. Counts
are not CPU-time shares or an uninstrumented FPS benchmark. Keep raw stack words,
module paths and addresses in ignored artifacts.

The reader checks receipt identity, complete sample count, monotonic timing,
nonoverlapping module ranges and the recorded engine hash. Engine samples are
grouped by primary x64 unwind owner. Two narrow stack interpretations are enabled
only for the exact installed engine hash and matching prolog bytes. Return slots
must point immediately after a direct call to the expected helper. This is not
a general stack unwinder and supplies no hook ABI or permission to skip work.

## Results on 10 September

All trials used the accepted Lua, focused Present CPU native DLL, DLSS Quality,
FG off, 13 workers, unlimited cap, 120 Hz simulator and stationary SoloPlay
`cm_archives`, difficulty 3. Each captured 1,000 samples successfully. Clean
benchmark exit and exact installation/settings restoration passed.

The first instruction-only capture found 133 samples at engine RVA `6f77dd`.
Static inspection resolves its enclosing helper to
`ThreadPool::do_work_while_waiting_for_signal`. It checks a completion signal,
tries to obtain and execute queued work, and executes `pause` when none is found.
Thus high thread CPU usage includes active waiting, not only useful rendering.

The second capture read 64 stack bytes: all 153 wait-loop samples yielded verified
direct callers, with 126 from list-wait helper `6f94d0`. The third used 256 bytes
to resolve that helper's caller too. Of 141 wait-loop samples, 123 passed through
the list helper, with these verified parents:

| Parent call RVA | Primary owner | Samples | Static classification |
| --- | --- | ---: | --- |
| `7ac4a5` | `7aa1c0` | 91 | D3D12 dispatcher, following parallel dispatch |
| `41e2f2` | `419910` | 10 | Cascaded shadow/render preparation |
| `37bf5f` | `37b240` | 7 | Culled-scene rendering |
| `397cca` | `397990` | 7 | Not yet classified |
| `38457c` | `383f00` | 4 | Not yet classified |
| `7aa7e8` | `7aa1c0` | 3 | D3D12 dispatcher, command-sort wait |
| `389649` | `389440` | 1 | Not yet classified |

Another 12 wait samples came directly from dispatcher call `7ab720`, near state
and dynamic-buffer transfer. The dominant lead is command-building job division
and completion in the D3D12 dispatcher. The samples do not show that removing
waits, changing job order or sharing both eyes' commands would preserve behavior.

Mean pause durations were 46.13, 51.79 and 51.59 microseconds. The final maximum
was 296.9 microseconds; the second capture's maximum was 1,382.6 microseconds.
These perturbations must remain attached to interpretation of the results.

Windows x64 Release build and `thread_residency_self` pass, including a foreign
suspend-count preservation check. PowerShell parses successfully. The Python
reader successfully maps the live receipts. Evidence is under
`synthetic-solo-thread-residency-{a,b,c}-20260910` in ignored unattended artifacts.
No engine code was patched and no physical or worn visual acceptance is claimed.
