import importlib.util
import struct
import tempfile
import unittest
from pathlib import Path

import numpy as np

source = Path(__file__).resolve().parents[2] / "tools/stereo/check-dlss-ui-alpha.py"
spec = importlib.util.spec_from_file_location("ui_alpha_check", source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AlphaCheck(unittest.TestCase):
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
