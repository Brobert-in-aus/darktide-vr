import importlib.util
from pathlib import Path
import unittest
import tempfile
from unittest import mock

import numpy as np

spec = importlib.util.spec_from_file_location("generated_ui", Path(__file__).resolve().parents[2] /
    "tools/stereo/compare-dlss-generated-ui.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class GeneratedUiCheck(unittest.TestCase):
    def test_cli_checks_both_ui_images_before_output(self):
        ui = np.arange(16, dtype=np.uint8).reshape(2, 2, 4)
        packed = np.concatenate((ui, ui), axis=1)
        metadata = {"width": 4, "height": 2, "left_hash": module.pixel_hash(ui, 3),
                    "right_hash": module.pixel_hash(ui, 3),
                    "ui_rgba_hashes": {"left": "8972538887847352181", "right": "8972538887847352181"}}
        changed = ui.copy()
        changed[0, 0, 3] ^= 1
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "report"
            with mock.patch.object(module, "verify_match", return_value=metadata), \
                    mock.patch.object(module.ui_alpha, "read_rgba", side_effect=[packed, ui, changed]), \
                    mock.patch("sys.argv", ["compare", "ui", "generated.bmp", "--output", str(destination)]):
                with self.assertRaisesRegex(ValueError, "right UI RGBA content"):
                    module.main()
            self.assertFalse(destination.exists())

    def test_ui_checksum_includes_transparency(self):
        ui = np.arange(16, dtype=np.uint8).reshape(2, 2, 4)
        metadata = {"width": 4, "height": 2, "ui_rgba_hashes": {"left": "8972538887847352181"}}
        module.verify_ui_content(metadata, "left", ui)
        for channel in (0, 3):
            changed = ui.copy()
            changed[0, 0, channel] ^= 1
            with self.assertRaisesRegex(ValueError, "UI RGBA content"):
                module.verify_ui_content(metadata, "left", changed)
        legacy = {"width": 4, "height": 2, "ui_rgba_hashes": {}}
        module.verify_ui_content(legacy, "left", ui)
        self.assertNotIn("ui_rgba_hash_verified", legacy)

    def test_native_rgb_hash_checks_each_eye_in_row_order(self):
        # Standard FNV-1a 64-bit "foobar" vector, laid out as two RGB rows.
        packed = np.array([[[102, 111, 111, 255], [102, 111, 111, 0]],
                           [[98, 97, 114, 0], [98, 97, 114, 255]]], dtype=np.uint8)
        metadata = {"width": 2, "height": 2, "left_hash": 0x85944171f73967e8,
                    "right_hash": 0x85944171f73967e8}
        module.verify_content(metadata, packed)
        self.assertTrue(metadata["generated_rgb_hash_verified"])
        alpha_changed = packed.copy()
        alpha_changed[:, :, 3] = 17
        module.verify_content(metadata, alpha_changed)  # Native checksum covers RGB only.
        for eye in (0, 1):
            changed = packed.copy()
            changed[0, eye, 0] ^= 1
            with self.assertRaisesRegex(ValueError, "native export hash"):
                module.verify_content(metadata, changed)
            self.assertNotIn("generated_rgb_hash_verified", metadata)
        with self.assertRaisesRegex(ValueError, "native export hash"):
            module.verify_content(metadata, packed[::-1])

    def test_cli_rejects_bitmap_extent_before_writing_report(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "report"
            with mock.patch.object(module, "verify_match", return_value={"width": 256, "height": 128}), \
                    mock.patch.object(module.ui_alpha, "read_rgba", return_value=np.zeros((128, 128, 4), dtype=np.uint8)), \
                    mock.patch("sys.argv", ["compare", "ui", "generated.bmp", "--output", str(destination)]):
                with self.assertRaisesRegex(ValueError, "logged RGBA8 extent"):
                    module.main()
            self.assertFalse(destination.exists())

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

    def test_capture_identity_requires_completed_matching_owners(self):
        with tempfile.TemporaryDirectory() as directory:
            stem = Path(directory) / "ui"
            output = Path(directory) / "generated.bmp"
            input_text = ("UI_READBACK_MATCH pose=8 left_scene=abc right_scene=def owned_ui=1\n"
                          "UI_READBACK phase=staged result=0x00000000\n"
                          "UI_READBACK phase=exported result=0x00000000\n")
            identity = ("pose=8 left_scene=abc right_scene=def left_call=20 right_call=21 "
                        "source=src owned=own readback=read width=256 height=128 row_pitch=1024 bytes=131072 "
                        "left_hash=9625390261332436968 right_hash=9625390261332436968 "
                        "result=0x00000000\n")
            def logs(ui_text=input_text, staged=identity, exported=identity):
                stem.with_suffix(".log").write_text(ui_text)
                output.with_suffix(".log").write_text("NGX_COPY phase=staged " + staged +
                                                     "NGX_COPY phase=exported " + exported)
            logs()
            self.assertEqual(module.verify_match(stem, output)["left_call"], "20")
            metadata = module.verify_match(stem, output)
            self.assertEqual(metadata["ui_content_evidence"], "legacy_metadata_only")
            module.verify_extent(metadata, np.zeros((128, 256, 4), dtype=np.uint8))
            for image in (np.zeros((64, 256, 4), dtype=np.uint8),
                          np.zeros((128, 128, 4), dtype=np.uint8),
                          np.zeros((128, 256, 3), dtype=np.uint8),
                          np.zeros((128, 256, 4), dtype=np.float32)):
                with self.assertRaisesRegex(ValueError, "logged RGBA8 extent"):
                    module.verify_extent(metadata, image)
            for old, new in (("width=256", "width=255"), ("height=128", "height=0"),
                             ("row_pitch=1024", "row_pitch=512"), ("row_pitch=1024", "row_pitch=1025"),
                             ("bytes=131072", "bytes=1024"), ("pose=8", "pose=-8"),
                             ("right_call=21", "right_call=20"),
                             ("left_hash=9625390261332436968", "left_hash=-1"),
                             ("right_hash=9625390261332436968", "right_hash=18446744073709551616"),
                             ("right_hash=9625390261332436968 ", "")):
                changed = identity.replace(old, new)
                logs(ui_text=input_text.replace(old, new), staged=changed, exported=changed)
                with self.assertRaises(ValueError):
                    module.verify_match(stem, output)
            image_rows = ("UI_READBACK_IMAGE phase=exported role=left-ui width=128 height=128 rgba_hash=1\n"
                          "UI_READBACK_IMAGE phase=exported role=right-ui width=128 height=128 rgba_hash=2\n")
            logs(ui_text=input_text + image_rows)
            self.assertEqual(module.verify_match(stem, output)["ui_rgba_hashes"], {"left": "1", "right": "2"})
            declared = input_text.replace("result=0x00000000", "result=0x00000000 image_checksum=rgba_fnv1a64")
            logs(ui_text=declared + image_rows)
            self.assertEqual(module.verify_match(stem, output)["ui_content_evidence"], "native_rgba_checksums")
            for text in (declared, declared.replace("rgba_fnv1a64", "unknown") + image_rows,
                         input_text.replace("phase=exported", "phase=exported image_checksum=rgba_fnv1a64") + image_rows):
                logs(ui_text=text)
                with self.assertRaises(ValueError):
                    module.verify_match(stem, output)
            for changed in (image_rows.splitlines(True)[0], image_rows + image_rows,
                            image_rows.replace("width=128", "width=64"),
                            image_rows.replace("rgba_hash=1", "rgba_hash=-1"),
                            image_rows.replace("phase=exported", "phase=staged")):
                logs(ui_text=input_text + changed)
                with self.assertRaises(ValueError):
                    module.verify_match(stem, output)
            logs(ui_text=input_text.replace("UI_READBACK phase=exported result=0x00000000\n", ""))
            with self.assertRaises(ValueError):
                module.verify_match(stem, output)
            for old, new in (("left_call=20", "left_call=22"), ("readback=read", "readback=other"),
                             ("pose=8", "pose=9"), ("result=0x00000000", "result=0x80004005")):
                logs(exported=identity.replace(old, new))
                with self.assertRaises(ValueError):
                    module.verify_match(stem, output)


if __name__ == "__main__":
    unittest.main()
