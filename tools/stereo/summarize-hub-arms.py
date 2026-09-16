"""One row per instrumented Hub run: GPU per pair, loop rate, pair period, fresh pairs, errors.

Usage: summarize-hub-arms.py [--root DIR] <run-name> [<run-name> ...]
Reads <root>/<run-name>/{console.log,viewer.log,summary.json} written by
run-darktide-session.ps1 with the frame-profile, cpu-render-timing and
performance-profile request files (docs/LUA-FRAME-PROFILE-2026-09-16.md,
"Experiments for the user"). GPU per pair is the mean of the last five
DARKTIDEVR_GPU_PERF interval_sum_avg_ms values (steady state); the loop rate is
frames per report over the reports after the first two; the pair period is the
viewer's last source_period_ms. Whole-run pair counts move with time spent in
the Hub and are shown for completeness only. No test: it reads logs.
"""
import json
import os
import re
import statistics
import sys

ROOT = 'artifacts/unattended/profile-20260916/'
if len(sys.argv) > 2 and sys.argv[1] == '--root':
    ROOT = sys.argv[2].rstrip('/' + os.sep) + '/'
    del sys.argv[1:3]


def row(name):
    console = open(ROOT + name + '/console.log', 'rb').read().decode('utf-8', 'replace')
    try:
        viewer = open(ROOT + name + '/viewer.log', 'rb').read().decode('utf-8', 'replace')
    except FileNotFoundError:
        viewer = ''
    frames = [int(m) for m in re.findall(r'DARKTIDEVR_FRAME_PROFILE report=\d+ frames=(\d+)', console)]
    if len(frames) > 4:
        loop = statistics.mean(frames[2:]) / 5
    else:
        loop = statistics.mean(frames) / 5 if frames else 0
    sums = [float(m) for m in re.findall(r'interval_sum_avg_ms=([\d.]+)', console)]
    gpu = statistics.mean(sums[-5:]) if sums else 0
    period = re.findall(r'source_period_ms=([\d.]+)', viewer)
    period = float(period[-1]) if period else 0
    pairs = re.findall(r'fresh_shared_pairs=(\d+)', viewer)
    pairs = int(pairs[-1]) if pairs else 0
    submit = re.findall(r'openxr\.live\.submission_fps=([\d.]+)', viewer)
    submit = float(submit[-1]) if submit else 0
    errors = len(re.findall(r'\[MOD\]\[darktidevr\]\[ERROR\]', console))
    try:
        summary = json.loads(open(ROOT + name + '/summary.json', 'rb').read().decode('utf-8-sig'))
        state = 'ok' if summary.get('scene_reached') and not summary.get('crash') else 'BAD'
    except Exception:
        state = '?'
    return (name, state, gpu, loop, period, pairs, submit, errors)


print('%-28s %-4s %9s %8s %10s %7s %8s %6s' % (
    'run', 'st', 'gpu/pair', 'loop Hz', 'period ms', 'pairs', 'submit/s', 'errors'))
for run_name in sys.argv[1:]:
    n, st, gpu, loop, period, pairs, submit, errors = row(run_name)
    print('%-28s %-4s %9.1f %8.1f %10.1f %7d %8.1f %6d' % (
        n, st, gpu, loop, period, pairs, submit, errors))
