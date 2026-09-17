#!/usr/bin/env python3
"""Compare rotating shared-eye captures with binocular culling on and off.

The offline benchmark performs a pure 360-degree yaw every 20 seconds. Capture
process startup makes two runs land at slightly different headings, so direct
pixel subtraction is not meaningful. This tool derives each frame's benchmark
phase from its modification time, pairs nearby headings, then refines a small
camera-space yaw warp before comparing the outer and central image regions.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image


@dataclass(frozen=True)
class Capture:
    sample: str
    path: Path
    phase_seconds: float


def parse_time(value: str) -> datetime:
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        raise argparse.ArgumentTypeError("benchmark times must include a UTC offset")
    return parsed


def captures(root: Path, eye: str, benchmark_start: datetime) -> list[Capture]:
    found: list[Capture] = []
    for path in sorted(root.glob(f"s*/*-{eye}.ppm")):
        captured = datetime.fromtimestamp(path.stat().st_mtime, benchmark_start.tzinfo)
        elapsed = (captured - benchmark_start).total_seconds()
        found.append(Capture(path.parent.name, path, elapsed % 20.0))
    if not found:
        raise SystemExit(f"No {eye}-eye PPM captures found below {root}")
    return found


def circular_delta_seconds(first: float, second: float) -> float:
    return (second - first + 10.0) % 20.0 - 10.0


def load_rgb(path: Path, size: tuple[int, int]) -> np.ndarray:
    """The image at `path`, refusing a size this run was not set up for.

    It used to resize whatever it was given. That mattered once Virtual
    Desktop's FOV tangent came into use: at 90 per cent an eye is 1908x2076
    rather than 2112x2304, so a capture squashed to the assumed 264x288 has
    the wrong aspect and is then warped with the 100 per cent half-angles
    (--horizontal-half-fov / --vertical-half-fov, which default to the
    2112-wide eye). Every number printed was wrong and nothing said so, which
    is the failure this whole day has been about. Pass --width/--height to
    match the capture, and scale the half-angles by width / 2112.
    """
    with Image.open(path) as source:
        if source.size != tuple(size):
            raise SystemExit(
                f"{path.name} is {source.size[0]}x{source.size[1]}, not "
                f"{size[0]}x{size[1]}. Pass --width/--height for this capture "
                f"and scale the half field of view by width / 2112 "
                f"(Virtual Desktop's FOV tangent changes both)."
            )
        converted = source.convert("RGB")
    return np.asarray(converted, dtype=np.float32)


def yaw_warp(
    source: np.ndarray,
    relative_yaw: float,
    horizontal_half_fov: float,
    vertical_half_fov: float,
) -> tuple[np.ndarray, np.ndarray]:
    """Project source-camera pixels into a target camera separated only by yaw."""
    height, width = source.shape[:2]
    x = (2.0 * (np.arange(width, dtype=np.float32) + 0.5) / width - 1.0)
    y = (1.0 - 2.0 * (np.arange(height, dtype=np.float32) + 0.5) / height)
    ray_x, ray_y = np.meshgrid(x * math.tan(horizontal_half_fov),
                              y * math.tan(vertical_half_fov))
    cosine = math.cos(relative_yaw)
    sine = math.sin(relative_yaw)
    source_x = cosine * ray_x + sine
    source_z = -sine * ray_x + cosine
    source_y = ray_y
    projected_x = source_x / source_z / math.tan(horizontal_half_fov)
    projected_y = source_y / source_z / math.tan(vertical_half_fov)
    pixel_x = (projected_x + 1.0) * 0.5 * width - 0.5
    pixel_y = (1.0 - projected_y) * 0.5 * height - 0.5
    valid = (
        (source_z > 0.0)
        & (pixel_x >= 0.0)
        & (pixel_x <= width - 1.001)
        & (pixel_y >= 0.0)
        & (pixel_y <= height - 1.001)
    )
    x0 = np.clip(np.floor(pixel_x).astype(np.int32), 0, width - 1)
    y0 = np.clip(np.floor(pixel_y).astype(np.int32), 0, height - 1)
    x1 = np.clip(x0 + 1, 0, width - 1)
    y1 = np.clip(y0 + 1, 0, height - 1)
    wx = (pixel_x - x0)[..., None]
    wy = (pixel_y - y0)[..., None]
    top = source[y0, x0] * (1.0 - wx) + source[y0, x1] * wx
    bottom = source[y1, x0] * (1.0 - wx) + source[y1, x1] * wx
    return top * (1.0 - wy) + bottom * wy, valid


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def comparison_masks(height: int, width: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    yy, xx = np.mgrid[0:height, 0:width]
    unit_x = (xx + 0.5) / width
    unit_y = (yy + 0.5) / height
    ui = ((unit_x > 0.68) & (unit_y < 0.19)) | ((unit_x < 0.24) & (unit_y > 0.89))
    vertical = (unit_y > 0.08) & (unit_y < 0.89) & ~ui
    outer = vertical & ((unit_x < 0.16) | (unit_x > 0.84))
    center = vertical & (unit_x > 0.25) & (unit_x < 0.75)
    alignment = vertical & (unit_x > 0.16) & (unit_x < 0.68)
    return alignment, outer, center


def normalized_correlation(first: np.ndarray, second: np.ndarray, mask: np.ndarray) -> float:
    first_values = first[mask]
    second_values = second[mask]
    if first_values.size < 100 or first_values.std() < 1e-5 or second_values.std() < 1e-5:
        return -1.0
    first_values = (first_values - first_values.mean()) / first_values.std()
    second_values = (second_values - second_values.mean()) / second_values.std()
    return float(np.mean(first_values * second_values))


def fit_center_affine(target: np.ndarray, source: np.ndarray, mask: np.ndarray) -> np.ndarray:
    adjusted = source.copy()
    for channel in range(3):
        x = source[..., channel][mask].astype(np.float64)
        y = target[..., channel][mask].astype(np.float64)
        design = np.column_stack((x, np.ones_like(x)))
        gain, bias = np.linalg.lstsq(design, y, rcond=None)[0]
        adjusted[..., channel] = source[..., channel] * gain + bias
    return np.clip(adjusted, 0.0, 255.0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("enabled_root", type=Path)
    parser.add_argument("disabled_root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--enabled-start", type=parse_time, required=True)
    parser.add_argument("--disabled-start", type=parse_time, required=True)
    parser.add_argument("--width", type=int, default=264)
    parser.add_argument("--height", type=int, default=288)
    parser.add_argument("--horizontal-half-fov", type=float, default=0.777324)
    parser.add_argument("--vertical-half-fov", type=float, default=0.820800)
    parser.add_argument("--max-pairs", type=int, default=21)
    parser.add_argument("--minimum-correlation", type=float, default=0.65)
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    alignment_mask, outer_mask, center_mask = comparison_masks(args.height, args.width)
    records: list[dict[str, object]] = []
    for eye in ("left", "right"):
        enabled = captures(args.enabled_root, eye, args.enabled_start)[: args.max_pairs]
        disabled = captures(args.disabled_root, eye, args.disabled_start)
        for target_capture in enabled:
            source_capture = min(
                disabled,
                key=lambda item: abs(circular_delta_seconds(
                    target_capture.phase_seconds, item.phase_seconds
                )),
            )
            phase_delta = circular_delta_seconds(
                target_capture.phase_seconds, source_capture.phase_seconds
            )
            target = load_rgb(target_capture.path, (args.width, args.height))
            source = load_rgb(source_capture.path, (args.width, args.height))
            target_luma = luma(target)
            best: tuple[float, float, np.ndarray, np.ndarray] | None = None
            # Search both yaw conventions. The benchmark phase supplies the
            # close frame pair; this small absolute range resolves which
            # camera-space sign the engine's quaternion convention produces.
            for candidate in np.linspace(-0.25, 0.25, 51):
                yaw = float(candidate)
                warped, valid = yaw_warp(
                    source, yaw, args.horizontal_half_fov, args.vertical_half_fov
                )
                score = normalized_correlation(target_luma, luma(warped),
                                               valid & alignment_mask)
                if best is None or score > best[0]:
                    best = (score, yaw, warped, valid)
            assert best is not None
            score, yaw, warped, valid = best
            center_valid = valid & center_mask
            outer_valid = valid & outer_mask
            adjusted = fit_center_affine(target, warped, center_valid)
            residual = luma(target) - luma(adjusted)
            record: dict[str, object] = {
                "eye": eye,
                "enabled_sample": target_capture.sample,
                "disabled_sample": source_capture.sample,
                "enabled_phase_seconds": target_capture.phase_seconds,
                "disabled_phase_seconds": source_capture.phase_seconds,
                "phase_delta_seconds": phase_delta,
                "refined_relative_yaw_degrees": math.degrees(yaw),
                "alignment_correlation": score,
                "outer_mean_abs_luma": float(np.mean(np.abs(residual[outer_valid]))),
                "center_mean_abs_luma": float(np.mean(np.abs(residual[center_valid]))),
                "outer_disabled_darker_mean": float(np.mean(residual[outer_valid])),
                "center_disabled_darker_mean": float(np.mean(residual[center_valid])),
                "outer_disabled_darker_20_percent": float(
                    np.mean(residual[outer_valid] > 20.0) * 100.0
                ),
                "center_disabled_darker_20_percent": float(
                    np.mean(residual[center_valid] > 20.0) * 100.0
                ),
            }
            records.append(record)

    accepted = [
        row for row in records
        if float(row["alignment_correlation"]) >= args.minimum_correlation
    ]
    if not accepted:
        maximum = max(float(row["alignment_correlation"]) for row in records)
        raise SystemExit(
            "No phase pair reached the "
            f"{args.minimum_correlation:.2f} alignment-correlation gate; "
            f"maximum={maximum:.4f}"
        )

    def mean(name: str) -> float:
        return float(np.mean([float(row[name]) for row in accepted]))

    summary = {
        "enabled_root": str(args.enabled_root.resolve()),
        "disabled_root": str(args.disabled_root.resolve()),
        "image_size": [args.width, args.height],
        "analyzed_pairs": len(records),
        "accepted_pairs": len(accepted),
        "minimum_alignment_correlation": args.minimum_correlation,
        "mean_alignment_correlation": mean("alignment_correlation"),
        "outer_mean_abs_luma": mean("outer_mean_abs_luma"),
        "center_mean_abs_luma": mean("center_mean_abs_luma"),
        "outer_disabled_darker_mean": mean("outer_disabled_darker_mean"),
        "center_disabled_darker_mean": mean("center_disabled_darker_mean"),
        "outer_disabled_darker_20_percent": mean("outer_disabled_darker_20_percent"),
        "center_disabled_darker_20_percent": mean("center_disabled_darker_20_percent"),
        "interpretation": (
            "Positive disabled_darker values mean the disabled-cull image was darker "
            "after center-region affine exposure normalization."
        ),
    }
    payload = {"summary": summary, "pairs": records}
    metrics_path = args.output / "metrics.json"
    metrics_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
