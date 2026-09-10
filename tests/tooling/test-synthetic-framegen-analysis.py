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

    def test_selection_counts_and_publication_rates(self):
        def selection(original, generated, generation=1):
            return (f'openxr.generated_selection gameplay_generation={generation} interval_seconds=2 '
                    f'original_latest={original} generated_latest={generated} '
                    'reserved_original=60 unavailable=0 no_new=30 metadata_rejected=0 '
                    'original_missing=20 order_rejected=10 history_missing=0 selected=60')
        report = module.summarize_selection('\n'.join([
            selection(1, 1), selection(161, 141), selection(321, 281)]), 0)
        self.assertEqual(report['original_ring_publication_fps'], 80)
        self.assertEqual(report['generated_ring_publication_fps'], 70)
        self.assertEqual(sum(report['outcomes'].values()), 360)
        self.assertEqual(report['outcomes_per_second']['selected'], 30)
        restarted = module.summarize_selection('\n'.join([
            selection(100, 100), selection(1, 1, 2), selection(161, 141, 2)]), 0)
        self.assertEqual(restarted['original_ring_publication_fps'], 80)
        rollback = module.summarize_selection('\n'.join([
            selection(100, 100), selection(1, 1), selection(161, 141)]), 0)
        self.assertEqual(rollback['original_ring_publication_fps'], 80)
        with self.assertRaises(ValueError):
            module.summarize_selection(selection(1, 1).replace('interval_seconds=2', 'interval_seconds=nan'), 0)
        with self.assertRaises(ValueError):
            module.summarize_selection(selection(1, 1).replace('no_new=30', 'no_new=-1'), 0)

    def test_missing_selection_is_unknown(self):
        self.assertIsNone(module.summarize_selection('', 0)['outcomes'])

    def test_cadence_preserves_missing_and_uses_same_warmup(self):
        fields = (' cadence_distinct=118 cadence_repeats=2 repeat_runs_ended=1 '
                  'distinct_gap_samples=118 cadence_clock_breaks=0 '
                  'repeat_run_peak=2 distinct_gap_max_ms=25')
        report = module.summarize('\n'.join([record(1), record(61)+fields,
                                           record(121)+fields, record(181)]), 2)
        cadence = report['delivery_cadence']
        self.assertEqual(cadence['sample_seconds'], 2)
        self.assertEqual(cadence['counts']['cadence_repeats'], 2)
        self.assertEqual(cadence['longest_repeat_run'], 2)
        self.assertEqual(cadence['maximum_distinct_gap_ms'], 25)
        self.assertIsNone(module.summarize('\n'.join([record(1), record(61)]), 0)
                          ['delivery_cadence']['maximum_distinct_gap_ms'])
        for bad in (fields.replace('distinct_gap_max_ms=25', 'distinct_gap_max_ms=nan'),
                    fields.replace('distinct_gap_samples=118', 'distinct_gap_samples=0'),
                    ' repeat_run_peak=2'):
            with self.assertRaises(ValueError):
                module.summarize('\n'.join([record(1), record(61)+bad]), 0)

if __name__ == '__main__': unittest.main()
