"""Compare a matched NGX output with the exact UI supplied for that evaluation.

Only nearly opaque UI pixels are compared: their expected colour is independent
of the generated background. A translation search is a diagnostic, not proof of
motion-vector behaviour, source pose, or worn visual acceptance.
"""
import argparse
import importlib.util
import json
from pathlib import Path

import numpy as np
from PIL import Image

spec = importlib.util.spec_from_file_location(
    "ui_alpha", Path(__file__).with_name("check-dlss-ui-alpha.py"))
ui_alpha = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui_alpha)


def records(path, prefix):
    return [dict(field.split("=", 1) for field in line.split()[1:])
            for line in Path(path).read_text().splitlines() if line.startswith(prefix + " ")]


def verify_match(stem, generated):
    inputs = records(f"{stem}.log", "UI_READBACK_MATCH")
    outputs = records(generated.with_suffix(".log"), "NGX_COPY")
    if len(inputs) != 1 or inputs[0].get("owned_ui") != "1":
        raise ValueError("An exact owned-UI readback is required")
    ui_readbacks = records(f"{stem}.log", "UI_READBACK")
    for phase in ("staged", "exported"):
        rows = [row for row in ui_readbacks if row.get("phase") == phase]
        if len(rows) != 1 or rows[0].get("result") != "0x00000000":
            raise ValueError("UI input must have one staged and GPU-complete export")
    completed = [row for row in outputs if row.get("phase") == "exported"]
    staged = [row for row in outputs if row.get("phase") == "staged"]
    if len(completed) != 1 or len(staged) != 1:
        raise ValueError("Generated output must have one staged and GPU-complete export")
    for key in ("pose", "left_scene", "right_scene"):
        if inputs[0][key] != completed[0][key] or staged[0][key] != completed[0][key]:
            raise ValueError(f"Input/output identity mismatch: {key}")
    for key in ("left_call", "right_call", "source", "owned", "readback",
                "width", "height", "row_pitch", "bytes"):
        if not staged[0].get(key) or staged[0][key] != completed[0].get(key):
            raise ValueError(f"Staged/exported output identity mismatch: {key}")
    if any(int(completed[0][key]) <= 0 for key in ("left_call", "right_call")):
        raise ValueError("Both generated eye calls must have positive identities")
    if int(completed[0]["right_call"]) <= int(completed[0]["left_call"]):
        raise ValueError("Generated eye calls must retain native left/right order")
    if int(inputs[0]["pose"]) <= 0 or any(row["result"] != "0x00000000" for row in (staged[0], completed[0])):
        raise ValueError("Missing pose identity or failed output capture")
    layout = {key: int(completed[0][key]) for key in ("width", "height", "row_pitch", "bytes")}
    width, height, pitch = layout["width"], layout["height"], layout["row_pitch"]
    if width <= 0 or width % 2 or height <= 0 or pitch < width * 4 or pitch % 256 or \
            layout["bytes"] < (height - 1) * pitch + width * 4:
        raise ValueError("Invalid packed RGBA8 readback layout")
    try:
        hashes = {key: int(completed[0][key]) for key in ("left_hash", "right_hash")}
    except (KeyError, ValueError) as error:
        raise ValueError("Generated export requires both native RGB hashes") from error
    if any(value < 0 or value >= 2**64 for value in hashes.values()):
        raise ValueError("Generated RGB hashes must be unsigned 64-bit values")
    return {**{key: completed[0][key] for key in ("pose", "left_call", "right_call")},
            **layout, **{key: str(value) for key, value in hashes.items()}}


def verify_extent(identity, packed):
    if packed.shape != (identity["height"], identity["width"], 4) or packed.dtype != np.uint8:
        raise ValueError("Generated bitmap does not match the logged RGBA8 extent")


def rgb_hash(image):
    # Matches ngx_output_copy_probe.cpp: top-to-bottom RGB bytes, excluding
    # alpha and D3D12 row padding. The BMP reader has already restored RGBA.
    value = 14695981039346656037
    for byte in image[:, :, :3].tobytes():
        value = ((value ^ byte) * 1099511628211) & 0xffffffffffffffff
    return value


def verify_content(identity, packed):
    identity.pop("generated_rgb_hash_verified", None)
    verify_extent(identity, packed)
    width = identity["width"] // 2
    for index, eye in enumerate(("left", "right")):
        if rgb_hash(packed[:, index * width:(index + 1) * width]) != int(identity[eye + "_hash"]):
            raise ValueError(f"Generated {eye} RGB content does not match the native export hash")
    identity["generated_rgb_hash_verified"] = True


def compare(ui, generated, radius=64):
    if ui.shape != generated.shape or ui.ndim != 3 or ui.shape[2] != 4:
        raise ValueError("Generated output must match the UI eye extent")
    mask = (ui[:, :, 3] >= 254) & (ui[:, :, :3].max(axis=2) >= 30)
    y, x = np.nonzero(mask)
    if len(x) < 32:
        return {"opaque_pixels": len(x), "placement_check": "insufficient_opaque_UI"}
    # Fixed evenly distributed sample, bounded independently of headset size.
    sample = np.linspace(0, len(x) - 1, min(len(x), 4096), dtype=int)
    x, y = x[sample], y[sample]
    expected = ui[y, x, :3].astype(np.int16)

    def score(dx, dy):
        xx, yy = x + dx, y + dy
        valid = (xx >= 0) & (xx < ui.shape[1]) & (yy >= 0) & (yy < ui.shape[0])
        if valid.sum() < len(x) * 0.9:
            return (float("inf"), 0.0)
        error = np.abs(generated[yy[valid], xx[valid], :3].astype(np.int16) - expected[valid]).max(axis=1)
        return float(np.mean(np.minimum(error, 64))), float(np.mean(error <= 3))

    candidates = [(score(dx, dy)[0], dx, dy)
                  for dy in range(-radius, radius + 1, 8)
                  for dx in range(-radius, radius + 1, 8)]
    _, cx, cy = min(candidates)
    candidates += [(score(dx, dy)[0], dx, dy)
                   for dy in range(max(-radius, cy-7), min(radius, cy+7)+1)
                   for dx in range(max(-radius, cx-7), min(radius, cx+7)+1)]
    _, dx, dy = min(candidates)
    current, best = score(0, 0), score(dx, dy)
    return {
        "opaque_pixels": int(mask.sum()), "sample_pixels": len(x),
        "current_position_clipped_mean_error": current[0],
        "current_position_fraction_within_3": current[1],
        "best_translation_pixels": [dx, dy],
        "best_translation_clipped_mean_error": best[0],
        "best_translation_fraction_within_3": best[1],
        "placement_check": "measurement_only",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stem", type=Path)
    parser.add_argument("generated", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    identity = verify_match(args.stem, args.generated)
    generated = ui_alpha.read_rgba(args.generated)
    verify_content(identity, generated)
    args.output.mkdir(parents=True, exist_ok=True)
    width = generated.shape[1] // 2
    report = {"identity": identity, "visual_acceptance": "unverified", "eyes": {}}
    for i, eye in enumerate(("left", "right")):
        ui = ui_alpha.read_rgba(f"{args.stem}-{eye}-ui.bmp")
        output = generated[:, i*width:(i+1)*width]
        report["eyes"][eye] = compare(ui, output)
        Image.fromarray(output[:, :, :3]).save(args.output / f"{eye}-generated.png")
        Image.fromarray(ui).save(args.output / f"{eye}-submitted-ui.png")
    (args.output / "generated-ui-check.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
