"""Measure opaque UI contrast in an identity-matched generated frame.

This measures adjacent full-coverage pixels at their current coordinates. It
does not align images, diagnose a blur cause, or test translucent boundaries,
world geometry, motion, compositor/streaming quality or worn acceptance.
"""
import argparse
import importlib.util
import json
from pathlib import Path

import numpy as np

spec = importlib.util.spec_from_file_location(
    "generated_ui", Path(__file__).with_name("compare-dlss-generated-ui.py"))
generated_ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generated_ui)


def measure(ui, generated, minimum_contrast=16, minimum_pairs=32):
    if ui.shape != generated.shape or ui.ndim != 3 or ui.shape[2] != 4:
        raise ValueError("Expected matching RGBA eye extents")
    if ui.dtype != np.uint8 or generated.dtype != np.uint8:
        raise ValueError("Expected RGBA8 capture values")
    if not 0 < minimum_contrast <= 255 or minimum_pairs < 1:
        raise ValueError("Expected positive contrast threshold and sample minimum")
    opaque = ui[:, :, 3] == 255
    reference = ui[:, :, :3].astype(np.float32)
    output = generated[:, :, :3].astype(np.float32)
    report = {"measurement": "opaque_ui_adjacent_contrast",
              "visual_acceptance": "unverified", "alignment": "none",
              "opaque_pixels": int(opaque.sum()), "minimum_contrast": minimum_contrast,
              "axes": {}}
    for axis, name in ((1, "horizontal"), (0, "vertical")):
        first = (slice(None), slice(None, -1)) if axis == 1 else (slice(None, -1), slice(None))
        second = (slice(None), slice(1, None)) if axis == 1 else (slice(1, None), slice(None))
        delta = reference[second] - reference[first]
        observed = output[second] - output[first]
        selected = opaque[first] & opaque[second] & (np.abs(delta).max(axis=2) >= minimum_contrast)
        count = int(selected.sum())
        result = {"edge_pairs": count, "status": "insufficient_opaque_detail"}
        if count >= minimum_pairs:
            expected, actual = delta[selected], observed[selected]
            energy = np.sum(expected * expected, axis=1)
            agreement = np.sum(expected * actual, axis=1)
            ratio = agreement / energy
            result.update({
                "status": "measurement_only",
                # A signed projection avoids counting reversed or unrelated
                # output gradients as preserved source contrast.
                "energy_weighted_contrast_retention": float(agreement.sum(dtype=np.float64) / energy.sum(dtype=np.float64)),
                "median_contrast_retention": float(np.median(ratio)),
                "fraction_contrast_reversed": float(np.mean(agreement < 0)),
                "mean_gradient_max_channel_error": float(np.mean(np.abs(actual - expected).max(axis=1))),
            })
        report["axes"][name] = result
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stem", type=Path)
    parser.add_argument("generated", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    identity = generated_ui.verify_match(args.stem, args.generated)
    packed = generated_ui.ui_alpha.read_rgba(args.generated)
    generated_ui.verify_extent(identity, packed)
    width = packed.shape[1] // 2
    report = {"identity": identity, "visual_acceptance": "unverified", "eyes": {}}
    for i, eye in enumerate(("left", "right")):
        ui = generated_ui.ui_alpha.read_rgba(f"{args.stem}-{eye}-ui.bmp")
        report["eyes"][eye] = measure(ui, packed[:, i * width:(i + 1) * width])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
