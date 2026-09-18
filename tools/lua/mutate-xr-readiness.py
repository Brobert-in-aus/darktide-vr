"""Does validate-xr-readiness.ps1 catch a readiness gate that lets a run start?

The gate hard-required a VirtualDesktop.Streamer, the VDXR manifest and an ADB
read of Quest power. On a Steam Frame every one of those throws: no Streamer,
`steamxr_win64.json` as the active runtime, and no ADB at all. Splitting the
gate by runtime profile is what makes a Frame session possible -- and a split
that leaks in either direction is worse than no split, because a run that
starts without its headset ready burns a launch and, historically here, risks
a bugcheck during the level load.

Run it after changing either the gate or its test:

    python tools/lua/mutate-xr-readiness.py

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
GATE = os.path.join(ROOT, 'tools', 'unattended', 'xr-readiness.ps1')
TEST = os.path.join(ROOT, 'tests', 'tooling', 'validate-xr-readiness.ps1')

MUTATIONS = [
    ('a stale flag is waved through because one expected flag was named',
     '        @($Present) |\n'
     '            Where-Object { $_ } |\n'
     '            Where-Object { $permitted -notcontains $_.Trim().ToLowerInvariant() })',
     '        @($Present) |\n'
     '            Where-Object { $_ } |\n'
     '            Where-Object { $Expected.Count -eq 0 -and'
     ' $permitted -notcontains $_.Trim().ToLowerInvariant() })'),

    ('the flag comparison becomes case sensitive, so a renamed flag slips past',
     '$permitted -notcontains $_.Trim().ToLowerInvariant()',
     '$permitted -cnotcontains $_.Trim()'),

    ('every flag is treated as persistent',
     '''    if ($stale.Count -gt 0) {''',
     '''    if ($false) {'''),

    ('SteamVR is waved through without checking that vrserver is alive',
     "        if ($SteamVrServerCount -lt 1) {\n"
     "            throw ('SteamVR is the active OpenXR runtime but vrserver is not ' +\n"
     "                   'running. Start SteamVR with the headset connected.')\n"
     "        }\n"
     "        return",
     "        return"),

    ('an unknown runtime is treated as Virtual Desktop',
     "        default { return 'unsupported' }",
     "        default { return 'VDXR' }"),

    ('the manifest is no longer required to exist',
     '    if (-not (Test-Path -LiteralPath $Runtime -PathType Leaf)) {\n'
     '        throw "The active OpenXR runtime manifest does not exist: $Runtime"\n'
     '    }',
     ''),

    ('the Streamer check is lost from the Virtual Desktop path',
     "    if ($StreamerCount -lt 1) { throw 'Virtual Desktop Streamer is not running.' }",
     ''),

    ('the Quest power check is lost from the Virtual Desktop path',
     "    $power = $PowerLines -join \"`n\"",
     "    $power = 'mWakefulness=Awake mHoldingDisplaySuspendBlocker=true'"),

    ('the SteamVR branch also demands a Streamer, which no Frame has',
     "    if ($runtimeProfile -eq 'SteamVR') {",
     "    if ($runtimeProfile -eq 'SteamVR' -and $StreamerCount -ge 1) {"),

    ('the runtime name is matched case-sensitively, which the loader is not',
     '    switch ((Split-Path $Runtime -Leaf).ToLowerInvariant()) {',
     '    switch -CaseSensitive ((Split-Path $Runtime -Leaf)) {'),

    ('an empty runtime reads as Virtual Desktop rather than as nothing',
     "    if (-not $Runtime) { return 'none' }",
     "    if (-not $Runtime) { return 'VDXR' }"),
]

LEGITIMATE = [
    ('the two profile branches are written the other way round', [
        ("    if ($runtimeProfile -eq 'SteamVR') {\n"
         "        if ($SteamVrServerCount -lt 1) {\n"
         "            throw ('SteamVR is the active OpenXR runtime but vrserver is not ' +\n"
         "                   'running. Start SteamVR with the headset connected.')\n"
         "        }\n"
         "        return\n"
         "    }\n"
         "    if ($StreamerCount -lt 1) { throw 'Virtual Desktop Streamer is not running.' }",
         "    if ($runtimeProfile -ne 'VDXR') {\n"
         "        if ($SteamVrServerCount -lt 1) {\n"
         "            throw ('SteamVR is the active OpenXR runtime but vrserver is not ' +\n"
         "                   'running. Start SteamVR with the headset connected.')\n"
         "        }\n"
         "        return\n"
         "    }\n"
         "    if ($StreamerCount -lt 1) { throw 'Virtual Desktop Streamer is not running.' }"),
     ]),
    ('the profile names are returned from a table instead of a switch', [
        ("    switch ((Split-Path $Runtime -Leaf).ToLowerInvariant()) {\n"
         "        'virtualdesktop-openxr.json' { return 'VDXR' }\n"
         "        'steamxr_win64.json' { return 'SteamVR' }\n"
         "        default { return 'unsupported' }\n"
         "    }",
         "    $known = @{ 'virtualdesktop-openxr.json' = 'VDXR'\n"
         "                'steamxr_win64.json' = 'SteamVR' }\n"
         "    $leaf = (Split-Path $Runtime -Leaf).ToLowerInvariant()\n"
         "    if ($known.ContainsKey($leaf)) { return $known[$leaf] }\n"
         "    return 'unsupported'"),
     ]),
]


def run():
    p = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                        '-File', TEST], capture_output=True, text=True, cwd=ROOT)
    return 'xr_readiness=pass' in p.stdout, p.stdout + p.stderr


def reason(out):
    for line in out.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith('+') and 'At ' not in stripped \
                and 'CategoryInfo' not in stripped and 'FullyQualified' not in stripped:
            return stripped[:150]
    return '?'


ok, out = run()
if not ok:
    sys.exit('CONTROL FAILED -- the harness proves nothing:\n' + out)
print('control (unmutated): PASS\n')

source = io.open(GATE, encoding='utf-8', newline='').read()
CRLF = '\r\n' in source
fit = (lambda t: t.replace('\n', '\r\n')) if CRLF else (lambda t: t)
backup = GATE + '.readinessbak'
shutil.copy2(GATE, backup)
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
            io.open(GATE, 'w', encoding='utf-8', newline='').write(mutated)
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
    shutil.move(backup, GATE)

ok, out = run()
if not ok:
    sys.exit('THE RESTORE DID NOT WORK -- the gate is mutated:\n' + out)
print('restored: PASS')
if failures:
    sys.exit('%d case(s) went the wrong way' % failures)
print('every mutation caught, every legitimate edit allowed, control passes')
