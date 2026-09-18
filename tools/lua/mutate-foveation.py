"""Does foveation_tests.cpp catch a shading rate image pointed at the wrong place?

Nobody can check a foveation pattern by looking at it through a headset -- what
a wrong one looks like is "foveation looks bad", which is indistinguishable
from "foveation is not worth it". So the pattern is pure, and the test carries
the whole judgement.

The fault it is written against is specific: each eye is submitted with a
recentred symmetric projection, and the reticle readback on 18 September put
the two eyes' optical centres at equal and OPPOSITE horizontal NDC. A pattern
centred on the render target points its sharp region off to one side in the
left eye and the other side in the right.

Run it after changing either the pattern or the test:

    python tools/lua/mutate-foveation.py

Every mutation must be CAUGHT and every legitimate edit ALLOWED. The control
runs unmutated and must PASS. Not in ctest: the mutations anchor on exact
source text.
"""
import io
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HEADER = os.path.join(ROOT, 'src', 'core', 'foveation.h')
CMAKE = os.path.join(
    r'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE'
    r'\CommonExtensions\Microsoft\CMake\CMake\bin', 'cmake.exe')
BUILD = os.path.join(ROOT, 'build', 'windows-vs2022')
EXE = os.path.join(BUILD, 'tests', 'core_math', 'Release',
                   'darktidevr-foveation-tests.exe')

MUTATIONS = [
    ('the pattern is centred on the render target, ignoring the optics',
     '      const auto dx = ndc_x - pattern.centre_ndc_x;\n'
     '      const auto dy = ndc_y - pattern.centre_ndc_y;',
     '      const auto dx = ndc_x;\n'
     '      const auto dy = ndc_y;'),

    ('the horizontal centre is honoured but the vertical is not',
     '      const auto dy = ndc_y - pattern.centre_ndc_y;',
     '      const auto dy = ndc_y;'),

    ('NDC y is not flipped, so the pattern is upside down',
     '    const auto ndc_y =\n'
     '        1.0F - 2.0F * pixel_y / static_cast<float>(height);',
     '    const auto ndc_y =\n'
     '        2.0F * pixel_y / static_cast<float>(height) - 1.0F;'),

    ('the middle ring is dropped, so 1x1 steps straight to 4x4',
     '      row[tx] = middle <= 1.0F ? static_cast<std::uint8_t>(pattern.middle_rate)\n'
     '                               : static_cast<std::uint8_t>(pattern.outer_rate);',
     '      static_cast<void>(middle);\n'
     '      row[tx] = static_cast<std::uint8_t>(pattern.outer_rate);'),

    ('the row pitch is ignored and rows are packed by tile count',
     '    auto* row = tiles + static_cast<std::size_t>(ty) * row_pitch;',
     '    static_cast<void>(row_pitch);\n'
     '    auto* row = tiles + static_cast<std::size_t>(ty) * tiles_x;'),

    ('a partial tile at the edge is dropped',
     '  return tile_size == 0U ? 0U : (extent + tile_size - 1U) / tile_size;',
     '  return tile_size == 0U ? 0U : extent / tile_size;'),

    ('the vertical radius is used for both axes, making the region circular',
     '      const auto inner = (dx / inner_x) * (dx / inner_x) +\n'
     '                         (dy / inner_y) * (dy / inner_y);',
     '      static_cast<void>(inner_x);\n'
     '      const auto inner = (dx / inner_y) * (dx / inner_y) +\n'
     '                         (dy / inner_y) * (dy / inner_y);'),

    # NOT a mutation: swapping the two log2 shifts in the cost. The cost is
    # their PRODUCT, and a product is commutative, so 2x4 and 4x2 come to the
    # same eighth either way. Nothing any caller can observe changes, which
    # makes it not a defect rather than one the test misses.
    ('the cost counts every tile as full rate',
     '      shaded += 1.0 / static_cast<double>(coarse_x * coarse_y);',
     '      static_cast<void>(coarse_x);\n'
     '      static_cast<void>(coarse_y);\n'
     '      shaded += 1.0;'),

    ('a null image is written through anyway',
     '  if (tiles == nullptr || tile_size == 0U || width == 0U || height == 0U) {\n'
     '    return;\n'
     '  }',
     '  if (tile_size == 0U || width == 0U || height == 0U) {\n'
     '    return;\n'
     '  }'),
]

LEGITIMATE = [
    ('the zone test is written with multiplies instead of divides', [
        ('      const auto inner = (dx / inner_x) * (dx / inner_x) +\n'
         '                         (dy / inner_y) * (dy / inner_y);',
         '      const auto rx = 1.0F / inner_x;\n'
         '      const auto ry = 1.0F / inner_y;\n'
         '      const auto inner = (dx * rx) * (dx * rx) + (dy * ry) * (dy * ry);'),
     ]),
    ('the default zone radii are widened', [
        ('  float inner_radius_x{0.35F};\n  float inner_radius_y{0.45F};',
         '  float inner_radius_x{0.40F};\n  float inner_radius_y{0.50F};'),
     ]),
    ('the middle rate becomes the non-square 2x4', [
        ('  ShadingRate middle_rate{shading_rate_2x2};',
         '  ShadingRate middle_rate{shading_rate_2x4};'),
     ]),
]


def run():
    build = subprocess.run(
        [CMAKE, '--build', BUILD, '--config', 'Release', '--target',
         'darktidevr-foveation-tests'],
        capture_output=True, text=True, cwd=ROOT)
    if build.returncode != 0:
        return False, 'BUILD FAILED: ' + '\n'.join(
            l for l in build.stdout.splitlines() if 'error' in l.lower())
    p = subprocess.run([EXE], capture_output=True, text=True, cwd=ROOT)
    return 'foveation.result=pass' in p.stdout, p.stdout + p.stderr


ok, out = run()
if not ok:
    sys.exit('CONTROL FAILED -- the harness proves nothing:\n' + out)
print('control (unmutated): PASS\n')

source = io.open(HEADER, encoding='utf-8', newline='').read()
CRLF = '\r\n' in source
fit = (lambda t: t.replace('\n', '\r\n')) if CRLF else (lambda t: t)
backup = HEADER + '.foveationbak'
shutil.copy2(HEADER, backup)
failures = 0
try:
    for group, cases in (('caught', MUTATIONS), ('allowed', LEGITIMATE)):
        for case in cases:
            why = case[0]
            edits = case[1] if len(case) == 2 else [(case[1], case[2])]
            mutated = source
            for old, new in edits:
                o, n = fit(old), fit(new)
                if mutated.count(o) != 1:
                    sys.exit('%r does not apply (%d occurrences of %r)'
                             % (why, mutated.count(o), old[:60]))
                mutated = mutated.replace(o, n)
            io.open(HEADER, 'w', encoding='utf-8', newline='').write(mutated)
            os.utime(HEADER, None)
            passed, out = run()
            detail = next((l.strip() for l in out.splitlines()
                           if l.startswith('foveation: ')), out.strip()[:150])
            built = not detail.startswith('BUILD FAILED')
            if (group == 'caught') == (not passed):
                if group == 'caught':
                    print('%s %s\n            %s'
                          % ('caught     ' if built else 'compiler   ', why,
                             detail[:150]))
                else:
                    print('allowed     %s' % why)
            else:
                failures += 1
                print('%s %s%s' % ('NOT CAUGHT ' if group == 'caught' else 'FALSE ALARM',
                                   why, '' if passed else '\n            ' + detail[:150]))
        print()
finally:
    shutil.move(backup, HEADER)
    # copy2 preserved the original's timestamp, so the restored header looks
    # OLDER than the object built from the mutated one and MSBuild skips the
    # rebuild -- leaving a mutated binary behind a clean source tree. Touch it.
    os.utime(HEADER, None)

ok, out = run()
if not ok:
    sys.exit('THE RESTORE DID NOT WORK -- the header is mutated:\n' + out)
print('restored: PASS')
if failures:
    sys.exit('%d case(s) went the wrong way' % failures)
print('every mutation caught, every legitimate edit allowed, control passes')
