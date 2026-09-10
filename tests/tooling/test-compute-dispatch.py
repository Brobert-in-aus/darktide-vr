import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('compute', Path(__file__).resolve().parents[2]
                                            / 'tools/renderer_probe/read-compute-dispatch.py')
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


class ComputeReaderTests(unittest.TestCase):
    def record(self, index=0):
        r = {k: 1 for k in reader.FIELDS}
        r.update(sample=index, begin=100, end=120, binding_ticks=10, batch=0x2765d852,
                 root_before=100, root_after=100)
        return r

    def test_nested_statistics_and_unknown_metadata(self):
        a, b = self.record(), self.record(1)
        b.update(metadata_valid=0, root_after=200, root_before_valid=0, binding_successes=0)
        result = reader.analyze([a, b], 1000)
        self.assertEqual(result['outer']['aggregate_worker_wall_ms'], 40)
        self.assertEqual(result['binding']['aggregate_worker_wall_ms'], 20)
        self.assertEqual(result['root_cache_comparable'], 1)
        self.assertEqual(result['root_cache_changed'], 0)
        self.assertEqual(result['metadata_valid'], 1)
        self.assertEqual(result['binding_successes'], 1)
        self.assertEqual({x['batch'] for x in result['batches']}, {'0x2765d852', 'unknown'})

    def capture(self):
        lines = ['COMPUTE_BEGIN schema=1 pid=42 frequency=1000 limit=4096 dispatch_rva=7c8410 binding_rva=7e21b0 gpu_timing=0']
        for i in range(4096):
            lines.append('COMPUTE ' + ' '.join(f'{k}={format(v, "x") if k in reader.HEX else v}'
                                               for k, v in self.record(i).items()))
        return '\n'.join(lines + ['COMPUTE_COMPLETE samples=4096'])

    def test_complete_contract_and_invalid_timings(self):
        capture = self.capture()
        self.assertEqual(len(reader.parse(capture)[1]), 4096)
        for bad in [capture.rsplit('\n', 1)[0], capture.replace('binding_ticks=10', 'binding_ticks=21', 1),
                    capture.replace('binding_successes=1', 'binding_successes=2', 1),
                    capture.replace('sample=1', 'sample=0', 1),
                    capture.replace('gpu_timing=0', 'gpu_timing=1'),
                    capture.replace('thread=1', 'thread=1 thread=2', 1),
                    capture.replace('flags_valid=1', 'flags_valid=2', 1)]:
            with self.assertRaises(ValueError): reader.parse(bad)

    def test_optional_stage_schema(self):
        lines = self.capture().replace('schema=1', 'schema=2').splitlines()
        lines[0] += ' stages=1'
        extra = ' '.join(f'stage{i}_{field}={1 if field == "calls" or (i == 0 and field == "successes") else 2 if field == "ticks" else 0}'
                         for i in range(4) for field in ('ticks', 'calls', 'successes'))
        for i in range(1, len(lines) - 1): lines[i] += ' ' + extra
        capture = '\n'.join(lines)
        _, rows, frequency = reader.parse(capture)
        result = reader.analyze(rows, frequency)
        self.assertEqual(result['stages'][0]['calls'], 4096)
        self.assertEqual(result['stages'][1]['boolean_successes'], None)
        for bad in [capture.replace('stages=1', 'stages=0'),
                    capture.replace('stage0_ticks=2', 'stage0_ticks=9', 1),
                    capture.replace('stage1_successes=0', 'stage1_successes=1', 1)]:
            with self.assertRaises(ValueError): reader.parse(bad)


if __name__ == '__main__': unittest.main()
