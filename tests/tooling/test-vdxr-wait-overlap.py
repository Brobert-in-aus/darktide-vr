import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


script = Path(__file__).resolve().parents[2] / 'tools/stereo/analyze-vdxr-wait-overlap.py'
overlap = load('wait_overlap', script)
fixture = load('trace_fixture', Path(__file__).with_name('test-vdxr-trace.py'))


class WaitOverlap(unittest.TestCase):
    def test_union_intersection_boundaries_and_modes(self):
        spans = {
            'OVR_BeginFrame': [(10, 30, '2', '2', 'unreported'),
                               (20, 40, '2', '2', 'unreported'),
                               (50, 60, '2', '2', 'unreported')],
            'WaitForAsyncSubmissionIdle': [(5, 20, '1', '1', '0'),
                (15, 55, '1', '1', '0'), (25, 35, '1', '1', '0'),
                (40, 50, '1', '1', '1'), (20, 20, '3', '3', '0')],
            'xrEndFrame': [(10, 60, '1', '1', 'unreported')]}
        result = overlap.correlate(spans)
        groups = {(g['name'], g['start_thread'], g['running_start']): g for g in result['groups']}
        wait = groups['WaitForAsyncSubmissionIdle', '1', '0']
        self.assertEqual(wait['boundary_excluded'], 1)
        self.assertEqual(wait['spans'], 2)
        self.assertEqual(wait['wait_union_ms'], 40 / 1e6)
        self.assertEqual(wait['overlap_fraction'], .75)
        self.assertEqual(groups['WaitForAsyncSubmissionIdle', '1', '1']['overlap_fraction'], 0)
        self.assertIsNone(groups['WaitForAsyncSubmissionIdle', '3', '0']['overlap_fraction'])
        self.assertEqual(groups['xrEndFrame', '1', 'unreported']['overlap_fraction'], .8)
        self.assertEqual(overlap.union([(2, 2), (1, 2), (2, 3)]), [(1, 3)])
        with self.assertRaises(ValueError):
            overlap.union([(2, 1)])

    def test_no_complete_begin(self):
        result = overlap.correlate({'OVR_BeginFrame': [], 'WaitForAsyncSubmissionIdle': [], 'xrEndFrame': []})
        self.assertEqual(result['status'], 'no_complete_begin_frame_spans')

    def test_span_collection_preserves_parser_acceptance(self):
        event = fixture.event
        source = fixture.capture(event(100, 1, '{a}', name='OVR_BeginFrame'),
            event(200, 2, '{a}', name='OVR_BeginFrame'),
            event(300, 1, '{b}'), event(400, 1, '{b}'), event(500, 2, '{b}'),
            event(600, 1, '{c}'), event(700, 2, '{c}'))
        spans = {'OVR_BeginFrame': [], 'WaitForAsyncSubmissionIdle': []}
        before = overlap.trace.summarize(io.StringIO(source), 10)
        after = overlap.trace.summarize(io.StringIO(source), 10, spans)
        self.assertEqual(before, after)
        self.assertEqual(len(spans['OVR_BeginFrame']), 1)
        self.assertEqual(len(spans['WaitForAsyncSubmissionIdle']), 1)
        self.assertEqual(spans['OVR_BeginFrame'][0][:2], (10000, 20000))

    def test_cli_preserves_source_and_hardlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / 'trace.xml'
            content = fixture.capture(fixture.event(100, 1, name='OVR_BeginFrame'),
                                      fixture.event(200, 2, name='OVR_BeginFrame')).encode()
            source.write_bytes(content)
            alias = Path(temporary) / 'alias.xml'
            alias.hardlink_to(source)
            for output in (source, alias):
                result = subprocess.run([sys.executable, '-B', str(script), str(source),
                    '--process-id', '10', '--output', str(output)], capture_output=True)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(source.read_bytes(), content)
            output = Path(temporary) / 'report.json'
            result = subprocess.run([sys.executable, '-B', str(script), str(source),
                '--process-id', '10', '--output', str(output)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(output.read_text())['status'], 'temporal_overlap_only')
            self.assertEqual(source.read_bytes(), content)


if __name__ == '__main__':
    unittest.main()
