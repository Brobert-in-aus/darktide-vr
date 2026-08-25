#!/usr/bin/env python3
"""Convert two eye captures to PNG and emit quantitative/visual differences."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageEnhance


def best_translation(
    left: np.ndarray,
    right: np.ndarray,
    bounds: tuple[float, float, float, float],
    maximum_x: int = 32,
    maximum_y: int = 8,
) -> dict[str, float | int]:
    """Estimate a region's right-to-left translation using normalized correlation."""
    height, width = left.shape
    x0, y0, x1, y1 = bounds
    x0, x1 = int(x0 * width), int(x1 * width)
    y0, y1 = int(y0 * height), int(y1 * height)
    left_region = left[y0:y1:2, x0:x1:2].astype(np.float64)
    best_score = -2.0
    best_x = 0
    best_y = 0
    for shift_y in range(-maximum_y, maximum_y + 1):
        for shift_x in range(-maximum_x, maximum_x + 1):
            right_region = right[
                y0 + shift_y : y1 + shift_y : 2,
                x0 + shift_x : x1 + shift_x : 2,
            ].astype(np.float64)
            if right_region.shape != left_region.shape:
                continue
            left_zeroed = left_region - left_region.mean()
            right_zeroed = right_region - right_region.mean()
            denominator = np.sqrt(
                np.square(left_zeroed).sum() * np.square(right_zeroed).sum()
            )
            if denominator == 0:
                continue
            score = float((left_zeroed * right_zeroed).sum() / denominator)
            if score > best_score:
                best_score = score
                best_x = shift_x
                best_y = shift_y
    return {
        "right_sample_offset_x_pixels": best_x,
        "right_sample_offset_y_pixels": best_y,
        "normalized_correlation": best_score,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("left", type=Path)
    parser.add_argument("right", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()

    arguments.output.mkdir(parents=True, exist_ok=True)
    left_image = Image.open(arguments.left).convert("RGB")
    right_image = Image.open(arguments.right).convert("RGB")
    if left_image.size != right_image.size:
        raise ValueError(f"Eye sizes differ: {left_image.size} vs {right_image.size}")

    left = np.asarray(left_image, dtype=np.int16)
    right = np.asarray(right_image, dtype=np.int16)
    left_luma = np.asarray(left_image.convert("L"), dtype=np.float32)
    right_luma = np.asarray(right_image.convert("L"), dtype=np.float32)
    absolute = np.abs(left - right)
    changed = np.any(absolute > 2, axis=2)
    metrics = {
        "width": left_image.width,
        "height": left_image.height,
        "mean_absolute_error": float(absolute.mean()),
        "root_mean_square_error": float(
            np.sqrt(np.mean(np.square(left - right, dtype=np.float64)))
        ),
        "changed_pixel_fraction_threshold_2": float(changed.mean()),
        "maximum_channel_difference": int(absolute.max()),
        "identical": bool(np.array_equal(left, right)),
        "translation_estimates": {
            "distant_upper_scene": best_translation(
                left_luma, right_luma, (0.08, 0.05, 0.92, 0.30)
            ),
            "near_character": best_translation(
                left_luma, right_luma, (0.31, 0.32, 0.47, 0.59)
            ),
            "foreground_floor": best_translation(
                left_luma, right_luma, (0.05, 0.67, 0.95, 0.95)
            ),
        },
    }

    left_path = arguments.output / "left.png"
    right_path = arguments.output / "right.png"
    diff_path = arguments.output / "diff-amplified.png"
    overlay_path = arguments.output / "red-cyan-overlay.png"
    metrics_path = arguments.output / "metrics.json"
    left_image.save(left_path)
    right_image.save(right_path)
    difference = ImageChops.difference(left_image, right_image)
    ImageEnhance.Contrast(difference).enhance(4.0).save(diff_path)

    left_array = np.asarray(left_image, dtype=np.uint8)
    right_array = np.asarray(right_image, dtype=np.uint8)
    overlay = np.empty_like(left_array)
    overlay[:, :, 0] = left_array[:, :, 0]
    overlay[:, :, 1] = right_array[:, :, 1]
    overlay[:, :, 2] = right_array[:, :, 2]
    Image.fromarray(overlay, "RGB").save(overlay_path)
    metrics_path.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metrics, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
