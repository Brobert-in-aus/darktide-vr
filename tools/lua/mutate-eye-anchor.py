"""Does tests/tooling/test-eye-anchor-offset.lua catch a mis-wired eye correction?

The worn session of 18 September 2026 sized the last of item 52's head error:
the eyes needed 5 cm up and 5 cm forward. The measured anchor is not wrong --
the avatar's eye node is where it is -- so the correction is added on top of
the capture, every call, and never folded into the stored capture.

Three ways that could have been written wrong, and all three are quiet: a
helper that is written and never called, a sign that pushes the eyes further
into the head, and a correction folded into the capture so it compounds on
every later read. None of them would error, and the second and third would look
like "the change did not work" and "the change worked too well" rather than
like a defect.

    python tools/lua/mutate-eye-anchor.py

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
TEST = os.path.join(ROOT, 'tests/tooling/test-eye-anchor-offset.lua')
MOD = os.path.join(ROOT, 'mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua')

APPLY = '''    local local_offset = presentation.eye_anchor_correction(Vector3(
        observation.body_camera_eye_offset_x,
        observation.body_camera_eye_offset_y,
        observation.body_camera_eye_offset_z))'''
RAW = '''    local local_offset = Vector3(
        observation.body_camera_eye_offset_x,
        observation.body_camera_eye_offset_y,
        observation.body_camera_eye_offset_z)'''

MUTATIONS = [
    # The one this whole file exists for. A helper with its own passing tests,
    # never called: the anchor returns the raw capture and nothing moves.
    ('the correction is written but the anchor never calls it', APPLY, RAW),

    ('forward is negated -- the eyes go further back into the head',
     'Vector3.y(local_offset) + presentation.EYE_ANCHOR_FORWARD_M',
     'Vector3.y(local_offset) - presentation.EYE_ANCHOR_FORWARD_M'),

    ('up is negated -- the eyes drop instead of rising',
     'Vector3.z(local_offset) + presentation.EYE_ANCHOR_UP_M',
     'Vector3.z(local_offset) - presentation.EYE_ANCHOR_UP_M'),

    ('the two axes are swapped, so forward goes up and up goes forward',
     '''        Vector3.y(local_offset) + presentation.EYE_ANCHOR_FORWARD_M,
        Vector3.z(local_offset) + presentation.EYE_ANCHOR_UP_M)''',
     '''        Vector3.y(local_offset) + presentation.EYE_ANCHOR_UP_M,
        Vector3.z(local_offset) + presentation.EYE_ANCHOR_FORWARD_M)'''),

    ('only one axis is corrected -- half the answer, and the half that reads as "still too low"',
     'Vector3.z(local_offset) + presentation.EYE_ANCHOR_UP_M)',
     'Vector3.z(local_offset))'),

    ('the correction becomes lateral, which a cyclopean camera must never be',
     'Vector3.x(local_offset),\n        Vector3.y(local_offset) + presentation.EYE_ANCHOR_FORWARD_M',
     'Vector3.x(local_offset) + presentation.EYE_ANCHOR_FORWARD_M,\n        Vector3.y(local_offset)'),

    # Folded into the capture instead of applied on read. The capture happens
    # once per unit, so this LOOKS right on the first frame and then compounds.
    ('the correction is folded into the stored capture, where it compounds',
     '''        observation.body_camera_eye_offset_y = Vector3.y(local_offset)
        observation.body_camera_eye_offset_z = Vector3.z(local_offset)''',
     '''        observation.body_camera_eye_offset_y = Vector3.y(local_offset) +
            presentation.EYE_ANCHOR_FORWARD_M
        observation.body_camera_eye_offset_z = Vector3.z(local_offset) +
            presentation.EYE_ANCHOR_UP_M'''),

    ('centimetres written as metres -- 5 m, not 5 cm',
     'presentation.EYE_ANCHOR_UP_M = 0.05', 'presentation.EYE_ANCHOR_UP_M = 5'),

    ('a nil capture is corrected anyway and errors on the first spawn',
     '    if not local_offset then return nil end\n', '\n'),

    # The three below were found by a review on 18 September, each of which
    # PASSED the first cut of the test. All three are the same mistake: the
    # test checked that the correction appeared somewhere in the function
    # rather than that it was what the function returned.
    ('the correction is folded in one line above the store, where it compounds',
     '''            component.rotation, model_eye - head_position, overdue)
        if not local_offset then''',
     '''            component.rotation, model_eye - head_position, overdue)
        local_offset = local_offset and presentation.eye_anchor_correction(local_offset)
        if not local_offset then'''),

    ('the correction is computed into an unused local beside a raw return',
     APPLY,
     '''    local _unused = presentation.eye_anchor_correction(Vector3(
        observation.body_camera_eye_offset_x,
        observation.body_camera_eye_offset_y,
        observation.body_camera_eye_offset_z))
''' + RAW),

    # The fallback. Correcting only the captured path grows the jump between
    # them from 8.6 cm to 14.8 cm, which is a world translation of the whole
    # scene and the reason EYE_CAPTURE_DEADLINE exists.
    ('the fallback is left uncorrected, so the capture lands with a bigger jump',
     '    return head_position + presentation.rotate_vector(basis, corrected)',
     '    return head_position + presentation.rotate_vector(basis, '
     'Vector3(0, 0, presentation.EYE_ANCHOR_FALLBACK_UP_M))'),

    ('the basis-less fallback keeps the old bare 5 cm',
     '''        return head_position + Vector3.up() *
            (presentation.EYE_ANCHOR_FALLBACK_UP_M + presentation.EYE_ANCHOR_UP_M)''',
     '        return head_position + Vector3.up() * presentation.EYE_ANCHOR_FALLBACK_UP_M'),

    # The capture deadline's timer, which was never cleared before today.
    ('a successful capture leaves its wait running, so the next one waives the pitch gate',
     '        observation.body_camera_eye_offset_since = nil\n', ''),

    ('the calibration reset leaves the timer behind',
     '    controller_observation.body_camera_eye_offset_since = nil\n    mod:info(',
     '    mod:info('),
]

# The negative direction: legitimate edits that must NOT be flagged. A guard
# that blocks an ordinary change is worse than none.
LEGITIMATE = [
    ('the helper is written with a local instead of three calls',
     '''    return Vector3(
        Vector3.x(local_offset),
        Vector3.y(local_offset) + presentation.EYE_ANCHOR_FORWARD_M,
        Vector3.z(local_offset) + presentation.EYE_ANCHOR_UP_M)''',
     '''    local x, y, z = Vector3.x(local_offset), Vector3.y(local_offset), Vector3.z(local_offset)
    return Vector3(x, y + presentation.EYE_ANCHOR_FORWARD_M, z + presentation.EYE_ANCHOR_UP_M)'''),
    # The next worn answer sizes these again. The test must hold the wiring and
    # the sign, not the two numbers, or the next 2 cm costs an argument with
    # the harness. The magnitudes themselves are asserted against the
    # constants, so both move together or the test says so.
    ('the correction is re-sized by a later worn answer',
     'presentation.EYE_ANCHOR_FORWARD_M = 0.05\npresentation.EYE_ANCHOR_UP_M = 0.05',
     'presentation.EYE_ANCHOR_FORWARD_M = 0.07\npresentation.EYE_ANCHOR_UP_M = 0.07'),
    ('the guard is written as an early return with a comment',
     '    if not local_offset then return nil end',
     '    -- No capture yet: there is nothing to correct.\n    if local_offset == nil then return nil end'),
]


def run(mod_path):
    p = subprocess.run([LUA, TEST, mod_path], capture_output=True, text=True)
    out = (p.stdout + p.stderr).strip()
    return p.returncode == 0 and 'eye_anchor_offset=pass' in p.stdout, out


def first_line(out):
    named = [l.split('test-eye-anchor-offset.lua:', 1)[1] for l in out.splitlines()
             if 'test-eye-anchor-offset.lua:' in l]
    return (named[:1] or [l for l in out.splitlines() if l.strip()][:1] or ['(no output)'])[0]


ok, out = run(MOD)
if not ok:
    sys.exit('CONTROL FAILED -- the harness proves nothing:\n' + out)
print('control (unmutated): PASS\n')

source = io.open(MOD, encoding='utf-8', newline='').read()
# The file is CRLF on disk; the mutations are written LF.
CRLF = '\r\n' in source


def fit(text):
    return text.replace('\n', '\r\n') if CRLF else text


failures = 0
tmp = tempfile.mkdtemp()
path = os.path.join(tmp, 'darktidevr.lua')
for label, group, expect_caught in (('mutation', MUTATIONS, True),
                                    ('legitimate edit', LEGITIMATE, False)):
    for name, old, new in group:
        old, new = fit(old), fit(new)
        if source.count(old) != 1:
            sys.exit('%s %r does not apply (%d occurrences)' % (label, name, source.count(old)))
        io.open(path, 'w', encoding='utf-8', newline='').write(source.replace(old, new))
        passed, out = run(path)
        if expect_caught and passed:
            print('NOT CAUGHT  %s' % name)
            failures += 1
        elif expect_caught:
            print('caught      %s\n            %s' % (name, first_line(out)[:150]))
        elif passed:
            print('allowed     %s' % name)
        else:
            print('FALSE ALARM %s -- %s' % (name, first_line(out)[:150]))
            failures += 1
    print()
shutil.rmtree(tmp, ignore_errors=True)
if failures:
    sys.exit('%d mutation(s) passed the test -- the guard does not guard them' % failures)
print('every mutation caught, every legitimate edit allowed, control passes')
