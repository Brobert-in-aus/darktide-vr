import importlib.util
from pathlib import Path
import unittest

import numpy as np

spec = importlib.util.spec_from_file_location("generated_ui", Path(__file__).resolve().parents[2] /
    "tools/stereo/compare-dlss-generated-ui.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class GeneratedUiCheck(unittest.TestCase):
    def setUp(self):
        self.ui = np.zeros((128, 128, 4), dtype=np.uint8)
        self.ui[40:80, 40:80, :3] = np.random.default_rng(12).integers(30, 255, (40, 40, 3))
        self.ui[40:80, 40:80, 3] = 255

    def test_exact_current_ui(self):
        result = module.compare(self.ui, self.ui.copy(), radius=16)
        self.assertEqual(result["best_translation_pixels"], [0, 0])
        self.assertEqual(result["current_position_fraction_within_3"], 1)

    def test_shift_is_measured(self):
        output = np.roll(self.ui, (8, -8), axis=(0, 1))
        result = module.compare(self.ui, output, radius=16)
        self.assertEqual(result["best_translation_pixels"], [-8, 8])
        self.assertEqual(result["best_translation_fraction_within_3"], 1)
        self.assertLess(result["current_position_fraction_within_3"], 0.01)

    def test_missing_ui_is_not_a_placement_pass(self):
        result = module.compare(self.ui, np.zeros_like(self.ui), radius=16)
        self.assertEqual(result["best_translation_fraction_within_3"], 0)
        self.assertEqual(result["placement_check"], "measurement_only")

    def test_translucent_pixels_cannot_establish_expected_colour(self):
        self.ui[:, :, 3] = 100
        self.assertEqual(module.compare(self.ui, self.ui)["placement_check"], "insufficient_opaque_UI")


if __name__ == "__main__":
    unittest.main()
