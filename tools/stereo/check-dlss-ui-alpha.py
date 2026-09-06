"""Check a captured UI layer against the same frame's scene and final colour.

Reads the raw 32-bit BMP alpha bytes: many image loaders discard BI_RGB alpha.
This checks composition/coverage, not visual acceptance of generated frames.
"""
import argparse
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image


def read_rgba(path):
    data = Path(path).read_bytes()
    if len(data) < 54 or data[:2] != b"BM":
        raise ValueError("Expected a complete BMP")
    offset = struct.unpack_from("<I", data, 10)[0]
    dib, width, height, planes, bits, compression = struct.unpack_from("<IiiHHI", data, 14)
    if dib != 40 or width <= 0 or height == 0 or planes != 1 or bits != 32 or compression != 0:
        raise ValueError("Expected native readback's uncompressed 32-bit BMP")
    size = width * abs(height) * 4
    if offset < 54 or offset + size > len(data):
        raise ValueError("Truncated BMP pixels")
    pixels = np.frombuffer(data, np.uint8, size, offset).reshape(abs(height), width, 4)
    if height > 0:
        pixels = pixels[::-1]
    return pixels[:, :, [2, 1, 0, 3]].copy()


def compare(scene, final, ui, tolerance=3):
    if scene.shape != final.shape or ui.shape != final.shape or final.shape[-1] != 4:
        raise ValueError("All inputs must have identical RGBA eye extents")
    colour = ui[:, :, :3].astype(np.float32)
    alpha = ui[:, :, 3:4].astype(np.float32) / 255
    composed = colour + (1 - alpha) * scene[:, :, :3].astype(np.float32)
    error = np.abs(composed - final[:, :, :3].astype(np.float32)).max(axis=2)
    changed = np.abs(final[:, :, :3].astype(np.int16) - scene[:, :, :3].astype(np.int16)).max(axis=2) > tolerance
    covered = ui[:, :, 3] > 0
    relevant = changed | covered
    residual = (error > tolerance) & relevant
    missed = changed & ~covered
    # Premultiplied source-over RGBA8 cannot contain RGB greater than coverage.
    invalid_premultiplied = colour.max(axis=2) > ui[:, :, 3].astype(np.float32) + 1
    count = int(relevant.sum())
    report = {
        "extent": [int(final.shape[1]), int(final.shape[0])],
        "changed_pixels": int(changed.sum()),
        "covered_pixels": int(covered.sum()),
        "missed_changed_pixels": int(missed.sum()),
        "invalid_premultiplied_pixels": int(invalid_premultiplied.sum()),
        "relevant_pixels": count,
        "residual_pixels_over_tolerance": int(residual.sum()),
        "residual_fraction_of_relevant": float(residual.sum() / count) if count else None,
        "max_channel_error": float(error.max()),
        "alpha_min": int(ui[:, :, 3].min()),
        "alpha_max": int(ui[:, :, 3].max()),
        "composition_check_pass": bool(changed.any() and covered.any() and (ui[:, :, 3] == 0).any() and
            not invalid_premultiplied.any() and not missed.any() and
            count and residual.sum() / count <= 0.01),
    }
    return report, np.clip(composed, 0, 255).astype(np.uint8), error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stem", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {}
    for eye in ("left", "right"):
        scene, final, ui = [read_rgba(f"{args.stem}-{eye}-{role}.bmp")
                            for role in ("scene", "final", "ui")]
        result, composed, error = compare(scene, final, ui)
        report[eye] = result
        Image.fromarray(ui).save(args.output / f"{eye}-ui.png")
        Image.fromarray(ui[:, :, 3]).save(args.output / f"{eye}-alpha.png")
        Image.fromarray(composed).save(args.output / f"{eye}-recomposed.png")
        Image.fromarray(np.clip(error * 8, 0, 255).astype(np.uint8)).save(
            args.output / f"{eye}-error-x8.png")
    (args.output / "alpha-check.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if all(eye["composition_check_pass"] for eye in report.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
