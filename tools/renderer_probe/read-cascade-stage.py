"""Read bounded cascade CPU observations; matching fields do not establish reusable shadows."""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import statistics
import struct

ARRAYS = {'arg': 6, 'settings': 12, 'light': 3, 'view': 6}


def fields(line):
    result = {}
    for token in line.split()[1:]:
        key, value = token.split('=', 1)
        if key in result:
            raise ValueError('Duplicate field')
        result[key] = int(value)
    return result


def summarize(text):
    lines = text.splitlines()
    if not lines or not lines[0].startswith('CASCADE_BEGIN '):
        raise ValueError('Missing cascade header')
    header = fields(lines[0])
    if (header.keys() != {'schema', 'pid', 'rva', 'frequency', 'limit'} or
            header['schema'] != 1 or header['rva'] != 0x419910 or header['limit'] != 256 or
            not 0 < header['pid'] <= 0xffffffff or not 0 < header['frequency'] <= 0x7fffffffffffffff):
        raise ValueError('Unsupported cascade header')
    if len(lines) != 258 or lines[-1] != 'CASCADE_COMPLETE samples=256':
        raise ValueError('Incomplete cascade capture')
    required = {'sample', 'thread', 'present', 'generation', 'begin', 'end',
                'settings_valid', 'light_valid', 'view_valid',
                *(f'{prefix}{i}' for prefix, count in ARRAYS.items() for i in range(count))}
    rows = []
    for index, line in enumerate(lines[1:-1]):
        if not line.startswith('CASCADE sample='):
            raise ValueError('Unknown cascade record')
        row = fields(line)
        if (row.keys() != required or row['sample'] != index or
                any(not 0 <= value <= 0xffffffffffffffff for value in row.values()) or
                not 0 < row['thread'] <= 0xffffffff or not row['present'] or not row['generation'] or
                not 0 < row['begin'] <= row['end'] <= 0x7fffffffffffffff):
            raise ValueError('Invalid cascade record')
        for prefix in ('settings', 'light', 'view'):
            values = [row[f'{prefix}{i}'] for i in range(ARRAYS[prefix])]
            if (row[prefix + '_valid'] not in (0, 1) or any(v > 0xffffffff for v in values) or
                    (not row[prefix + '_valid'] and any(values))):
                raise ValueError('Invalid or contradictory sampled fields')
        rows.append(row)
    durations = [(r['end'] - r['begin']) * 1000 / header['frequency'] for r in rows]
    by_present = collections.Counter((r['generation'], r['present']) for r in rows)
    valid = [r for r in rows if all(r[p + '_valid'] for p in ('settings', 'light', 'view'))]
    matching = collections.Counter((r['generation'], r['present'],
        *(r[f'{p}{i}'] for p in ('settings', 'light', 'view') for i in range(ARRAYS[p]))) for r in valid)
    norms = []
    for r in rows:
        if r['light_valid']:
            vector = struct.unpack('<fff', struct.pack('<III', *(r[f'light{i}'] for i in range(3))))
            if all(math.isfinite(v) for v in vector):
                norms.append(math.sqrt(sum(v*v for v in vector)))
    return {'header': header, 'records': len(rows),
            'scope': 'CPU wall time including nested work/waits; sampled fields are not a complete reuse key or eye identity',
            'timing_ms': {'mean': statistics.mean(durations), 'median': statistics.median(durations),
                          'p95': sorted(durations)[math.ceil(len(durations)*.95)-1], 'maximum': max(durations),
                          'aggregate_overlapping_calls': sum(durations)},
            'capture_span_seconds': (max(r['end'] for r in rows) - min(r['begin'] for r in rows))/header['frequency'],
            'threads': dict(collections.Counter(r['thread'] for r in rows)),
            'generations': sorted({r['generation'] for r in rows}),
            'present_range': [min(r['present'] for r in rows), max(r['present'] for r in rows)],
            'calls_per_present_distribution': dict(collections.Counter(by_present.values())),
            'valid_snapshots': {p: sum(r[p + '_valid'] for r in rows) for p in ('settings', 'light', 'view')},
            'matching_selected_input_groups': sum(count > 1 for count in matching.values()),
            'maximum_calls_with_matching_selected_inputs': max(matching.values(), default=0),
            'finite_light_vectors': len(norms), 'light_norm_range': [min(norms), max(norms)] if norms else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    args = parser.parse_args()
    data = args.log.read_bytes()
    result = summarize(data.decode('utf-8-sig'))
    result['source_sha256'] = hashlib.sha256(data).hexdigest()
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
