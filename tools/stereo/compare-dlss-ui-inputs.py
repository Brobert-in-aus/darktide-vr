"""Inspect a one-shot stereo UI readback without modifying its source images."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

parser = argparse.ArgumentParser()
parser.add_argument("stem", type=Path)
parser.add_argument("--output", required=True, type=Path)
args = parser.parse_args()
inputs = [Path(f'{args.stem}-{eye}-{role}.bmp')
          for eye in ('left', 'right') for role in ('scene', 'final')]
for name in ('left-difference-x4.png', 'right-difference-x4.png',
             'comparison.png', 'comparison.json'):
    destination = args.output / name
    for source in inputs:
        if destination.resolve() == source.resolve() or (destination.exists() and
                source.exists() and destination.samefile(source)):
            raise ValueError('Output must not replace a capture input')
images = {}
# Decode and validate both eyes before creating or replacing any report files.
# A malformed second eye must not leave a new left result beside an old report.
for eye in ("left", "right"):
    pair = []
    for role in ("scene", "final"):
        with Image.open(f"{args.stem}-{eye}-{role}.bmp") as source:
            pair.append(source.convert("RGB"))
    scene_image, final_image = pair
    if scene_image.size != final_image.size:
        raise ValueError(f"{eye}: mismatching extents")
    images[eye] = pair
args.output.mkdir(parents=True, exist_ok=True)
report = {}
panels = []
for eye in ("left", "right"):
    scene_image, final_image = images[eye]
    scene = np.asarray(scene_image).astype(np.int16)
    final = np.asarray(final_image).astype(np.int16)
    difference = np.abs(final - scene)
    magnitude = difference.max(axis=2)
    changed = magnitude > 2
    # Bounds need occupied rows/columns, not coordinates for every changed pixel.
    ys = np.flatnonzero(changed.any(axis=1))
    xs = np.flatnonzero(changed.any(axis=0))
    report[eye] = {
        "extent": list(scene_image.size),
        "changed_pixels_over_2": int(changed.sum()),
        "changed_fraction_over_2": float(changed.mean()),
        "mean_absolute_rgb_difference": float(difference.mean()),
        "changed_bounds": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
        if xs.size else None,
    }
    # Difference is evidence of composition, not a recovered alpha mask.
    diff_image = Image.fromarray(np.minimum(difference * 4, 255).astype(np.uint8))
    diff_image.save(args.output / f"{eye}-difference-x4.png")
    for title, image in (("scene input", scene_image), ("final input", final_image),
                         ("absolute difference x4", diff_image)):
        image.thumbnail((660, 700))
        panel = Image.new("RGB", (680, 740), "#181b20")
        ImageDraw.Draw(panel).text((12, 8), f"{eye}: {title}", fill="white")
        panel.paste(image, ((680-image.width)//2, 32))
        panels.append(panel)
contact = Image.new("RGB", (2040, 1480))
for index, panel in enumerate(panels):
    contact.paste(panel, ((index % 3)*680, (index//3)*740))
contact.save(args.output / "comparison.png")
(args.output / "comparison.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
print(json.dumps(report))
