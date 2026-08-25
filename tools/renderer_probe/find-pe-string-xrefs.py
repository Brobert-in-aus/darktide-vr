#!/usr/bin/env python3
"""Find x64 RIP-relative references to an ASCII string in a PE image."""

from __future__ import annotations

import argparse
import struct
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Section:
    name: str
    virtual_address: int
    virtual_size: int
    raw_offset: int
    raw_size: int

    def raw_to_rva(self, offset: int) -> int | None:
        if self.raw_offset <= offset < self.raw_offset + self.raw_size:
            return self.virtual_address + offset - self.raw_offset
        return None


def sections(image: bytes) -> list[Section]:
    pe_offset = struct.unpack_from("<I", image, 0x3C)[0]
    if image[pe_offset : pe_offset + 4] != b"PE\0\0":
        raise ValueError("not a PE image")
    section_count = struct.unpack_from("<H", image, pe_offset + 6)[0]
    optional_size = struct.unpack_from("<H", image, pe_offset + 20)[0]
    table = pe_offset + 24 + optional_size
    result = []
    for index in range(section_count):
        entry = table + index * 40
        name = image[entry : entry + 8].rstrip(b"\0").decode("ascii")
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from(
            "<IIII", image, entry + 8
        )
        result.append(
            Section(name, virtual_address, virtual_size, raw_offset, raw_size)
        )
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("text")
    args = parser.parse_args()

    image = args.image.read_bytes()
    pe_sections = sections(image)
    needle = args.text.encode("ascii")
    positions = []
    start = 0
    while (position := image.find(needle, start)) >= 0:
        positions.append(position)
        start = position + 1
    if not positions:
        raise SystemExit("string not found")

    text_section = next(section for section in pe_sections if section.name == ".text")
    text_start = text_section.raw_offset
    text_end = text_start + text_section.raw_size
    for position in positions:
        target_rva = next(
            rva
            for section in pe_sections
            if (rva := section.raw_to_rva(position)) is not None
        )
        print(f"string raw=0x{position:x} rva=0x{target_rva:x}")
        for instruction in range(text_start, text_end - 7):
            # REX.W + LEA r64,[RIP+disp32]. ModRM must use mod=00,r/m=101.
            if image[instruction] not in range(0x48, 0x50):
                continue
            if image[instruction + 1] != 0x8D:
                continue
            if image[instruction + 2] & 0xC7 != 0x05:
                continue
            instruction_rva = text_section.virtual_address + instruction - text_start
            displacement = struct.unpack_from("<i", image, instruction + 3)[0]
            if instruction_rva + 7 + displacement == target_rva:
                print(
                    f"  lea-xref raw=0x{instruction:x} rva=0x{instruction_rva:x}"
                )


if __name__ == "__main__":
    main()
