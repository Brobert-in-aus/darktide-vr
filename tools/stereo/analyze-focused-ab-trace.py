#!/usr/bin/env python3
"""Compare focused Darktide draw traces across viewport-half A/B phases."""

from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path
from typing import Any


def parse_record(line: str) -> dict[str, str]:
    record: dict[str, str] = {}
    for field in line.rstrip("\r\n").split("\t"):
        if "=" in field:
            key, value = field.split("=", 1)
            record[key] = value
        elif field:
            record.setdefault("event", field)
    return record


def counter_delta(
    left: collections.Counter[str], right: collections.Counter[str]
) -> tuple[int, int, int]:
    common = sum((left & right).values())
    return common, sum((left - right).values()), sum((right - left).values())


def set_overlap(left: set[str], right: set[str]) -> dict[str, Any]:
    intersection = len(left & right)
    union = len(left | right)
    return {
        "left": len(left),
        "right": len(right),
        "shared": intersection,
        "left_only": len(left - right),
        "right_only": len(right - left),
        "jaccard": intersection / union if union else 1.0,
    }


def summarize_group(records: list[dict[str, str]]) -> dict[str, Any]:
    coarse = collections.Counter(record["coarse"] for record in records)
    exact = collections.Counter(record["exact"] for record in records)
    return {
        "records": len(records),
        "frames": sorted({int(record["frame"]) for record in records}),
        "coarse_counter": coarse,
        "exact_counter": exact,
        "coarse_keys": set(coarse),
        "exact_keys": set(exact),
    }


def compare_groups(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
    coarse_common, coarse_left, coarse_right = counter_delta(
        left["coarse_counter"], right["coarse_counter"]
    )
    exact_common, exact_left, exact_right = counter_delta(
        left["exact_counter"], right["exact_counter"]
    )
    return {
        "records": {"left": left["records"], "right": right["records"]},
        "coarse_distinct": set_overlap(left["coarse_keys"], right["coarse_keys"]),
        "coarse_multiset": {
            "shared": coarse_common,
            "left_only": coarse_left,
            "right_only": coarse_right,
        },
        "exact_distinct": set_overlap(left["exact_keys"], right["exact_keys"]),
        "exact_multiset": {
            "shared": exact_common,
            "left_only": exact_left,
            "right_only": exact_right,
        },
    }


def rank_pso_deltas(
    left_records: list[dict[str, str]], right_records: list[dict[str, str]]
) -> list[dict[str, Any]]:
    left: dict[str, collections.Counter[str]] = collections.defaultdict(
        collections.Counter
    )
    right: dict[str, collections.Counter[str]] = collections.defaultdict(
        collections.Counter
    )
    examples: dict[tuple[str, str], str] = {}
    for side, records in ((left, left_records), (right, right_records)):
        for record in records:
            side[record["pso"]][record["coarse"]] += 1
            examples[(record["pso"], record["coarse"])] = record.get("a", "")

    rows: list[dict[str, Any]] = []
    for pso in set(left) | set(right):
        common, left_only, right_only = counter_delta(left[pso], right[pso])
        if left_only == 0 and right_only == 0:
            continue
        left_keys = set(left[pso])
        right_keys = set(right[pso])
        example_keys = list((left_keys ^ right_keys))[:3]
        rows.append(
            {
                "pso": pso,
                "shared_draws": common,
                "left_only_draws": left_only,
                "right_only_draws": right_only,
                "delta_draws": left_only + right_only,
                "left_distinct": len(left_keys),
                "right_distinct": len(right_keys),
                "example_arguments": [examples[(pso, key)] for key in example_keys],
            }
        )
    rows.sort(key=lambda row: (-row["delta_draws"], row["pso"]))
    return rows


def signature_overlap(
    left_records: list[dict[str, str]],
    right_records: list[dict[str, str]],
    fields: tuple[str, ...],
) -> dict[str, Any]:
    left = collections.Counter(
        tuple(record.get(field, "") for field in fields) for record in left_records
    )
    right = collections.Counter(
        tuple(record.get(field, "") for field in fields) for record in right_records
    )
    shared, left_only, right_only = counter_delta(left, right)
    total = shared + left_only + right_only
    return {
        "fields": list(fields),
        "shared": shared,
        "left_only": left_only,
        "right_only": right_only,
        "overlap": shared / total if total else 1.0,
    }


def same_frame_comparison(
    left_records: list[dict[str, str]], right_records: list[dict[str, str]]
) -> dict[str, Any]:
    common_frames = sorted(
        {record["frame"] for record in left_records}
        & {record["frame"] for record in right_records},
        key=int,
    )
    left = [record for record in left_records if record["frame"] in common_frames]
    right = [record for record in right_records if record["frame"] in common_frames]
    signatures = {}
    for fields in (
        ("coarse",),
        ("exact",),
        ("exact", "sc"),
        ("exact", "s4"),
        ("exact", "s7"),
        ("exact", "constants"),
        ("exact", "bind"),
    ):
        signatures["+".join(fields)] = signature_overlap(left, right, fields)
    left_counter = collections.Counter(record["coarse"] for record in left)
    right_counter = collections.Counter(record["coarse"] for record in right)
    left_examples = {record["coarse"]: record for record in left}
    right_examples = {record["coarse"]: record for record in right}

    def delta_examples(
        delta: collections.Counter[str], examples: dict[str, dict[str, str]]
    ) -> list[dict[str, Any]]:
        rows = []
        for coarse, count in delta.most_common(30):
            record = examples[coarse]
            rows.append(
                {
                    "coarse": coarse,
                    "excess_occurrences": count,
                    "pso": record.get("pso", ""),
                    "arguments": record.get("a", ""),
                    "exact": record.get("exact", ""),
                    "s4": record.get("s4", ""),
                }
            )
        return rows

    return {
        "common_frames": [int(frame) for frame in common_frames],
        "records": {"left": len(left), "right": len(right)},
        "signatures": signatures,
        "coarse_delta_examples": {
            "left_only": delta_examples(left_counter - right_counter, left_examples),
            "right_only": delta_examples(right_counter - left_counter, right_examples),
        },
    }


def public_group(group: dict[str, Any]) -> dict[str, Any]:
    return {
        "records": group["records"],
        "frames": group["frames"],
        "distinct_coarse": len(group["coarse_keys"]),
        "distinct_exact": len(group["exact_keys"]),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace", type=Path)
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()

    draws: list[dict[str, str]] = []
    for line in args.trace.read_text(encoding="utf-8", errors="replace").splitlines():
        if "\tDRAW\t" not in line:
            continue
        record = parse_record(line)
        if record.get("phase") in {"1", "2"} and record.get("eye") in {"0", "1"}:
            draws.append(record)

    records = {
        "phase_a_primary_left": [
            record for record in draws if record["phase"] == "1" and record["eye"] == "0"
        ],
        "phase_a_duplicate_right": [
            record for record in draws if record["phase"] == "1" and record["eye"] == "1"
        ],
        "phase_b_duplicate_left": [
            record for record in draws if record["phase"] == "2" and record["eye"] == "0"
        ],
        "phase_b_primary_right": [
            record for record in draws if record["phase"] == "2" and record["eye"] == "1"
        ],
    }
    groups = {name: summarize_group(group) for name, group in records.items()}

    comparisons = {
        "same_primary_a_left_vs_b_right": compare_groups(
            groups["phase_a_primary_left"], groups["phase_b_primary_right"]
        ),
        "same_duplicate_a_right_vs_b_left": compare_groups(
            groups["phase_a_duplicate_right"], groups["phase_b_duplicate_left"]
        ),
        "phase_a_physical_left_vs_right": compare_groups(
            groups["phase_a_primary_left"], groups["phase_a_duplicate_right"]
        ),
        "phase_b_physical_left_vs_right": compare_groups(
            groups["phase_b_duplicate_left"], groups["phase_b_primary_right"]
        ),
    }
    pso_deltas = {
        "same_primary_a_left_vs_b_right": rank_pso_deltas(
            records["phase_a_primary_left"], records["phase_b_primary_right"]
        ),
        "same_duplicate_a_right_vs_b_left": rank_pso_deltas(
            records["phase_a_duplicate_right"], records["phase_b_duplicate_left"]
        ),
    }

    same_frame = {
        "phase_a_physical_left_vs_right": same_frame_comparison(
            records["phase_a_primary_left"], records["phase_a_duplicate_right"]
        ),
        "phase_b_physical_left_vs_right": same_frame_comparison(
            records["phase_b_duplicate_left"], records["phase_b_primary_right"]
        ),
    }

    report = {
        "trace": str(args.trace),
        "total_draw_records": len(draws),
        "groups": {name: public_group(group) for name, group in groups.items()},
        "comparisons": comparisons,
        "same_frame_physical_comparisons": same_frame,
        "top_pso_deltas": {name: rows[:20] for name, rows in pso_deltas.items()},
    }

    args.output_directory.mkdir(parents=True, exist_ok=True)
    json_path = args.output_directory / "focused-primary-half-ab-analysis.json"
    markdown_path = args.output_directory / "focused-primary-half-ab-analysis.md"
    json_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Focused primary-half A/B draw comparison",
        "",
        f"Trace: `{args.trace}`",
        "",
        f"Parsed draw records: {len(draws)}",
        "",
        "## Groups",
        "",
        "| Group | Records | Frames | Distinct coarse | Distinct exact |",
        "|---|---:|---|---:|---:|",
    ]
    for name, group in report["groups"].items():
        lines.append(
            f"| {name} | {group['records']} | {group['frames']} | "
            f"{group['distinct_coarse']} | {group['distinct_exact']} |"
        )
    lines.extend(["", "## Comparisons", ""])
    for name, comparison in comparisons.items():
        coarse = comparison["coarse_distinct"]
        exact = comparison["exact_distinct"]
        lines.extend(
            [
                f"### {name}",
                "",
                f"- Records: {comparison['records']['left']} vs {comparison['records']['right']}",
                f"- Coarse keys: {coarse['shared']} shared, {coarse['left_only']} left-only, "
                f"{coarse['right_only']} right-only, Jaccard {coarse['jaccard']:.4f}",
                f"- Exact keys: {exact['shared']} shared, {exact['left_only']} left-only, "
                f"{exact['right_only']} right-only, Jaccard {exact['jaccard']:.4f}",
                "",
            ]
        )
    lines.extend(["## Same-frame physical-half signatures", ""])
    for name, comparison in same_frame.items():
        lines.extend(
            [
                f"### {name}",
                "",
                f"- Common frames: {comparison['common_frames']}",
                f"- Records: {comparison['records']['left']} vs {comparison['records']['right']}",
            ]
        )
        for signature, metrics in comparison["signatures"].items():
            lines.append(
                f"- `{signature}`: {metrics['shared']} shared, "
                f"{metrics['left_only']} left-only, {metrics['right_only']} right-only, "
                f"overlap {metrics['overlap']:.4f}"
            )
        lines.append("")
    lines.extend(["## Largest same-primary PSO deltas", ""])
    lines.extend(
        [
            "| PSO | Shared draws | A-only | B-only | A distinct | B distinct |",
            "|---|---:|---:|---:|---:|---:|",
        ]
    )
    for row in pso_deltas["same_primary_a_left_vs_b_right"][:20]:
        lines.append(
            f"| {row['pso']} | {row['shared_draws']} | {row['left_only_draws']} | "
            f"{row['right_only_draws']} | {row['left_distinct']} | {row['right_distinct']} |"
        )
    markdown_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
