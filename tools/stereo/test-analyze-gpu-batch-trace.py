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
        path.write_text(trace.replace("batches=2", "batches=3"), encoding="utf-8")
        partial = MODULE.analyze(path)["eyes"]["0"]
        assert not partial["render_segment_comparisons"], "Incomplete capture produced a timing comparison"
        assert "batch_count_mismatch" in partial["integrity_issues"]
        path.write_text(trace + trace.replace("eye=0", "eye=1"), encoding="utf-8")
        mixed = MODULE.analyze(path)
        assert mixed["eye_pair_comparison"] is None, "Mixed render-eye captures were labelled left/right"
        variants = {
            "missing_completion": "".join(row for row in trace.splitlines(True) if "GPU_BATCH_COMPLETE" not in row),
            "truncated_capture": trace.replace("truncated=0", "truncated=1"),
            "command_list_count_mismatch": trace.replace("lists=1", "lists=2", 1),
            "duplicate_batch": trace + line(1, "GPU_BATCH", "eye=0", "ordinal=0", "duration_ms=1", "lists=0", "terminal=1", "terminal_eye=0"),
            "mixed_capture_frames": trace.replace("frame=1\tGPU_BATCH_COMPLETE", "frame=2\tGPU_BATCH_COMPLETE"),
            "noncontiguous_batches": trace.replace("ordinal=1", "ordinal=3").replace("batch=1", "batch=3"),
            "unterminated_render_segment": trace.replace("terminal=1\tterminal_eye=0", "terminal=0\tterminal_eye=0"),
            "ambiguous_render_eye": trace.replace("terminal_eye=0", "terminal_eye=1"),
            "command_list_index_mismatch": trace.replace("GPU_BATCH_LIST\t", "GPU_BATCH_LIST\tlist_index=1\t"),
        }
        for expected, broken in variants.items():
            path.write_text(broken, encoding="utf-8")
            data = MODULE.analyze(path)["eyes"]["0"]
            assert expected in data["integrity_issues"], (expected, data["integrity_issues"])
            assert not data["render_segment_comparisons"], expected
        for duration in ("nan", "inf", "-1"):
            path.write_text(trace.replace("duration_ms=2.0", "duration_ms=" + duration), encoding="utf-8")
            try:
                MODULE.analyze(path)
            except ValueError as error:
                assert "duration" in str(error)
            else:
                raise AssertionError("Invalid GPU duration admitted: " + duration)
        pair_trace = ""
        for eye in (0, 1):
            pair_trace += line(1, "GPU_BATCH", f"eye={eye}", "ordinal=0", f"duration_ms={eye+1}",
                               "lists=0", "terminal=1", f"terminal_eye={eye}")
            pair_trace += line(1, "GPU_BATCH_COMPLETE", f"eye={eye}", "batches=1", "truncated=0")
        path.write_text(pair_trace, encoding="utf-8")
        pair = MODULE.analyze(path)["eye_pair_comparison"]
        assert pair and pair["left_timed_ms"] == 1 and pair["right_timed_ms"] == 2
        assert pair["right_minus_left_ms"] == 1

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
