# Release checklist: 0.3.0-alpha.2 (drafted 17 October 2026)

A compatibility release for Darktide 1.13 (1.13.1 and the 7 October 1.13.2)
with the small fixes from the 5 October review and the 17 October worn
session. It is **0.3.0-alpha.2**: the suffix counts re-releases within the
0.3.0 cycle, as 0.1.0-alpha.2 and .3 did. Branch
`codex/game-patch-1.13-2026-10-05`; `CHANGELOG.md`'s "0.3.0-alpha.2
(unreleased)" section is the release text.

Items are numbered as headings because the reader's viewer renumbers lists.
Each says what decides it and whether it is done.

## Progress

**17 October.** Items 2 and 3 done. Item 4 run as a release candidate ahead
of the worn pass, to prove the pipeline on this branch: provenance recorded
(`artifacts/packages/component-provenance-0.3.0-alpha.2.json`, 2
components), package built and tested (`runtime_package=pass files=124`):

    darktidevr-0.3.0-alpha.2-4efdd3369405.zip
    9,430,291 bytes
    SHA-256 4E7B66C4601A37BC5830CAEDF6F5E60677978F9DB62B4BBBD7C53E433FCE62DD
    built from 4efdd3369405 (release_candidate, source_dirty=False)

It carries the patch tool's three builds (1.12.5, 1.13.1, 1.13.2), 102 Lua
files (the tracked count), and only the two shipped `bin` flags. Its Lua and
native components are what is deployed for item 1, so a clean worn pass
releases this archive as it is, apart from the dated headings (item 6).
Items 1, 5 and 6 are the user's.

**17 October, 13:05: published.** The user uploaded the candidate archive
(`darktidevr-0.3.0-alpha.2-4efdd3369405.zip`, SHA-256 above, rechecked
before the GitHub upload) to Nexus and ordered the GitHub release. The worn
pass (item 1) and the fresh-install pass (item 5) were not reported before
publication. The archive's own changelog reads "unreleased"; the dated
headings are in the publication commit, not in the archive. Tag
`v0.3.0-alpha.2` on `4efdd33`, the build commit.

## 1. Worn pass on the deployed build — open, the user's

Deployed 17 October (deployment `f1ee05a0c296472086ccd752c7baa9e8`, head
`7438aa6`), not yet worn. The checks, from
[the 5 October checklist](phase1/test-checklist-2026-10-05.md) and the
17 October changes:

- crouch lowers the view, and standing straight puts it back at your height;
- both triggers cancel matchmaking in the Mourningstar, and the prompt
  reads LT+RT;
- with "Teammate status above teammates" on, in a mission: the team panel
  is on the HUD and only one name shows above each teammate;
- the Psykhanium: lights and particles the same in both eyes, aim and
  reticle on target, reach-to-interact working (checklist items 3 and 4);
- the end screen, if reached: the new buttons labelled, and whether the
  right trigger on them also skips the screen (checklist item 7).

Anything that fails here is fixed before item 4, and the package rebuilt.

## 2. Full test suite — done 17 October, 284/284

`ctest --test-dir build\windows-vs2022 -C Release` with the Visual Studio
CMake. Rerun at item 4 if anything changes.

## 3. Documents — done 17 October

`CHANGELOG.md`, `tools/release/package-README.txt` (after a game update:
the mod loader's toggle first), `docs/USER-GUIDE.md` (the same, and the
teammate status text), `docs/NEXUS-PAGE.md` (header, the install paragraph,
a 0.3.0-alpha.2 changelog post). On the publication day the changelog and
Nexus headings get the date, in the commit the archive is built from.

## 4. Build the release archive

From a clean checkout (the untracked `Testing/` at the repo root counts as
dirty: move it aside). Release build of the native targets, then
`tools\release\record-component-provenance.ps1 -OutputPath <explicit path>`,
then `tools\release\build-runtime-package.ps1 -ReleaseVersion 0.3.0-alpha.2
-OutputDirectory <explicit path> -ComponentProvenancePath <the record>
-RequireComponentProvenance`, then `tools\release\test-runtime-package.ps1`.
Record the archive name, size and SHA-256 here.

## 5. Install the archive fresh and play it — the user's

Not the dev install: delete the root-level dev flags the sync placed,
extract the zip over the game folder, run the mod loader's toggle if the
game has updated since, run `Darktide VR Mode.bat`, choose VR mode, launch
through Steam. Only this tests the package as a player receives it.

## 6. Publish — on the user's word only

The user publishes on Nexus. Then: date the changelog and Nexus headings
(and rebuild if the archive must carry the date, as 0.3.0-alpha.1's did),
fast-forward `main` on both remotes to the branch (never by force), an
annotated tag `v0.3.0-alpha.2` on the archive's build commit pushed to both,
and `gh release create v0.3.0-alpha.2 --repo Brobert-in-aus/darktide-vr
--latest --notes-file <notes>` with the zip attached (sections Changes,
Install, Archive).

## 7. Known issues to state

- Every game update switches the mod loader off and replaces the executable;
  a new executable needs a mod update before VR mode accepts it. Weekly
  hotfixes make this frequent; the second patch is to recognise the patch
  sites on an unknown build (a decision for the user).
- The first load into the Mourningstar after a game update can still stall
  while the game rebuilds its shaders; the mod no longer adds to it.
- The 5 October review's larger items wait for the second patch: the ogryn
  camera height, the full body's height stretch, the animation machine on a
  weapon wield, the back-buffer table, the shared-surface release.
