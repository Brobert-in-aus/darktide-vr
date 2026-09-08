# Offline shader interface validation

`tools/stereo/test-shader-interface.py` checks captured/candidate bytecode with
the actual native vertex-substitution gate. It copies the requested native DLL
and reflection library into an isolated fixture, selects test transports and
calls `dtvr_validate_shader_interface`. It does not install hooks, start the
game or create a graphics/OpenXR device. The JSON receipt records both library
hashes, every bytecode hash and each result. The fixture remains for inspection.

Build the Release `darktidevr_native_capture` target first, then run:

```powershell
python tools/stereo/test-shader-interface.py `
  --native-capture build/windows-vs2022/src/producer/Release/darktidevr_native_capture.dll `
  --reflection-library build/dependencies/dxc-runtime/dxcompiler.dll `
  --pair ORIGINAL.bin CANDIDATE.dxil `
  --output artifacts/unattended/shader-interface-result.json
```

Repeat `--pair` for multiple candidates. Exit zero means all interfaces passed.
Native results are 0 compatible, 1 invalid pointer/size, 2 reflection or interface
mismatch, and 3 caught exception. The maximum bytecode size is 64 MiB per input.
This is the vertex interface gate; it is not the relaxed pixel-color probe gate.
No compatibility rules were weakened to support this tool.

## 8 September billboard reconstructions

The eight active non-production VS families from the passive census were
converted through the local dxil-spirv and SPIRV-Cross tools, then compiled with
Windows SDK DXC as `vs_6_0`. Generated source and bytecode remain local under
`artifacts/unattended/billboard-vertex-analysis-20260908`.

Raw conversion was insufficient. Repairs, checked against original DXC dumps:

- Restore original input semantics and ordering, including unused
  `SV_InstanceID` fields removed by conversion in `9edf...` and `6a015...`.
- Restore output ordering with `SV_Position` first so register/component
  packing matches the original. Preserve component widths and used masks.
- Remove the conversion-only base-instance cbuffer and use the original
  D3D instance ID directly.
- Restore atlas-index resources to `StructuredBuffer<uint>` with four-byte
  elements and indexed loads. Conversion produced `Buffer<uint4>`, which has
  a different resource interface. Original reflection explicitly reports a
  four-byte uint element.

After these repairs, all eight candidates pass the actual native interface
gate: `30408e39c8028272`, `42f73c7d12e99db7`, `6a0153ef1f6c56fd`,
`9edf5361a4db2da1`, `c403cfbf17d9fc49`, `e18a274cd89282e8`,
`f0c85040e349f799`, and `fe64037664924d52`. Receipt:
`artifacts/unattended/billboard-roundtrip-interfaces-20260908.json`.
An original-against-itself control also passes. The initial unrepaired
candidates all failed, correctly exposing the mismatches above.

This establishes interface compatibility only. It does not establish numerical
equivalence, identify visible smoke, validate a changed orientation, or imply
that atlas-generation shaders should receive the same change as display
shaders. None of these reconstructed candidates has been deployed.

Windows x64 Release build and both pipeline-probe CTests pass (1.76 seconds),
including same-stage success, stage mismatch, malformed bytecode, null/zero and
oversized input checks before hook installation. Evidence:
`artifacts/unattended/shader-interface-build-20260908.log` and
`artifacts/unattended/shader-interface-tests-20260908.log`.
