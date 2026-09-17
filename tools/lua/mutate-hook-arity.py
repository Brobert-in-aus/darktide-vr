"""Does the hook-arity invariant actually catch what it claims?

`tools/stereo/test-darktide-lua-invariants.ps1` refuses a mod:hook handler
that names the stock signature, and a forward that passes a fixed list. Its
first version passed every mutation below while each one was a real dropped
argument -- it matched one spelling of the call, one shape of the signature,
and gave up silently on anything spanning two lines (review, 18 September).

Run it after changing either the invariant or a hook:

    python tools/lua/mutate-hook-arity.py

Every line must read CAUGHT. SKIPPED means an anchor has drifted and that
mutation no longer tests what it says -- fix the anchor rather than the
expectation. Not in ctest: the mutations anchor on exact source text, so an
ordinary edit would break the build rather than the thing being tested.
"""
import os
import shutil
import subprocess
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MOD = os.path.join(REPO, 'mods', 'darktidevr', 'scripts', 'mods', 'darktidevr')
CHECK = os.path.join(REPO, 'tools', 'stereo', 'test-darktide-lua-invariants.ps1')

NL = chr(10)

# file, what to replace, what to replace it with, why it matters
MUTATIONS = [
    ('darktidevr_communication_wheel.lua',
     'pack(pcall(func,self,...))', 'pack(pcall(func,self))',
     'a compact pcall forward, spelled without spaces'),
    ('darktidevr.lua',
     'local result = func(' + NL +
     '            self, dt, t, input_service, ui_renderer, render_settings, ...)',
     'local result = func(' + NL +
     '            self, dt, t, input_service, ui_renderer, render_settings)',
     'a forward split across two lines'),
    ('darktidevr.lua',
     'mod:hook("HudElementWorldMarkers", "_apply_scale", function(func, self, widget, scale, ...)',
     'mod:hook("HudElementWorldMarkers", "_apply_scale", function(func, self, widget, scale)',
     'an ordinary handler signature'),
    ('darktidevr.lua',
     'mod:hook(World, "update_lod_levels", function(func, world, camera, ...)',
     'mod:hook(World, "update_lod_levels", function(func, world, camera)',
     'a handler whose second parameter is not self'),
    ('darktidevr_spectator_input.lua',
     "mod:hook('HudElementSpectatorText','_get_cycle_input_text',function(func,self,...)",
     "mod:hook('HudElementSpectatorText','_get_cycle_input_text',function(func,self)",
     'a handler that takes no stock arguments at all'),
    ('darktidevr_eye_targets.lua',
     '            shading, callback, mood, targets, ...)',
     '            shading, callback, mood, targets)',
     'a handler signature split across three lines'),
]


def run_check(root):
    return subprocess.run(
        ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', CHECK,
         '-SourcePath', os.path.join(root, 'darktidevr.lua')],
        capture_output=True, text=True)


failures = []
for name, old, new, why in MUTATIONS:
    root = tempfile.mkdtemp(prefix='darktidevr-hook-arity-')
    try:
        for entry in os.listdir(MOD):
            if entry.endswith('.lua'):
                shutil.copy2(os.path.join(MOD, entry), os.path.join(root, entry))
        # The check reads the mod descriptor beside the source.
        descriptor = os.path.join(REPO, 'mods', 'darktidevr', 'darktidevr.mod')
        if os.path.exists(descriptor):
            shutil.copy2(descriptor, os.path.join(root, 'darktidevr.mod'))
        target = os.path.join(root, name)
        text = open(target, encoding='utf-8', newline='').read()
        if text.count(old) != 1:
            print('SKIPPED %-58s (anchor matched %d)' % (why, text.count(old)))
            failures.append(why + ' [anchor]')
            continue
        open(target, 'w', encoding='utf-8', newline='').write(text.replace(old, new))
        result = run_check(root)
        if result.returncode != 0:
            print('CAUGHT  %s' % why)
        else:
            print('MISSED  %s' % why)
            failures.append(why)
    finally:
        shutil.rmtree(root, ignore_errors=True)

print()
print('every mutation caught' if not failures
      else 'MISSED: ' + '; '.join(failures))
