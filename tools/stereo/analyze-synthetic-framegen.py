#!/usr/bin/env python3
"""Summarize simulator consumer rates without treating repeated frames as gains."""
import argparse
import json
import math
import re
from pathlib import Path


def summarize(text, warmup_seconds=10.0):
    metrics = ('interval_submission_fps', 'interval_fresh_pair_fps',
               'interval_generated_pair_fps', 'interval_distinct_pair_fps',
               'interval_cached_pair_fps')
    totals = {key: 0.0 for key in metrics}
    seconds = 0.0
    windows = 0
    source_count = 0
    previous = None
    generation_elapsed = 0.0
    for line in text.splitlines():
        if not line.startswith('openxr.live.submission_fps='):
            continue
        fields = dict(part.split('=', 1) for part in line.split() if '=' in part)
        required = (*metrics, 'interval_seconds', 'gameplay_generation', 'shared_ready')
        if any(key not in fields for key in required):
            continue  # Legacy logs do not establish a weighted interval.
        values = {key: float(fields[key]) for key in required}
        if any(not math.isfinite(value) or value < 0 for value in values.values()):
            raise ValueError('Invalid consumer rate record')
        dt = values['interval_seconds']
        generation = int(fields['gameplay_generation'])
        ready = int(fields['shared_ready'])
        if dt <= 0 or generation <= 0 or ready <= 0:
            previous = None
            generation_elapsed = 0
            continue
        if previous is None or generation != previous[0] or ready < previous[1]:
            generation_elapsed = 0
            previous = (generation, ready)
            continue
        generation_elapsed += dt
        if generation_elapsed <= warmup_seconds:
            previous = (generation, ready)
            continue
        if abs(values['interval_distinct_pair_fps'] - values['interval_fresh_pair_fps'] -
               values['interval_generated_pair_fps']) > 0.02:
            raise ValueError('Distinct-frame accounting mismatch')
        for key in metrics:
            totals[key] += values[key] * dt
        source_count += ready - previous[1]
        previous = (generation, ready)
        seconds += dt
        windows += 1
    def final(name):
        matches = re.findall(r'^openxr\.' + re.escape(name) + r'=(\d+)$', text, re.M)
        return int(matches[-1]) if matches else None
    return {
        'sample_seconds': seconds, 'windows': windows, 'warmup_seconds': warmup_seconds,
        'rates': {key: total / seconds if seconds else None for key, total in totals.items()},
        'legacy_publication_fps': source_count / seconds if seconds else None,
        'fresh_pairs_total': final('fresh_shared_pairs'),
        'generated_submissions_total': final('generated_submitted_frames'),
        'pose_mismatches_total': final('pair_pose_mismatches'),
        'clean_exit': 'openxr.lifecycle=stopped' in text and 'result=pass' in text,
        'scope': 'simulator consumer; not physical headset latency or SSW',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--warmup-seconds', type=float, default=10)
    args = parser.parse_args()
    if not math.isfinite(args.warmup_seconds) or args.warmup_seconds < 0:
        parser.error('warmup must be finite and nonnegative')
    result = summarize((args.directory / 'consumer.log').read_text(encoding='utf-8-sig'), args.warmup_seconds)
    result['configuration'] = json.loads((args.directory / 'configuration.json').read_text(encoding='utf-8-sig'))
    restoration = args.directory / 'restoration.json'
    result['files_restored'] = (all(item['restored'] for item in json.loads(restoration.read_text(encoding='utf-8-sig')))
                                if restoration.exists() else None)
    (args.directory / 'summary.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
