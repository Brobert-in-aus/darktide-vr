import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[2] / "tools/stereo/summarize-xr-frame-stages.py"
spec = importlib.util.spec_from_file_location("frame_stages", path)
stages = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stages)


def presentation(mode=1):
    return f"openxr.presentation mode={mode} generation=1 sequence=10 source=2496x2688 crop=0,0,2496x2688"


def row(frame=120, gpu_count=120, gpu_mean=1):
    text = (f"openxr.frame_stage_timing clock=steady units=ms scope=cpu_wall "
            f"window_end_frame={frame} last_display_period_ms=8.33333 invalid_samples=0")
    for stage in stages.STAGES:
        count = gpu_count if stage == "gpu_fence" else 360 if stage == "swapchain_acquire_wait" else 120
        mean = gpu_mean if stage == "gpu_fence" else 0.25
        text += f" {stage}_samples={count}"
        if count:
            text += f" {stage}_mean={mean} {stage}_max={mean + 2}"
    return text


class FrameStages(unittest.TestCase):
    def test_actual_call_weighting_and_absence(self):
        result = stages.summarize([presentation(), row(gpu_count=60), row(240, gpu_mean=3)])
        self.assertEqual(result["excluded_windows"], {})
        gpu = result["groups"][0]["all"]["stages"]["gpu_fence"]
        self.assertEqual(gpu["count"], 180)
        self.assertAlmostEqual(gpu["mean_call_ms"], 7 / 3)
        self.assertEqual(gpu["maximum_observed_call_ms"], 5)
        absent = stages.summarize([presentation(), row(gpu_count=0)])["groups"][0]["all"]["stages"]["gpu_fence"]
        self.assertEqual(absent, {"count": 0})

    def test_mixed_context_and_frame_gap(self):
        result = stages.summarize([presentation(2), row(), presentation(), row(240), row(360), row(600), row(720)])
        self.assertEqual(result["excluded_windows"], {"unknown_or_mixed_presentation": 1, "frame_discontinuity": 1})
        self.assertEqual([r["window_end_frame"] for r in result["windows"]], [120, 360, 720])
        self.assertEqual(len(result["groups"]), 2)
        unknown = stages.summarize([row()])
        self.assertEqual(unknown["groups"], [])

    def test_malformed_and_incomplete_windows(self):
        mutations = [
            ("wait_frame_mean=0.25", "wait_frame_mean=nan"),
            ("wait_frame_max=2.25", "wait_frame_max=0.1"),
            ("tracking_samples=120", "tracking_samples=119"),
            ("invalid_samples=0", "invalid_samples=1"),
            ("clock=steady", "clock=coarse"),
            ("gpu_fence_samples=120", "gpu_fence_samples=-1"),
            ("scope=cpu_wall", "scope=cpu_wall scope=gpu"),
        ]
        for old, new in mutations:
            result = stages.summarize([presentation(), row().replace(old, new)])
            self.assertEqual(result["groups"], [], new)
            self.assertEqual(sum(result["excluded_windows"].values()), 1)
        with self.assertRaises(ValueError):
            stages.parse(row(gpu_count=0) + " gpu_fence_mean=0")

    def test_restart_cannot_merge_timing_epochs(self):
        result = stages.summarize([presentation(), row(), row(240), row(), row(240)])
        self.assertEqual(len(result["groups"]), 2)
        self.assertEqual([g["epoch"] for g in result["groups"]], [0, 1])
        self.assertEqual(result["excluded_windows"], {"frame_discontinuity": 1})

    def test_optional_poll_samples_and_wait_modes(self):
        legacy = row()
        standard = row(240) + " pair_wait_mode=standard pair_poll_sleep_samples=0"
        precise = row(360) + (" pair_wait_mode=high_resolution pair_poll_sleep_samples=300"
                              " pair_poll_sleep_mean=0.6 pair_poll_sleep_max=1.1")
        result = stages.summarize([presentation(), legacy, standard, precise])
        self.assertEqual(result["excluded_windows"], {})
        self.assertEqual(len(result["groups"]), 3)
        groups = {g["pair_wait_mode"]: g["all"]["stages"]["pair_poll_sleep"]
                  for g in result["groups"]}
        self.assertEqual(groups["unreported"], {"count": 0, "observed_windows": 0})
        self.assertEqual(groups["standard"], {"count": 0, "observed_windows": 1})
        self.assertEqual(groups["high_resolution"]["count"], 300)
        self.assertEqual(groups["high_resolution"]["mean_call_ms"], 0.6)
        for invalid in (" pair_poll_sleep_mean=1", " pair_wait_mode=mixed_failure",
                        " pair_poll_sleep_samples=0 pair_poll_sleep_max=1"):
            self.assertEqual(stages.summarize([presentation(), legacy + invalid])["groups"], [])
        recovery = stages.summarize([presentation(), legacy,
                                    row(240) + " pair_wait_mode=mixed_failure",
                                    row(360) + " pair_wait_mode=standard"])
        self.assertEqual([r["window_end_frame"] for r in recovery["windows"]], [120, 360])
        self.assertEqual(recovery["excluded_windows"], {"unknown_or_mixed_pair_wait_mode": 1})


if __name__ == "__main__":
    unittest.main()
