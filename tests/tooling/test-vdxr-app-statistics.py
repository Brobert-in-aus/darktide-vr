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


script = Path(__file__).resolve().parents[2] / 'tools/stereo/summarize-vdxr-app-statistics.py'
app = load('app_stats', script)
fixture = load('trace_fixture', Path(__file__).with_name('test-vdxr-trace.py'))


def event(frame, field, value, **kwargs):
    return fixture.event(100, 0, name='App_Statistics', **kwargs).replace(
        '<Data Name="DoRunningStart">1</Data>',
        f'<Data Name="FrameId">{frame}</Data><Data Name="{field}">{value}</Data>')


class AppStatistics(unittest.TestCase):
    def test_first_duplicate_restart_and_field_separation(self):
        source = fixture.capture(event(1, 'AppRenderCpuTime', 1000000),
            event(2, 'AppRenderCpuTime', 4), event(2, 'AppRenderCpuTime', 6),
            event(3, 'AppRenderGpuTime', 3), event(1, 'AppRenderCpuTime', 2),
            event(4, 'AppRenderCpuTime', 9999, pid=11))
        result = app.summarize(io.StringIO(source), 10)
        groups = {(g['field'], g['epoch']): g for g in result['groups']}
        initial = groups['AppRenderCpuTime', 0]
        self.assertEqual(initial['first_reported_value'], 1000000)
        self.assertEqual(initial['all_reported']['maximum'], 1000000)
        self.assertEqual(initial['all_reported']['samples'], 3)
        self.assertEqual(initial['after_first_reported']['mean'], 5)
        self.assertEqual(initial['duplicate_frame_samples'], 1)
        self.assertEqual(groups['AppRenderCpuTime', 1]['all_reported']['mean'], 2)
        self.assertEqual(groups['AppRenderGpuTime', 0]['after_first_reported'], {'samples': 0})

    def test_invalid_fields_zero_and_unsigned_limit(self):
        repeated = event(1, 'AppRenderCpuTime', 1).replace('</EventData>',
            '<Data Name="AppRenderCpuTime">2</Data></EventData>')
        source = fixture.capture(event(-1, 'AppRenderCpuTime', 1),
            event(1, 'AppRenderCpuTime', -1), event(2, 'AppRenderCpuTime', 'nan'),
            event(3, 'AppRenderCpuTime', 2**64), repeated,
            event(4, 'AppRenderCpuTime', 0), event(5, 'AppRenderCpuTime', 2**64 - 1))
        result = app.summarize(io.StringIO(source), 10)
        self.assertEqual(result['excluded_records'], {'invalid_frame_id': 1,
            'invalid_reported_value': 3, 'duplicate_field': 1})
        self.assertEqual(result['groups'][0]['first_reported_value'], 0)
        self.assertEqual(result['groups'][0]['all_reported']['maximum'], 2**64 - 1)

    def test_cli_preserves_source_and_hardlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / 'trace.xml'
            content = fixture.capture(event(1, 'AppRenderCpuTime', 4000)).encode()
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
            self.assertEqual(json.loads(output.read_text())['groups'][0]['first_reported_value'], 4000)
            self.assertEqual(source.read_bytes(), content)


if __name__ == '__main__':
    unittest.main()
