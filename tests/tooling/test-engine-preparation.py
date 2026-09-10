import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('preparation', Path(__file__).parents[2] / 'tools/renderer_probe/read-engine-preparation.py')
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


def capture(kind):
    limit = (4096, 512)[kind]
    lines = [f'PREPARATION_BEGIN schema=1 pid=123 kind={kind} rva={(0x796370, 0x398870)[kind]} frequency=10000000 limit={limit}']
    for index in range(limit):
        row = dict(sample=index, kind=kind, thread=7, present=index // 4 + 1,
                   begin=10000 + index * 100, end=10030 + index * 100,
                   context=100000, payload=0, resource=0, description_valid=0,
                   before_valid=0, after_valid=0, links_before=0, links_after=0,
                   **{f'word{i}': 0 for i in range(6)})
        if kind:
            row.update(before_valid=1, after_valid=1, links_before=9, links_after=9)
        else:
            row.update(description_valid=1, word0=10, word1=100, word2=1024, word3=7)
        lines.append('PREPARATION ' + ' '.join(f'{key}={value}' for key, value in row.items()))
    lines.append(f'PREPARATION_COMPLETE kind={kind} samples={limit}')
    return '\n'.join(lines) + '\n'


class PreparationReaderTests(unittest.TestCase):
    def test_both_valid_capture_kinds(self):
        dynamic = reader.analyze(capture(0))
        self.assertEqual(dynamic['valid_descriptions'], 4096)
        self.assertEqual(dynamic['type10_format_indices'], {7: 4096})
        self.assertAlmostEqual(dynamic['timing']['mean_ms'], .003)
        links = reader.analyze(capture(1))
        self.assertEqual(links['links']['unchanged_count'], 512)
        self.assertEqual(links['repeated_context_present_groups'], 128)

    def test_reject_incomplete_and_invalid_time(self):
        valid = capture(1)
        with self.assertRaises(ValueError):
            reader.analyze('\n'.join(valid.splitlines()[:-1]))
        with self.assertRaises(ValueError):
            reader.analyze(valid.replace('end=10030', 'end=9999', 1))
        with self.assertRaises(ValueError):
            reader.analyze(valid.replace('sample=1 ', 'sample=0 ', 1))

    def test_invalid_reads_remain_unknown(self):
        invalid = capture(0).replace('description_valid=1', 'description_valid=0', 1)
        with self.assertRaises(ValueError):
            reader.analyze(invalid)
        invalid = capture(1).replace('before_valid=1', 'before_valid=0', 1)
        with self.assertRaises(ValueError):
            reader.analyze(invalid)


if __name__ == '__main__':
    unittest.main()
