import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[2] / 'tools/stereo/analyze-synthetic-framegen.py'
spec = importlib.util.spec_from_file_location('framegen_analysis', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def record(ready, dt=2, fresh=30, generated=30, generation=1):
    return (f'openxr.live.submission_fps=90 interval_seconds={dt} gameplay_generation={generation} '
            f'shared_ready={ready} interval_submission_fps=90 interval_fresh_pair_fps={fresh} '
            f'interval_generated_pair_fps={generated} interval_distinct_pair_fps={fresh+generated} '
            f'interval_cached_pair_fps={90-fresh-generated}')

class AnalysisTests(unittest.TestCase):
    def test_weighted_rates_separate_cached(self):
        report = module.summarize('\n'.join([record(1), record(61), record(181,4,20,20)]),0)
        self.assertEqual(report['sample_seconds'],6)
        self.assertEqual(report['legacy_publication_fps'],30)
        self.assertAlmostEqual(report['rates']['interval_distinct_pair_fps'],280/6)
        self.assertEqual(report['rates']['interval_submission_fps'],90)
        self.assertIsNone(report['generated_submissions_total'])

    def test_warmup_and_restart_do_not_create_fake_source_rate(self):
        report = module.summarize('\n'.join([record(1),record(61),record(121),
            record(181),record(1,generation=2),record(61,generation=2)]),2)
        self.assertEqual(report['windows'],2)
        self.assertEqual(report['legacy_publication_fps'],30)

    def test_missing_legacy_timing_unknown(self):
        report = module.summarize('openxr.live.submission_fps=90 shared_ready=9')
        self.assertIsNone(report['legacy_publication_fps'])
        self.assertFalse(report['clean_exit'])

    def test_invalid_interval_rejected(self):
        with self.assertRaises(ValueError): module.summarize(record(1,dt=float('nan')))

if __name__ == '__main__': unittest.main()
