"""Does tests/tooling/test-interaction-profiles.py catch a broken binding set?

The Steam Frame and Index profiles cannot be tested against a live runtime --
neither exists on this machine -- so a source test carries the whole contract:
a Frame or Index session must not reach the game with fewer controls than a
Touch session, and every component path must be one the vendor documents,
because a path the runtime does not know makes it reject the entire profile
and fall back silently to emulation.

Run it after changing either the bindings or the test:

    python tools/lua/mutate-interaction-profiles.py

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
SOURCE = os.path.join(ROOT, 'src', 'xr', 'main.cpp')
TEST = os.path.join(ROOT, 'tests', 'tooling', 'test-interaction-profiles.py')

MUTATIONS = [
    # These two fix the declared count as well as removing the bindings, so the
    # array-size check cannot fire and the COVERAGE contract is what has to
    # catch them. A mutation caught by the wrong check tests the wrong thing.
    ('the Frame set loses the menu button entirely', [
        ('const std::array<XrActionSuggestedBinding, 20> frame_bindings{{',
         'const std::array<XrActionSuggestedBinding, 18> frame_bindings{{'),
        ('            {menu_action_, path("/user/hand/left/input/view/click")},\n'
         '            {menu_action_, path("/user/hand/right/input/menu/click")},\n',
         ''),
     ]),

    ('the Frame set binds the trigger on one hand only',
     'const std::array<XrActionSuggestedBinding, 20> frame_bindings{{\n'
     '            {aim_action_, path("/user/hand/left/input/aim/pose")},\n'
     '            {aim_action_, path("/user/hand/right/input/aim/pose")},\n'
     '            {grip_action_, path("/user/hand/left/input/grip/pose")},\n'
     '            {grip_action_, path("/user/hand/right/input/grip/pose")},\n'
     '            {trigger_action_, path("/user/hand/left/input/trigger/value")},\n'
     '            {trigger_action_, path("/user/hand/right/input/trigger/value")},\n',
     'const std::array<XrActionSuggestedBinding, 19> frame_bindings{{\n'
     '            {aim_action_, path("/user/hand/left/input/aim/pose")},\n'
     '            {aim_action_, path("/user/hand/right/input/aim/pose")},\n'
     '            {grip_action_, path("/user/hand/left/input/grip/pose")},\n'
     '            {grip_action_, path("/user/hand/right/input/grip/pose")},\n'
     '            {trigger_action_, path("/user/hand/left/input/trigger/value")},\n'),

    ('the Index set loses the thumbstick click on the right hand', [
        ('const std::array<XrActionSuggestedBinding, 21> index_bindings{{',
         'const std::array<XrActionSuggestedBinding, 20> index_bindings{{'),
        ('            {stick_click_action_,\n'
         '             path("/user/hand/right/input/thumbstick/click")},\n'
         '            {menu_action_, path("/user/hand/left/input/trackpad/force")},',
         '            {menu_action_, path("/user/hand/left/input/trackpad/force")},'),
     ]),

    ('a Frame component path is misspelled, which rejects the whole profile',
     'path("/user/hand/left/input/dpad_down/click")',
     'path("/user/hand/left/input/dpad-down/click")'),

    ('the left hand is given the right hand\'s menu spelling',
     'path("/user/hand/left/input/view/click")',
     'path("/user/hand/left/input/menu/click")'),

    ('the Frame array is declared one longer than its contents',
     'const std::array<XrActionSuggestedBinding, 20> frame_bindings{{',
     'const std::array<XrActionSuggestedBinding, 21> frame_bindings{{'),

    ('the Frame profile is suggested without its extension enabled',
     '      if (frame_controller_extension_) {\n'
     '        const std::array<XrActionSuggestedBinding, 20> frame_bindings{{',
     '      if (true) {\n'
     '        const std::array<XrActionSuggestedBinding, 20> frame_bindings{{'),

    ('an Index path that belongs to the Frame profile only',
     'path("/user/hand/left/input/trackpad/force")',
     'path("/user/hand/left/input/view/click")'),
]

LEGITIMATE = [
    ('the Frame set also binds the bumper, a documented path', [
        ('const std::array<XrActionSuggestedBinding, 20> frame_bindings{{',
         'const std::array<XrActionSuggestedBinding, 22> frame_bindings{{'),
        ('            {haptic_action_, path("/user/hand/right/output/haptic")},\n'
         '        }};\n'
         '        suggest_optional("frame", kFrameControllerProfilePath,',
         '            {haptic_action_, path("/user/hand/right/output/haptic")},\n'
         '            {secondary_action_, path("/user/hand/left/input/bumper/click")},\n'
         '            {secondary_action_, path("/user/hand/right/input/bumper/click")},\n'
         '        }};\n'
         '        suggest_optional("frame", kFrameControllerProfilePath,'),
     ]),
    ('primary and secondary swap ends of the Frame diamond',
     '            {primary_action_, path("/user/hand/left/input/dpad_down/click")},\n'
     '            {primary_action_, path("/user/hand/right/input/a/click")},\n'
     '            {secondary_action_, path("/user/hand/left/input/dpad_up/click")},\n'
     '            {secondary_action_, path("/user/hand/right/input/y/click")},',
     '            {primary_action_, path("/user/hand/left/input/dpad_up/click")},\n'
     '            {primary_action_, path("/user/hand/right/input/y/click")},\n'
     '            {secondary_action_, path("/user/hand/left/input/dpad_down/click")},\n'
     '            {secondary_action_, path("/user/hand/right/input/a/click")},'),
]


def run():
    p = subprocess.run([sys.executable, '-B', TEST], capture_output=True,
                       text=True, cwd=ROOT)
    return 'interaction_profiles=pass' in p.stdout, p.stdout + p.stderr


def reason(out):
    for line in out.splitlines():
        if line.strip().startswith('- '):
            return line.strip()[2:][:150]
    return (out.strip().splitlines() or ['?'])[0][:150]


ok, out = run()
if not ok:
    sys.exit('CONTROL FAILED -- the harness proves nothing:\n' + out)
print('control (unmutated): PASS\n')

source = io.open(SOURCE, encoding='utf-8', newline='').read()
CRLF = '\r\n' in source
fit = (lambda t: t.replace('\n', '\r\n')) if CRLF else (lambda t: t)
backup = SOURCE + '.profilebak'
shutil.copy2(SOURCE, backup)
failures = 0
try:
    for group, cases in (('caught', MUTATIONS), ('allowed', LEGITIMATE)):
        for case in cases:
            why, edits = case[0], case[1] if len(case) == 2 else [(case[1], case[2])]
            mutated = source
            for old, new in edits:
                o, n = fit(old), fit(new)
                if mutated.count(o) != 1:
                    sys.exit('%r does not apply (%d occurrences of %r)'
                             % (why, mutated.count(o), old[:60]))
                mutated = mutated.replace(o, n)
            io.open(SOURCE, 'w', encoding='utf-8', newline='').write(mutated)
            passed, out = run()
            if (group == 'caught') == (not passed):
                if group == 'caught':
                    print('caught      %s\n            %s' % (why, reason(out)))
                else:
                    print('allowed     %s' % why)
            else:
                failures += 1
                print('%s %s%s' % ('NOT CAUGHT ' if group == 'caught' else 'FALSE ALARM',
                                   why, '' if passed else '\n            ' + reason(out)))
        print()
finally:
    shutil.move(backup, SOURCE)

ok, out = run()
if not ok:
    sys.exit('THE RESTORE DID NOT WORK -- the source is mutated:\n' + out)
print('restored: PASS')
if failures:
    sys.exit('%d case(s) went the wrong way' % failures)
print('every mutation caught, every legitimate edit allowed, control passes')
