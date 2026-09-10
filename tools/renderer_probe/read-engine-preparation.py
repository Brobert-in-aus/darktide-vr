"""Read bounded engine preparation timings; worker wall sums are not frame costs."""
import argparse
import collections
import json
import math
import statistics
from pathlib import Path


def fields(line):
    return {key: int(value) for key, value in (part.split('=', 1) for part in line.split()[1:])}


def analyze(text):
    lines = text.splitlines()
    if not lines or not lines[0].startswith('PREPARATION_BEGIN '):
        raise ValueError('Missing preparation header')
    header = fields(lines[0])
    kind = header.get('kind')
    if (header.get('schema') != 1 or kind not in (0, 1) or header.get('pid', 0) <= 0 or
            header.get('frequency', 0) <= 0 or header.get('limit') != (4096, 512)[kind] or
            header.get('rva') != (0x796370, 0x398870)[kind]):
        raise ValueError('Unsupported preparation identity')
    if header.get('stride', 1) not in ((1, 64) if kind == 0 else (1,)):
        raise ValueError('Unsupported sampling stride')
    rows = [fields(line) for line in lines[1:] if line.startswith('PREPARATION sample=')]
    if (len(rows) != header['limit'] or
            lines[-1] != f"PREPARATION_COMPLETE kind={kind} samples={header['limit']}" or
            len(lines) != len(rows) + 2):
        raise ValueError('Incomplete preparation capture')
    required = {'sample', 'kind', 'thread', 'present', 'begin', 'end', 'context', 'payload', 'resource',
                'description_valid', 'before_valid', 'after_valid', 'links_before', 'links_after',
                *(f'word{i}' for i in range(6))}
    for index, row in enumerate(rows):
        if (row.keys() != required or row['sample'] != index or row['kind'] != kind or
                row['begin'] <= 0 or row['end'] < row['begin'] or row['thread'] <= 0 or
                any(value < 0 for value in row.values()) or
                any(row[key] not in (0, 1) for key in ('description_valid', 'before_valid', 'after_valid'))):
            raise ValueError('Invalid preparation record')
        if not row['description_valid'] and any(row[f'word{i}'] for i in range(6)):
            raise ValueError('Invalid descriptor must remain unknown')
        if ((not row['before_valid'] and row['links_before']) or
                (not row['after_valid'] and row['links_after'])):
            raise ValueError('Invalid link count must remain unknown')

    def durations(items):
        values = [(r['end'] - r['begin']) * 1000 / header['frequency'] for r in items]
        return {'count': len(values), 'mean_ms': statistics.mean(values),
                'median_ms': statistics.median(values),
                'p95_ms': sorted(values)[math.ceil(len(values) * .95) - 1], 'max_ms': max(values),
                'aggregate_worker_wall_ms': sum(values)} if values else None

    groups = collections.Counter((r['context'], r['present']) for r in rows if r['context'] and r['present'])
    types = sorted({r['word0'] & 0xffff for r in rows if r['description_valid']})
    links = [r for r in rows if r['before_valid'] and r['after_valid']]
    return {'header': header, 'records': len(rows), 'timing': durations(rows),
            'capture_span_seconds': (max(r['end'] for r in rows) - min(r['begin'] for r in rows)) / header['frequency'],
            'threads': dict(collections.Counter(r['thread'] for r in rows)),
            'contexts': len({r['context'] for r in rows if r['context']}),
            'present_range': [min(r['present'] for r in rows), max(r['present'] for r in rows)],
            'repeated_context_present_groups': sum(n > 1 for n in groups.values()),
            'maximum_calls_per_context_present': max(groups.values(), default=0),
            'valid_descriptions': sum(r['description_valid'] for r in rows),
            'dynamic_types': [{'type': t, 'timing': durations([r for r in rows if r['description_valid'] and r['word0'] & 0xffff == t])}
                              for t in types],
            'type10_format_indices': dict(collections.Counter(r['word3'] for r in rows
                if r['description_valid'] and r['word0'] & 0xffff == 10)),
            'links': {'valid': len(links), 'unchanged_count': sum(r['links_before'] == r['links_after'] for r in links),
                      'count_range': [min(r['links_before'] for r in links), max(r['links_before'] for r in links)] if links else None},
            'limitations': ['Instrumented function wall time, not isolated CPU execution or GPU time.',
                'Worker intervals overlap; aggregate duration is not a frame-time share.',
                'Each function has its own bounded sample window with partial boundary frames.',
                'Stride sampling is periodic per thread, not random sampling or complete call accounting.',
                'Repeated context/Present IDs do not establish duplicated work or eye identity.',
                'An unchanged link count does not mean unchanged linked transforms.']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.capture.resolve() == args.output.resolve() or (args.output.exists() and args.output.samefile(args.capture)):
        parser.error('Output must not overwrite capture')
    result = analyze(args.capture.read_text())
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
