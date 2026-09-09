import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image

SCRIPT = Path(__file__).resolve().parents[2] / 'tools/stereo/compare-dlss-ui-inputs.py'


class UiInputComparison(unittest.TestCase):
    def test_output_hardlinks_cannot_replace_source_bitmaps(self):
        names = ('left-difference-x4.png', 'right-difference-x4.png',
                 'comparison.png', 'comparison.json')
        for name in names:
            with self.subTest(output=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                stem, output = root / 'capture', root / 'report'
                output.mkdir()
                for eye in ('left', 'right'):
                    for role in ('scene', 'final'):
                        Image.new('RGB', (4, 3), (10, 20, 30)).save(f'{stem}-{eye}-{role}.bmp')
                source = Path(f'{stem}-right-final.bmp')
                (output / name).hardlink_to(source)
                before = {p: p.read_bytes() for p in root.glob('*.bmp')}
                result = subprocess.run([sys.executable, '-B', str(SCRIPT), str(stem),
                    '--output', str(output)], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('replace a capture input', result.stderr)
                self.assertEqual({p: p.read_bytes() for p in before}, before)
                self.assertEqual(sorted(p.name for p in output.iterdir()), [name])

    def test_stereo_validation_precedes_any_output(self):
        for failure in ('missing', 'extent', 'decode'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                stem = root / 'capture'
                for eye in ('left', 'right'):
                    for role in ('scene', 'final'):
                        Image.new('RGB', (4, 3), (10, 20, 30)).save(f'{stem}-{eye}-{role}.bmp')
                bad = Path(f'{stem}-right-final.bmp')
                if failure == 'missing':
                    bad.unlink()
                elif failure == 'extent':
                    Image.new('RGB', (3, 3)).save(bad)
                else:
                    bad.write_bytes(b'invalid bitmap')
                for existing in (False, True):
                    output = root / ('old-report' if existing else 'new-report')
                    if existing:
                        output.mkdir()
                        (output / 'comparison.json').write_bytes(b'old report')
                        (output / 'left-difference-x4.png').write_bytes(b'old image')
                    before = {p.name: p.read_bytes() for p in output.glob('*')}
                    result = subprocess.run([sys.executable, '-B', str(SCRIPT), str(stem),
                        '--output', str(output)], capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual({p.name: p.read_bytes() for p in output.glob('*')}, before)
                    self.assertEqual(output.exists(), existing)

    def test_valid_pair_preserves_sources_and_known_difference(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stem, output = root / 'capture', root / 'report'
            for eye in ('left', 'right'):
                Image.new('RGB', (4, 3), (10, 20, 30)).save(f'{stem}-{eye}-scene.bmp')
                final = Image.new('RGB', (4, 3), (10, 20, 30))
                if eye == 'right':
                    final.putpixel((2, 1), (20, 20, 30))
                final.save(f'{stem}-{eye}-final.bmp')
            before = {p: p.read_bytes() for p in root.glob('*.bmp')}
            result = subprocess.run([sys.executable, '-B', str(SCRIPT), str(stem),
                '--output', str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((output / 'comparison.json').read_text())
            self.assertEqual(report['left']['changed_pixels_over_2'], 0)
            self.assertEqual(report['right']['changed_pixels_over_2'], 1)
            self.assertEqual(report['right']['changed_bounds'], [2, 1, 2, 1])
            with Image.open(output / 'right-difference-x4.png') as difference:
                self.assertEqual(difference.getpixel((2, 1)), (40, 0, 0))
            self.assertEqual({p: p.read_bytes() for p in before}, before)


if __name__ == '__main__':
    unittest.main()
