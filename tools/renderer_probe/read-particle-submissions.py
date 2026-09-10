"""Read bounded particle helper observations; no GPU execution or FPS claim."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import statistics

HEX_FIELDS = {'object', 'resource', 'object_tag', 'batch', 'shader', 'transform',
              'sort', 'buffer_a', 'buffer_b', 'handle_a', 'handle_b'}
FIELDS = HEX_FIELDS | {'sample', 'thread', 'begin', 'end', 'valid', 'update',
    'buffer_serial', 'needed', 'present', 'eye', 'pose', 'queued', 'arms', 'resets',
    'after_present', 'after_eye', 'after_pose', 'after_queued', 'after_arms',
    'after_resets', 'constants'}
DWORD_FIELDS = {'thread', 'object_tag', 'batch', 'update', 'buffer_serial', 'handle_a', 'handle_b'}


def fields(line):
    result = {}
    for word in line.split()[1:]:
        key, value = word.split('=', 1)
        if key in result:
            raise ValueError('Duplicate field')
        result[key] = value
    return result


def parse(text):
    lines = text.splitlines()
    if not lines or not lines[0].startswith('PARTICLE_BEGIN '):
        raise ValueError('Missing observer header')
    header = fields(lines[0])
    if (header.get('schema') != '1' or header.get('rva') != '564e80' or
            header.get('eye_attribution_verified') != '0' or header.get('limit') != '1024'):
        raise ValueError('Unsupported observer contract')
    frequency = int(header['frequency'])
    if frequency <= 0 or int(header['pid']) <= 0:
        raise ValueError('Invalid clock or process')
    if lines[-1] != 'PARTICLE_COMPLETE samples=1024' or len(lines) != 1026:
        raise ValueError('Incomplete capture')
    records = []
    for index, line in enumerate(lines[1:-1]):
        if not line.startswith('PARTICLE '):
            raise ValueError('Unknown record')
        raw = fields(line)
        if set(raw) != FIELDS:
            raise ValueError('Missing or unknown record fields')
        record = {k: int(v, 16 if k in HEX_FIELDS else 10)
                  for k, v in raw.items() if k != 'constants'}
        if len(raw['constants']) != 384:
            raise ValueError('Wrong constant byte count')
        record['constants'] = bytes.fromhex(raw['constants'])
        if (record['sample'] != index or record['valid'] not in (0, 1) or
                record['eye'] not in (-1, 0, 1) or record['after_eye'] not in (-1, 0, 1) or
                record['begin'] <= 0 or record['end'] < record['begin'] or record['thread'] == 0 or
                record['needed'] > 255 or len(record['constants']) != 192 or
                any(not 0 <= v < 2**(32 if k in DWORD_FIELDS else 64)
                    for k, v in record.items() if k not in ('eye', 'after_eye', 'constants'))):
            raise ValueError('Invalid record values')
        records.append(record)
    return header, records, frequency


def stable_context(record):
    return (record['queued'] == 1 and record['eye'] in (0, 1) and record['pose'] > 0 and
            all(record[k] == record['after_' + k]
                for k in ('present', 'eye', 'pose', 'queued', 'arms', 'resets')))


def analyze(records, frequency):
    groups = defaultdict(lambda: defaultdict(list))
    batches = defaultdict(list)
    object_updates = Counter()
    valid = stable = 0
    for r in records:
        if not r['valid']:
            continue
        valid += 1
        object_updates[tuple(r[k] for k in ('object', 'resource', 'object_tag', 'batch',
                                           'update', 'buffer_serial'))] += 1
        batches[r['batch']].append((r['end'] - r['begin']) * 1000 / frequency)
        if not stable_context(r):
            continue
        stable += 1
        # Include pose and reset epoch to avoid joining separate captures or
        # object-address reuse across lifecycle changes. Require one per eye.
        key = tuple(r[k] for k in ('object', 'resource', 'object_tag', 'batch',
                                  'update', 'buffer_serial', 'pose', 'resets'))
        groups[key][r['eye']].append(r)
    pairs = []
    ambiguous = 0
    for key, eyes in groups.items():
        if set(eyes) != {0, 1}:
            continue
        if len(eyes[0]) != 1 or len(eyes[1]) != 1:
            ambiguous += 1
            continue
        left, right = eyes[0][0], eyes[1][0]
        differing = [i for i, (a, b) in enumerate(zip(left['constants'], right['constants'])) if a != b]
        pairs.append({'object': hex(key[0]), 'batch': hex(key[3]), 'update': key[4],
                      'pose': key[6], 'samples': [left['sample'], right['sample']],
                      'same_shader': left['shader'] == right['shader'],
                      'same_buffers': all(left[k] == right[k] for k in
                          ('buffer_a', 'buffer_b', 'handle_a', 'handle_b')),
                      'same_constants': not differing, 'different_constant_bytes': differing,
                      'same_present': left['present'] == right['present']})
    return {
        'scope': 'CPU command-builder submissions; application eye context, not proven GPU attribution',
        'records': len(records), 'valid_snapshots': valid, 'stable_eye_records': stable,
        'threads': dict(Counter(str(r['thread']) for r in records)),
        'repeated_object_update_groups_by_batch': dict(Counter(hex(k[3])
            for k, count in object_updates.items() if count > 1)),
        'paired_same_update_groups': len(pairs), 'ambiguous_both_eye_groups': ambiguous,
        'pairs_same_buffers': sum(p['same_buffers'] for p in pairs),
        'pairs_same_constants': sum(p['same_constants'] for p in pairs),
        'paired_batches': dict(Counter(p['batch'] for p in pairs)),
        'batch_original_call_ms': {hex(k): {'calls': len(v), 'mean': statistics.mean(v), 'max': max(v)}
                                   for k, v in sorted(batches.items())},
        'pairs': pairs,
        'limitations': ['Bounded interval can start or end within a frame.',
                       'Worker preparation can overlap Present/eye-tag changes; pending tags do not identify the view.',
                       'Object counters are observations, not independently verified simulation-frame identifiers.',
                       'Same buffers and bytes do not establish safe reuse or GPU completion.',
                       'Durations include nested command preparation; observation perturbs the workload.'],
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.capture.resolve() == args.output.resolve() or (
            args.output.exists() and args.output.samefile(args.capture)):
        parser.error('Output must not overwrite the capture')
    header, records, frequency = parse(args.capture.read_text())
    result = {'header': header, **analyze(records, frequency)}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('pairs', 'header')}, indent=2))
