#!/usr/bin/env python3
"""Measure opaque-magenta particle orientation in extracted diagnostic frames.

The 10x billboard diagnostic produces sparse, bright quads.  This tool avoids
scene-specific feature matching: it segments those pixels, finds connected
components, and reports the doubled-angle mean of elongated components.  A
spherical billboard remains near zero degrees in screen space during headset
roll; a world-up cylindrical billboard follows the rolled world instead.
"""

from __future__ import annotations

import argparse
import csv
import math
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


def component_angles(mask: np.ndarray) -> list[tuple[float, int, float]]:
    height, width = mask.shape
    visited = np.zeros_like(mask, dtype=np.bool_)
    angles: list[tuple[float, int, float]] = []
    for seed_y, seed_x in np.argwhere(mask):
        if visited[seed_y, seed_x]:
            continue
        queue = deque([(int(seed_y), int(seed_x))])
        visited[seed_y, seed_x] = True
        points: list[tuple[int, int]] = []
        while queue:
            y, x = queue.popleft()
            points.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    ny, nx = y + dy, x + dx
                    if (0 <= ny < height and 0 <= nx < width and
                            mask[ny, nx] and not visited[ny, nx]):
                        visited[ny, nx] = True
                        queue.append((ny, nx))
        area = len(points)
        # Large connected magenta islands are overlapping quads; their PCA
        # axis describes the cluster layout, not a billboard. Keep isolated
        # rectangles only.
        if area < 24 or area > 1600:
            continue
        coordinates = np.asarray([(x, y) for y, x in points], dtype=np.float64)
        covariance = np.cov(coordinates, rowvar=False)
        eigenvalues, eigenvectors = np.linalg.eigh(covariance)
        if eigenvalues[0] <= 0:
            continue
        aspect = math.sqrt(float(eigenvalues[1] / eigenvalues[0]))
        if aspect < 1.35:
            continue
        axis = eigenvectors[:, 1]
        angle = math.degrees(math.atan2(float(axis[1]), float(axis[0])))
        while angle >= 90:
            angle -= 180
        while angle < -90:
            angle += 180
        angles.append((angle, area, aspect))
    return angles


def doubled_angle_mean(angles: list[tuple[float, int, float]]) -> float | None:
    if not angles:
        return None
    radians = np.radians([angle * 2 for angle, _, _ in angles])
    weights = np.asarray([area for _, area, _ in angles], dtype=np.float64)
    sine = float(np.average(np.sin(radians), weights=weights))
    cosine = float(np.average(np.cos(radians), weights=weights))
    return math.degrees(math.atan2(sine, cosine)) * 0.5


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("frames", type=Path, help="Directory of ordered PNG frames")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    rows: list[dict[str, object]] = []
    for index, path in enumerate(sorted(args.frames.glob("*.png"))):
        rgb = np.asarray(Image.open(path).convert("RGB"))
        red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
        mask = (red >= 185) & (blue >= 140) & (green <= 125) & (red > green * 1.6)
        angles = component_angles(mask)
        mean = doubled_angle_mean(angles)
        rows.append({
            "frame": index,
            "file": path.name,
            "components": len(angles),
            "mean_axis_degrees": "" if mean is None else f"{mean:.4f}",
            "median_aspect": "" if not angles else f"{np.median([a[2] for a in angles]):.4f}",
        })

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    valid = [float(row["mean_axis_degrees"]) for row in rows
             if row["mean_axis_degrees"] != ""]
    print(f"frames={len(rows)} valid={len(valid)}")
    if valid:
        print(f"axis_min={min(valid):.3f} axis_max={max(valid):.3f} "
              f"axis_span={max(valid) - min(valid):.3f}")
    print(f"output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
