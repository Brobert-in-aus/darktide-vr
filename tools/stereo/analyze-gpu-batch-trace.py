#!/usr/bin/env python3
"""Summarize focused D3D12 GPU batch traces emitted by native_capture."""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter, defaultdict
from pathlib import Path


def optional_count(values: dict[str, str], name: str) -> int | None:
    if name not in values:
        return None
    count = int(values[name])
    if not 0 <= count < 2**64:
        raise ValueError("GPU work counter must fit an unsigned 64-bit value")
    return count


def known_sum(values) -> int | None:
    total = 0
    for value in values:
        if value is None:
            return None
        total += value
    return total


def display_count(value: int | None) -> str:
    return "unknown" if value is None else str(value)


def fields(line: str) -> tuple[list[str], dict[str, str]]:
    parts = line.rstrip("\r\n").split("\t")
    values: dict[str, str] = {}
    for part in parts:
        if "=" in part:
            key, value = part.split("=", 1)
            values[key] = value
    return parts, values


def compare_pso_counters(
    left_psos: Counter[str], right_psos: Counter[str]
) -> dict[str, object]:
    union = set(left_psos) | set(right_psos)
    shared = set(left_psos) & set(right_psos)
    multiset_intersection = sum(
        min(left_psos[pso], right_psos[pso]) for pso in union
    )
    multiset_union = sum(
        max(left_psos[pso], right_psos[pso]) for pso in union
    )
    bind_deltas = sorted(
        (
            {
                "pso": pso,
                "left_binds": left_psos[pso],
                "right_binds": right_psos[pso],
                "right_minus_left": right_psos[pso] - left_psos[pso],
            }
            for pso in union
            if left_psos[pso] != right_psos[pso]
        ),
        key=lambda item: abs(int(item["right_minus_left"])),
        reverse=True,
    )
    return {
        "left_pso_binds": sum(left_psos.values()),
        "right_pso_binds": sum(right_psos.values()),
        "shared_unique_psos": len(shared),
        "union_unique_psos": len(union),
        "unique_pso_jaccard": round(len(shared) / len(union), 6)
        if union
        else 0.0,
        "pso_bind_multiset_jaccard": round(
            multiset_intersection / multiset_union, 6
        )
        if multiset_union
        else 0.0,
        "largest_bind_deltas": bind_deltas[:16],
    }


def analyze(path: Path) -> dict[str, object]:
    pso_binds: dict[tuple[str, int], list[str]] = defaultdict(list)
    terminal_identities: dict[tuple[str, int], int] = {}
    batches: dict[tuple[int, int], dict[str, object]] = {}
    complete: dict[int, dict[str, int]] = {}
    integrity: dict[int, set[str]] = defaultdict(set)
    capture_frames: dict[int, set[tuple[str, str]]] = defaultdict(set)

    with path.open("r", encoding="utf-8", errors="replace") as source:
        for line in source:
            parts, values = fields(line)
            if len(parts) < 3:
                continue
            event = parts[2]
            if event in ("GPU_BATCH", "GPU_BATCH_LIST", "GPU_BATCH_COMPLETE"):
                capture_frames[int(values["eye"])].add((values.get("phase", ""), values.get("frame", "")))
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
                duration = float(values["duration_ms"])
                if not math.isfinite(duration) or duration < 0:
                    raise ValueError("GPU batch duration must be finite and nonnegative")
                if (eye, ordinal) in batches:
                    integrity[eye].add("duplicate_batch")
                batches[(eye, ordinal)] = {
                    "eye": eye,
                    "ordinal": ordinal,
                    "duration_ms": duration,
                    "declared_list_count": int(values["lists"]),
                    "terminal": bool(int(values["terminal"])),
                    "terminal_eye": int(values.get("terminal_eye", "-1")),
                    "lists": [],
                }
            elif event == "GPU_BATCH_LIST":
                key = (int(values["eye"]), int(values["batch"]))
                if key in batches:
                    batches[key]["lists"].append(
                        {
                            "cl": values["CL"],
                            "generation": int(values["gen"]),
                            "list_index": int(values["list_index"]) if "list_index" in values else None,
                            "draws": optional_count(values, "draws"),
                            "indexed_draws": optional_count(values, "indexed"),
                            "dispatches": optional_count(values, "dispatches"),
                            "indirects": optional_count(values, "indirects"),
                            "copies": optional_count(values, "copies"),
                            "resolves": optional_count(values, "resolves"),
                            "barriers": optional_count(values, "barriers"),
                            "passes": optional_count(values, "passes"),
                        }
                    )
                else:
                    integrity[key[0]].add("orphan_command_list")
            elif event == "GPU_BATCH_COMPLETE":
                if int(values["eye"]) in complete:
                    integrity[int(values["eye"])].add("duplicate_completion")
                complete[int(values["eye"])] = {
                    "batches": int(values["batches"]),
                    "truncated": int(values["truncated"]),
                }

    eyes: dict[str, object] = {}
    eye_psos: dict[int, Counter[str]] = {}
    for eye in sorted({key[0] for key in batches} | set(complete) | set(integrity)):
        eye_batches = [value for (batch_eye, _), value in batches.items() if batch_eye == eye]
        eye_batches.sort(key=lambda item: int(item["ordinal"]))
        issues = integrity[eye]
        completion = complete.get(eye)
        if completion is None:
            issues.add("missing_completion")
        else:
            if completion["batches"] != len(eye_batches):
                issues.add("batch_count_mismatch")
            if completion["truncated"] != 0:
                issues.add("truncated_capture")
        if [batch["ordinal"] for batch in eye_batches] != list(range(len(eye_batches))):
            issues.add("noncontiguous_batches")
        if len(capture_frames[eye]) != 1:
            issues.add("mixed_capture_frames")
        if any(not phase or not frame for phase, frame in capture_frames[eye]):
            issues.add("missing_capture_identity")
        for batch in eye_batches:
            if len(batch["lists"]) != batch["declared_list_count"]:
                issues.add("command_list_count_mismatch")
            indices = [item["list_index"] for item in batch["lists"]]
            if any(index is not None for index in indices) and indices != list(range(len(indices))):
                issues.add("command_list_index_mismatch")
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
            for metric, names in {
                "draw_count": ("draws", "indexed_draws"),
                "dispatch_count": ("dispatches",), "indirect_count": ("indirects",),
                "copy_count": ("copies",), "resolve_count": ("resolves",),
                "barrier_count": ("barriers",), "pass_count": ("passes",),
            }.items():
                batch[metric] = known_sum(item[name] for item in batch["lists"] for name in names
                    ) if len(batch["lists"]) == batch["declared_list_count"] else None
            if batch["terminal_eye"] < 0 and len(inferred_terminal_eyes) == 1:
                batch["terminal_eye"] = next(iter(inferred_terminal_eyes))
            if batch["terminal"] and (batch["terminal_eye"] not in (0, 1) or
                    any(value != batch["terminal_eye"] for value in inferred_terminal_eyes)):
                issues.add("ambiguous_render_eye")
            batch["top_psos"] = [
                {"pso": pso, "binds": count}
                for pso, count in signatures.most_common(8)
            ]
        ranked = sorted(eye_batches, key=lambda item: float(item["duration_ms"]), reverse=True)
        segments: list[dict[str, object]] = []
        segment_start = 0
        segment_duration = 0.0
        segment_psos: Counter[str] = Counter()
        segment_draws = 0
        segment_dispatches = 0
        segment_indirects = 0
        segment_copies = 0
        segment_resolves = 0
        segment_barriers = 0
        segment_passes = 0
        for batch in eye_batches:
            segment_duration += float(batch["duration_ms"])
            segment_draws = known_sum((segment_draws, batch["draw_count"]))
            segment_dispatches = known_sum((segment_dispatches, batch["dispatch_count"]))
            segment_indirects = known_sum((segment_indirects, batch["indirect_count"]))
            segment_copies = known_sum((segment_copies, batch["copy_count"]))
            segment_resolves = known_sum((segment_resolves, batch["resolve_count"]))
            segment_barriers = known_sum((segment_barriers, batch["barrier_count"]))
            segment_passes = known_sum((segment_passes, batch["pass_count"]))
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
                        "draw_count": segment_draws,
                        "dispatch_count": segment_dispatches,
                        "indirect_count": segment_indirects,
                        "copy_count": segment_copies,
                        "resolve_count": segment_resolves,
                        "barrier_count": segment_barriers,
                        "pass_count": segment_passes,
                        "pso_bind_count": sum(segment_psos.values()),
                        "unique_pso_count": len(segment_psos),
                        "_pso_counts": segment_psos,
                    }
                )
                segment_start = int(batch["ordinal"]) + 1
                segment_duration = 0.0
                segment_psos = Counter()
                segment_draws = 0
                segment_dispatches = 0
                segment_indirects = 0
                segment_copies = 0
                segment_resolves = 0
                segment_barriers = 0
                segment_passes = 0
        segment_comparisons: list[dict[str, object]] = []
        if eye_batches and not eye_batches[-1]["terminal"]:
            issues.add("unterminated_render_segment")
        for left, right in zip(segments, segments[1:]):
            if issues:
                break
            left_psos = left["_pso_counts"]
            right_psos = right["_pso_counts"]
            comparison = compare_pso_counters(left_psos, right_psos)
            left_ms = float(left["timed_gpu_ms"])
            right_ms = float(right["timed_gpu_ms"])
            comparison.update(
                {
                    "left_render_eye": left["render_eye"],
                    "right_render_eye": right["render_eye"],
                    "left_timed_ms": round(left_ms, 6),
                    "right_timed_ms": round(right_ms, 6),
                    "right_minus_left_ms": round(right_ms - left_ms, 6),
                }
            )
            segment_comparisons.append(comparison)
        eye_psos[eye] = Counter()
        for batch in eye_batches:
            for item in batch["lists"]:
                eye_psos[eye].update(
                    pso_binds.get((str(item["cl"]), int(item["generation"])), [])
                )
        for segment in segments:
            del segment["_pso_counts"]
        eyes[str(eye)] = {
            "integrity_issues": sorted(issues),
            "capture_frames": [{"phase": phase, "frame": frame} for phase, frame in sorted(capture_frames[eye])],
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

    eye_pair_comparison = None
    if all(str(eye) in eyes and not eyes[str(eye)]["integrity_issues"] and
           len(eyes[str(eye)]["render_segments"]) == 1 and
           eyes[str(eye)]["render_segments"][0]["render_eye"] == eye for eye in (0, 1)):
        left_psos = eye_psos[0]
        right_psos = eye_psos[1]
        left_ms = float(eyes["0"]["total_timed_ms"])
        right_ms = float(eyes["1"]["total_timed_ms"])
        eye_pair_comparison = compare_pso_counters(left_psos, right_psos)
        eye_pair_comparison.update({
            "left_timed_ms": round(left_ms, 6),
            "right_timed_ms": round(right_ms, 6),
            "right_minus_left_ms": round(right_ms - left_ms, 6),
        })

    return {
        "source": str(path.resolve()),
        "comparison_scope": "observed_direct_queue_work_only",
        "eye_pair_comparison": eye_pair_comparison,
        "eyes": eyes,
    }


def markdown(report: dict[str, object]) -> str:
    lines = ["# GPU batch trace", "", f"Source: `{report['source']}`", "",
             "Durations cover recorded direct-queue work, not whole-frame GPU time or a controlled settings comparison.",
             "Unknown work counts indicate omitted counters or missing command-list records, not zero work.", ""]
    pair = report.get("eye_pair_comparison")
    if pair:
        lines.extend(
            [
                "## Eye-pair comparison",
                "",
                f"- Timed work: left {pair['left_timed_ms']:.3f} ms, right "
                f"{pair['right_timed_ms']:.3f} ms (right-left "
                f"{pair['right_minus_left_ms']:+.3f} ms)",
                f"- PSO binds: left {pair['left_pso_binds']}, right "
                f"{pair['right_pso_binds']}",
                f"- Unique PSO overlap: {pair['shared_unique_psos']}/"
                f"{pair['union_unique_psos']} (Jaccard "
                f"{pair['unique_pso_jaccard']:.3f}); bind-count multiset "
                f"Jaccard {pair['pso_bind_multiset_jaccard']:.3f}",
                "",
                "| PSO | Left binds | Right binds | Right-left |",
                "|:---|---:|---:|---:|",
            ]
        )
        for delta in pair["largest_bind_deltas"]:
            lines.append(
                f"| {delta['pso']} | {delta['left_binds']} | "
                f"{delta['right_binds']} | {delta['right_minus_left']:+d} |"
            )
        lines.append("")
    else:
        lines.extend(["No eye-pair comparison: complete single-eye captures with matching left/right identity are required.", ""])
    for eye, data in report["eyes"].items():
        complete = data["complete"] or {}
        segment_eyes = {segment["render_eye"] for segment in data["render_segments"]}
        heading = (
            f"Eye {eye}"
            if len(segment_eyes) == 1 and int(eye) in segment_eyes
            else f"Timing capture {eye}"
        )
        lines.extend(
            [
                f"## {heading}",
                "",
                f"- Timed batches: {data['batch_count']} (reported {complete.get('batches', 'unknown')}, truncated {complete.get('truncated', 'unknown')})",
                f"- Capture integrity: {', '.join(data['integrity_issues']) or 'complete'}",
                f"- Total timed GPU work: {data['total_timed_ms']:.3f} ms",
                f"- Command lists matched to generation-aware PSO records: {data['matched_list_count']}/{data['submitted_list_count']}",
                "",
                "| Render segment | Render eye | Timed direct-queue work | Draws | Dispatches | Indirect | Copies | Resolves | Barriers | Passes | PSO binds | Unique PSOs |",
                "|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
            ]
        )
        for segment in data["render_segments"]:
            lines.append(
                f"| {segment['start_batch']}-{segment['end_batch']} | "
                f"{segment['render_eye']} | {segment['timed_gpu_ms']:.3f} ms | "
                f"{display_count(segment['draw_count'])} | {display_count(segment['dispatch_count'])} | "
                f"{display_count(segment['indirect_count'])} | {display_count(segment['copy_count'])} | "
                f"{display_count(segment['resolve_count'])} | "
                f"{display_count(segment['barrier_count'])} | {display_count(segment['pass_count'])} | "
                f"{segment['pso_bind_count']} | {segment['unique_pso_count']} |"
            )
        for comparison in data["render_segment_comparisons"]:
            lines.append("")
            lines.append(
                f"Adjacent render-eye comparison ({comparison['left_render_eye']} -> "
                f"{comparison['right_render_eye']}): "
                f"{comparison['left_timed_ms']:.3f} -> "
                f"{comparison['right_timed_ms']:.3f} ms "
                f"({comparison['right_minus_left_ms']:+.3f} ms); "
                f"PSO binds {comparison['left_pso_binds']} -> "
                f"{comparison['right_pso_binds']}; overlap "
                f"{comparison['shared_unique_psos']}/"
                f"{comparison['union_unique_psos']} unique (Jaccard "
                f"{comparison['unique_pso_jaccard']:.3f}); bind-count multiset "
                f"Jaccard {comparison['pso_bind_multiset_jaccard']:.3f}."
            )
        lines.extend(
            [
                "",
                "| Batch | GPU ms | Lists | Matched | Draws | Dispatches | Indirect | Copies | Resolves | Barriers | Passes | PSO binds | Unique PSOs | Terminal |",
                "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|:---:|",
            ]
        )
        for batch in data["top_batches"]:
            lines.append(
                f"| {batch['ordinal']} | {batch['duration_ms']:.3f} | "
                f"{len(batch['lists'])} | {batch['matched_list_count']} | "
                f"{display_count(batch['draw_count'])} | {display_count(batch['dispatch_count'])} | "
                f"{display_count(batch['indirect_count'])} | {display_count(batch['copy_count'])} | "
                f"{display_count(batch['resolve_count'])} | "
                f"{display_count(batch['barrier_count'])} | {display_count(batch['pass_count'])} | "
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
