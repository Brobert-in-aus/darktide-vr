# Atlas shader execution checks

8 September: all three reconstructed stock atlas-display shaders agree with
their captured originals in controlled D3D12 stream-output checks on both WARP
and the RTX 4090. The cylindrical candidates also preserve their complete
outputs when only camera pitch/roll changes at a fixed yaw, under the fixture's
fixed projection and scene inputs. No game deployment occurs in this test.

The optional `darktidevr-billboard-equivalence-tests` executable reflects the
original vertex interface, binds controlled constants, a populated volume
texture, cube texture, structured atlas indices and vertex inputs, then captures
all declared outputs through stream output. Semantic names/indices drive the
bindings; reflection enumeration order can differ for packed scalar outputs.
This follows the [D3D12 stream-output declaration](https://learn.microsoft.com/en-us/windows/win32/api/d3d12/ns-d3d12-d3d12_so_declaration_entry).

Each shader receives 108 cases: three yaw, three pitch and three roll values,
with fog disabled, analytic fog, volume fog and volume-plus-distance fog.
Four corners and eight instances produce 32 vertices per case. Alternating
start-instance offsets of zero and three exercise atlas addressing, including
valid atlas tiers and the invalid-index fallback. All outputs must be finite;
the filled-byte counter must match the complete expected stream size.

| Display VS | Scalars per run | Stock/original maximum delta, WARP | Stock/original maximum delta, RTX | Cylindrical pitch/roll maximum delta, RTX |
| --- | ---: | ---: | ---: | ---: |
| `c403cfbf17d9fc49` | 69,120 | 2.32831e-10 | 1.74623e-10 | 2.38419e-7 |
| `e18a274cd89282e8` | 76,032 | 9.53674e-7 | 9.53674e-7 | 1.19209e-7 |
| `fe64037664924d52` | 100,224 | 2.32831e-10 | 1.74623e-10 | 2.38419e-7 |

Tolerance is `1e-5 + 2e-5 * abs(reference)` per scalar; observed deltas are
smaller. All positive runs finish without D3D12 debug-layer errors. An original
against itself produces zero difference. The cylindrical candidate correctly
fails stock-equivalence checking at the first position component. Conversely,
the stock shader correctly fails the cylindrical pitch/roll-invariance check.
Those controls demonstrate that the fixture detects the intended geometry change.

Build target: `darktidevr-billboard-equivalence-tests` with the Windows Release
preset. Run with arguments `ORIGINAL.bin CANDIDATE.dxil dxcompiler.dll`;
`--hardware` selects the high-performance physical adapter instead of WARP.
`--cylindrical-invariance` compares the candidate's current pitch/roll against
its own zero-pitch/zero-roll output at the same yaw and instance offset.
The originals are the verified local dumps used by the existing candidate
builder. They are not committed or required by default CTest. Logs are under
`artifacts/unattended/billboard-{equivalence,cylindrical}-*-20260908.log`.

This narrows the reconstruction risk beyond interface/basis checks. It does not
cover every game material, texture, constant range, draw topology, raster pixel,
or extreme vertical-view behavior. Existing pole/basis tests remain separate.
The two families observed affecting background/floor haze (`e18a...`, `fe640...`)
are prepared for a focused stock/cylindrical worn comparison. These shader
families may serve other effects too, so that comparison must inspect nearby
effects and lighting as well as the reported haze. The accepted SoloPlay session
remains running with no atlas orientation replacement installed.
