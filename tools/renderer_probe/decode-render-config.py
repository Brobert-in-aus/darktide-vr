#!/usr/bin/env python3
"""Decode Stingray's compiled typed-SJSON render_config resource."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


class Decoder:
    def __init__(self, data: bytes):
        self.data = data

    def u32(self, offset: int) -> int:
        if offset < 0 or offset + 4 > len(self.data):
            raise ValueError(f"u32 offset out of range: 0x{offset:x}")
        return struct.unpack_from("<I", self.data, offset)[0]

    def string(self, offset: int) -> str:
        if offset < 0 or offset >= len(self.data):
            raise ValueError(f"string offset out of range: 0x{offset:x}")
        end = self.data.find(b"\0", offset)
        if end < 0:
            raise ValueError(f"unterminated string at 0x{offset:x}")
        return self.data[offset:end].decode("utf-8")

    def value(self, kind: int, payload: int, depth: int = 0, path: str = "$"):
        if depth > 256:
            raise ValueError("render config nesting exceeds 256 levels")
        if kind == 0:
            return None
        if kind == 1:
            return bool(payload)
        if kind == 2:
            return payload
        if kind == 3:
            return struct.unpack("<f", struct.pack("<I", payload))[0]
        if kind == 4:
            return self.string(payload)
        if kind == 5:
            element_kind = self.u32(payload)
            count = self.u32(payload + 4)
            return [
                self.value(
                    element_kind,
                    self.u32(payload + 8 + index * 4),
                    depth + 1,
                    f"{path}[{index}]",
                )
                for index in range(count)
            ]
        if kind == 6:
            count = self.u32(payload)
            result = {}
            for index in range(count):
                entry = payload + 4 + index * 12
                key = self.string(self.u32(entry))
                result[key] = self.value(
                    self.u32(entry + 4),
                    self.u32(entry + 8),
                    depth + 1,
                    f"{path}.{key}",
                )
            return result
        raise ValueError(
            f"unknown typed-SJSON kind {kind} payload=0x{payload:x} "
            f"at {path} depth {depth}"
        )

    def decode(self):
        kind = self.u32(0)
        payload = self.u32(4)
        return self.value(kind, payload)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("-o", "--output", type=Path)
    args = parser.parse_args()

    decoded = Decoder(args.input.read_bytes()).decode()
    text = json.dumps(decoded, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
