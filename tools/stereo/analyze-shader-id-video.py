#!/usr/bin/env python3
"""Rank shader-ID colours observed in moving pixels of a mirror recording."""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
from pathlib import Path

import numpy as np


def srgb_encode(linear: np.ndarray) -> np.ndarray:
    return np.where(
        linear <= 0.0031308,
        linear * 12.92,
        1.055 * np.power(linear, 1.0 / 2.4) - 0.055,
    )


def video_size(ffprobe: str, video: Path) -> tuple[int, int]:
    result = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "json",
            str(video),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    stream = json.loads(result.stdout)["streams"][0]
    return int(stream["width"]), int(stream["height"])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    parser.add_argument("--fps", type=int, default=15)
    parser.add_argument("--top", type=int, default=20)
    args = parser.parse_args()

    with args.manifest.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    expected_linear = np.array(
        [[float(row["red"]), float(row["green"]), float(row["blue"])] for row in rows],
        dtype=np.float32,
    )
    expected = srgb_encode(expected_linear)
    expected /= np.maximum(expected.sum(axis=1, keepdims=True), 1.0e-6)

    width, height = video_size(args.ffprobe, args.video)
    frame_bytes = width * height * 3
    process = subprocess.Popen(
        [
            args.ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(args.video),
            "-vf",
            f"fps={args.fps}",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-",
        ],
        stdout=subprocess.PIPE,
    )
    assert process.stdout is not None

    scores = np.zeros(len(rows), dtype=np.float64)
    pixels = np.zeros(len(rows), dtype=np.int64)
    previous: np.ndarray | None = None
    frame_count = 0
    while True:
        payload = process.stdout.read(frame_bytes)
        if len(payload) != frame_bytes:
            break
        current = np.frombuffer(payload, dtype=np.uint8).reshape(height, width, 3)
        if previous is not None:
            difference = np.max(
                np.abs(current.astype(np.int16) - previous.astype(np.int16)), axis=2
            )
            maximum = current.max(axis=2)
            minimum = current.min(axis=2)
            mask = (difference >= 16) & ((maximum - minimum) >= 45) & (maximum >= 70)
            mask[:80, :] = False
            mask[:, width - 260 :] = False
            moving = current[mask].astype(np.float32) / 255.0
            strength = difference[mask].astype(np.float32)
            if moving.shape[0] > 60_000:
                order = np.argpartition(strength, -60_000)[-60_000:]
                moving = moving[order]
                strength = strength[order]
            moving /= np.maximum(moving.sum(axis=1, keepdims=True), 1.0e-6)
            for start in range(0, moving.shape[0], 4096):
                sample = moving[start : start + 4096]
                weight = strength[start : start + 4096]
                distances = np.sum(
                    (sample[:, None, :] - expected[None, :, :]) ** 2, axis=2
                )
                nearest = np.argmin(distances, axis=1)
                nearest_distance = distances[np.arange(len(sample)), nearest]
                accepted = nearest_distance <= 0.004
                np.add.at(pixels, nearest[accepted], 1)
                np.add.at(scores, nearest[accepted], weight[accepted])
        previous = current.copy()
        frame_count += 1

    return_code = process.wait()
    if return_code != 0:
        raise RuntimeError(f"ffmpeg exited with {return_code}")

    ranking = np.argsort(scores)[::-1]
    print(f"frames={frame_count} size={width}x{height}")
    print("rank\tindex\thash\trgb\tpixels\tscore")
    for rank, candidate in enumerate(ranking[: args.top], start=1):
        row = rows[int(candidate)]
        print(
            f"{rank}\t{row['index']}\t{row['hash']}\t"
            f"{row['red']},{row['green']},{row['blue']}\t"
            f"{pixels[candidate]}\t{scores[candidate]:.0f}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
