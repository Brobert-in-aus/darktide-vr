import importlib.util
from pathlib import Path
import unittest
import tempfile
import json

spec = importlib.util.spec_from_file_location('gpu_stages', Path(__file__).with_name('summarize-synthetic-gpu-stages.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TimingEvidenceTests(unittest.TestCase):
    def test_launcher_transition_identity(self):
        for suffix in ('', ' during launcher transition'):
            with tempfile.TemporaryDirectory() as root:
                directory = Path(root)
                (directory / 'configuration.json').write_text(json.dumps({'gpu_profile': True}))
                (directory / 'launch.log').write_text(f'Authenticated Darktide process started{suffix}: PID 123.')
                result = module.summarize(directory)
                self.assertEqual(result['ngx_workloads'], [])
                self.assertIsNone(result['capture_and_pack']['mean_ms'])

    def test_rejects_invalid_measurements(self):
        for value in ('nan', 'inf', '-1'):
            with self.assertRaises(ValueError):
                module.records(f'TIMING samples=120 span={value}', 'TIMING ', ('span',))
        with self.assertRaises(ValueError):
            module.records('TIMING samples=120 span=1 span=2', 'TIMING ', ('span',))
        with self.assertRaises(ValueError):
            module.records('TIMING samples=0 span=1', 'TIMING ', ('span',))

    def test_partial_reports_do_not_consume_warmup(self):
        rows = module.records('TIMING samples=12 span=100\nTIMING samples=120 span=10\n'
                              'TIMING samples=120 span=2\nTIMING samples=120 span=4',
                              'TIMING ', ('span',))
        result = module.aggregate(rows, ('span',), 1)
        self.assertEqual(result['samples'], 240)
        self.assertEqual(result['mean_ms'], {'span': 3})

    def test_absent_measurement_is_unknown(self):
        self.assertIsNone(module.aggregate([], ('span',), 5)['mean_ms'])


if __name__ == '__main__':
    unittest.main()
