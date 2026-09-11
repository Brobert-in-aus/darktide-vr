# Third-party notices

## Khronos OpenXR SDK

The build fetches and compiles the official Khronos OpenXR SDK loader from
commit `5267613edf3d937e3d77556a106a65c2f82b25c6` (release 1.1.61).

- Source: <https://github.com/KhronosGroup/OpenXR-SDK>
- License: Apache License 2.0

The upstream `LICENSE` file is copied beside each built harness executable as
`OPENXR-LICENSE.txt`. No prebuilt third-party binary is committed to this
repository.

## MinHook

The native capture module installs its D3D12, DXGI and Streamline hooks with
MinHook, fetched and built from https://github.com/TsudaKageyu/minhook at
commit `c3fcafdc10146beb5919319d0683e44e3c30d537` and statically linked into
`darktidevr_native_capture.dll`. Copyright Tsuda Kageyu and contributors;
BSD 2-Clause "Simplified" License. The upstream `LICENSE.txt` applies; the
hooks are installed only inside the game process that loads the module and
never system-wide.

## NVIDIA Streamline ABI

The module interposes the game's own NVIDIA Streamline 2.7.30 calls (DLSS
Frame Generation tagging, constants and options). It ships no Streamline or
DLSS binary and no NVIDIA header; `src/producer/streamline_abi_2_7_30.h` is
the project's own declaration of the structures and function signatures
needed to read and forward those calls. NVIDIA DLSS, Streamline and Reflex
are trademarks of NVIDIA Corporation; the game's installed Streamline
plugins remain under NVIDIA's terms.

## LuaJIT source validator

The development-only syntax/compiler gate builds LuaJIT from
https://github.com/LuaJIT/LuaJIT at commit
`24c20c94e7db195b640854619577441f9b4bc6be` (v2.1 branch).
Copyright Mike Pall and contributors; MIT license, retained in the dependency
checkout's COPYRIGHT file. This validator compiles chunks without running them;
it is not shipped into Darktide and does not replace the game's Lua runtime.
Development candidate packages include the validator as a separate launch-time
validation utility, retaining the upstream COPYRIGHT file alongside it.

## DirectX Shader Compiler reflection runtime

The native capture module uses the x64 `dxcompiler.dll` from Microsoft's
[v1.8.2505.1 release](https://github.com/microsoft/DirectXShaderCompiler/releases/tag/v1.8.2505.1)
to inspect shader interfaces before replacement. The dependency preparation
tool pins the release archive's published SHA256 and each selected file.

The package retains the release archive's `LICENSE-LLVM.txt`, `LICENSE-MIT.txt`
and `LICENSE-MS.txt` alongside the dependency. Installation copies them as
`DXC-LICENSE-LLVM.txt`, `DXC-LICENSE-MIT.txt` and `DXC-LICENSE-MS.txt` beside the
native module and reflection DLL. Refer to those unmodified upstream terms.
No upstream binary is committed to Git. `dxc.exe`, `dxv.exe` and `dxil.dll` are
not part of this runtime payload; native reflection is tested without them in
the isolated module directory.
