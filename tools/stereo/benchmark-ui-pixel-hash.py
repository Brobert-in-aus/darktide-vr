"""Explicit numeric-array benchmark for the optional offline checksum helper."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import statistics
import time

import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    args = parser.parse_args()
    source = Path(__file__).with_name("check-dlss-ui-alpha.py")
    spec = importlib.util.spec_from_file_location("alpha_hash", source)
    analysis = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(analysis)
    image = np.arange(1024 * 1024 * 4, dtype=np.uint8).reshape(1024, 1024, 4)
    results = []
    for name, array, channels in (("rgba", image, 4), ("rgb", image, 3),
                                  ("strided_rgba", image[::-1, ::2], 4)):
        analysis.configure_pixel_hash()
        expected = analysis.pixel_hash(array, channels)
        samples = {"python": [], "native": []}
        for trial in range(5):
            order = ("python", "native") if trial % 2 == 0 else ("native", "python")
            for mode in order:
                analysis.configure_pixel_hash(args.library if mode == "native" else None)
                began = time.perf_counter()
                actual = analysis.pixel_hash(array, channels)
                elapsed = (time.perf_counter() - began) * 1000
                assert actual == expected
                samples[mode].append(elapsed)
        results.append({"case": name, "bytes": array.shape[0] * array.shape[1] * channels,
            "checksum": expected, "equal": True, "trials_ms": samples,
            "medians_ms": {mode: statistics.median(values) for mode, values in samples.items()}})
    print(json.dumps({"scope": "numeric byte hashing, including packing; excludes helper setup",
        "library_sha256": hashlib.sha256(args.library.read_bytes()).hexdigest(),
        "results": results}, indent=2))


if __name__ == "__main__":
    main()
