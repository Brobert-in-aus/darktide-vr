"""Do the display tests catch a display that switches itself off for good?

Seven presentation modules stop drawing after an error. Five counted failures
and re-armed at a level load; `teammate_status` and `forearm_holsters` latched
on the FIRST one, and the teammate nameplates had no `destroy` at all, so a
single transient nil took them out until the game was restarted.

Run it after changing either module or either test:

    python tools/lua/mutate-display-rearm.py

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
MODS = os.path.join(ROOT, 'mods/darktidevr/scripts/mods/darktidevr')

SUBJECTS = {
    'teammate_status': {
        'test': os.path.join(ROOT, 'tests/tooling/test-teammate-status.lua'),
        'module': os.path.join(MODS, 'darktidevr_teammate_status.lua'),
        'extra': [],
        'pass': 'teammate_status=pass',
    },
    'forearm_holsters': {
        'test': os.path.join(ROOT, 'tests/tooling/test-forearm-holsters.lua'),
        'module': os.path.join(MODS, 'darktidevr_forearm_holsters.lua'),
        'extra': [os.path.join(MODS, 'darktidevr_holsters.lua')],
        'pass': 'forearm_holsters=pass',
    },
}

MUTATIONS = [
    ('teammate_status', 'the nameplates latch on the first error again',
     '''        consecutive_failures = consecutive_failures + 1
        total_failures = total_failures + 1
        -- The total matters as well as the run: a fault that fails every
        -- other frame for a whole level would reset the run for ever and
        -- warn on every bad frame.
        failed = consecutive_failures >= 3 or total_failures >= 20''',
     '''        consecutive_failures = consecutive_failures + 1
        total_failures = total_failures + 1
        failed = true'''),

    ('teammate_status', 'a level load no longer forgives the count',
     '        consecutive_failures, total_failures, failed = 0, 0, false\n    end\n'
     '    -- Three in a row is a broken display.',
     '    end\n    -- Three in a row is a broken display.'),

    ('teammate_status', 'a success does not clear the run of failures',
     '        if ok then\n            consecutive_failures = 0\n            return\n        end',
     '        if ok then\n            return\n        end'),

    ('forearm_holsters', 'the previews latch on the first error again',
     '''        if ok then
            consecutive_failures = 0
            return
        end
        consecutive_failures = consecutive_failures + 1
        total_failures = total_failures + 1
        teardown()''',
     '''        if ok then
            return
        end
        failed = true
        teardown()'''),

    ('forearm_holsters', 'the bad frame goes through destroy(), which forgives the count it is judged on',
     '        total_failures = total_failures + 1\n        teardown()',
     '        total_failures = total_failures + 1\n        api.destroy()'),

    ('forearm_holsters', 'destroy() tears down but no longer re-arms',
     '    function api.destroy()\n        teardown()\n'
     '        consecutive_failures, total_failures, failed = 0, 0, false\n    end',
     '    function api.destroy()\n        teardown()\n    end'),
]

LEGITIMATE = [
    ('teammate_status', 'the two counters are incremented in the other order',
     '        consecutive_failures = consecutive_failures + 1\n        total_failures = total_failures + 1',
     '        total_failures = total_failures + 1\n        consecutive_failures = consecutive_failures + 1'),
    ('forearm_holsters', 'the two counters are incremented in the other order',
     '        consecutive_failures = consecutive_failures + 1\n        total_failures = total_failures + 1',
     '        total_failures = total_failures + 1\n        consecutive_failures = consecutive_failures + 1'),
]


def run(subject, module_path):
    s = SUBJECTS[subject]
    p = subprocess.run([LUA, s['test'], module_path] + s['extra'],
                       capture_output=True, text=True, cwd=ROOT)
    out = p.stdout + p.stderr
    return (p.returncode == 0 and s['pass'] in p.stdout), out


def named(out, subject):
    leaf = os.path.basename(SUBJECTS[subject]['test'])
    return [l.split(leaf + ':', 1)[1] for l in out.splitlines() if leaf + ':' in l]


for subject, s in SUBJECTS.items():
    ok, out = run(subject, s['module'])
    if not ok:
        sys.exit('CONTROL FAILED for %s -- the harness proves nothing:\n%s' % (subject, out))
    print('control %-18s PASS' % subject)
print()

tmp = tempfile.mkdtemp(prefix='darktidevr-display-mutants-')
failures = 0
for group, label, cases in (('caught', 'NOT CAUGHT ', MUTATIONS),
                            ('allowed', 'FALSE ALARM', LEGITIMATE)):
    for subject, why, old, new in cases:
        module = SUBJECTS[subject]['module']
        source = io.open(module, encoding='utf-8', newline='').read()
        crlf = '\r\n' in source
        o = old.replace('\n', '\r\n') if crlf else old
        n = new.replace('\n', '\r\n') if crlf else new
        if source.count(o) != 1:
            sys.exit('%s: %r does not apply (%d occurrences)' % (subject, why, source.count(o)))
        path = os.path.join(tmp, os.path.basename(module))
        io.open(path, 'w', encoding='utf-8', newline='').write(source.replace(o, n))
        passed, out = run(subject, path)
        detail = (named(out, subject)[:1] or ['?'])[0][:140]
        if (group == 'caught') == (not passed):
            if group == 'caught':
                print('caught      %-18s %s\n            %s' % (subject, why, detail))
            else:
                print('allowed     %-18s %s' % (subject, why))
        else:
            failures += 1
            print('%s %-18s %s%s' % (label, subject, why,
                                     '' if passed else '\n            ' + detail))
    print()

shutil.rmtree(tmp, ignore_errors=True)
if failures:
    sys.exit('%d case(s) went the wrong way' % failures)
print('every mutation caught, every legitimate edit allowed, controls pass')
