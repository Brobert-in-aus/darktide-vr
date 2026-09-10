import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("coherence", Path(__file__).resolve().parents[2] /
                                            "tools/stereo/analyze-stereo-camera-coherence.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


def row(basis, position):
    result = dict(zip(("camera_right", "camera_fwd", "camera_up"),
                      [",".join(map(str, values)) for values in tool.transpose(basis)]))
    result["camera_pos"] = ",".join(map(str, position))
    return result


class CoherenceTests(unittest.TestCase):
    def test_optical_offsets_are_removed_but_head_mismatch_is_detected(self):
        fovs = [[-0.94, 0.70, 0.76, -0.94], [-0.70, 0.94, 0.76, -0.94]]
        left = row(tool.optical(fovs[0]), [-0.032, 0, 0])
        right = row(tool.optical(fovs[1]), [0.032, 0, 0])
        measured = tool.measure(left, right, fovs, 0.064)
        self.assertGreater(measured["raw_forward_degrees"], 10)
        self.assertLess(measured["corrected_forward_degrees"], 0.00001)
        self.assertLess(measured["baseline_right_degrees"], 0.00001)
        self.assertEqual(measured["ipd_error_metres"], 0)
        wrong = tool.measure(right, left, fovs, 0.064)
        self.assertGreater(wrong["corrected_forward_degrees"], 20)
        self.assertGreater(wrong["baseline_right_degrees"], 160)

    def test_invalid_camera_metadata_is_rejected(self):
        fov = [-0.8, 0.8, 0.8, -0.8]
        good = row(tool.optical(fov), [0.032, 0, 0])
        for bad in ("nan,0,0", "2,0,0", "-1,0,0"):
            left = {**good, "camera_right": bad, "camera_pos": "-0.032,0,0"}
            with self.assertRaises(ValueError): tool.measure(left, good, [fov, fov], 0.064)
        with self.assertRaises(ValueError): tool.optical([0.8, -0.8, 0.8, -0.8])

    def test_duplicate_viewport_samples_are_not_paired(self):
        consumer = "openxr.render_projection=recentered-symmetric\nopenxr.runtime_fov.eye0=-0.8,0.8,0.8,-0.8\nopenxr.runtime_fov.eye1=-0.8,0.8,0.8,-0.8\nopenxr.runtime_ipd_metres=0.064\n"
        def line(viewport):
            data = {"viewport": viewport, "present_frame": 10, "frame_index": 9, "token": "abc", "result": 0,
                    **row(tool.optical([-0.8, 0.8, 0.8, -0.8]), [-0.032 if viewport == 1 else 0.032, 0, 0])}
            return "SET_CONSTANTS\t" + "\t".join(f"{key}={value}" for key,value in data.items())
        self.assertEqual(tool.analyze(consumer, line(1)+"\n"+line(2), 1, 2)["matched_pairs"], 1)
        with self.assertRaises(ValueError): tool.analyze(consumer, line(1)+"\n"+line(1)+"\n"+line(2), 1, 2)
        with self.assertRaises(ValueError): tool.analyze(consumer, line(1)+"\n"+line(2), 1, 2, 11)


if __name__ == "__main__": unittest.main()
