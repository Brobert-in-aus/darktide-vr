# Third-party notices

## Khronos OpenXR SDK

The build fetches and compiles the official Khronos OpenXR SDK loader from
commit `5267613edf3d937e3d77556a106a65c2f82b25c6` (release 1.1.61).

- Source: <https://github.com/KhronosGroup/OpenXR-SDK>
- License: Apache License 2.0

The upstream `LICENSE` file is copied beside each built harness executable as
`OPENXR-LICENSE.txt`. No prebuilt third-party binary is committed to this
repository.

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
