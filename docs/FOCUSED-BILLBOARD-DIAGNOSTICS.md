# Focused billboard diagnostic candidate

Base: `ff9719c`, the focused accepted-baseline melee preview. Its `src/` tree
matches the accepted native source at `23345e5`. This candidate first adds only
the concurrent identity-log append correction and cached pixel-probe correction
from integrated PRs #29 and #30, with their isolated native regressions.

Windows x64 Release native capture and all three test executables build. Five
focused CTests pass in 3.01 seconds: native hooks, concurrent append, cached
probe application/fallback and the pinned Lua gate (45 chunks). Both probe tests
also pass with a copy of the existing installation's DXC reflection library
(1.6.2104.52). No game files or shader replacements were modified by these tests.

Initial diagnostic DLL SHA256:
`D31B9DE47C04EA57945C5F655552A06FB411E34D8D177859E7B703E7B6915E31`.
Build/test evidence is in the primary checkout's `artifacts/unattended/` as
`focused-billboard-build-20260908.log` and `focused-billboard-tests-20260908.log`.

The subsequent startup fix makes native bootstrap and Lua read the same
diagnostic, shader-dump, substitution, pixel-probe and pass-trace requests.
Previously eager diagnostics could install before Lua requested diagnostics
off, causing the immutable native selector to reject stereo initialization.
Pixel probes now select before native installation, and text flags share a
bounded, case-insensitive ASCII grammar. Basic profiling and cluster tracing
alone still do not select broad diagnostics.

Seven focused CTests pass in 18.57 seconds, including 37 real proxy/device
startup cases and 128 Lua flag combinations. The pinned gate compiles 46 Lua
chunks. Evidence: `artifacts/unattended/startup-agreement-tests-20260908.log`
in this focused worktree. These isolated tests do not launch Darktide or XR.
Keep shader ownership and worn acceptance open.
Physical melee remains paused; preserve the current preview and accepted hand,
gun-pitch, draw/reload and roomscale behavior. A live diagnostic session still
requires normal closed-game readiness, a recoverable focused deployment and
fresh stereo initialization evidence.
