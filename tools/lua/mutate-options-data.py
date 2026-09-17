"""Does tests/tooling/test-options-data.lua actually catch what it claims?

Each mutation below is a real way to break the options tree: eight of them
stop DMF registering the mod (so nothing loads at all) and two lose a saved
setting. On 18 September 2026 a review put six of these through the test and
all six passed, which is how a guard written for the catastrophic case turned
out to be checking none of DMF's own rules.

Run it after changing either the tree or the test:

    python tools/lua/mutate-options-data.py

Every line must read CAUGHT. It is deliberately NOT in ctest: the mutations
anchor on exact source text, so an ordinary edit to the tree would break the
build rather than the thing being tested. SKIPPED means an anchor has drifted
and that mutation is no longer testing what it says -- fix the anchor.
"""
import subprocess

import os
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
M = os.path.join(REPO, 'mods', 'darktidevr', 'scripts', 'mods', 'darktidevr') + os.sep
S = tempfile.mkdtemp(prefix='darktidevr-options-mutants-') + os.sep
LUA = os.path.join(REPO, 'build', 'dependencies', 'luajit', 'src', 'luajit.exe')
TEST = os.path.join(REPO, 'tests', 'tooling', 'test-options-data.lua')

source = open(M + 'darktidevr_data.lua', encoding='utf-8').read()
NL = chr(10)
PAD = ' ' * 24
SCANNER = (PAD + 'setting_id = "scanner_test_keybind",' + NL +
           PAD + 'type = "keybind",' + NL +
           PAD + 'default_value = {"f7"},' + NL)
MARKER = (PAD + 'setting_id = "marker_plane",' + NL +
          PAD + 'type = "checkbox",' + NL)

MUTATIONS = {
    'bad_type': (MARKER, PAD + 'setting_id = "marker_plane",' + NL +
                 PAD + 'type = "checkboxx",' + NL),
    'default_not_an_option': (
        PAD + 'setting_id = "vr_haptics_mode",' + NL + PAD + 'type = "dropdown",' + NL +
        PAD + 'default_value = "off",',
        PAD + 'setting_id = "vr_haptics_mode",' + NL + PAD + 'type = "dropdown",' + NL +
        PAD + 'default_value = "none",'),
    'button_without_text': (PAD + 'button_text = "melee_preview_toggle_button",' + NL, ''),
    'keybind_without_trigger': (SCANNER + PAD + 'keybind_trigger = "pressed",' + NL, SCANNER),
    'keybind_trigger_typo': (SCANNER + PAD + 'keybind_trigger = "pressed",',
                             SCANNER + PAD + 'keybind_trigger = "press",'),
    'keybind_type_typo': (SCANNER + PAD + 'keybind_trigger = "pressed",' + NL +
                          PAD + 'keybind_type = "function_call",',
                          SCANNER + PAD + 'keybind_trigger = "pressed",' + NL +
                          PAD + 'keybind_type = "function_cal",'),
    'checkbox_default_not_boolean': (MARKER + PAD + 'default_value = true,',
                                     MARKER + PAD + 'default_value = 0,'),
    'one_option_dropdown': (
        ' ' * 36 + '{text = "vr_two_hand_grip_hold", value = "hold"},' + NL +
        ' ' * 36 + '{text = "vr_two_hand_grip_toggle", value = "toggle"},' + NL,
        ' ' * 36 + '{text = "vr_two_hand_grip_hold", value = "hold"},' + NL),
    'duplicate_option_value': ('{text = "vr_weapon_charge_style_bars", value = "bars"}',
                               '{text = "vr_weapon_charge_style_bars", value = "count"}'),
    'lost_setting': (' ' * 20 + '{' + NL + PAD + 'setting_id = "vr_skull_throw",' + NL +
                     PAD + 'type = "checkbox",' + NL + PAD + 'default_value = false,' + NL +
                     ' ' * 20 + '},' + NL, ''),
}

failures = []
for name, (old, new) in sorted(MUTATIONS.items()):
    if source.count(old) != 1:
        print('SKIPPED ' + name + ' (anchor matched ' + str(source.count(old)) + ')')
        failures.append(name + ' [anchor]')
        continue
    path = S + 'mutant_' + name + '.lua'
    open(path, 'w', encoding='utf-8', newline='').write(source.replace(old, new))
    result = subprocess.run(
        [LUA, TEST, path, M + 'darktidevr_localization.lua', M.rstrip(os.sep)],
        capture_output=True, text=True)
    if result.returncode != 0:
        first = [l.strip() for l in result.stdout.splitlines() if l.strip()]
        print('CAUGHT  ' + name)
        if first:
            print('          ' + first[0])
    else:
        print('MISSED  ' + name)
        failures.append(name)

print()
print('all mutations caught' if not failures else 'MISSED: ' + ', '.join(failures))
