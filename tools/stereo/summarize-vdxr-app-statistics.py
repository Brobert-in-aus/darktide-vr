"""Summarize reported runtime statistics without assuming units or discarding first samples."""
import argparse
from collections import Counter, defaultdict
import importlib.util
import json
from pathlib import Path
import statistics

path = Path(__file__).with_name('summarize-vdxr-trace.py')
spec = importlib.util.spec_from_file_location('vdxr_trace', path)
trace = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trace)
FIELDS = ('AppFrameCpuTime', 'AppRenderCpuTime', 'AppRenderGpuTime')


def stats(values):
    if not values:
        return {'samples': 0}
    ordered = sorted(values)
    return {'samples': len(values), 'minimum': ordered[0], 'maximum': ordered[-1],
            'median': statistics.median(values), 'mean': statistics.mean(values),
            'p95': ordered[(len(ordered) - 1) * 95 // 100]}


def summarize(source, process_id):
    groups = defaultdict(list)
    previous, epochs = {}, defaultdict(int)
    duplicates, excluded = Counter(), Counter()
    for element in trace.events(source):
        provider = element.find('e:System/e:Provider', trace.NS)
        execution = element.find('e:System/e:Execution', trace.NS)
        if provider is None or provider.get('Guid', '').lower() != trace.PROVIDER or \
                execution is None or execution.get('ProcessID') != str(process_id) or \
                element.findtext('e:RenderingInfo/e:Task', namespaces=trace.NS) != 'App_Statistics':
            continue
        data = {}
        repeated = False
        for item in element.findall('e:EventData/e:Data', trace.NS):
            if item.get('Name') in data:
                repeated = True
            data[item.get('Name')] = item.text
        if repeated:
            excluded['duplicate_field'] += 1
            continue
        try:
            frame = int(data['FrameId'])
            if frame < 0:
                raise ValueError()
        except (KeyError, TypeError, ValueError):
            excluded['invalid_frame_id'] += 1
            continue
        for field in FIELDS:
            if field not in data:
                continue
            try:
                value = int(data[field])
                if value < 0 or value > 2**64 - 1:
                    raise ValueError()
            except (TypeError, ValueError):
                excluded['invalid_reported_value'] += 1
                continue
            key = (execution.get('ThreadID', 'unknown'), field)
            if key in previous and frame < previous[key]:
                epochs[key] += 1
            group = (*key, epochs[key])
            if key in previous and frame == previous[key]:
                duplicates[group] += 1
            previous[key] = frame
            groups[group].append((frame, value))
    result = []
    for key, samples in sorted(groups.items()):
        values = [value for _, value in samples]
        result.append({'thread': key[0], 'field': key[1], 'epoch': key[2],
                       'first_frame': samples[0][0], 'last_frame': samples[-1][0],
                       'duplicate_frame_samples': duplicates[key],
                       'first_reported_value': values[0], 'all_reported': stats(values),
                       'after_first_reported': stats(values[1:])})
    return {'status': 'reported_statistics_only', 'process_id': process_id,
            'units': 'raw_reported_values_no_conversion', 'excluded_records': dict(excluded),
            'note': 'First samples and duplicate frame samples remain in all_reported. After-first is a separate view, not an automatic validity decision.',
            'groups': result}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xml', type=Path)
    parser.add_argument('--process-id', type=int, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.process_id <= 0:
        parser.error('process ID must be positive')
    if args.output.resolve() == args.xml.resolve() or \
            (args.output.exists() and args.output.samefile(args.xml)):
        parser.error('Output must not replace the input trace')
    result = summarize(args.xml, args.process_id)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
