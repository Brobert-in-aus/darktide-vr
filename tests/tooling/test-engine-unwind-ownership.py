"""Offline PE unwind ownership checks; no engine process or headset required."""
import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location(
    "engine_scopes", Path(__file__).resolve().parents[2]
    / "tools/renderer_probe/map-engine-render-scopes.py")
engine_scopes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine_scopes)


class Image:
    def __init__(self, data):
        self.data = data

    def get_data(self, rva, size):
        return self.data[rva:rva + size]


class OwnershipTests(unittest.TestCase):
    def test_odd_code_count_and_multiple_fragments(self):
        data = bytearray(64)
        # Three two-byte unwind slots require one padding slot before CHAININFO.
        data[0:4] = bytes([33, 0, 3, 0])
        data[12:24] = struct.pack("<III", 100, 110, 24)
        data[24:28] = bytes([33, 0, 0, 0])
        data[28:40] = struct.pack("<III", 80, 100, 40)
        data[40:44] = bytes([1, 0, 0, 0])
        result = engine_scopes.unwind_chain(Image(data), (110, 150, 0))
        self.assertEqual([item["begin_rva"] for item in result], [110, 100, 80])

    def test_handler_is_terminal(self):
        result = engine_scopes.unwind_chain(Image(bytes([9, 0, 0, 0])), (1, 2, 0))
        self.assertEqual(len(result), 1)

    def test_rejects_cycle(self):
        data = bytes([33, 0, 0, 0]) + struct.pack("<III", 1, 2, 0)
        with self.assertRaisesRegex(ValueError, "cyclic"):
            engine_scopes.unwind_chain(Image(data), (1, 2, 0))

    def test_rejects_truncated_records_and_invalid_headers(self):
        for data in (b"", bytes([1, 0]), bytes([0, 0, 0, 0]),
                     bytes([33, 0, 0, 0]), bytes([41, 0, 0, 0])):
            with self.subTest(data=data), self.assertRaises(ValueError):
                engine_scopes.unwind_chain(Image(data), (1, 2, 0))

    def test_rejects_empty_range(self):
        with self.assertRaisesRegex(ValueError, "Invalid"):
            engine_scopes.unwind_chain(Image(bytes([1, 0, 0, 0])), (2, 2, 0))


if __name__ == "__main__":
    unittest.main()
