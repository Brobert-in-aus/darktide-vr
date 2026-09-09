import ctypes
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch

import numpy as np

DLL = Path(sys.argv.pop(1)).resolve()
SOURCE = Path(__file__).resolve().parents[2] / "tools/stereo/check-dlss-ui-alpha.py"
spec = importlib.util.spec_from_file_location("ui_hash_analysis", SOURCE)
analysis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analysis)


class PixelHash(unittest.TestCase):
    def tearDown(self):
        analysis.configure_pixel_hash()

    def test_byte_order_channels_strides_and_input_preservation(self):
        image = np.random.default_rng(173).integers(0, 256, (19, 23, 4), dtype=np.uint8)
        saved = image.copy()
        arrays = (image, image[::-1, ::-1], image[:, ::2], np.asfortranarray(image), image[:0])
        for array in arrays:
            for channels in (0, 1, 3, 4, 5):
                analysis.configure_pixel_hash()
                expected = analysis.pixel_hash(array, channels)
                analysis.configure_pixel_hash(DLL)
                self.assertEqual(analysis.pixel_hash(array, channels), expected)
        np.testing.assert_array_equal(image, saved)

    def test_native_empty_and_invalid_arguments(self):
        library = ctypes.CDLL(str(DLL))
        compute = library.dtvr_analysis_fnv1a64
        compute.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_uint64)]
        compute.restype = ctypes.c_int
        result = ctypes.c_uint64(42)
        self.assertEqual(compute(None, 1, ctypes.byref(result)), 1)
        self.assertEqual(result.value, 42)
        self.assertEqual(compute(b"x", 1, None), 1)
        self.assertEqual(compute(None, 0, ctypes.byref(result)), 0)
        self.assertEqual(result.value, 14695981039346656037)

    def test_explicit_bad_version_and_checksum_fail(self):
        version = Mock(return_value=2)
        with patch("ctypes.CDLL", return_value=Mock(dtvr_analysis_hash_version=version)):
            with self.assertRaisesRegex(ValueError, "version"):
                analysis.configure_pixel_hash(DLL)
        version.return_value = 1
        compute = Mock(return_value=0)  # Leaves the checksum output at zero.
        with patch("ctypes.CDLL", return_value=Mock(dtvr_analysis_hash_version=version,
                                                    dtvr_analysis_fnv1a64=compute)):
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                analysis.configure_pixel_hash(DLL)

    def test_existing_native_capture_proof_with_compiled_hash(self):
        fixture_spec = importlib.util.spec_from_file_location(
            "alpha_native_proof", Path(__file__).with_name("test_ui_alpha_check.py"))
        fixture = importlib.util.module_from_spec(fixture_spec)
        fixture_spec.loader.exec_module(fixture)
        fixture.module.configure_pixel_hash(DLL)
        try:
            case = fixture.AlphaCheck("test_native_proof_requires_every_role_and_rgba_byte")
            case.test_native_proof_requires_every_role_and_rgba_byte()
        finally:
            fixture.module.configure_pixel_hash()

    def test_default_requires_no_library(self):
        analysis.configure_pixel_hash(DLL)
        with patch("ctypes.CDLL", side_effect=AssertionError("implicit load")):
            analysis.configure_pixel_hash()
            image = np.array([[[97, 0, 0, 0]]], dtype=np.uint8)
            self.assertEqual(analysis.pixel_hash(image, 1), 12638187200555641996)


if __name__ == "__main__":
    unittest.main()
