"""Decode observed Oodle-packed shader records without modifying game assets."""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys

spec = importlib.util.spec_from_file_location("dxbc", Path(__file__).with_name("extract-dxbc-containers.py"))
dxbc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dxbc)
MAX_DECODED = 16 * 1024 * 1024


def candidates(data):
    """Recognize the observed length/Oodle/tag-5/raw-length envelope only."""
    cursor = 0
    while True:
        offset = data.find(b"\x8c\x06", cursor)
        if offset < 0:
            return
        cursor = offset + 2
        if offset < 4:
            continue
        compressed = struct.unpack_from("<I", data, offset - 4)[0]
        if not 6 <= compressed <= len(data) - offset - 8:
            continue
        tag, decoded = struct.unpack_from("<II", data, offset + compressed)
        if tag == 5 and 32 <= decoded <= MAX_DECODED:
            yield offset, compressed, decoded


def decode_records(data, decompress):
    for offset, compressed, size in candidates(data):
        decoded = decompress(data[offset:offset + compressed], size)
        if len(decoded) != size:
            raise ValueError(f"decoder length mismatch at {offset:#x}")
        # A marker or successful decompression alone is not a shader container.
        matches = list(dxbc.containers(decoded))
        if len(matches) != 1 or matches[0][0] != 0 or len(matches[0][1]) != size:
            raise ValueError(f"invalid decoded DXBC container at {offset:#x}")
        yield {"offset": offset, "compressed_size": compressed, "decoded_size": size,
               "sha256": hashlib.sha256(decoded).hexdigest()}, decoded


class OodleDecoder:
    def __init__(self, path, expected_hash):
        if sys.platform != "win32" or ctypes.sizeof(ctypes.c_void_p) != 8:
            raise ValueError("decoder requires Windows x64")
        path = path.resolve(strict=True)
        self.sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
        if self.sha256 != expected_hash.lower():
            raise ValueError("Oodle DLL hash mismatch")
        self.library = ctypes.CDLL(str(path))
        self.function = self.library.OodleLZ_Decompress
        ptr, size, integer = ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int
        self.function.restype = size
        self.function.argtypes = [ptr, size, ptr, size, integer, integer, integer,
                                  ptr, size, ptr, ptr, ptr, size, integer]

    def __call__(self, data, size):
        source = ctypes.create_string_buffer(data)
        destination = ctypes.create_string_buffer(size)
        result = self.function(source, len(data), destination, size, 1, 0, 0,
                               None, 0, None, None, None, 0, 3)
        if result != size:
            raise ValueError("Oodle rejected packed shader record")
        return destination.raw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--oodle", type=Path, required=True)
    parser.add_argument("--oodle-sha256", required=True)
    args = parser.parse_args()
    if not args.input.is_dir():
        parser.error("input must be an extracted shader-group directory")
    if args.output.exists():
        parser.error("output must be a new directory")
    decoder = OodleDecoder(args.oodle, args.oodle_sha256)
    sources = sorted(p for p in args.input.iterdir() if p.is_file())
    args.output.mkdir(parents=True)
    report = {"schema": 1, "oodle_sha256": decoder.sha256, "sources": [], "records": [],
              "complete_group_format_decoded": False}
    unique = set()
    for path in sources:
        data = path.read_bytes()
        report["sources"].append({"name": path.name, "sha256": hashlib.sha256(data).hexdigest()})
        for record, decoded in decode_records(data, decoder):
            record["source"] = path.name
            report["records"].append(record)
            digest = record["sha256"]
            if digest not in unique:
                (args.output / f"{digest}.dxbc").write_bytes(decoded)
                unique.add(digest)
    (args.output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"validated_records={len(report['records'])} unique_containers={len(unique)}")


if __name__ == "__main__":
    main()
