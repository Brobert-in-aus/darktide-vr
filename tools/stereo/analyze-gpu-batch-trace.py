#!/usr/bin/env python3
"""Summarize focused D3D12 GPU batch traces emitted by native_capture."""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path


def fields(line: str) -> tuple[list[str], dict[str, str]]:
    parts = line.rstrip("\r\n").split("\t")
    values: dict[str, str] = {}
    for part in parts:
        if "=" in part:
            key, value = part.split("=", 1)
            values[key] = value
    return parts, values


def analyze(path: Path) -> dict[str, object]:
    pso_binds: dict[tuple[str, int], list[str]] = defaultdict(list)
    terminal_identities: dict[tuple[str, int], int] = {}
    batches: dict[tuple[int, int], dict[str, object]] = {}
    complete: dict[int, dict[str, int]] = {}

    with path.open("r", encoding="utf-8", errors="replace") as source:
        for line in source:
            parts, values = fields(line)
            if len(parts) < 3:
                continue
            event = parts[2]
            if event.startswith("CL=") and len(parts) >= 4 and parts[3] == "PSO":
                generation = int(values.get("gen", "0"))
                pso_binds[(values["CL"], generation)].append(values["pso"])
            elif (
                event.startswith("CL=")
                and len(parts) >= 4
                and parts[3] == "OUTPUT_BATCH_IDENTITY"
                and values.get("terminal") == "1"
            ):
                terminal_identities[(values["CL"], int(values.get("gen", "0")))] = int(
                    values["render_eye"]
                )
            elif event == "GPU_BATCH":
                eye = int(values["eye"])
                ordinal = int(values["ordinal"])
                batches[(eye, ordinal)] = {
                    "eye": eye,
                    "ordinal": ordinal,
                    "duration_ms": float(values["duration_ms"]),
                    "declared_list_count": int(values["lists"]),
                    "terminal": bool(int(values["terminal"])),
                    "terminal_eye": int(values.get("terminal_eye", "-1")),
                    "lists": [],
                }
            elif event == "GPU_BATCH_LIST":
                key = (int(values["eye"]), int(values["batch"]))
                if key in batches:
                    batches[key]["lists"].append(
                        {"cl": values["CL"], "generation": int(values["gen"])}
                    )
            elif event == "GPU_BATCH_COMPLETE":
                complete[int(values["eye"])] = {
                    "batches": int(values["batches"]),
                    "truncated": int(values["truncated"]),
                }

    eyes: dict[str, object] = {}
    for eye in sorted({key[0] for key in batches}):
        eye_batches = [value for (batch_eye, _), value in batches.items() if batch_eye == eye]
        eye_batches.sort(key=lambda item: int(item["ordinal"]))
        for batch in eye_batches:
            signatures: Counter[str] = Counter()
            bind_count = 0
            matched_lists = 0
            inferred_terminal_eyes: set[int] = set()
            for item in batch["lists"]:
                key = (str(item["cl"]), int(item["generation"]))
                binds = pso_binds.get(key, [])
                if binds:
                    matched_lists += 1
                    bind_count += len(binds)
                    signatures.update(binds)
                if key in terminal_identities:
                    inferred_terminal_eyes.add(terminal_identities[key])
            batch["matched_list_count"] = matched_lists
            batch["pso_bind_count"] = bind_count
            batch["unique_pso_count"] = len(signatures)
            if batch["terminal_eye"] < 0 and len(inferred_terminal_eyes) == 1:
                batch["terminal_eye"] = next(iter(inferred_terminal_eyes))
            batch["top_psos"] = [
                {"pso": pso, "binds": count}
                for pso, count in signatures.most_common(8)
            ]
        ranked = sorted(eye_batches, key=lambda item: float(item["duration_ms"]), reverse=True)
        segments: list[dict[str, object]] = []
        segment_start = 0
        segment_duration = 0.0
        segment_psos: Counter[str] = Counter()
        for batch in eye_batches:
            segment_duration += float(batch["duration_ms"])
            for item in batch["lists"]:
                segment_psos.update(
                    pso_binds.get((str(item["cl"]), int(item["generation"])), [])
                )
            if batch["terminal"]:
                segments.append(
                    {
                        "start_batch": segment_start,
                        "end_batch": batch["ordinal"],
                        "render_eye": batch["terminal_eye"],
                        "timed_gpu_ms": round(segment_duration, 6),
                        "pso_bind_count": sum(segment_psos.values()),
                        "unique_pso_count": len(segment_psos),
                        "_pso_counts": segment_psos,
                    }
                )
                segment_start = int(batch["ordinal"]) + 1
                segment_duration = 0.0
                segment_psos = Counter()
        segment_comparisons: list[dict[str, object]] = []
        for left, right in zip(segments, segments[1:]):
            left_psos = left["_pso_counts"]
            right_psos = right["_pso_counts"]
            shared = set(left_psos) & set(right_psos)
            union = set(left_psos) | set(right_psos)
            multiset_intersection = sum(min(left_psos[pso], right_psos[pso]) for pso in union)
            multiset_union = sum(max(left_psos[pso], right_psos[pso]) for pso in union)
            segment_comparisons.append(
                {
                    "left_render_eye": left["render_eye"],
                    "right_render_eye": right["render_eye"],
                    "shared_unique_psos": len(shared),
                    "union_unique_psos": len(union),
                    "unique_pso_jaccard": round(len(shared) / len(union), 6) if union else 0.0,
                    "pso_bind_multiset_jaccard": round(multiset_intersection / multiset_union, 6)
                    if multiset_union
                    else 0.0,
                }
            )
        for segment in segments:
            del segment["_pso_counts"]
        eyes[str(eye)] = {
            "complete": complete.get(eye),
            "total_timed_ms": round(sum(float(item["duration_ms"]) for item in eye_batches), 6),
            "batch_count": len(eye_batches),
            "matched_list_count": sum(int(item["matched_list_count"]) for item in eye_batches),
            "submitted_list_count": sum(len(item["lists"]) for item in eye_batches),
            "render_segments": segments,
            "render_segment_comparisons": segment_comparisons,
            "top_batches": ranked[:12],
            "batches": eye_batches,
        }

    return {"source": str(path.resolve()), "eyes": eyes}


def markdown(report: dict[str, object]) -> str:
    lines = ["# GPU batch trace", "", f"Source: `{report['source']}`", ""]
    for eye, data in report["eyes"].items():
        complete = data["complete"] or {}
        lines.extend(
            [
                f"## Eye {eye}",
                "",
                f"- Timed batches: {data['batch_count']} (reported {complete.get('batches', 'unknown')}, truncated {complete.get('truncated', 'unknown')})",
                f"- Total timed GPU work: {data['total_timed_ms']:.3f} ms",
                f"- Command lists matched to generation-aware PSO records: {data['matched_list_count']}/{data['submitted_list_count']}",
                "",
                "| Render segment | Render eye | Timed direct-queue work | PSO binds | Unique PSOs |",
                "|:---|---:|---:|---:|---:|",
            ]
        )
        for segment in data["render_segments"]:
            lines.append(
                f"| {segment['start_batch']}-{segment['end_batch']} | "
                f"{segment['render_eye']} | {segment['timed_gpu_ms']:.3f} ms | "
                f"{segment['pso_bind_count']} | {segment['unique_pso_count']} |"
            )
        for comparison in data["render_segment_comparisons"]:
            lines.append("")
            lines.append(
                f"Adjacent render-eye PSO overlap ({comparison['left_render_eye']} -> "
                f"{comparison['right_render_eye']}): {comparison['shared_unique_psos']}/"
                f"{comparison['union_unique_psos']} unique (Jaccard "
                f"{comparison['unique_pso_jaccard']:.3f}); bind-count multiset "
                f"Jaccard {comparison['pso_bind_multiset_jaccard']:.3f}."
            )
        lines.extend(
            [
                "",
                "| Batch | GPU ms | Lists | Matched | PSO binds | Unique PSOs | Terminal |",
                "|---:|---:|---:|---:|---:|---:|:---:|",
            ]
        )
        for batch in data["top_batches"]:
            lines.append(
                f"| {batch['ordinal']} | {batch['duration_ms']:.3f} | "
                f"{len(batch['lists'])} | {batch['matched_list_count']} | "
                f"{batch['pso_bind_count']} | {batch['unique_pso_count']} | "
                f"{'yes' if batch['terminal'] else 'no'} |"
            )
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace", type=Path)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--markdown", type=Path)
    args = parser.parse_args()
    report = analyze(args.trace)
    rendered = markdown(report)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if args.markdown:
        args.markdown.parent.mkdir(parents=True, exist_ok=True)
        args.markdown.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)


if __name__ == "__main__":
    main()
