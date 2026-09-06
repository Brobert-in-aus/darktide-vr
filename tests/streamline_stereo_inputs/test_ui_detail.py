import importlib.util
from pathlib import Path
import unittest

import numpy as np

spec = importlib.util.spec_from_file_location("ui_detail", Path(__file__).resolve().parents[2] /
    "tools/stereo/measure-dlss-ui-detail.py")
detail = importlib.util.module_from_spec(spec)
spec.loader.exec_module(detail)


class UiDetail(unittest.TestCase):
    def setUp(self):
        self.ui = np.full((32, 32, 4), 255, dtype=np.uint8)
        self.ui[:, :, :3] = np.random.default_rng(72).integers(20, 235, (32, 32, 3), dtype=np.uint8)

    def test_identity_preserves_contrast(self):
        for value in detail.measure(self.ui, self.ui.copy())["axes"].values():
            self.assertEqual(value["energy_weighted_contrast_retention"], 1)
            self.assertEqual(value["mean_gradient_max_channel_error"], 0)

    def test_known_smoothing_loses_contrast(self):
        # Numerical fixture only; no game/headset motion or visual acceptance.
        output = self.ui.copy()
        rgb = self.ui[:, :, :3].astype(np.float32)
        smooth = sum(np.roll(rgb, (y, x), axis=(0, 1)) for y in (-1, 0, 1) for x in (-1, 0, 1)) / 9
        output[:, :, :3] = smooth.astype(np.uint8)
        for value in detail.measure(self.ui, output)["axes"].values():
            self.assertLess(value["energy_weighted_contrast_retention"], 0.3)

    def test_reversed_edges_are_not_sharpness_preservation(self):
        output = self.ui.copy()
        output[:, :, :3] = 255 - output[:, :, :3]
        for value in detail.measure(self.ui, output)["axes"].values():
            self.assertEqual(value["energy_weighted_contrast_retention"], -1)
            self.assertEqual(value["fraction_contrast_reversed"], 1)

    def test_translucency_and_flat_colour_are_insufficient(self):
        self.ui[:, :, 3] = 254
        self.assertTrue(all(a["status"] == "insufficient_opaque_detail"
                            for a in detail.measure(self.ui, self.ui)["axes"].values()))
        self.ui[:, :, :] = 255
        self.assertTrue(all(a["edge_pairs"] == 0
                            for a in detail.measure(self.ui, self.ui)["axes"].values()))

    def test_rejects_mismatched_extents_and_types(self):
        with self.assertRaises(ValueError):
            detail.measure(self.ui, self.ui[:-1])
        with self.assertRaises(ValueError):
            detail.measure(self.ui.astype(float), self.ui.astype(float))


if __name__ == "__main__":
    unittest.main()
