import importlib.util
from pathlib import Path
import sys
import unittest

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'build/dependencies/engine-inspection'))
spec = importlib.util.spec_from_file_location('residency', root / 'tools/renderer_probe/read-thread-residency.py')
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)

class BundleReaderTests(unittest.TestCase):
    def row(self):
        result = {'bundle_attempted': '4'}
        for i, flags in enumerate((0, 4, 0x24, 0x80000024)):
            result.update({f'bundle{i}_valid': '1', f'bundle{i}_index': str(i),
                           f'bundle{i}_flags': str(flags), f'bundle{i}_opcode': '35'})
        return result

    def test_precedence_and_older_capture(self):
        attempted, values = reader.read_bundle_samples(self.row(), 4)
        self.assertEqual(attempted, 4)
        self.assertEqual([v[0] for v in values], [0, 1, 2, 3])
        self.assertEqual(reader.read_bundle_samples({}, 5000), (0, []))

    def test_unknown_is_not_zero_opcode(self):
        row = self.row()
        row.update(bundle0_valid='0', bundle0_opcode='0')
        self.assertEqual(len(reader.read_bundle_samples(row, 4)[1]), 3)

    def test_invalid_rejected(self):
        for key, value in [('bundle_attempted', '9'), ('bundle0_index', '1'),
                           ('bundle0_flags', '-1'), ('bundle0_flags', '4294967296'),
                           ('bundle0_opcode', '65536'), ('bundle0_valid', '2'),
                           ('bundle0_valid', '0')]:
            row = self.row()
            row[key] = value
            with self.assertRaises(ValueError): reader.read_bundle_samples(row, 4)

    def test_kernel_route_precedence_and_missing_data(self):
        self.assertEqual(reader.kernel_route(0x24, None), 'unknown')
        self.assertEqual(reader.kernel_route(0x24, 0), 'compute_graphics_queue_candidate')
        self.assertEqual(reader.kernel_route(0x24, 3), 'compute_async_queue_candidate')
        self.assertEqual(reader.kernel_route(0x24, 4), 'ray_dispatch_candidate')
        self.assertEqual(reader.kernel_route(0x24, 5), 'compute_graphics_queue_candidate')
        self.assertEqual(reader.kernel_route(0x80000004, 0), 'instancer_candidate')
        self.assertEqual(reader.kernel_route(4, 0), 'direct_draw_candidate')
        row = self.row()
        row.update(bundle2_kernel_valid='1', bundle2_kernel_flags='3')
        self.assertEqual(reader.read_bundle_samples(row, 4)[1][2][4], 'compute_async_queue_candidate')
        row['bundle2_opcode'] = '6'
        with self.assertRaises(ValueError): reader.read_bundle_samples(row, 4)

    def test_kernel_identity_unknown_and_bounds(self):
        row = self.row()
        self.assertIsNone(reader.read_bundle_samples(row, 4)[1][2][5])
        row.update(bundle2_identity_valid='1', bundle2_resource_tag='0x123456789abcdef0',
                   bundle2_object_tag='7', bundle2_batch_tag='8', bundle2_kernel_handle='9')
        self.assertEqual(reader.read_bundle_samples(row, 4)[1][2][5], (0x123456789abcdef0, 7, 8, 9))
        for key, value in [('bundle2_identity_valid', '0'), ('bundle2_resource_tag', '0x10000000000000000'),
                           ('bundle2_kernel_handle', '-1'), ('bundle2_object_tag', '4294967296'),
                           ('bundle2_opcode', '6')]:
            with self.assertRaises(ValueError): reader.read_bundle_samples({**row, key:value}, 4)

if __name__ == '__main__': unittest.main()
