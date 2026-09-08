# Atlas display billboard orientation candidate

Three display families observed in the passive character-select census now
have offline stock controls and cylindrical candidates. They are not deployed,
included in the runtime package, or enabled by a production flag. The smoke
owner remains unidentified; do not activate all three based on draw counts.

Later 8 September evidence: [passive before/after readback](BILLBOARD-DRAW-READBACK.md)
now shows `e18a...` and `fe640...` affecting background/floor haze in the
character-select scene. `c403...` changed no pixels in its earlier sampled draw;
that does not exclude later draws. The user's specific orientation artifact and
full numerical equivalence remain unaccepted. No orientation candidate was
activated for the readback, and the accepted SoloPlay session is restored.

| Display VS | Paired atlas-generation VS | Specific output behavior |
| --- | --- | --- |
| `c403cfbf17d9fc49` | `42f73c7d12e99db7` | Authored spin, atlas UVs, world position and fog |
| `e18a274cd89282e8` | `30408e39c8028272` | Unspun basis, atlas UVs, extra material outputs |
| `fe64037664924d52` | `f0c85040e349f799` | Authored spin plus tangent-frame outputs for lighting |

Each reconstructed source includes `billboard-cylindrical-basis.hlsli`.
Original reflection places `c_billboard.view` at byte zero and `view_proj` at
byte 64. The original right/up reads use view registers 0 and 2; register 1 is
the forward axis. The candidate projects forward onto the world XY plane,
derives a normalized right axis and uses world Z as up. This follows the basis
of the previously accepted raw-particle correction, adapted to this layout.

Only those basis reads change. Existing spin, dimensions, atlas-index loads,
UVs, projection, world-position/fog and material output equations remain.
In `fe640...`, the changed basis also feeds tangent-frame outputs, so lighting
follows geometry. Atlas-generation shaders, tangent/ribbon families and the
accepted raw-particle shader are untouched.

Unlike the accepted raw-particle shader's zero-spin option, these candidates
preserve authored spin. Their unspun plane is independent of headset roll;
authored spin can still tilt a particle inside that plane. Exact vertical views
use a finite horizontal-right fallback. Yaw is undefined at that pole, so
continuity across it is not claimed. Worn behavior still requires observation.

## Build and validation

The builder requires exact original bytecode hashes and checks all six outputs
with the unchanged runtime interface gate. Use a fresh output directory:

```powershell
python tools/stereo/build-atlas-billboard-candidates.py `
  --dxc 'C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/dxc.exe' `
  --original-directory "$env:TEMP/darktidevr-vertex-shaders" `
  --native-capture build/windows-vs2022/src/producer/Release/darktidevr_native_capture.dll `
  --reflection-library build/dependencies/dxc-runtime/dxcompiler.dll `
  --output artifacts/unattended/atlas-billboard-candidates-NEW
```

`build.json` records source/helper/compiler/output hashes and explicit pending
ownership, equivalence and worn-acceptance status. `interfaces.json` records
native/reflection hashes and original/candidate pairs. Output names contain
`.stock` or `.cylindrical`, so the runtime does not discover them as replacement
filenames. The builder performs no deployment or rename.

On 8 September, all six compile as `vs_6_0` and pass interface validation:
`artifacts/unattended/atlas-billboard-candidates-20260908/`.
The Windows x64 Release `billboard_compiled_basis` CTest separately executes
the actual shared HLSL basis on D3D11 WARP, with 343 yaw/pitch/roll combinations
and three pole/degenerate cases in each mode. Stock axes match the inputs;
cylindrical axes match independent yaw/world-up expectations. All 692 cases
pass in 0.09 seconds. It does not open XR or interact with Darktide. Logs:
`artifacts/unattended/atlas-billboard-basis-{build,tests}-20260908.log`.

Later [shader execution checks](BILLBOARD-SHADER-EQUIVALENCE.md) compare all
declared outputs against the originals in 108 controlled cases per shader on
WARP and the RTX 4090. Stock agreement and cylindrical pitch/roll invariance
pass, including negative controls. These are controlled input cases, not full
numerical coverage of all materials or worn acceptance. Before
live activation, identify the intended smoke/effect family, perform Ready
preflight and use a reversible focused deployment. Compare its stock control
and cylindrical behavior with a specific worn observation. Preserve the
accepted preview session until that live work is appropriate.
