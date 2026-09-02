#!/usr/bin/env python3
"""Measure edge-specific luminance changes during the offline yaw benchmark.

Adjacent captures see mostly the same static scene from a slightly advanced
yaw. This tool perspective-warps each previous frame into the next frame,
normalizes exposure from the stable centre, and compares signed residuals in
the surviving outer strips. Running the same analysis with shared binocular
culling enabled and disabled provides a control for temporal scene noise.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image


@dataclass(frozen=True)
class Frame:
    sample: str
    path: Path
    timestamp: float


def frames(root: Path, eye: str) -> list[Frame]:
    result = [
        Frame(path.parent.name, path, path.stat().st_mtime)
        for path in root.glob(f"s*/*-{eye}.ppm")
    ]
    result.sort(key=lambda frame: frame.timestamp)
    if len(result) < 2:
        raise SystemExit(f"Need at least two {eye}-eye captures below {root}")
    return result


def load_rgb(path: Path, size: tuple[int, int]) -> np.ndarray:
    with Image.open(path) as source:
        resized = source.convert("RGB").resize(size, Image.Resampling.LANCZOS)
    return np.asarray(resized, dtype=np.float32)


def yaw_warp(
    source: np.ndarray,
    relative_yaw: float,
    horizontal_half_fov: float,
    vertical_half_fov: float,
) -> tuple[np.ndarray, np.ndarray]:
    height, width = source.shape[:2]
    x = 2.0 * (np.arange(width, dtype=np.float32) + 0.5) / width - 1.0
    y = 1.0 - 2.0 * (np.arange(height, dtype=np.float32) + 0.5) / height
    ray_x, ray_y = np.meshgrid(
        x * math.tan(horizontal_half_fov),
        y * math.tan(vertical_half_fov),
    )
    cosine = math.cos(relative_yaw)
    sine = math.sin(relative_yaw)
    source_x = cosine * ray_x + sine
    source_z = -sine * ray_x + cosine
    projected_x = source_x / source_z / math.tan(horizontal_half_fov)
    projected_y = ray_y / source_z / math.tan(vertical_half_fov)
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


def masks(height: int, width: int) -> dict[str, np.ndarray]:
    yy, xx = np.mgrid[0:height, 0:width]
    unit_x = (xx + 0.5) / width
    unit_y = (yy + 0.5) / height
    ui = ((unit_x > 0.68) & (unit_y < 0.19)) | (
        (unit_x < 0.24) & (unit_y > 0.89)
    )
    vertical = (unit_y > 0.08) & (unit_y < 0.89) & ~ui
    return {
        "alignment": vertical & (unit_x > 0.18) & (unit_x < 0.82),
        "center": vertical & (unit_x > 0.30) & (unit_x < 0.70),
        "left": vertical & (unit_x < 0.16),
        "right": vertical & (unit_x > 0.84),
    }


def correlation(first: np.ndarray, second: np.ndarray, mask: np.ndarray) -> float:
    first_values = first[mask]
    second_values = second[mask]
    if (
        first_values.size < 100
        or first_values.std() < 1e-5
        or second_values.std() < 1e-5
    ):
        return -1.0
    first_values = (first_values - first_values.mean()) / first_values.std()
    second_values = (second_values - second_values.mean()) / second_values.std()
    return float(np.mean(first_values * second_values))


def fit_affine(target: np.ndarray, source: np.ndarray, mask: np.ndarray) -> np.ndarray:
    adjusted = source.copy()
    for channel in range(3):
        x = source[..., channel][mask].astype(np.float64)
        y = target[..., channel][mask].astype(np.float64)
        design = np.column_stack((x, np.ones_like(x)))
        gain, bias = np.linalg.lstsq(design, y, rcond=None)[0]
        adjusted[..., channel] = source[..., channel] * gain + bias
    return np.clip(adjusted, 0.0, 255.0)


def analyze_run(
    root: Path,
    label: str,
    width: int,
    height: int,
    horizontal_half_fov: float,
    vertical_half_fov: float,
    revolution_seconds: float,
) -> list[dict[str, object]]:
    region_masks = masks(height, width)
    records: list[dict[str, object]] = []
    for eye in ("left", "right"):
        sequence = frames(root, eye)
        previous = load_rgb(sequence[0].path, (width, height))
        for prior_frame, current_frame in zip(sequence, sequence[1:]):
            current = load_rgb(current_frame.path, (width, height))
            delta_seconds = current_frame.timestamp - prior_frame.timestamp
            nominal_yaw = 2.0 * math.pi * delta_seconds / revolution_seconds
            best: tuple[float, float, np.ndarray, np.ndarray] | None = None
            for sign in (-1.0, 1.0):
                for correction in np.linspace(-0.10, 0.10, 21):
                    candidate = sign * nominal_yaw + float(correction)
                    warped, valid = yaw_warp(
                        previous,
                        candidate,
                        horizontal_half_fov,
                        vertical_half_fov,
                    )
                    score = correlation(
                        luma(current),
                        luma(warped),
                        valid & region_masks["alignment"],
                    )
                    if best is None or score > best[0]:
                        best = (score, candidate, warped, valid)
            assert best is not None
            score, yaw, warped, valid = best
            center_valid = valid & region_masks["center"]
            adjusted = fit_affine(current, warped, center_valid)
            residual = luma(current) - luma(adjusted)
            record: dict[str, object] = {
                "run": label,
                "eye": eye,
                "prior_sample": prior_frame.sample,
                "sample": current_frame.sample,
                "delta_seconds": delta_seconds,
                "relative_yaw_degrees": math.degrees(yaw),
                "alignment_correlation": score,
            }
            for region in ("left", "right", "center"):
                selected = valid & region_masks[region]
                values = residual[selected]
                record[f"{region}_pixels"] = int(values.size)
                record[f"{region}_mean_signed_luma"] = (
                    float(np.mean(values)) if values.size else None
                )
                record[f"{region}_mean_abs_luma"] = (
                    float(np.mean(np.abs(values))) if values.size else None
                )
                record[f"{region}_darker_20_percent"] = (
                    float(np.mean(values < -20.0) * 100.0) if values.size else None
                )
            records.append(record)
            previous = current
    return records


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("enabled_root", type=Path)
    parser.add_argument("disabled_root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--width", type=int, default=264)
    parser.add_argument("--height", type=int, default=288)
    parser.add_argument("--horizontal-half-fov", type=float, default=0.777324)
    parser.add_argument("--vertical-half-fov", type=float, default=0.820800)
    parser.add_argument("--revolution-seconds", type=float, default=20.0)
    parser.add_argument("--minimum-correlation", type=float, default=0.60)
    args = parser.parse_args()

    records = analyze_run(
        args.enabled_root,
        "enabled",
        args.width,
        args.height,
        args.horizontal_half_fov,
        args.vertical_half_fov,
        args.revolution_seconds,
    ) + analyze_run(
        args.disabled_root,
        "disabled",
        args.width,
        args.height,
        args.horizontal_half_fov,
        args.vertical_half_fov,
        args.revolution_seconds,
    )
    accepted = [
        row
        for row in records
        if float(row["alignment_correlation"]) >= args.minimum_correlation
    ]
    if not accepted:
        raise SystemExit("No adjacent frame pair passed the alignment gate")

    summary: dict[str, object] = {
        "minimum_alignment_correlation": args.minimum_correlation,
        "analyzed_pairs": len(records),
        "accepted_pairs": len(accepted),
        "runs": {},
        "interpretation": (
            "Negative signed luma and larger darker_20 percentages mean the "
            "current registered region became darker than the preceding yaw frame."
        ),
        "overlap_note": (
            "The benchmark yaws in one direction, so only the right outer strip "
            "survives the previous-to-current perspective overlap."
        ),
    }
    run_summaries: dict[str, object] = {}
    for label in ("enabled", "disabled"):
        selected = [row for row in accepted if row["run"] == label]
        values: dict[str, object] = {
            "accepted_pairs": len(selected),
            "mean_alignment_correlation": float(
                np.mean([float(row["alignment_correlation"]) for row in selected])
            ),
        }
        for region in ("left", "right"):
            valid_rows = [
                row
                for row in selected
                if row[f"{region}_mean_signed_luma"] is not None
            ]
            values[f"{region}_mean_signed_luma"] = (
                float(
                    np.mean(
                        [
                            float(row[f"{region}_mean_signed_luma"])
                            for row in valid_rows
                        ]
                    )
                )
                if valid_rows
                else None
            )
            values[f"{region}_darker_20_percent"] = (
                float(
                    np.mean(
                        [
                            float(row[f"{region}_darker_20_percent"])
                            for row in valid_rows
                        ]
                    )
                )
                if valid_rows
                else None
            )
            values[f"{region}_median_signed_luma"] = (
                float(
                    np.median(
                        [
                            float(row[f"{region}_mean_signed_luma"])
                            for row in valid_rows
                        ]
                    )
                )
                if valid_rows
                else None
            )
            values[f"{region}_signed_luma_stddev"] = (
                float(
                    np.std(
                        [
                            float(row[f"{region}_mean_signed_luma"])
                            for row in valid_rows
                        ],
                        ddof=1,
                    )
                )
                if len(valid_rows) > 1
                else None
            )
            values[f"{region}_median_darker_20_percent"] = (
                float(
                    np.median(
                        [
                            float(row[f"{region}_darker_20_percent"])
                            for row in valid_rows
                        ]
                    )
                )
                if valid_rows
                else None
            )
        run_summaries[label] = values
    summary["runs"] = run_summaries

    args.output.mkdir(parents=True, exist_ok=True)
    payload = {"summary": summary, "pairs": records}
    (args.output / "metrics.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
