#!/usr/bin/env python3
"""Create deterministic pixel-difference diagnostics for two eye captures."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("left", type=Path)
    parser.add_argument("right", type=Path)
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--threshold", type=int, default=2)
    args = parser.parse_args()

    left = Image.open(args.left).convert("RGB")
    right = Image.open(args.right).convert("RGB")
    if left.size != right.size:
        raise SystemExit(f"Capture sizes differ: {left.size} != {right.size}")

    args.output_directory.mkdir(parents=True, exist_ok=True)
    difference = ImageChops.difference(left, right)
    difference.save(args.output_directory / "difference-raw.png")
    difference.point(lambda value: min(255, value * 8)).save(
        args.output_directory / "difference-amplified-8x.png"
    )

    left_array = np.asarray(left, dtype=np.float64)
    right_array = np.asarray(right, dtype=np.float64)
    comparison_mask = np.ones((left.height, left.width), dtype=bool)
    # The development profile's FPS counter is drawn only in the first region.
    comparison_mask[:80, max(0, left.width - 180) :] = False
    normalized_right = right_array.copy()
    affine_channels = []
    for channel in range(3):
        source = right_array[:, :, channel][comparison_mask]
        target = left_array[:, :, channel][comparison_mask]
        design = np.column_stack((source, np.ones_like(source)))
        gain, bias = np.linalg.lstsq(design, target, rcond=None)[0]
        normalized_right[:, :, channel] = (
            right_array[:, :, channel] * gain + bias
        )
        affine_channels.append({"gain": float(gain), "bias": float(bias)})
    normalized_right = np.clip(normalized_right, 0, 255).astype(np.uint8)
    normalized_image = Image.fromarray(normalized_right, "RGB")
    normalized_image.save(args.output_directory / "right-affine-normalized.png")
    normalized_difference = ImageChops.difference(left, normalized_image)
    normalized_difference.save(
        args.output_directory / "difference-affine-normalized.png"
    )
    normalized_difference.point(lambda value: min(255, value * 8)).save(
        args.output_directory / "difference-affine-normalized-8x.png"
    )

    histogram = difference.histogram()
    channel_pixels = left.width * left.height
    squared_error = 0
    absolute_error = 0
    maximum_error = 0
    changed_channels = 0
    for channel in range(3):
        channel_histogram = histogram[channel * 256 : (channel + 1) * 256]
        changed_channels += sum(channel_histogram[args.threshold + 1 :])
        for value, count in enumerate(channel_histogram):
            absolute_error += value * count
            squared_error += value * value * count
            if count:
                maximum_error = max(maximum_error, value)

    pixel_pairs = list(zip(left.get_flattened_data(), right.get_flattened_data()))
    changed_pixels = sum(
        1
        for left_pixel, right_pixel in pixel_pairs
        if max(abs(a - b) for a, b in zip(left_pixel, right_pixel)) > args.threshold
    )
    mean_absolute_error = absolute_error / (channel_pixels * 3)
    mean_squared_error = squared_error / (channel_pixels * 3)
    psnr = math.inf if mean_squared_error == 0 else 10 * math.log10(255**2 / mean_squared_error)

    normalized_delta = np.abs(left_array - normalized_right.astype(np.float64))
    normalized_pixels = normalized_delta.max(axis=2) > args.threshold
    normalized_changed = int(normalized_pixels[comparison_mask].sum())
    normalized_samples = int(comparison_mask.sum())
    normalized_mae = float(normalized_delta[comparison_mask].mean())
    normalized_mse = float((normalized_delta[comparison_mask] ** 2).mean())
    normalized_psnr = (
        math.inf
        if normalized_mse == 0
        else 10 * math.log10(255**2 / normalized_mse)
    )

    left_luma = left_array.mean(axis=2)
    right_luma = normalized_right.astype(np.float64).mean(axis=2)
    left_edges = np.concatenate(
        (np.diff(left_luma, axis=1).ravel(), np.diff(left_luma, axis=0).ravel())
    )
    right_edges = np.concatenate(
        (np.diff(right_luma, axis=1).ravel(), np.diff(right_luma, axis=0).ravel())
    )
    edge_correlation = float(np.corrcoef(left_edges, right_edges)[0, 1])

    metrics = {
        "size": [left.width, left.height],
        "threshold": args.threshold,
        "changed_pixels": changed_pixels,
        "changed_pixel_percent": changed_pixels * 100 / channel_pixels,
        "changed_channels": changed_channels,
        "mean_absolute_error": mean_absolute_error,
        "mean_squared_error": mean_squared_error,
        "maximum_channel_error": maximum_error,
        "psnr_db": "infinity" if math.isinf(psnr) else psnr,
        "affine_channels": affine_channels,
        "affine_normalized_changed_pixels": normalized_changed,
        "affine_normalized_changed_pixel_percent": (
            normalized_changed * 100 / normalized_samples
        ),
        "affine_normalized_mean_absolute_error": normalized_mae,
        "affine_normalized_psnr_db": (
            "infinity" if math.isinf(normalized_psnr) else normalized_psnr
        ),
        "affine_normalized_edge_correlation": edge_correlation,
    }
    metrics_path = args.output_directory / "metrics.json"
    metrics_path.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metrics, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
