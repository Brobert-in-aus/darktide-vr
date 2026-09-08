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


def coverage_regions(alpha, radius):
    if alpha.ndim != 2 or alpha.dtype != np.uint8 or not alpha.size:
        raise ValueError("Expected a nonempty UI alpha plane")
    if not isinstance(radius, int) or isinstance(radius, bool) or not 0 <= radius <= 64:
        raise ValueError("Near-UI radius must be an integer from 0 to 64 pixels")
    covered = alpha > 0
    nearby = covered
    # Separable box dilation using prefix counts: bounded work per image,
    # without wraparound at image borders or a quadratic radius-sized kernel.
    for axis in (1, 0):
        padding = [(0, 0), (0, 0)]
        padding[axis] = (radius + 1, radius)
        prefix = np.cumsum(np.pad(nearby, padding), axis=axis, dtype=np.int64)
        high, low = [slice(None), slice(None)], [slice(None), slice(None)]
        high[axis], low[axis] = slice(2 * radius + 1, None), slice(None, -2 * radius - 1)
        nearby = prefix[tuple(high)] != prefix[tuple(low)]
    return {"opaque_ui": alpha == 255, "translucent_ui": covered & (alpha < 255),
            "transparent_near_ui": nearby & ~covered, "transparent_far_ui": ~nearby}


def pixel_hash(image, channels):
    """Native FNV-1a order: top-to-bottom RGB(A), excluding row padding."""
    value = 14695981039346656037
    for byte in image[:, :, :channels].tobytes():
        value = ((value ^ byte) * 1099511628211) & 0xffffffffffffffff
    return value


def verify_native_capture(stem, images):
    """Require complete native metadata and content hashes for all six inputs."""
    records = {}
    for line in Path(f"{stem}.log").read_text().splitlines():
        fields = line.split()
        if fields and fields[0] in ("UI_READBACK_MATCH", "UI_READBACK", "UI_READBACK_IMAGE"):
            records.setdefault(fields[0], []).append(dict(field.split("=", 1) for field in fields[1:]))
    owners = records.get("UI_READBACK_MATCH", [])
    if len(owners) != 1 or owners[0].get("owned_ui") != "1" or int(owners[0].get("pose", "0")) <= 0:
        raise ValueError("One positive-pose owned UI capture is required")
    for phase in ("staged", "exported"):
        rows = [row for row in records.get("UI_READBACK", []) if row.get("phase") == phase]
        if len(rows) != 1 or rows[0].get("result") != "0x00000000" or rows[0].get("image_checksum") != "rgba_fnv1a64":
            raise ValueError("Complete native RGBA checksum exports are required; legacy logs are unverified")
    rows = records.get("UI_READBACK_IMAGE", [])
    if len(rows) != 6 or set(images) != {f"{eye}-{role}" for eye in ("left", "right") for role in ("scene", "final", "ui")}:
        raise ValueError("Exactly six native image records and inputs are required")
    for role, image in images.items():
        matches = [row for row in rows if row.get("role") == role]
        if len(matches) != 1 or matches[0].get("phase") != "exported":
            raise ValueError(f"Missing or duplicate completed image: {role}")
        row = matches[0]
        if image.dtype != np.uint8 or image.shape != (int(row.get("height", "0")), int(row.get("width", "0")), 4):
            raise ValueError(f"Native image extent mismatch: {role}")
        checksum = int(row.get("rgba_hash", "-1"))
        if not 0 <= checksum < 2**64 or pixel_hash(image, 4) != checksum:
            raise ValueError(f"Native RGBA content mismatch: {role}")
    return {"pose": owners[0]["pose"], "content_evidence": "six_native_rgba_checksums"}


def compare(scene, final, ui, tolerance=3, near_ui_radius=8):
    if any(image.ndim != 3 or image.shape[2] != 4 or not image.size or image.dtype != np.uint8
           for image in (scene, final, ui)) or scene.shape != final.shape or ui.shape != final.shape:
        raise ValueError("All inputs must have identical RGBA eye extents")
    regions = coverage_regions(ui[:, :, 3], near_ui_radius)
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
        "measurement": "premultiplied_source_over_residual",
        "capture_identity_verified": False,
        "visual_acceptance": "unverified",
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
    report["near_ui_radius_pixels"] = near_ui_radius
    report["near_ui_distance"] = "chebyshev"
    report["regions"] = {}
    for name, mask in regions.items():
        pixels = int(mask.sum())
        failures = int((residual & mask).sum())
        report["regions"][name] = {
            "pixels": pixels, "residual_pixels_over_tolerance": failures,
            "residual_fraction": failures / pixels if pixels else None,
            "max_channel_error": float(error[mask].max()) if pixels else None,
        }
    return report, np.clip(composed, 0, 255).astype(np.uint8), error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stem", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--near-ui-radius", type=int, default=8,
                        help="Transparent-pixel neighborhood in capture pixels (0-64; default 8)")
    parser.add_argument("--verify-native", action="store_true",
                        help="Require complete native logs and RGBA hashes for all six images")
    args = parser.parse_args()
    report = {}
    prepared = {}
    inputs = {f"{eye}-{role}": read_rgba(f"{args.stem}-{eye}-{role}.bmp")
              for eye in ("left", "right") for role in ("scene", "final", "ui")}
    identity = verify_native_capture(args.stem, inputs) if args.verify_native else None
    for eye in ("left", "right"):
        scene, final, ui = [inputs[f"{eye}-{role}"]
                            for role in ("scene", "final", "ui")]
        result, composed, error = compare(scene, final, ui, near_ui_radius=args.near_ui_radius)
        if identity:
            result.update(capture_identity_verified=True, capture_identity=identity)
        report[eye] = result
        prepared[eye] = (ui, composed, error)
    # Check both eyes before creating output. A malformed second eye must not
    # leave a new left-eye result beside older evidence from the other eye.
    args.output.mkdir(parents=True, exist_ok=True)
    for eye, (ui, composed, error) in prepared.items():
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
