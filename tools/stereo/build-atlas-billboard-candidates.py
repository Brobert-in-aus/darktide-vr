#!/usr/bin/env python3
"""Build and strictly validate stock/cylindrical atlas display candidates offline."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


# Exact captured display families only; atlas-generation/ribbon shaders excluded.
ORIGINALS = {
    'c403cfbf17d9fc49': 'fc41250d146b7dd703b0f53ffe57b718175f555d5c6ddf51856769e63638b82e',
    'e18a274cd89282e8': 'ee185f27bd26e76796b0b0c62963264ba5c93a098643c8c4eafaf3e0e27d8b84',
    'fe64037664924d52': 'a14700b2ad887ac3b0532b5b8276147454f2f9396d679a3394bafaa367efe874',
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dxc', type=Path, required=True)
    parser.add_argument('--original-directory', type=Path, required=True)
    parser.add_argument('--native-capture', type=Path, required=True)
    parser.add_argument('--reflection-library', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source_root = Path(__file__).resolve().parent
    if args.output.exists():
        raise FileExistsError('Choose a new output directory; preserve prior or partial build evidence')
    # Verify every original before writing any output or invoking compilers.
    for identity, expected in ORIGINALS.items():
        original = args.original_directory / f'vs-{identity}.bin'
        if sha256(original) != expected:
            raise ValueError(f'Captured display shader hash mismatch: {original}')
    # Claim the destination exclusively. A competing run can create it after
    # the early check while originals are being verified; never share outputs.
    args.output.mkdir(parents=True, exist_ok=False)
    validation = [sys.executable, str(source_root / 'test-shader-interface.py'),
                  '--native-capture', str(args.native_capture),
                  '--reflection-library', str(args.reflection_library),
                  '--output', str(args.output / 'interfaces.json')]
    records = []
    for identity in ORIGINALS:
        source = source_root / f'atlas-display-{identity}.vs.hlsl'
        original = args.original_directory / f'vs-{identity}.bin'
        for profile, cylindrical in [('stock', 0), ('cylindrical', 1)]:
            # Deliberately distinct from the runtime's vs-HASH.dxil filename.
            output = args.output / f'vs-{identity}.{profile}.dxil'
            subprocess.run([str(args.dxc), '-T', 'vs_6_0', '-E', 'main',
                            '-D', f'DTVR_ATLAS_CYLINDRICAL={cylindrical}',
                            '-Fo', str(output), str(source)], check=True)
            validation += ['--pair', str(original), str(output)]
            records.append(dict(identity=identity, profile=profile,
                                source_sha256=sha256(source),
                                shader_sha256=sha256(output)))
    # No success receipt is written until the actual native gate accepts all six.
    subprocess.run(validation, check=True)
    (args.output / 'build.json').write_text(json.dumps(dict(
        schema_version=1, deployed=False, smoke_owner_identified=False,
        authored_spin_preserved=True, interface_compatible=True,
        numerical_equivalence_verified=False, worn_acceptance=False,
        dxc_sha256=sha256(args.dxc),
        basis_sha256=sha256(source_root / 'billboard-cylindrical-basis.hlsli'),
        candidates=records), indent=2) + '\n', encoding='utf-8')
    print(f'Built six interface-compatible offline candidates: {args.output}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
