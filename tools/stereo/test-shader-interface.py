#!/usr/bin/env python3
"""Check candidate bytecode with the actual native substitution gate, offline."""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-capture', type=Path, required=True)
    parser.add_argument('--reflection-library', type=Path, required=True)
    parser.add_argument('--pair', nargs=2, type=Path, action='append', required=True,
                        metavar=('ORIGINAL', 'CANDIDATE'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fixture = Path(tempfile.mkdtemp(prefix='shader-interface-', dir=args.output.parent)).resolve()
    # Load only an isolated copy; leave the running game and installed DLLs alone.
    native = fixture / 'darktidevr_native_capture.dll'
    reflection = fixture / 'dxcompiler.dll'
    shutil.copyfile(args.native_capture, native)
    shutil.copyfile(args.reflection_library, reflection)
    os.environ['DARKTIDEVR_TEST_TRANSPORTS'] = '1'
    library = ctypes.WinDLL(str(native))
    validate = library.dtvr_validate_shader_interface
    validate.argtypes = (ctypes.c_void_p, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_uint64)
    validate.restype = ctypes.c_int
    records = []
    for original, candidate in args.pair:
        buffers = []
        sizes = []
        hashes = []
        for path in (original, candidate):
            if not 0 < path.stat().st_size <= 64 * 1024 * 1024:
                raise ValueError(f'Invalid shader byte count: {path}')
            data = path.read_bytes()
            buffers.append(ctypes.create_string_buffer(data))
            sizes.append(len(data))
            hashes.append(hashlib.sha256(data).hexdigest())
        result = validate(buffers[0], sizes[0], buffers[1], sizes[1])
        record = dict(original=str(original.resolve()), candidate=str(candidate.resolve()),
                      original_sha256=hashes[0], candidate_sha256=hashes[1], result=result,
                      compatible=result == 0)
        records.append(record)
        print(f'shader_interface={"pass" if result == 0 else "fail"} '
              f'code={result} candidate={candidate.name}')
    args.output.write_text(json.dumps(dict(
        schema_version=1, fixture=str(fixture), game_started=False, hooks_installed=False,
        native_sha256=hashlib.sha256(native.read_bytes()).hexdigest(),
        reflection_sha256=hashlib.sha256(reflection.read_bytes()).hexdigest(), pairs=records),
        indent=2) + '\n', encoding='utf-8')
    return 0 if all(record['compatible'] for record in records) else 1


if __name__ == '__main__':
    raise SystemExit(main())
