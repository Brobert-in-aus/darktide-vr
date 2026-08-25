# Static renderer observation map

**Build:** Darktide `1.12.0-b773907`
**Method:** Read-only PE headers/imports/exports and artifact fingerprints
**Runtime interaction:** None; the game was not started or attached to

## Observed creation chain

```text
Darktide.exe
  imports D3D12CreateDevice / D3D12GetDebugInterface
  imports CreateDXGIFactory / D3D11CreateDevice
                 |
                 v
          sl.interposer.dll 2.7.30.0
          exports D3D11, D3D12, and DXGI creation entry points
                 |
                 v
       runtime-loaded system D3D12 / DXGI implementation
```

The executable does not directly import `d3d12.dll` or `dxgi.dll`. Its graphics
creation symbols occur under the `sl.interposer.dll` import descriptor. The
interposer exports `CreateDXGIFactory`, `CreateDXGIFactory1`,
`CreateDXGIFactory2`, `D3D12CreateDevice`, root-signature helpers, and D3D12
debug interfaces. It does not statically import D3D12/DXGI itself, consistent
with resolving the downstream implementation dynamically.

The final `IDXGISwapChain::Present` call is a COM vtable method, so its absence
from the PE import table is expected. Static inspection does not yet identify
which factory creates the gameplay swapchain, which swapchain is final, or
whether Streamline wraps that object.

## Build-scoped renderer artifacts

| Artifact | Version | SHA-256 |
| --- | --- | --- |
| `binaries/Darktide.exe` | `1.3.770.210` | `e0f581d2c63b692c7d9f328e3edeb39c0f484956905569d38ba27bbb3fcc0aae` |
| `binaries/sl.interposer.dll` | `2.7.30.0` | `34411f9ae0ba3c55897aa8bd229568671409d1094f210d75595ff57dc6ab6908` |
| `shader_cache/D3D12/D3D12Core.dll` | `1.606.4.0` branch build | `1a1327f343966ad72fcbe1d2873a7feb5fbdccd89e89f5ff2d39066e904238f2` |

These hashes identify the inspected artifacts only. They do not approve any
runtime hook or establish anti-cheat compatibility.

## Observation implications

1. The first renderer observation experiment must account for Streamline's
   interposition. Treating the process as a direct `d3d12.dll`/`dxgi.dll`
   consumer would be an incorrect model for this build.
2. Factory/swapchain observation is a stronger early seam than searching the
   executable for a direct `Present` import. Any candidate must log factory,
   adapter LUID, device, queue, HWND, swapchain description, resize count, and
   per-swapchain present count before selecting a final swapchain.
3. A Streamline-owned or wrapped swapchain may affect call order and temporal
   feature state. DLSS frame generation remains disabled for early VR work.
4. The presence of `WinPixEventRuntime.dll` and local D3D12 debug settings can
   help a staged pass census, but neither proves that capture tooling is safe
   under EAC.

## Camera source map status

The design brief's semantic camera seam remains the Lua camera manager's final
`post_update`/`ScriptCamera` write. Static PE inspection adds no validated native
address or constant-buffer identity. The next camera work still requires a
staged desktop observation experiment correlating semantic camera state with
native transforms and D3D12 resource use. No AOB or address should be recorded
until it is proven against the exact executable fingerprint.

## Reproduce

```powershell
tools\renderer_probe\inspect-static-renderer.ps1 `
  -GameRoot 'Warhammer 40,000 DARKTIDE' `
  -Output 'artifacts\phase0\static-renderer.json'
```

Generated reports belong under ignored `artifacts/`; do not commit local game
paths or proprietary binaries.
