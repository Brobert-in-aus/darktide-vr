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
