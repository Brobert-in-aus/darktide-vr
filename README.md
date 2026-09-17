# DarktideVR

Experimental Windows x64 PCVR work for Warhammer 40,000: Darktide, using a
native D3D12 producer, a Lua mod, and a separate OpenXR viewer.

For the proposed first tester release, see [very early alpha readiness](docs/EARLY-ALPHA-READINESS.md).

Start with the [working agreements](AGENTS.md) and the
[docs index](docs/README.md), which lists the maintained entry points.

**For the next development session, read the newest of each of these** (they
are dated, and the newest is always the current one):
[`docs/handoffs/`](docs/handoffs/) for what happened last and why,
[`docs/phase1/todo-*.md`](docs/phase1/) for what is next, and
[`docs/phase1/test-checklist-*.md`](docs/phase1/) for what is waiting on a
worn test. At the time of writing that is the
[17 September handover](docs/handoffs/2026-09-17-session.md), the
[18 September list](docs/phase1/todo-2026-09-18.md) with its
[detailed away-list](docs/phase1/todo-2026-09-18-detailed.md), and the
[worn checklist](docs/phase1/test-checklist-2026-09-16.md).

[Current status and operation](docs/CURRENT-STATUS.md) and the
[maintenance implementation plan](docs/maintenance-plan-2026-09-05.md) cover
the engine and DLSS investigations; both predate the VR presentation work
above and are not a description of what the mod does today.
The game integration is build-specific and used with EAC inactive. The project
contains no anti-cheat bypass implementation.

## Build and test

Install Visual Studio 2022 C++ tools, CMake 3.25+, Git, and Python 3 (validated
with 3.13.3). Install the pinned analysis packages in the Python environment
selected by CMake, then build the pinned Lua compiler and project:

```powershell
python -m pip install -r tools/stereo/requirements-analysis.txt
tools/lua/build-luajit.ps1
tools/dependencies/get-dxc-runtime.ps1
cmake --preset windows-vs2022 -DDARKTIDEVR_ENABLE_HEADSET_TESTS=OFF
cmake --build --preset windows-vs2022-release
ctest --test-dir build/windows-vs2022 -C Release --output-on-failure
tools/stereo/test-darktide-lua-source.ps1
```

Dependencies and revisions are in [third-party notices](THIRD_PARTY_NOTICES.md).
CTest transport fixtures use private process-specific mappings. Headset tests
remain opt-in and require a fresh XR readiness check; avoid running compositor
smoke tests alongside a worn session.
The ordinary D3D12 smoke/resize checks pass `--no-openxr`, which skips runtime
discovery even when a Quest is connected. This option is also available for
manual desktop-only harness checks and rejects conflicting XR requests.

The ordinary launcher, development sync and readiness preflight discover Darktide through registered
Steam libraries and its app manifest. If several installations exist, choose one
with `-GameRoot <folder>`. A shortcut can save that choice through
`tools/stereo/install-darktide-vr-shortcut.ps1 -GameRoot <folder>`; omitting it
keeps automatic discovery at launch. This does not install Darktide, DMF or mod
dependencies. Other standalone diagnostic scripts still take their own GameRoot.

Automatic hub/Psykhanium launches require a successful shared-stereo delivery
summary as well as successful viewer/game exit status. Flat fallback alone does
not pass. Direct shared-eye runner checks can opt in with `-RequireSharedStereo`.
This is a delivery check; fresh game-log initialization and worn visual checks
remain part of live acceptance.

## Repository map

- `src/core`: math, input/presentation policy, and shared-memory transports.
- `src/bridge`: shared D3D12 eye/menu/generated-surface contracts.
- `src/producer`: native game hooks, bootstrapping, and object lifetime helpers.
- `src/xr`: production OpenXR viewer, capture, input, and scene rendering.
- `src/adapters/darktide`: feasibility camera/observation helpers.
- `mods`: game Lua modules, including isolated projection and embodiment code.
- `tests`: regressions and standalone diagnostic executables.
- `tools`: deployment, launch, readiness, and research analysis utilities.
- `docs/CURRENT-STATUS.md`: current operation and unresolved acceptance.
- `docs/handoffs` and phase histories: dated evidence, not current instructions.

The viewer still builds to `build/windows-vs2022/tests/xr_harness/<configuration>`
for launcher compatibility. The retired winmm bootstrap is available only with
`-DDARKTIDEVR_BUILD_LEGACY_WINMM=ON`; normal deployment uses d3d12.dll.
