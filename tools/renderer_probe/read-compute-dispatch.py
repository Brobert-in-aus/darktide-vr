"""Summarize bounded worker compute/binding wall durations, not GPU timings."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import statistics

HEX = {'context', 'resource', 'object', 'batch', 'handle', 'sort', 'flags',
       'caller_flags', 'root_before', 'root_after'}
BOOL = {'metadata_valid', 'flags_valid', 'root_before_valid', 'root_after_valid', 'alternate_queue'}
FIELDS = HEX | BOOL | {'sample', 'thread', 'present', 'begin', 'end', 'binding_ticks',
                      'binding_calls', 'binding_successes'}
DWORD = {'thread', 'object', 'batch', 'handle', 'flags', 'caller_flags', 'binding_calls', 'binding_successes'}
STAGE_FIELDS = {f'stage{i}_{field}' for i in range(4) for field in ('ticks', 'calls', 'successes')}


def fields(line):
    result = {}
    for token in line.split()[1:]:
        key, value = token.split('=', 1)
        if key in result:
            raise ValueError('Duplicate field')
        result[key] = value
    return result


def parse(text):
    lines = text.splitlines()
    if not lines or not lines[0].startswith('COMPUTE_BEGIN '):
        raise ValueError('Missing header')
    header = fields(lines[0])
    expected = {'limit': '4096', 'dispatch_rva': '7c8410',
                'binding_rva': '7e21b0', 'gpu_timing': '0'}
    if (any(header.get(k) != v for k, v in expected.items()) or header.get('schema') not in ('1', '2') or
            (header['schema'] == '2' and header.get('stages') not in ('0', '1'))):
        raise ValueError('Unsupported probe contract')
    frequency = int(header['frequency'])
    if frequency <= 0 or int(header['pid']) <= 0:
        raise ValueError('Invalid clock/process')
    if len(lines) != 4098 or lines[-1] != 'COMPUTE_COMPLETE samples=4096':
        raise ValueError('Incomplete capture')
    rows = []
    for index, line in enumerate(lines[1:-1]):
        if not line.startswith('COMPUTE '):
            raise ValueError('Unknown record')
        raw = fields(line)
        if set(raw) != FIELDS | (STAGE_FIELDS if header['schema'] == '2' else set()):
            raise ValueError('Missing or unknown fields')
        r = {k: int(v, 16 if k in HEX else 10) for k, v in raw.items()}
        if (r['sample'] != index or not r['thread'] or r['begin'] <= 0 or r['end'] < r['begin'] or
                r['binding_ticks'] > r['end'] - r['begin'] or r['binding_successes'] > r['binding_calls'] or
                any(r[k] not in (0, 1) for k in BOOL) or
                any(not 0 <= v < 2**(32 if k in DWORD else 64) for k, v in r.items())):
            raise ValueError('Invalid observation')
        if header['schema'] == '2':
            if (sum(r[f'stage{i}_ticks'] for i in range(4)) > r['binding_ticks'] or
                    any(r[f'stage{i}_successes'] > r[f'stage{i}_calls'] for i in range(4)) or
                    any(r[f'stage{i}_successes'] != 0 for i in range(1, 4)) or
                    (header['stages'] == '0' and any(r[k] for k in STAGE_FIELDS))):
                raise ValueError('Invalid nested stage observation')
        rows.append(r)
    return header, rows, frequency


def durations(values, frequency):
    ms = sorted(v * 1000 / frequency for v in values)
    if not ms:
        return None
    return {'count': len(ms), 'mean_ms': statistics.mean(ms), 'median_ms': statistics.median(ms),
            'p95_ms': ms[int((len(ms) - 1) * .95)], 'max_ms': ms[-1], 'aggregate_worker_wall_ms': sum(ms)}


def analyze(rows, frequency):
    groups = defaultdict(list)
    for r in rows:
        key = (hex(r['batch']) if r['metadata_valid'] else 'unknown',
               hex(r['flags']) if r['flags_valid'] else 'unknown', r['alternate_queue'])
        groups[key].append(r)
    return {
        'scope': 'inclusive instrumented command-recording wall time across workers; not CPU shares or GPU time',
        'records': len(rows), 'threads': dict(Counter(str(r['thread']) for r in rows)),
        'metadata_valid': sum(r['metadata_valid'] for r in rows),
        'outer': durations([r['end'] - r['begin'] for r in rows], frequency),
        'binding': durations([r['binding_ticks'] for r in rows], frequency),
        'binding_calls': sum(r['binding_calls'] for r in rows),
        'binding_successes': sum(r['binding_successes'] for r in rows),
        'stages': [{'index': i, 'rva': hex(rva),
                    'calls': sum(r.get(f'stage{i}_calls', 0) for r in rows),
                    'boolean_successes': sum(r.get(f'stage{i}_successes', 0) for r in rows) if i == 0 else None,
                    'per_timed_dispatch': durations([r[f'stage{i}_ticks'] for r in rows
                        if r.get(f'stage{i}_calls', 0)], frequency)}
                   for i, rva in enumerate((0x7dec60, 0x7db0a0, 0x7e0fe0, 0x7dc320))],
        'root_cache_comparable': sum(r['root_before_valid'] and r['root_after_valid'] for r in rows),
        'root_cache_changed': sum(r['root_before_valid'] and r['root_after_valid'] and
                                  r['root_before'] != r['root_after'] for r in rows),
        'batches': [{'batch': k[0], 'flags': k[1], 'alternate_queue': bool(k[2]),
                     'outer': durations([r['end'] - r['begin'] for r in v], frequency),
                     'binding': durations([r['binding_ticks'] for r in v], frequency)}
                    for k, v in sorted(groups.items())],
        'limitations': ['Partial boundary frames; Present counter is not worker view/frame attribution.',
                       'Nested probe overhead is included in outer time.',
                       'Worker intervals overlap; aggregate wall durations cannot be added to a frame time.',
                       'Binding success does not establish GPU execution or completion.'],
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.capture.resolve() == args.output.resolve() or (
            args.output.exists() and args.output.samefile(args.capture)):
        parser.error('Output must not overwrite the capture')
    header, rows, frequency = parse(args.capture.read_text())
    result = {'header': header, **analyze(rows, frequency)}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
