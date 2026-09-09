import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("packed", Path(__file__).resolve().parents[2] /
                                            "tools/renderer_probe/decode-packed-shader-groups.py")
packed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packed)


def container():
    return b"DXBC" + bytes(16) + struct.pack("<4I", 1, 44, 1, 36) + b"TEST" + struct.pack("<I", 0)


def envelope(tag=5, size=44):
    payload = b"\x8c\x06test"
    return struct.pack("<I", len(payload)) + payload + struct.pack("<II", tag, size)


class PackedShaders(unittest.TestCase):
    def test_decodes_only_bounded_payload_with_declared_length(self):
        calls = []
        def decode(data, size):
            calls.append((data, size))
            return container()
        records = list(packed.decode_records(b"prefix" + envelope() + envelope(), decode))
        self.assertEqual(calls, [(b"\x8c\x06test", 44)] * 2)
        self.assertEqual([r[0]["offset"] for r in records], [10, 28])
        self.assertEqual(records[0][0]["sha256"], records[1][0]["sha256"])

    def test_rejects_unbounded_truncated_unknown_envelopes(self):
        for data in (b"\x8c\x06", envelope()[:-1], envelope(tag=4), envelope(size=31),
                     envelope(size=packed.MAX_DECODED + 1),
                     struct.pack("<I", 0xffffffff) + envelope()[4:]):
            self.assertEqual(list(packed.candidates(data)), [])

    def test_rejects_wrong_output_length_and_invalid_chunks(self):
        invalid = bytearray(container())
        struct.pack_into("<I", invalid, 32, 43)
        for result in (container()[:-1], b"x" * 44, bytes(invalid)):
            with self.assertRaises(ValueError):
                list(packed.decode_records(envelope(), lambda data, size: result))

    def test_propagates_decoder_failure(self):
        def fail(data, size):
            raise ValueError("decompression failed")
        with self.assertRaisesRegex(ValueError, "decompression failed"):
            list(packed.decode_records(envelope(), fail))


if __name__ == "__main__":
    unittest.main()
