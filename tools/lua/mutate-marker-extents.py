"""Does tests/tooling/test-marker-world.lua catch a conflated extents report?

The atlas cell was resized on 18 September 2026 from one maximum taken over
everything that claims a cell -- a width from the interaction popup and a
height that could not have come from it. The extents instrument now keeps a
maximum per claimant, and each mutation here is a real way that could have
been written wrong.

Run it after changing either the instrument or the test:

    python tools/lua/mutate-marker-extents.py

Every mutation must be CAUGHT and every legitimate edit ALLOWED. The control
runs unmutated and must PASS, so an environmental failure cannot be read as
"every mutation caught". Deliberately NOT in ctest: the mutations anchor on
exact source text, so an ordinary edit would break the build rather than the
thing being tested.
"""
import io
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LUA = os.path.join(ROOT, 'build/dependencies/luajit/src/luajit.exe')
TEST = os.path.join(ROOT, 'tests/tooling/test-marker-world.lua')
MOD = os.path.join(ROOT, 'mods/darktidevr/scripts/mods/darktidevr/darktidevr_marker_world.lua')
PLANE = os.path.join(ROOT, 'mods/darktidevr/scripts/mods/darktidevr/darktidevr_marker_plane.lua')

MUTATIONS = [
    ('scope tagged but the tag never threaded through shifted',
     'size and (size[2] or 0) * unit * factor, scope.claimant)',
     'size and (size[2] or 0) * unit * factor)'),

    ('one conflated line again, the 18 September shape',
     '''    for name, each in pairs(extent.per) do
        if each.dx > each.reported_dx + 0.5 or each.dy > each.reported_dy + 0.5 then
            each.reported_dx, each.reported_dy = each.dx, each.dy
            state.api.log(string.format(
                "DARKTIDEVR_MARKER extents claimant=%s max_dx=%.1f max_dy=%.1f half_cell=%.1f,%.1f boxed=1",
                name, each.dx, each.dy, (atlas and atlas.CELL_WIDTH or 0) * 0.5,
                (atlas and atlas.CELL_HEIGHT or 0) * 0.5))
        end
    end''',
     '''    state.api.log(string.format(
        "DARKTIDEVR_MARKER extents max_dx=%.1f max_dy=%.1f half_cell=%.1f,%.1f boxed=1",
        extent.dx, extent.dy, (atlas and atlas.CELL_WIDTH or 0) * 0.5,
        (atlas and atlas.CELL_HEIGHT or 0) * 0.5))'''),

    ('only the claimant drawing on the tick is reported',
     '    for name, each in pairs(extent.per) do\n        if each.dx',
     '    for name, each in pairs({[who] = slot}) do\n        if each.dx'),

    ('the global maximum still gates the whole report',
     '    local atlas = scope_atlas\n    if not (state.api and state.api.log) then return end',
     '''    if extent.dx <= (extent.reported_dx or 0) + 0.5 and
            extent.dy <= (extent.reported_dy or 0) + 0.5 then return end
    extent.reported_dx, extent.reported_dy = extent.dx, extent.dy
    local atlas = scope_atlas
    if not (state.api and state.api.log) then return end'''),

    ('the per-claimant maximum keeps only the last draw, not the worst',
     '    if ax > slot.dx then slot.dx = ax end\n    if ay > slot.dy then slot.dy = ay end',
     '    slot.dx, slot.dy = ax, ay'),
]


# The negative direction: legitimate edits that must NOT be flagged. A guard
# that blocks an ordinary change is worse than none.
LEGITIMATE = [
    ('the unnamed fallback is renamed',
     'local who = claimant or "?"', 'local who = claimant or "unnamed"'),
    ('the growth throttle is tightened to a quarter pixel',
     'each.dx > each.reported_dx + 0.5 or each.dy > each.reported_dy + 0.5',
     'each.dx > each.reported_dx + 0.25 or each.dy > each.reported_dy + 0.25'),
]


def run(mod_path):
    p = subprocess.run([LUA, TEST, mod_path, PLANE], capture_output=True, text=True)
    out = (p.stdout + p.stderr).strip()
    return p.returncode == 0 and 'marker_world.result=pass' in p.stdout, out


ok, out = run(MOD)
if not ok:
    sys.exit('CONTROL FAILED -- the harness proves nothing:\n' + out)
print('control (unmutated): PASS\n')

source = io.open(MOD, encoding='utf-8', newline='').read()
failures = 0
tmp = tempfile.mkdtemp()
for name, old, new in MUTATIONS:
    if source.count(old) != 1:
        sys.exit('mutation %r does not apply (%d occurrences)' % (name, source.count(old)))
    path = os.path.join(tmp, 'darktidevr_marker_world.lua')
    io.open(path, 'w', encoding='utf-8', newline='').write(source.replace(old, new))
    passed, out = run(path)
    named = [l.split('test-marker-world.lua:', 1)[1] for l in out.splitlines()
             if 'test-marker-world.lua:' in l]
    last = named[:1] or [l for l in out.splitlines() if l.strip()][:1] or ['(no output)']
    if passed:
        print('NOT CAUGHT  %s' % name)
        failures += 1
    else:
        print('caught      %s\n            %s' % (name, last[0][:150]))
print()
for name, old, new in LEGITIMATE:
    if source.count(old) != 1:
        sys.exit('legitimate edit %r does not apply (%d occurrences)' % (name, source.count(old)))
    path = os.path.join(tmp, 'darktidevr_marker_world.lua')
    io.open(path, 'w', encoding='utf-8', newline='').write(source.replace(old, new))
    passed, out = run(path)
    named = [l.split('test-marker-world.lua:', 1)[1] for l in out.splitlines()
             if 'test-marker-world.lua:' in l]
    if passed:
        print('allowed     %s' % name)
    else:
        print('FALSE ALARM %s -- %s' % (name, (named[:1] or ['?'])[0][:150]))
        failures += 1
shutil.rmtree(tmp, ignore_errors=True)
print()
if failures:
    sys.exit('%d mutation(s) passed the test -- the guard does not guard them' % failures)
print('every mutation caught, control passes')
