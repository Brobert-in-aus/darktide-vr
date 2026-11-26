# Release checklist: 0.3.0-alpha.3 (drafted 26 November 2026)

A hotfix for the game's 23 October update. A player reported that the newest
release did not work with the current game; 0.3.0-alpha.2's
`set-skinner-assert-patch.ps1` knew executables only by hash and reports the
23 October `Darktide.exe` (SHA-256 43803E11…79FA7) as `state=unsupported`,
so `Darktide VR Mode.bat` refuses VR mode.

Branch `codex/hotfix-0.3.0-alpha.3-2026-11-26`: v0.3.0-alpha.2's publication
commit `fa03568` plus the two patch-tool commits written on 17 October after
alpha.2 was tagged (`98d5718` → `dfd214c`, `b560328` → `e75af90`), which
cherry-picked cleanly. No Lua changed since `v0.3.0-alpha.2`. Nothing else
from `codex/steam-frame-2026-10-26` is in it. `CHANGELOG.md`'s
"0.3.0-alpha.3 (unreleased)" section is the release text.

Items are numbered as headings because the reader's viewer renumbers lists.

## 1. The patch tool on the real executable — done 26 November

The pristine 23 October executable (the copy alpha.2's dev install kept in
`%LOCALAPPDATA%\DarktideVR`), copied to scratch:

- alpha.2's tool: `state=unsupported build=unknown` (the report reproduced).
- this branch's tool, and the copy shipped in the archive:
  `state=original build=unlisted-43803e119fc1`, sites `0x7c9706,0x7c9802`.
- Apply gives SHA-256 06B4DA6D…E1E84A01, identical to the executable the dev
  install has run since 26 October; Restore gives back 43803E11….

## 2. Full test suite — done 26 November, 281/283

`ctest --test-dir build\windows-vs2022 -C Release` in a fresh worktree.
The two failures, `dispatch_bundle_reader` and `residency_unwind_index`, are
`ModuleNotFoundError: No module named 'pefile'`: this workstation's Python
3.13 has lost the module, so they fail on any checkout here; they read
engine binaries for research and touch nothing packaged. The Lua gate:
`lua_source_check=pass compiler=LuaJIT chunks=103`.

A fresh worktree needs machine-local inputs the build does not fetch:
`build\dependencies\luajit` and `dxc-runtime`, `build\generated\billboard_shaders`,
and the two empty `tools\release\package-files\bin\*.flag` files (ignored by
the `bin/` rule). They were copied from the main checkout.

## 3. Build the release archive — done 26 November

Provenance `artifacts/packages/component-provenance-0.3.0-alpha.3.json`
(2 components, revision `3adf81a`), then:

    darktidevr-0.3.0-alpha.3-3adf81a250e8.zip
    9,436,042 bytes
    SHA-256 AA7CBD2ADA82228EFB4A853E4C8F86A774078467FE59C8FB030D60E4A9F08408
    built from 3adf81a250e8 (release_candidate, headset_tested=false)

`runtime_package=pass files=124`; 102 Lua files; only the two shipped `bin`
flags. This checklist's own commit comes after the build commit and is not
in the archive.

## 4. Install the archive fresh and play it — open, the user's

Not the dev install: extract the zip over the game folder, run
`Darktide VR Mode.bat`, choose VR mode, launch through Steam. The dev install
already runs the same executable patch and the alpha.2 Lua, so this checks
the package as a player receives it rather than the fix itself.

## 5. Publish — on the user's word only

The user publishes on Nexus (the changelog post is in `docs/NEXUS-PAGE.md`).
Then: date the changelog and Nexus headings, fast-forward `main` on both
remotes to the branch (never by force), an annotated tag `v0.3.0-alpha.3` on
`3adf81a` pushed to both, and `gh release create v0.3.0-alpha.3 --repo
Brobert-in-aus/darktide-vr --latest --notes-file <notes>` with the zip.

Afterwards `codex/steam-frame-2026-10-26` needs `main` merged in: it holds
the original patch-tool commits, and its changelog's "Unreleased" heading
becomes this release.

## 6. Known issues to state

- Every game update still switches the mod loader off: run its
  `toggle_darktide_mods.bat` before the batch file.
- Microsoft Store / Game Pass support came with the patch-tool commit and has
  never run on a Store install.
