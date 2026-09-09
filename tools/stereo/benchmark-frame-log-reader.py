"""Compare eager/streamed reading of an existing capture without changing it."""
import argparse
import gc
import hashlib
import importlib.util
from pathlib import Path
import time
import tracemalloc


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    path = Path(__file__).with_name("summarize-xr-frame-stages.py")
    spec = importlib.util.spec_from_file_location("frame_stages", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    before = digest(args.log)

    def read(eager):
        if eager:
            return module.summarize(args.log.read_text(encoding="utf-8").splitlines())
        with args.log.open(encoding="utf-8") as source:
            return module.summarize(source)

    expected = read(True)
    assert read(False) == expected
    for trial in range(5):
        for eager in ([True, False] if trial % 2 == 0 else [False, True]):
            gc.collect()
            tracemalloc.start()
            start = time.perf_counter()
            result = read(eager)
            elapsed = (time.perf_counter() - start) * 1000
            _, peak = tracemalloc.get_traced_memory()
            tracemalloc.stop()
            assert result == expected
            del result
            print(f"mode={'eager' if eager else 'streamed'} trial={trial} "
                  f"instrumented_wall_ms={elapsed:.4f} peak_python_bytes={peak}", flush=True)
    assert digest(args.log) == before
    print(f"PASS equal_reports=10 input_sha256={before} bytes={args.log.stat().st_size} "
          f"timing_rows={expected['timing_rows']} valid_windows={len(expected['windows'])}")


if __name__ == "__main__":
    main()
