# DarktideVR

Experimental Windows x64 PCVR work for Warhammer 40,000: Darktide, using a
native D3D12 producer, a Lua mod, and a separate OpenXR viewer.

Start with [current status and operation](docs/CURRENT-STATUS.md),
[working agreements](AGENTS.md), and the
[maintenance implementation plan](docs/maintenance-plan-2026-09-05.md).
The game integration is build-specific and used with EAC inactive. The project
contains no anti-cheat bypass implementation.

## Build and test

Install Visual Studio 2022 C++ tools, CMake 3.25+, Git, and Python 3. Build the
pinned Lua compiler once, then build and test the project:

```powershell
tools/lua/build-luajit.ps1
cmake --preset windows-vs2022 -DDARKTIDEVR_ENABLE_HEADSET_TESTS=OFF
cmake --build --preset windows-vs2022-release
ctest --test-dir build/windows-vs2022 -C Release --output-on-failure
tools/stereo/test-darktide-lua-source.ps1
```

Dependencies and revisions are in [third-party notices](THIRD_PARTY_NOTICES.md).
CTest transport fixtures use private process-specific mappings. Headset tests
remain opt-in and require a fresh XR readiness check; avoid running compositor
smoke tests alongside a worn session.

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
