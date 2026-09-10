import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('particle', Path(__file__).resolve().parents[2]
                                            / 'tools/renderer_probe/read-particle-submissions.py')
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


class ParticleReaderTests(unittest.TestCase):
    def record(self, eye=0, sample=0):
        r = {k: 1 for k in reader.FIELDS if k != 'constants'}
        r.update(sample=sample, eye=eye, after_eye=eye, begin=10, end=20,
                 constants=bytes(192), batch=0x2765d852)
        return r

    def test_pair_and_detect_changed_inputs(self):
        left, right = self.record(), self.record(1, 1)
        result = reader.analyze([left, right], 1000)
        self.assertEqual(result['paired_same_update_groups'], 1)
        self.assertEqual(result['pairs_same_constants'], 1)
        right.update(constants=b'\x01' + bytes(191), buffer_b=20)
        pair = reader.analyze([left, right], 1000)['pairs'][0]
        self.assertFalse(pair['same_buffers'])
        self.assertEqual(pair['different_constant_bytes'], [0])

    def test_unstable_unknown_and_multiple_are_not_pairs(self):
        left, right = self.record(), self.record(1, 1)
        for patch in [{'after_pose': 2}, {'queued': 2}, {'valid': 0}, {'eye': -1}, {'update': 2}, {'resets': 2, 'after_resets': 2}]:
            with self.subTest(patch=patch):
                self.assertEqual(reader.analyze([left, {**right, **patch}], 1000)['paired_same_update_groups'], 0)
        result = reader.analyze([left, left, right], 1000)
        self.assertEqual(result['paired_same_update_groups'], 0)
        self.assertEqual(result['ambiguous_both_eye_groups'], 1)

    def capture(self):
        lines = ['PARTICLE_BEGIN schema=1 pid=42 frequency=1000 limit=1024 rva=564e80 eye_attribution_verified=0']
        for i in range(1024):
            r = self.record(i % 2, i)
            lines.append('PARTICLE ' + ' '.join(f'{k}={v.hex() if k == "constants" else format(v, "x") if k in reader.HEX_FIELDS else v}' for k, v in r.items()))
        return '\n'.join(lines + ['PARTICLE_COMPLETE samples=1024'])

    def test_complete_parse_and_reject_truncation_or_bad_fields(self):
        capture = self.capture()
        self.assertEqual(len(reader.parse(capture)[1]), 1024)
        for bad in [capture.rsplit('\n', 1)[0], capture.replace('sample=1 ', 'sample=0 ', 1),
                    capture.replace('valid=1 ', 'valid=2 ', 1), capture.replace('schema=1', 'schema=2'),
                    capture.replace('begin=10 ', 'begin=30 ', 1), capture.replace('thread=1 ', 'thread=1 thread=2 ', 1)]:
            with self.assertRaises(ValueError): reader.parse(bad)


if __name__ == '__main__': unittest.main()
