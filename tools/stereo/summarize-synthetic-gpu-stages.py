"""Summarize instrumented GPU command-list spans, not total FG cost or latency."""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import re


def records(text, prefix, metrics):
    result = []
    for line in text.splitlines():
        if not line.startswith(prefix):
            continue
        fields = {}
        for word in line.split():
            if '=' in word:
                key, value = word.split('=', 1)
                if key in fields:
                    raise ValueError('Duplicate timing field')
                fields[key] = value
        count = int(fields['samples'])
        if not 1 <= count <= 120:
            raise ValueError('Invalid GPU sample count')
        row = {'samples': count, 'fields': fields}
        for key in metrics:
            value = float(fields[key])
            if not math.isfinite(value) or value < 0:
                raise ValueError('Invalid GPU duration')
            row[key] = value
        result.append(row)
    return result


def aggregate(rows, metrics, skip):
    # Each full report covers 120 completed evaluations, not a wall-clock second.
    full = [row for row in rows if row['samples'] == 120]
    selected = full[skip:]
    count = sum(row['samples'] for row in selected)
    return {'full_reports': len(full), 'discarded_initial_reports': min(skip, len(full)),
            'selected_reports': len(selected), 'samples': count,
            'mean_ms': {key: sum(row[key] * row['samples'] for row in selected) / count
                        for key in metrics} if count else None}


def summarize(directory, skip=5):
    if skip < 0:
        raise ValueError('Negative warmup report count')
    configuration = json.loads((directory / 'configuration.json').read_text(encoding='utf-8-sig'))
    if configuration.get('gpu_profile') is not True:
        raise ValueError('Run did not explicitly request GPU profiling')
    launch = (directory / 'launch.log').read_text(encoding='utf-8-sig')
    match = re.search(r'Authenticated Darktide process started(?: during launcher transition)?: PID (\d+)\.', launch)
    if not match:
        raise ValueError('Missing run-owned process identity')
    ngx_path = directory / f'darktidevr-ngx-gpu-timing-{match[1]}.log'
    pack_path = directory / 'darktidevr-streamline-probe.tsv'
    ngx_metrics = ('evaluate_gpu_ms', 'post_evaluate_gpu_ms')
    pack_metrics = ('capture_left_gpu_ms', 'capture_right_gpu_ms', 'pack_publish_gpu_ms')
    groups = collections.defaultdict(list)
    if ngx_path.exists():
        for row in records(ngx_path.read_text(encoding='utf-8-sig'), 'NGX_GPU_TIMING ', ngx_metrics):
            fields = row['fields']
            eye, lifetime = int(fields['eye']), int(fields['feature_lifetime'])
            width, height = int(fields['eye_width']), int(fields['eye_height'])
            if eye not in (0, 1) or lifetime <= 0 or width <= 0 or height <= 0:
                raise ValueError('Invalid GPU workload identity')
            if (width, height) != (configuration['eye_width'], configuration['eye_height']):
                continue
            groups[(eye, lifetime, width, height)].append(row)
    pack_rows = records(pack_path.read_text(encoding='utf-8-sig'),
                        'STEREO_CONTINUOUS\tphase=timing\t', pack_metrics) if pack_path.exists() else []
    paths = [directory / 'configuration.json', directory / 'launch.log', ngx_path, pack_path]
    return {
        'scope': 'instrumented command-list GPU spans; not total asynchronous FG cost or display latency',
        'selection': 'discard first full reports per workload; 120 samples/report, not UTC-aligned warmup',
        'ngx_workloads': [dict(eye=key[0], feature_lifetime=key[1], width=key[2], height=key[3],
                               **aggregate(rows, ngx_metrics, skip)) for key, rows in sorted(groups.items())],
        'capture_and_pack': aggregate(pack_rows, pack_metrics, skip),
        'source_sha256': {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in paths if path.exists()},
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--skip-reports', type=int, default=5)
    args = parser.parse_args()
    result = summarize(args.directory, args.skip_reports)
    (args.directory / 'gpu-stage-summary.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
