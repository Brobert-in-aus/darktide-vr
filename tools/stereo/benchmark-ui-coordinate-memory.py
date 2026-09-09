"""Explicit offline comparison of actual placement functions on numeric arrays."""
import argparse
import ast
import gc
import json
from pathlib import Path
import statistics
import time
import tracemalloc

import numpy as np


def load_compare(path):
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    functions = [node for node in tree.body
                 if isinstance(node, ast.FunctionDef) and node.name == "compare"]
    if len(functions) != 1:
        raise ValueError("Expected one compare function")
    namespace = {"np": np}
    exec(compile(ast.Module(body=functions, type_ignores=[]), str(path), "exec"), namespace)
    return namespace["compare"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()
    variants = {"baseline": load_compare(args.baseline),
                "candidate": load_compare(args.candidate)}
    results = []
    for kind in ("empty", "sparse", "dense"):
        ui = np.zeros((2048, 2048, 4), dtype=np.uint8)
        if kind == "dense":
            ui[:] = (80, 120, 160, 255)
        elif kind == "sparse":
            ui[::31, ::29] = (80, 120, 160, 255)
        generated = ui.copy()
        expected = variants["baseline"](ui, generated, radius=0)
        assert variants["candidate"](ui, generated, radius=0) == expected
        samples = {name: [] for name in variants}
        for trial in range(5):
            order = list(variants) if trial % 2 == 0 else list(reversed(variants))
            for name in order:
                gc.collect()
                tracemalloc.start()
                began = time.perf_counter()
                actual = variants[name](ui, generated, radius=0)
                elapsed = (time.perf_counter() - began) * 1000
                _, peak = tracemalloc.get_traced_memory()
                tracemalloc.stop()
                assert actual == expected
                samples[name].append({"wall_ms": elapsed, "peak_bytes": peak})
        results.append({"case": kind, "shape": list(ui.shape), "equal": True,
            "measurements": {name: {"trials": rows,
                "median_wall_ms": statistics.median(row["wall_ms"] for row in rows),
                "median_peak_bytes": statistics.median(row["peak_bytes"] for row in rows)}
                for name, rows in samples.items()}})
    print(json.dumps({"scope": "numeric arrays; no rendering or visual evidence",
                      "numpy": np.__version__, "results": results}, indent=2))


if __name__ == "__main__":
    main()
