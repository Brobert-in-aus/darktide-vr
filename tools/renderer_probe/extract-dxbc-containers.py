#!/usr/bin/env python3
"""Extract embedded DXBC/DXIL containers from Stingray shader groups."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from collections.abc import Iterator
from pathlib import Path


def containers(data: bytes) -> Iterator[tuple[int, bytes]]:
    offset = 0
    while True:
        offset = data.find(b"DXBC", offset)
        if offset < 0:
            return
        # DXBC header: magic, 16-byte checksum, version, total size, chunks.
        if offset + 32 <= len(data):
            total_size = struct.unpack_from("<I", data, offset + 24)[0]
            chunk_count = struct.unpack_from("<I", data, offset + 28)[0]
            header_size = 32 + chunk_count * 4
            header_valid = (
                chunk_count <= 128
                and total_size >= header_size
                and offset + total_size <= len(data)
            )
            if header_valid:
                for index in range(chunk_count):
                    chunk_offset = struct.unpack_from(
                        "<I", data, offset + 32 + index * 4
                    )[0]
                    if chunk_offset + 8 > total_size:
                        header_valid = False
                        break
                    chunk_size = struct.unpack_from(
                        "<I", data, offset + chunk_offset + 4
                    )[0]
                    if chunk_size > total_size - chunk_offset - 8:
                        header_valid = False
                        break
            if header_valid:
                yield offset, data[offset : offset + total_size]
        offset += 4


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    if not args.input.is_dir():
        parser.error(f"input is not a directory: {args.input}")
    args.output.mkdir(parents=True, exist_ok=True)
    records = []
    seen = set()
    for source in sorted(path for path in args.input.iterdir() if path.is_file()):
        for offset, container in containers(source.read_bytes()):
            digest = hashlib.sha256(container).hexdigest()
            if digest in seen:
                continue
            seen.add(digest)
            output_name = f"{source.stem}-{offset:08x}-{digest[:12]}.dxbc"
            (args.output / output_name).write_bytes(container)
            records.append(
                {
                    "source": source.name,
                    "offset": offset,
                    "size": len(container),
                    "sha256": digest,
                    "output": output_name,
                }
            )

    (args.output / "manifest.json").write_text(
        json.dumps(records, indent=2) + "\n", encoding="utf-8"
    )
    print(f"extracted={len(records)}")


if __name__ == "__main__":
    main()
