# Optional Custom HUD editor integration

The VR mod interoperates with a separately installed and enabled Custom HUD.
The inspected local distribution identifies itself as 2.1.6; its changelog
credits current maintenance to Sungrief. The package contains no LICENSE file
or other explicit redistribution grant. Attribution by itself is not a grant.
The release approach is therefore an optional dependency, not bundling or
copying Custom HUD source into this mod. Upstream redistribution permission
remains unverified and would be needed before changing that approach.

`tools/stereo/install-custom-hud-editor.ps1` is a developer helper for installing
an existing user-supplied source directory. It preserves an existing installed
copy and is not a downloader or permission to redistribute the dependency.

## Player flow

With the VR HUD active in gameplay, open Mod Options > Darktide VR and select
**Toggle editor**. Close the menus and the full Custom HUD editor opens in the
flat desktop mirror, using the VR canvas and existing border/cursor adapter.
The same button requests closing an active editor. Selecting it again while
still in menus cancels the pending request. Custom HUD's own configured editing
key continues to work.

While editing, the shared HUD texture displays:

> Use the desktop view to edit your HUD layout.

Both eyes consume the same instruction texture. The instruction disappears on
editor close; it does not take over the cursor or modify saved element positions.
Custom HUD owns editing, visibility, persistence and its keybindings. The adapter
waits for its normal menu-input guard instead of toggling while a menu owns input.
Missing/disabled dependencies and attempts before an active gameplay HUD produce
an explanatory notification. Pending requests are cleared on HUD destruction or
dependency disable, so they cannot unexpectedly open after a level transition.

## Validation

Windows x64 CTest `hud_panel`, `hud_options` and `lua_source_compile` pass.
The fixture covers missing dependency, unavailable HUD, deferred execution,
cancellation, one-shot toggling, dependency disable, persistent instruction
drawing only while editing, and restoration of renderer pass state.
Live editor rendering and worn readability are tracked separately from these
offline checks.

The initial live check reached the private range with fresh shared eyes and
the accepted HUD dimensions. Opening Esc then left the desktop showing the
world while the harness switched to native menu presentation mode 5. This
blocks the new button/notice acceptance until the menu rendering path is fixed;
the editor itself had not been activated when it occurred. Initial evidence is in
`artifacts/unattended/hud-editor-live-20260906.log` (ignored). The implementation
was checkpointed before repairing that separate rendering issue.

The follow-up menu mirror fix unblocked the check. The new options button
responded at its displayed position, closing menus opened the full Custom HUD
editor with its border and element list, and the desktop instruction rendered
in the shared HUD texture. F3 closed the editor, removed the instruction, and
restored the alive HUD group (26 elements). Fresh eye pairs continued without
pose mismatches. No saved item positions were edited during this check.
See `artifacts/unattended/menu-mirror-live-20260906.log` and the
[menu follow-up](MENU-INTERACTION-AUDIT.md). Worn readability remains pending.
