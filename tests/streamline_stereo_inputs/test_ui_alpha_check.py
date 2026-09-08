import importlib.util
import struct
import tempfile
import unittest
from unittest import mock
from pathlib import Path

import numpy as np

source = Path(__file__).resolve().parents[2] / "tools/stereo/check-dlss-ui-alpha.py"
spec = importlib.util.spec_from_file_location("ui_alpha_check", source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AlphaCheck(unittest.TestCase):
    def test_cli_checks_both_eyes_before_creating_output(self):
        image = np.zeros((2, 3, 4), np.uint8)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report"
            with mock.patch.object(module, "read_rgba", side_effect=[image, image, image, ValueError("bad right eye")]), \
                    mock.patch("sys.argv", ["alpha", "stem", "--output", str(output)]):
                with self.assertRaisesRegex(ValueError, "bad right eye"):
                    module.main()
            self.assertFalse(output.exists())

    def test_coverage_regions_partition_without_border_wrap(self):
        alpha = np.zeros((5, 5), np.uint8)
        alpha[0, 0] = 255
        alpha[2, 2] = 128
        regions = module.coverage_regions(alpha, 1)
        self.assertEqual(int(regions["opaque_ui"].sum()), 1)
        self.assertEqual(int(regions["translucent_ui"].sum()), 1)
        self.assertFalse(regions["transparent_near_ui"][-1, -1])
        np.testing.assert_array_equal(sum(mask.astype(int) for mask in regions.values()), np.ones((5, 5), int))
        # Independently enumerate the local neighborhood, including clipped edges.
        for y in range(5):
            for x in range(5):
                expected = alpha[y, x] == 0 and any(
                    alpha[yy, xx] > 0 for yy in range(max(0, y - 1), min(5, y + 2))
                    for xx in range(max(0, x - 1), min(5, x + 2)))
                self.assertEqual(bool(regions["transparent_near_ui"][y, x]), expected)
        self.assertFalse(module.coverage_regions(alpha, 0)["transparent_near_ui"].any())

    def test_local_residuals_keep_surrounding_scene_separate(self):
        scene = np.full((9, 9, 4), 80, np.uint8)
        scene[:, :, 3] = 255
        ui = np.zeros_like(scene)
        ui[4, 4] = [120, 100, 80, 255]
        ui[4, 5] = [30, 20, 10, 128]
        final = scene.copy()
        final[:, :, :3] = np.rint(ui[:, :, :3] + (1 - ui[:, :, 3:4] / 255) * scene[:, :, :3])
        final[4, 3, 0] += 25  # Outside UI coverage but beside the HUD.
        final[0, 0, 0] += 10  # Far from UI coverage.
        final[4, 5, 0] += 15  # Inside a translucent boundary.
        report, _, _ = module.compare(scene, final, ui, near_ui_radius=1)
        self.assertEqual(report["regions"]["opaque_ui"]["residual_pixels_over_tolerance"], 0)
        for name in ("translucent_ui", "transparent_near_ui", "transparent_far_ui"):
            self.assertEqual(report["regions"][name]["residual_pixels_over_tolerance"], 1)
        self.assertEqual(report["regions"]["transparent_near_ui"]["max_channel_error"], 25)
        self.assertEqual(sum(r["pixels"] for r in report["regions"].values()), 81)
        self.assertFalse(report["capture_identity_verified"])
        self.assertEqual(report["visual_acceptance"], "unverified")

    def test_empty_regions_and_invalid_radius(self):
        alpha = np.zeros((2, 3), np.uint8)
        regions = module.coverage_regions(alpha, 64)
        self.assertTrue(regions["transparent_far_ui"].all())
        scene = np.zeros((2, 3, 4), np.uint8)
        report, _, _ = module.compare(scene, scene, scene)
        self.assertIsNone(report["regions"]["opaque_ui"]["max_channel_error"])
        self.assertIsNone(report["regions"]["transparent_near_ui"]["residual_fraction"])
        for radius in (-1, 65, 1.5, True):
            with self.assertRaises(ValueError):
                module.coverage_regions(alpha, radius)

    def test_composition_and_missing_draw(self):
        scene = np.full((4, 5, 4), 80, np.uint8)
        scene[:, :, 3] = 255
        ui = np.zeros_like(scene)
        ui[1:3, 1:4] = [96, 64, 0, 128]
        final = scene.copy()
        final[:, :, :3] = np.rint(ui[:, :, :3] + (1 - ui[:, :, 3:4] / 255) * scene[:, :, :3])
        report, _, _ = module.compare(scene, final, ui)
        self.assertTrue(report["composition_check_pass"])
        ui[1, 1] = 0
        report, _, _ = module.compare(scene, final, ui)
        self.assertFalse(report["composition_check_pass"])
        self.assertEqual(report["missed_changed_pixels"], 1)

    def test_opaque_final_is_not_accepted_as_ui(self):
        scene = np.full((2, 2, 4), 100, np.uint8)
        final = scene.copy()
        final[0, 0, :3] = 220
        # An opaque final can reproduce itself mathematically; the expected
        # transparent background must still be present.
        final[:, :, 3] = 255
        self.assertFalse(module.compare(scene, final, final)[0]["composition_check_pass"])

    def test_bmp_keeps_alpha_and_orientation(self):
        rgba = np.array([[[7, 11, 13, 0]], [[17, 19, 23, 129]]], np.uint8)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "readback.bmp"
            for height in (-2, 2):
                pixels = rgba if height < 0 else rgba[::-1]
                header = struct.pack("<2sIHHI", b"BM", 62, 0, 0, 54)
                dib = struct.pack("<IiiHHIIiiII", 40, 1, height, 1, 32, 0, 8, 0, 0, 0, 0)
                path.write_bytes(header + dib + pixels[:, :, [2, 1, 0, 3]].tobytes())
                np.testing.assert_array_equal(module.read_rgba(path), rgba)


if __name__ == "__main__":
    unittest.main()
