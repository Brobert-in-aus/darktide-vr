# DLSS outer-runtime observation candidate

Branch: `codex/dlss-output-boundary-2026-09-06`.

The user requested a hub-capable headset launch and continued DLSS investigation
while testing. Ready preflight passed; Quest proximity override was reapplied.
The old launch was stopped, its Psykhanium flag removed after shutdown, and the
new launch omitted `-EnterPsykhanium`. It uses `-EnableHudPanel
-AutoAdvanceSplash -ManualCharacterSelect -StreamlineStereoSwapchainProbe
-StreamlineTargetTokenProbe`. Startup verified windowed presentation. Gameplay
subsequently reported fresh shared pairs, nonzero `shared_ready` and zero interval
fallback/pose mismatches. Those counters do not establish worn acceptance.

## New candidate boundary

Read-only module inventory found the driver runtime `_nvngx.dll` version
32.0.16.1088. Its exported `NVSDK_NGX_D3D12_EvaluateFeature` is distinct from the
caller-validated `nvngx_dlssg.dll` feature export examined previously. Static
disassembly of this installed runtime shows the outer export forwarding the
original command list, feature, parameters and callback into its internal
feature dispatch and then returning the result.

In this binary the runtime export is at RVA 0x66f90, the internal indirect call
at 0x67044, and its return address at 0x6704a. These are inspection evidence only:
the diagnostic resolves the export by name. A trampoline at the outer entry
resumes the runtime before its internal call, so the feature's return address
should remain within NVIDIA's real runtime. This is a compatibility hypothesis
pending live testing, not proof that the output blocker is resolved.

## Parameter ABI gate

The official [Streamline v2.7.30 NGX parameter interface](https://github.com/NVIDIA-RTX/Streamline/blob/v2.7.30/external/ngx-sdk/include/nvsdk_ngx_params.h)
provides typed resource getters. MSVC x64 reverses each overloaded method group:
the D3D12 resource getter is vtable slot 9 (byte offset 0x48), not declaration
index 14. The unsigned getter is slot 12 (0x60).

`ngx_abi_reference` implements the official interface, dispatches through the
local ABI adapter, and checks overload selection, pointer/value results and
unchanged failure returns. The two reference headers are external, pinned by
SHA-256 during CMake configuration, and are not bundled into the mod. The local
reader is not a generic pointer validator; only a synchronous verified NGX
callback may use it.

NVIDIA's [DLSS-G helper](https://github.com/NVIDIA/DLSS/blob/main/include/nvsdk_ngx_helpers_dlssg.h)
names an interpolated-output resource separately from backbuffer, depth, motion
and HUDless inputs. Newer helper declarations alone do not certify installed
feature support, so missing/failed resource queries remain explicitly recorded.

## Prepared diagnostic (not deployed in the user's test session)

`ngx_output_probe.cpp` is registered only when
`darktidevr_ngx_output_probe.flag` exists in the mod root (one directory above
the native capture DLL). It requires the inspected runtime version and export
prologue, and a readable parameter object whose resource getter belongs to that
runtime. Unsupported versions or signatures reject the requested diagnostic.
Normal launches without the flag do not install this hook.

The observer preserves arguments and the original result. It samples at most
256 evaluations with a nonnull interpolated output within 32,768 runtime calls.
It logs the command list, feature/parameter identity, output and four input
resource addresses, getter statuses, evaluation status, thread and timestamp to
`%TEMP%/darktidevr-ngx-output-<pid>.log`. It neither dereferences the returned COM
resources nor retains them, and adds no GPU commands, waits or XR publication.
Logging `output_complete=0 publication=0` is intentional: successful evaluation
does not mean GPU completion or correct stereo/pose association.

No feature-library patch or return-address spoofing is used. The live game has
not been restarted or hot-patched for this candidate. At the next diagnostic
launch, first verify hook acceptance, successful evaluations and populated
input/output records before trying to match them against stereo submissions.
Do not enable generated XR publication from pointer records alone. Queue/fence
ownership, pose association and continuous stereo history remain outstanding.

## Validation

Windows x64 Release native-capture and NGX-reference targets build successfully.
The focused CTest selection `ngx_abi_reference|streamline_abi_reference|
streamline_submission|streamline_input_lifetime|streamline_stereo_inputs` passes
all five cases. No Lua source changed. The reference headers live under ignored
`artifacts/diagnostics/dlss-output-boundary-20260906`; configure their directory
with `DARKTIDEVR_NGX_REFERENCE_INCLUDE_DIR` to reproduce the ABI test.

Live caller compatibility and resource association are still unverified. This
checkpoint prepares the next experiment without disturbing the user's hub test.
