"""The controller binding sets the viewer suggests, checked against each other.

A Steam Frame session that comes up on emulated Oculus Touch, or on SteamVR's
generic profile, loses most of the gameplay controls -- SteamVR looks for a
generic-controller binding BEFORE a Touch one, and this viewer offers one. The
answer is a native Frame profile, and the contract that actually matters is
simple: **a Frame or Index session must not reach the game with fewer actions
than a Touch session.** That is what this checks, from the source, because
neither runtime is available to check it against.

It also holds the component paths to what Valve and Khronos document, so a
typo in a path -- which makes xrSuggestInteractionProfileBindings reject the
whole profile and silently drop the session back to emulation -- is a test
failure rather than a line in a log nobody reads.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, 'src', 'xr', 'main.cpp')

# Every action the gameplay set defines. `aim`/`grip` are poses; the rest are
# what core/gameplay_input.cpp turns into Darktide actions.
GAMEPLAY_ACTIONS = {
    'aim_action_', 'grip_action_', 'trigger_action_', 'squeeze_action_',
    'thumbstick_action_', 'primary_action_', 'secondary_action_',
    'stick_click_action_', 'menu_action_', 'haptic_action_',
}

# Valve's Steam Frame controller profile, from the OpenXR paths table in
# <https://github.com/ValveSoftware/Unity> com.valvesoftware.openxr.utils.
# The left hand spells its four face buttons dpad_*; the right hand a/b/x/y.
# The left hand's button in the menu position is `view`, not `menu`.
FRAME_PATHS = {
    'left': {
        'input/aim/pose', 'input/grip/pose', 'input/trigger/value',
        'input/trigger/click', 'input/trigger/touch', 'input/squeeze/value',
        'input/squeeze/click', 'input/squeeze/touch', 'input/thumbstick',
        'input/thumbstick/click', 'input/thumbstick/touch',
        'input/bumper/click', 'input/bumper/touch', 'input/view/click',
        'input/view/touch', 'input/system/click', 'input/system/touch',
        'input/dpad_up/click', 'input/dpad_down/click',
        'input/dpad_left/click', 'input/dpad_right/click',
        'input/dpad_up/touch', 'input/dpad_down/touch',
        'input/dpad_left/touch', 'input/dpad_right/touch', 'output/haptic',
    },
    'right': {
        'input/aim/pose', 'input/grip/pose', 'input/trigger/value',
        'input/trigger/click', 'input/trigger/touch', 'input/squeeze/value',
        'input/squeeze/click', 'input/squeeze/touch', 'input/thumbstick',
        'input/thumbstick/click', 'input/thumbstick/touch',
        'input/bumper/click', 'input/bumper/touch', 'input/menu/click',
        'input/menu/touch', 'input/system/click', 'input/system/touch',
        'input/a/click', 'input/b/click', 'input/x/click', 'input/y/click',
        'input/a/touch', 'input/b/touch', 'input/x/touch', 'input/y/touch',
        'output/haptic',
    },
}

# Khronos' core Valve Index profile. Both hands are identical.
INDEX_SIDE = {
    'input/aim/pose', 'input/grip/pose', 'input/system/click',
    'input/system/touch', 'input/a/click', 'input/a/touch', 'input/b/click',
    'input/b/touch', 'input/squeeze/value', 'input/squeeze/force',
    'input/trigger/click', 'input/trigger/value', 'input/trigger/touch',
    'input/thumbstick', 'input/thumbstick/x', 'input/thumbstick/y',
    'input/thumbstick/click', 'input/thumbstick/touch', 'input/trackpad',
    'input/trackpad/x', 'input/trackpad/y', 'input/trackpad/force',
    'input/trackpad/touch', 'output/haptic',
}
INDEX_PATHS = {'left': INDEX_SIDE, 'right': INDEX_SIDE}

BINDING = re.compile(
    r'\{\s*(\w+_action_)\s*,\s*\n?\s*path\("/user/hand/(left|right)/([^"]+)"\)\s*\}')
DECLARATION = re.compile(
    r'const std::array<XrActionSuggestedBinding,\s*(\d+)>\s*(\w+)_bindings\{\{')

failures = []


def fail(message):
    failures.append(message)


def parse(source):
    """Each declared binding array, as {name: (declared_count, [(action, hand, path)])}."""
    sets = {}
    for match in DECLARATION.finditer(source):
        declared, name = int(match.group(1)), match.group(2)
        # The array literal runs to the closing `}};` that balances it.
        end = source.index('}};', match.end())
        body = source[match.end():end]
        sets[name] = (declared, BINDING.findall(body))
    return sets


def actions_of(entries):
    """Which actions are bound, and on which hands."""
    by_action = {}
    for action, hand, _ in entries:
        by_action.setdefault(action, set()).add(hand)
    return by_action


source = open(SOURCE, encoding='utf-8').read()
sets = parse(source)

for required in ('touch', 'frame', 'index', 'simple'):
    if required not in sets:
        fail('no %s binding array found in src/xr/main.cpp -- the viewer no '
             'longer suggests that profile, or it was renamed' % required)
if failures:
    print('\n'.join(failures))
    sys.exit(1)

# 1. Declared size against actual entries. `std::array<T, 20>` given 19
#    initialisers compiles: the last element is value-initialised to a null
#    action and a null path, and the runtime rejects the entire profile.
for name, (declared, entries) in sets.items():
    if declared != len(entries):
        fail('%s_bindings declares %d entries and has %d. A short array leaves '
             'a null binding, which makes the runtime reject the whole profile '
             'and drop the session back to whatever it can emulate.'
             % (name, declared, len(entries)))

# 2. The contract. Touch is the proven set; Frame and Index must cover every
#    action it covers, on every hand it covers.
touch_actions = actions_of(sets['touch'][1])
unknown = set(touch_actions) - GAMEPLAY_ACTIONS
if unknown:
    fail('the Touch set binds actions this test does not know about (%s); add '
         'them to GAMEPLAY_ACTIONS and decide their Frame and Index mapping'
         % ', '.join(sorted(unknown)))

for name in ('frame', 'index'):
    bound = actions_of(sets[name][1])
    for action, hands in sorted(touch_actions.items()):
        if action not in bound:
            fail('%s binds %s on %s and %s binds it nowhere: a %s session '
                 'would reach the game with that control missing.'
                 % ('touch', action, '/'.join(sorted(hands)), name, name))
            continue
        missing = hands - bound[action]
        if missing:
            fail('%s binds %s on %s but %s does not: that hand loses the '
                 'control.' % ('touch', action, '/'.join(sorted(missing)), name))

# 3. Paths held to what the vendors document. A typo here is not a compile
#    error and not a crash -- it is a rejected profile and a silent fallback.
for name, table in (('frame', FRAME_PATHS), ('index', INDEX_PATHS)):
    for action, hand, component in sets[name][1]:
        if component not in table[hand]:
            fail('%s binds %s to /user/hand/%s/%s, which is not in the '
                 'documented profile. A path the runtime does not know makes '
                 'it reject every binding in the profile, not just this one.'
                 % (name, action, hand, component))

# 4. The Frame profile only exists behind its extension, and suggesting a
#    profile whose extension is not enabled fails with XR_ERROR_PATH_UNSUPPORTED.
if 'frame_controller_extension_' not in source:
    fail('nothing probes XR_VALVE_frame_controller_interaction, so the Frame '
         'profile path cannot be suggested at all')
# The guard must be the one around the BINDINGS. There is a second
# `if (frame_controller_extension_)` around the instance-creation list, and
# matching that one passes this check while the profile is suggested
# unconditionally -- which fails with XR_ERROR_PATH_UNSUPPORTED on any runtime
# without the extension, VDXR included.
guarded = False
for guard in re.finditer(r'if\s*\(frame_controller_extension_\)\s*\{', source):
    if 'frame_bindings' in source[guard.end():guard.end() + 400]:
        guarded = True
        break
if not guarded:
    fail('the Frame binding set is not behind its extension probe; suggesting '
         'that profile without the extension enabled fails the call with '
         'XR_ERROR_PATH_UNSUPPORTED on every runtime that lacks it')

# 5. Neither new profile may be able to stop the session. Both are untested
#    against a live runtime, and a viewer that refuses to start is worse than
#    one that comes up emulated and says so in the log.
for profile in ('frame', 'index'):
    if re.search(r'check_xr\(xrSuggestInteractionProfileBindings\(instance_,\s*&%s\)'
                 % profile, source):
        fail('the %s profile is suggested through check_xr, so a rejected path '
             'throws and the viewer never starts. Suggest it optionally and '
             'log the result.' % profile)

if failures:
    print('interaction_profiles=fail')
    for message in failures:
        print('  - ' + message)
    sys.exit(1)

print('interaction_profiles=pass touch=%d frame=%d index=%d simple=%d'
      % tuple(len(sets[name][1]) for name in ('touch', 'frame', 'index', 'simple')))
