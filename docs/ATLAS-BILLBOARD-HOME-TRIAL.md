# Focused smoke comparison preparation

8 September 2026. **Staged only; no shader has been installed by this work.**
The live SoloPlay/accepted preview session remains available. The two
pixel-confirmed background/floor haze families, `e18a274cd89282e8` and
`fe64037664924d52`, have reconstructed-stock and cylindrical variants ready for
a worn comparison. The unrelated `c403...` family is excluded from this trial.

The [shader-output checks](BILLBOARD-SHADER-EQUIVALENCE.md) establish controlled
stock equivalence and cylindrical pitch/roll invariance. The passive readback
establishes affected pixels, not the user's exact smoke artifact or acceptance.

## Accepted runtime compatibility

All four staged variants pass the actual native interface gate with an isolated
copy of the **installed DXC 1.6 reflection library**. No library update is needed.
The reflection loader, complete interface-gate/helper section and replacement
selection section are text-identical between accepted native source `23345e5`
and the tested source. The accepted target list includes both shader families.
Installed native hashes still match the accepted deployment.

This resolves the previously open matching-runtime/reflection prerequisite.
The trial can change only the two shader files, preserving native capture,
bootstrap, Lua, SoloPlay configuration and the accepted `42e...` particle shader.
It still needs a fresh game process to create replacement pipelines and verify
that those substitutions actually apply in the intended scene.

Local staged evidence and helpers:
`artifacts/unattended/atlas-billboard-home-trial-20260908/`

- `trial.json`: variants, SHA-256 values and runtime verification.
- `installed-reflection-interface.json`: four successful exact-gate calls.
- `runtime-gate-source-comparison.json`: three identical source sections.
- `apply-trial.ps1`: validates both installed native copies, reflection and
  staged hashes, rejects an existing trial, runs Ready, then transactionally
  adds only the two known shader files. `-ValidateOnly` does no game writes.
- `restore-trial.ps1`: restricts recovery to the two added atlas files, runs
  Ready, uses the saved transaction without allowing changed files, and checks
  the production particle shader is preserved.

Both apply profiles pass `-ValidateOnly` against the current installation.
Both helper scripts parse successfully. Their mutation paths have **not** been
executed; they reuse the project's previously tested transaction/recovery tools.
Machine paths, hashes and payloads remain local artifacts outside Git.

## Home comparison sequence

1. Keep the current SoloPlay test available until the user is ready to compare
   the reported smoke. Close Darktide gracefully and let the launcher clean up.
2. Apply `-Profile stock`, then launch with the existing focused deployment.
   Verify fresh Lua/stereo startup and substitution evidence. Compare the same
   affected scene with natural head movement; stock reconstruction is a control.
3. Close gracefully, restore using that profile's saved deployment receipt,
   then apply `-Profile cylindrical` and repeat the same scene/head movement.
4. Record each eye's smoke orientation, authored particle motion and any new
   distortions. Restore after an adverse or inconclusive result. No frame
   counter, successful shader gate or flat screenshot counts as worn acceptance.

The apply helper is not run while the user is away. There is no synthetic
tracking or color probe in this preparation.
