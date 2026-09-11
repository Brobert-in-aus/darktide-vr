import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('cascade_reader', ROOT / 'tools/renderer_probe/read-cascade-stage.py')
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
native = None
if '--native' in sys.argv:
    at = sys.argv.index('--native')
    native = Path(sys.argv[at + 1])
    del sys.argv[at:at + 2]


def fixture():
    lines = ['CASCADE_BEGIN schema=1 pid=10 rva=4299024 frequency=1000000 limit=256']
    for i in range(256):
        row = {'sample': i, 'thread': 2, 'present': 10 + i//2, 'generation': 9,
               'begin': 1000 + i*50, 'end': 1005 + i*50,
               'settings_valid': 1, 'light_valid': 1, 'view_valid': 1}
        for prefix, count in reader.ARRAYS.items():
            row.update({f'{prefix}{j}': 0 for j in range(count)})
        row['light2'] = 0x3f800000
        lines.append('CASCADE ' + ' '.join(f'{k}={v}' for k, v in row.items()))
    lines.append('CASCADE_COMPLETE samples=256')
    return '\n'.join(lines) + '\n'


class CascadeReader(unittest.TestCase):
    def test_timing_and_selected_input_groups(self):
        result = reader.summarize(fixture())
        self.assertEqual(result['records'], 256)
        self.assertAlmostEqual(result['timing_ms']['mean'], .005)
        self.assertEqual(result['calls_per_present_distribution'], {2: 128})
        self.assertEqual(result['matching_selected_input_groups'], 128)
        self.assertEqual(result['light_norm_range'], [1, 1])

    def test_incomplete_and_contradictory_inputs(self):
        text = fixture()
        bad = [text.replace('CASCADE_COMPLETE samples=256', ''),
               text.replace('schema=1', 'schema=2'), text.replace('frequency=1000000', 'frequency=0'),
               text.replace('sample=0 ', 'sample=1 ', 1), text.replace('begin=1000', 'begin=-1', 1),
               text.replace('end=1005', 'end=999', 1), text.replace('light_valid=1', 'light_valid=0', 1),
               text.replace('view0=0', 'view0=4294967296', 1),
               text.replace('thread=2', 'thread=2 thread=2', 1), text.replace('generation=9', 'generation=0', 1)]
        for capture in bad:
            with self.subTest(capture=capture[:100]), self.assertRaises(ValueError):
                reader.summarize(capture)

    def test_missing_and_nonfinite_light_not_matches(self):
        text = fixture().replace('light_valid=1', 'light_valid=0', 1).replace('light2=1065353216', 'light2=0', 1)
        result = reader.summarize(text)
        self.assertEqual(result['valid_snapshots']['light'], 255)
        self.assertEqual(result['matching_selected_input_groups'], 127)
        result = reader.summarize(fixture().replace('light2=1065353216', 'light2=2143289344', 1))
        self.assertEqual(result['finite_light_vectors'], 255)

    @unittest.skipUnless(native, 'native formatter not supplied')
    def test_actual_native_formatter(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'cascade.log'
            subprocess.run([str(native), str(log)], check=True, capture_output=True, text=True)
            result = reader.summarize(log.read_text())
        self.assertEqual(result['records'], 256)
        self.assertEqual(result['valid_snapshots'], {'settings': 256, 'light': 255, 'view': 256})


if __name__ == '__main__':
    unittest.main()
