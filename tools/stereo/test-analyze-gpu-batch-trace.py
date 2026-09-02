#!/usr/bin/env python3
"""Focused regression tests for analyze-gpu-batch-trace.py."""

from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path


SCRIPT = Path(__file__).with_name("analyze-gpu-batch-trace.py")
SPEC = importlib.util.spec_from_file_location("analyze_gpu_batch_trace", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def line(frame: int, *parts: str) -> str:
    return "\t".join(("phase=1", f"frame={frame}", *parts)) + "\n"


def main() -> None:
    trace = "".join(
        (
            line(1, "CL=A", "PSO", "gen=1", "pso=P_SHARED"),
            line(1, "CL=A", "PSO", "gen=1", "pso=P_LEFT"),
            line(1, "CL=B", "PSO", "gen=1", "pso=P_SHARED"),
            line(1, "CL=B", "PSO", "gen=1", "pso=P_RIGHT"),
            line(
                1,
                "CL=A",
                "OUTPUT_BATCH_IDENTITY",
                "gen=1",
                "render_eye=1",
                "terminal=1",
            ),
            line(
                1,
                "CL=B",
                "OUTPUT_BATCH_IDENTITY",
                "gen=1",
                "render_eye=0",
                "terminal=1",
            ),
            line(
                1,
                "GPU_BATCH",
                "eye=0",
                "ordinal=0",
                "duration_ms=2.0",
                "lists=1",
                "terminal=1",
                "terminal_eye=1",
            ),
            line(
                1,
                "GPU_BATCH_LIST",
                "eye=0",
                "batch=0",
                "CL=A",
                "gen=1",
                "draws=2",
                "indexed=3",
                "dispatches=1",
                "indirects=2",
                "copies=3",
                "resolves=1",
                "barriers=9",
                "passes=4",
            ),
            line(
                1,
                "GPU_BATCH",
                "eye=0",
                "ordinal=1",
                "duration_ms=3.5",
                "lists=1",
                "terminal=1",
                "terminal_eye=0",
            ),
            line(
                1,
                "GPU_BATCH_LIST",
                "eye=0",
                "batch=1",
                "CL=B",
                "gen=1",
                "draws=5",
                "indexed=7",
                "dispatches=0",
                "indirects=1",
                "copies=4",
                "resolves=2",
                "barriers=7",
                "passes=6",
            ),
            line(1, "GPU_BATCH_COMPLETE", "eye=0", "batches=2", "truncated=0"),
        )
    )
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "trace.log"
        path.write_text(trace, encoding="utf-8")
        report = MODULE.analyze(path)

    capture = report["eyes"]["0"]
    comparison = capture["render_segment_comparisons"][0]
    assert comparison["left_render_eye"] == 1
    assert comparison["right_render_eye"] == 0
    assert comparison["left_timed_ms"] == 2.0
    assert comparison["right_timed_ms"] == 3.5
    assert comparison["right_minus_left_ms"] == 1.5
    assert comparison["shared_unique_psos"] == 1
    assert comparison["union_unique_psos"] == 3
    assert capture["render_segments"][0]["draw_count"] == 5
    assert capture["render_segments"][0]["dispatch_count"] == 1
    assert capture["render_segments"][0]["indirect_count"] == 2
    assert capture["render_segments"][0]["copy_count"] == 3
    assert capture["render_segments"][0]["resolve_count"] == 1
    assert capture["render_segments"][0]["barrier_count"] == 9
    assert capture["render_segments"][0]["pass_count"] == 4
    assert capture["render_segments"][1]["draw_count"] == 12
    assert capture["render_segments"][1]["dispatch_count"] == 0
    assert capture["render_segments"][1]["indirect_count"] == 1
    assert capture["render_segments"][1]["copy_count"] == 4
    assert capture["render_segments"][1]["resolve_count"] == 2
    assert capture["render_segments"][1]["barrier_count"] == 7
    assert capture["render_segments"][1]["pass_count"] == 6
    rendered = MODULE.markdown(report)
    assert "## Timing capture 0" in rendered
    assert "2.000 -> 3.500 ms (+1.500 ms)" in rendered
    assert (
        "| Draws | Dispatches | Indirect | Copies | Resolves | Barriers | Passes |"
        in rendered
    )
    assert "| 0-0 | 1 | 2.000 ms | 5 | 1 | 2 | 3 | 1 | 9 | 4 |" in rendered
    print("analyze_gpu_batch_trace_tests=pass")


if __name__ == "__main__":
    main()
