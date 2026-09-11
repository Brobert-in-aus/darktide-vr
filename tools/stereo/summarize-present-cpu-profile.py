#!/usr/bin/env python3
"""Summarise presentation-thread CPU and GPU per-eye profiles for one run.

Reads the native `darktidevr-present-cpu-<pid>.log` (PRESENT_CPU records: wall
and CPU time per presentation frame and inside the hook) and the Lua
`DARKTIDEVR_GPU_PERF` reports (command-list GPU spans per eye). Means are
aggregate windows; a single sample is not precise. This attributes CPU
execution and GPU spans, not elapsed waits, display latency or encoder cost.
"""
import argparse
import json
import statistics
from pathlib import Path


def summarize_present(text):
    rows = []
    for line in text.splitlines():
        if not line.startswith('PRESENT_CPU sample='):
            continue
        fields = dict(part.split('=', 1) for part in line.split() if '=' in part)
        rows.append({key: float(value) for key, value in fields.items() if key.endswith('_ms')})
    if not rows:
        return {'status': 'no_samples'}

    def mean(key):
        return statistics.mean(row[key] for row in rows)
    frame_wall, frame_cpu = mean('frame_wall_ms'), mean('frame_cpu_ms')
    return {
        'status': 'sampled', 'samples': len(rows),
        'frame_wall_ms': round(frame_wall, 3), 'frame_cpu_ms': round(frame_cpu, 3),
        'present_wall_ms': round(mean('present_wall_ms'), 3),
        'present_cpu_ms': round(mean('present_cpu_ms'), 3),
        'cpu_share_of_frame': round(frame_cpu / frame_wall, 3) if frame_wall else None,
        'implied_fps': round(1000.0 / frame_wall, 2) if frame_wall else None,
        'scope': 'presentation thread only; CPU share near 1 means busy or spinning, not waiting',
    }


def summarize_gpu(text, warmup_reports=5):
    left, right, total = [], [], []
    for line in text.splitlines():
        if 'DARKTIDEVR_GPU_PERF ' not in line:
            continue
        fields = dict(part.split('=', 1) for part in line.split() if '=' in part)
        try:
            left.append(float(fields['left_avg_ms']))
            right.append(float(fields['right_avg_ms']))
            total.append(float(fields['interval_sum_avg_ms']))
        except (KeyError, ValueError):
            continue
    if not left:
        return {'status': 'no_reports'}
    if len(left) > warmup_reports:
        left, right, total = left[warmup_reports:], right[warmup_reports:], total[warmup_reports:]
    return {
        'status': 'sampled', 'reports': len(left), 'warmup_reports_dropped': min(warmup_reports, len(left)),
        'left_avg_ms': round(statistics.mean(left), 3), 'right_avg_ms': round(statistics.mean(right), 3),
        'interval_sum_avg_ms': round(statistics.mean(total), 3),
        'scope': 'command-list GPU spans per eye; not asynchronous NVIDIA work or encoder time',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, help='run directory holding the copied profile logs')
    args = parser.parse_args()
    result = {'present_cpu': {'status': 'missing'}, 'gpu_eye': {'status': 'missing'}}
    cpu_logs = sorted(args.directory.glob('darktidevr-present-cpu-*.log'))
    if cpu_logs:
        result['present_cpu'] = summarize_present(cpu_logs[-1].read_text(encoding='utf-8', errors='replace'))
        result['present_cpu']['source'] = cpu_logs[-1].name
    gpu_log = args.directory / 'gpu-profile.log'
    if gpu_log.exists():
        result['gpu_eye'] = summarize_gpu(gpu_log.read_text(encoding='utf-8-sig', errors='replace'))
    (args.directory / 'profile-summary.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
