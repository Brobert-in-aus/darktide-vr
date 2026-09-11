#!/usr/bin/env python3
"""Summarize simulator consumer rates without treating repeated frames as gains."""
import argparse
import json
import math
import re
from pathlib import Path


def summarize_gpu_engine_activity(text):
    """Keep engine percentages separate; missing observations are never idle."""
    rows = [json.loads(line) for line in text.splitlines() if line.strip()]
    sampled = unavailable = 0
    processes = {}
    for row in rows:
        if row.get('schema') != 1 or row.get('status') not in ('sampled', 'unavailable'):
            raise ValueError('Unsupported GPU engine activity record')
        if row['status'] == 'unavailable':
            unavailable += 1
            continue
        sampled += 1
        names = {p['id']: p['name'] for p in row['processes']}
        for name in set(names.values()):
            process = processes.setdefault(name, {'present_samples': 0, 'busy_samples': 0,
                                                  'invalid_engine_samples': 0, 'engines': {}})
            process['present_samples'] += 1
        busy = set()
        for engine in row['engines']:
            name = engine['process_name']
            if names.get(engine['process_id']) != name:
                raise ValueError('GPU engine lacks matching process identity')
            process = processes[name]
            if not engine['valid']:
                if engine['percent'] is not None:
                    raise ValueError('Invalid engine sample carries a percentage')
                process['invalid_engine_samples'] += 1
                continue
            value = engine['percent']
            if not isinstance(value, (float, int)) or not math.isfinite(value) or value < 0:
                raise ValueError('Invalid GPU engine percentage')
            detail = process['engines'].setdefault(engine['instance'],
                {'type': engine['type'], 'samples': 0, 'busy_samples': 0, 'maximum_percent': 0.0})
            if detail['type'] != engine['type']:
                raise ValueError('GPU engine type changed within an instance')
            detail['samples'] += 1
            detail['maximum_percent'] = max(detail['maximum_percent'], value)
            if value > 0.1:
                detail['busy_samples'] += 1
                busy.add(name)
        for name in busy:
            processes[name]['busy_samples'] += 1
    for process in processes.values():
        process['activity'] = ('observed' if process['busy_samples'] else
            'unknown_incomplete_counter_coverage' if process['invalid_engine_samples'] or unavailable else
            'none_above_threshold_observed')
    return {'scope': 'whole run including startup; not the selected FPS window or board utilisation',
            'threshold_percent': 0.1, 'sampled_records': sampled, 'unavailable_records': unavailable,
            'status': 'sampled' if sampled else 'unavailable', 'processes': processes,
            'first_utc': rows[0]['utc'] if rows else None, 'last_utc': rows[-1]['utc'] if rows else None}


def summarize_selection(text, warmup_seconds):
    outcomes = ('reserved_original', 'unavailable', 'no_new', 'metadata_rejected',
                'original_missing', 'order_rejected', 'history_missing', 'selected')
    totals = dict.fromkeys(outcomes, 0)
    previous = None
    elapsed = seconds = 0.0
    source_count = generated_count = 0
    for line in text.splitlines():
        if not line.startswith('openxr.generated_selection '):
            continue
        fields = dict(part.split('=', 1) for part in line.split() if '=' in part)
        required = (*outcomes, 'gameplay_generation', 'interval_seconds',
                    'original_latest', 'generated_latest')
        if any(key not in fields for key in required):
            continue
        dt = float(fields['interval_seconds'])
        values = {key: int(fields[key]) for key in required if key != 'interval_seconds'}
        if not math.isfinite(dt) or dt <= 0 or any(value < 0 for value in values.values()):
            raise ValueError('Invalid selection record')
        current = (values['gameplay_generation'], values['original_latest'], values['generated_latest'])
        if not current[0]:
            previous = None
            elapsed = 0
            continue
        if previous is None or current[0] != previous[0] or any(current[i] < previous[i] for i in (1, 2)):
            previous = current
            elapsed = 0
            continue
        elapsed += dt
        if elapsed > warmup_seconds:
            for key in outcomes:
                totals[key] += values[key]
            seconds += dt
            source_count += current[1] - previous[1]
            generated_count += current[2] - previous[2]
        previous = current
    return {
        'sample_seconds': seconds,
        'outcomes': totals if seconds else None,
        'outcomes_per_second': {key: value / seconds for key, value in totals.items()} if seconds else None,
        'original_ring_publication_fps': source_count / seconds if seconds else None,
        'generated_ring_publication_fps': generated_count / seconds if seconds else None,
    }


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
    cadence_counts = dict.fromkeys(('cadence_distinct', 'cadence_repeats', 'repeat_runs_ended',
                                  'distinct_gap_samples', 'cadence_clock_breaks'), 0)
    cadence_seconds = 0.0
    repeat_peak = 0
    gap_max = 0.0
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
        cadence_keys = (*cadence_counts, 'repeat_run_peak', 'distinct_gap_max_ms')
        if any(key in fields for key in cadence_keys):
            if not all(key in fields for key in cadence_keys):
                raise ValueError('Incomplete delivery cadence record')
            counts = {key: int(fields[key]) for key in (*cadence_counts, 'repeat_run_peak')}
            gap = float(fields['distinct_gap_max_ms'])
            if any(value < 0 for value in counts.values()) or not math.isfinite(gap) or gap < 0:
                raise ValueError('Invalid delivery cadence record')
            if not counts['distinct_gap_samples'] and gap:
                raise ValueError('Delivery gap without observed interval')
            for key in cadence_counts:
                cadence_counts[key] += counts[key]
            repeat_peak = max(repeat_peak, counts['repeat_run_peak'])
            gap_max = max(gap_max, gap)
            cadence_seconds += dt
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
        'selection': summarize_selection(text, warmup_seconds),
        'delivery_cadence': {
            'scope': 'submitted images on runtime timeline; not photon latency or percentiles',
            'sample_seconds': cadence_seconds,
            'counts': cadence_counts if cadence_seconds else None,
            'longest_repeat_run': repeat_peak if cadence_seconds else None,
            'maximum_distinct_gap_ms': gap_max if cadence_counts['distinct_gap_samples'] else None,
        },
    }


def summarize_window_capture(text):
    """Report viewer desktop-capture counters; they are not frame-rate gains."""
    policy = re.findall(r'^openxr\.theatre_capture_policy=(\S+)$', text, re.M)
    if not policy:
        return {'status': 'not_requested'}

    def final(name):
        matches = re.findall(r'^openxr\.' + re.escape(name) + r'=(\d+)$', text, re.M)
        return int(matches[-1]) if matches else None
    window = re.findall(r'^openxr\.theatre_capture_window=(\S+)$', text, re.M)
    acquired = re.findall(r'^openxr\.capture_window=acquired frame=(\d+)$', text, re.M)
    active = re.findall(r'^openxr\.theatre_capture_active=([01]) attempts=(\d+)$', text, re.M)
    return {
        'status': 'requested',
        'policy': policy[-1],
        'window': window[-1] if window else None,
        'acquired_frame': int(acquired[0]) if acquired else None,
        'attempts_total': final('theatre_capture_attempts'),
        'failures_total': final('theatre_capture_failures'),
        'updates_total': final('theatre_capture_updates'),
        'active_transitions': len(active),
        'scope': 'viewer window-capture work; not game mirror rendering or VD encoding',
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
    result['desktop_window_capture'] = summarize_window_capture(
        (args.directory / 'consumer.log').read_text(encoding='utf-8-sig'))
    gpu_activity = args.directory / 'gpu-engine-activity.jsonl'
    result['gpu_engine_activity'] = (summarize_gpu_engine_activity(gpu_activity.read_text(encoding='utf-8-sig'))
                                     if gpu_activity.exists() else {'status': 'not_recorded'})
    restoration = args.directory / 'restoration.json'
    result['files_restored'] = (all(item['restored'] for item in json.loads(restoration.read_text(encoding='utf-8-sig')))
                                if restoration.exists() else None)
    (args.directory / 'summary.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
