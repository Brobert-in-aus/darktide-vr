# Simulator exit-status reliability

The first descriptor-demand baseline (`synthetic-descriptor-demand-a1-20260911`)
completed its bounded mission and the viewer printed `result=pass`, but the
runner received a null process exit code and failed with `Consumer failed:`.
All saved files were restored. This run is excluded from the comparison; the
repeat `a2` completed normally at 74.85 native FPS.

A standalone child-process reproduction on Windows PowerShell 5.1.26100.9444
returned `WaitForExit=true`, `HasExited=true`, but `ExitCode=null` after an early
`Refresh`/`HasExited` poll and a later wait. Reading `Process.Handle` immediately
after `Start-Process` retained the handle and returned the correct zero exit.
A separate nonzero child returned 7 correctly with the retained handle. The
simple immediate-wait control returned zero on both PowerShell 5.1 and 7.6.5;
the earlier poll/later wait sequence is material to this reproduction.

Commit `fc0064b` retains the simulator process handle before its readiness poll.
It does not reinterpret a missing code as success or weaken failure handling.
The process is still disposed in the existing finally block. No rendering or
benchmark timing setting changes. Validation used standalone child processes
with redirected stdout/stderr; local evidence is under
`artifacts/unattended/exit-code-{repro,held,nonzero}-*.log` plus the session tool
results. The candidate mission also exercises the updated runner on PowerShell 7.
