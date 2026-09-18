"""Does anything actually guard the marker-atlas claimant rules?

On 18 September 2026 a review found that three of the four fixes for the
conflated extents instrument lived in `darktidevr.lua` while every test that
covered them loaded a DIFFERENT file, so restoring any of the three left all
278 tests green. A fourth was guarded by a prefix rule that `"hud_marker"`
walks straight past while pooling all twenty marker templates back into one
bucket -- the exact failure being fixed.

The guard is now a real scan of each `marker_plane_scope` argument list in
`tools/stereo/test-darktide-lua-invariants.ps1`. Run this after touching
either:

    python tools/lua/mutate-claimant-rules.py

Every mutation must be CAUGHT and every legitimate edit ALLOWED. The control
runs unmutated and must PASS, so an environmental failure cannot be read as
"every mutation caught". Deliberately NOT in ctest: the mutations anchor on
exact source text.
"""
import io
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MOD = os.path.join(ROOT, 'mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua')
INV = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
       os.path.join(ROOT, 'tools/stereo/test-darktide-lua-invariants.ps1')]

MUTATIONS = [
    ('the world markers pool under one name again, prefixed so a prefix rule allows it',
     'markers_element and markers_element._player_camera, t,\n                "hud_interaction_popup") or nil',
     'markers_element and markers_element._player_camera, t,\n                "hud_marker") or nil'),

    ('a marker type is replaced by a template name that collides with the popup',
     'self._player_camera, t,\n                                        marker_type)',
     'self._player_camera, t,\n                                        "interaction")'),

    ('the world-marker call site stops naming its claimant at all',
     'self._player_camera, t,\n                                        marker_type)',
     'self._player_camera, t)'),

    ('the loop stops binding the marker type, making it an undeclared global',
     'for marker_type, markers in pairs(self._markers_by_type or {}) do',
     'for _, markers in pairs(self._markers_by_type or {}) do'),

    ('the scope builder defaults the claimant again, burying an unnamed call site',
     'claimant = claimant,',
     'claimant = claimant or "marker",'),

    ('the scope stops carrying its claimant',
     'claimant = claimant,',
     'no_claimant = claimant,'),

    ('the drop knob stops starting the measurement again',
     'presentation.marker_world.forget_extents("drop")',
     'local _unused_drop_reset = true'),

    ('the text knob stops starting the measurement again',
     'presentation.marker_world.forget_extents("text")',
     'local _unused_text_reset = true'),

    ('the surface knob stops starting the measurement again',
     'presentation.marker_world.forget_extents("surface")',
     'local _unused_surface_reset = true'),
]

LEGITIMATE = [
    ('the tag prompt and the popup swap which is written first',
     '"hud_interaction_popup") or nil', '"hud_interaction_popup" ) or nil'),
    ('a comment quotes a call site with a bare claimant',
     'function presentation.marker_plane_scope(ui_renderer, anchor, camera, t, claimant)',
     '-- e.g. presentation.marker_plane_scope(r, a, c, t, "interaction")\n'
     'function presentation.marker_plane_scope(ui_renderer, anchor, camera, t, claimant)'),
    ('the position is wrapped in one more helper call',
     'presentation.marker_plane_scope(ui_renderer,\n                Vector3Box.unbox(marker.position),',
     'presentation.marker_plane_scope(ui_renderer,\n                Vector3Box.unbox(rawget(marker, "position")),'),
]


def run():
    p = subprocess.run(INV, capture_output=True, text=True, cwd=ROOT)
    return 'lua_source_assertions=pass' in p.stdout, p.stdout + p.stderr


def detail(out):
    lines = [l.strip() for l in out.splitlines()
             if l.strip() and not l.strip().startswith('+') and 'At ' not in l]
    # The throw's first line is the same banner every time; the reason is the
    # indented line under it.
    for i, l in enumerate(lines):
        if l.startswith('The marker-atlas claimant rules are broken'):
            return (lines[i + 1][:150] if i + 1 < len(lines) else l[:150])
    return (lines[:1] or ['?'])[0][:150]


ok, out = run()
if not ok:
    sys.exit('CONTROL FAILED -- the harness proves nothing:\n' + out)
print('control (unmutated): PASS\n')

source = io.open(MOD, encoding='utf-8', newline='').read()
backup = MOD + '.claimantbak'
shutil.copy2(MOD, backup)
failures = 0
try:
    for group, cases in (('caught', MUTATIONS), ('allowed', LEGITIMATE)):
        for why, old, new in cases:
            if source.count(old) != 1:
                sys.exit('%r does not apply (%d occurrences)' % (why, source.count(old)))
            io.open(MOD, 'w', encoding='utf-8', newline='').write(source.replace(old, new))
            passed, out = run()
            if (group == 'caught') == (not passed):
                if group == 'caught':
                    print('caught      %s\n            %s' % (why, detail(out)))
                else:
                    print('allowed     %s' % why)
            else:
                failures += 1
                print('%s %s%s' % ('NOT CAUGHT ' if group == 'caught' else 'FALSE ALARM',
                                   why, '' if passed else '\n            ' + detail(out)))
        print()
finally:
    shutil.move(backup, MOD)

ok, out = run()
if not ok:
    sys.exit('THE RESTORE DID NOT WORK -- the tree is mutated:\n' + out)
print('restored: PASS')
if failures:
    sys.exit('%d case(s) went the wrong way' % failures)
print('every mutation caught, every legitimate edit allowed, control passes')
