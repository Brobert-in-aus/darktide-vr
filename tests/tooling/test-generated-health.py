import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("health", Path(__file__).resolve().parents[2] /
                                            "tools/stereo/summarize-generated-health.py")
health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(health)


def row(count, **changes):
    fields = dict(engine_fps=50, legacy_publish_fps=0, original_ring_fps=50,
                  present_mean_ms=.1234, foreground=1, original_failed=0,
                  evaluations=count*2, complete=count*2, paired=count, published=count)
    fields.update(changes)
    return "health " + " ".join(f"{key}={value}" for key, value in fields.items())


class Health(unittest.TestCase):
    def test_fractional_timing_and_slow_windows_survive(self):
        report = health.summarize([row(0, present_clock="steady"), row(1, present_clock="steady"),
                                   row(2, present_clock="steady", engine_fps=2)])
        group, = report["groups"]
        self.assertEqual(group["windows"], 2)
        self.assertEqual(group["metrics"]["engine_fps"]["minimum_window_value"], 2)
        self.assertEqual(group["metrics"]["present_mean_ms"]["median_window_value"], .1234)

    def test_focus_and_clock_not_mixed(self):
        report = health.summarize([row(0), row(1), row(2, foreground=0), row(3, foreground=0),
                                   row(4, foreground=0, present_clock="steady"),
                                   row(5, foreground=0, present_clock="steady")])
        self.assertEqual(len(report["groups"]), 3)
        self.assertEqual(report["excluded_windows"]["focus_or_clock_transition"], 2)

    def test_progress_is_not_graphics_setting_inference(self):
        report = health.summarize([row(0), row(0), row(0, evaluations=2),
                                   row(1, evaluations=2)])
        self.assertEqual(len(report["groups"]), 3)
        self.assertEqual(report["comparison_status"], "observational_only")

    def test_resets_and_invalid_rows_break_counter_chain(self):
        report = health.summarize([row(10), row(0), row(1, engine_fps="nan"), row(2), row(3),
                                   "disabled", "enabled", row(4), row(5)])
        self.assertEqual(report["excluded_windows"]["counter_reset"], 1)
        self.assertEqual(report["excluded_windows"]["invalid_health_row"], 1)
        self.assertEqual(report["excluded_windows"]["counter_baseline"], 3)
        self.assertEqual(sum(group["windows"] for group in report["groups"]), 2)

    def test_output_failure_and_absence_are_reported(self):
        report = health.summarize([row(0), row(1, original_failed=1),
                                   row(2, original_ring_fps=0), row(3, engine_fps=0)])
        self.assertEqual(report["excluded_windows"]["original_failure"], 1)
        self.assertEqual(report["excluded_windows"]["no_observed_original_output"], 2)
        self.assertEqual(report["groups"], [])

    def test_native_timing_counter_boundary_breaks_publication_history(self):
        report = health.summarize([row(0), row(1),
                                   "health_boundary reason=counter_regression", row(2), row(3)])
        self.assertEqual(report["excluded_windows"]["counter_baseline"], 2)
        self.assertEqual(sum(group["windows"] for group in report["groups"]), 2)
        self.assertEqual(report["timing_counter_boundaries"], 1)

    def test_away_and_back_with_same_end_focus_is_not_a_stable_window(self):
        report = health.summarize([row(0, focus_changes=0), row(1, focus_changes=2),
                                   row(2, focus_changes=0)])
        self.assertEqual(report["excluded_windows"]["within_window_focus_transition"], 1)
        group, = report["groups"]
        self.assertEqual(group["windows"], 1)
        self.assertEqual(group["focus_tracking"], "per_present")

    def test_legacy_focus_evidence_is_not_mixed_with_per_present_evidence(self):
        report = health.summarize([row(0), row(1), row(2, focus_changes=0), row(3, focus_changes=0)])
        self.assertEqual({group["focus_tracking"] for group in report["groups"]},
                         {"endpoint_only", "per_present"})
        self.assertEqual(sum(group["windows"] for group in report["groups"]), 2)
        for value in (-1, "nan", "0.5"):
            report = health.summarize([row(0), row(1, focus_changes=value)])
            self.assertEqual(report["excluded_windows"]["invalid_health_row"], 1)


if __name__ == "__main__":
    unittest.main()
