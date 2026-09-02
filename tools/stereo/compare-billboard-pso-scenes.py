#!/usr/bin/env python3
"""Rank billboard PSO families enriched in one Darktide scene versus another."""

from __future__ import annotations

import argparse
import csv
from collections import Counter
from pathlib import Path


Pair = tuple[str, str]


def parse_identity(path: Path, include_all_classified: bool) -> Counter[Pair]:
    counts: Counter[Pair] = Counter()
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        fields = dict(
            part.split("=", 1) for part in line.split("\t") if "=" in part
        )
        vertex = fields.get("vs", "").lower()
        pixel = fields.get("ps", "").lower()
        classified = (
            len(vertex) == 16
            and len(pixel) == 16
            and vertex != "0000000000000000"
            and pixel != "0000000000000000"
        )
        if classified and (
            include_all_classified or fields.get("billboard") == "1"
        ):
            counts[(vertex, pixel)] += 1
    return counts


def family_metadata(path: Path | None) -> dict[str, dict[str, str]]:
    if path is None:
        return {}
    with path.open(newline="", encoding="utf-8") as stream:
        return {row["vertex_shader"].lower(): row for row in csv.DictReader(stream)}


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Compare run-scoped billboard=1 identity logs. The comparison log "
            "should be the scene containing the visual defect."
        )
    )
    parser.add_argument("baseline", type=Path)
    parser.add_argument("comparison", type=Path)
    parser.add_argument("--families", type=Path)
    parser.add_argument(
        "--include-all-classified",
        action="store_true",
        help=(
            "Compare every row with nonzero VS/PS identities. Use this when "
            "the billboard heuristic does not recognize the target family."
        ),
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    baseline = parse_identity(args.baseline, args.include_all_classified)
    comparison = parse_identity(args.comparison, args.include_all_classified)
    metadata = family_metadata(args.families)
    baseline_total = sum(baseline.values())
    comparison_total = sum(comparison.values())
    if comparison_total == 0:
        label = "classified shader" if args.include_all_classified else "billboard=1"
        raise SystemExit(f"comparison log contains no {label} identities")

    rows: list[dict[str, object]] = []
    for pair, comparison_count in comparison.items():
        baseline_count = baseline[pair]
        comparison_share = comparison_count / comparison_total
        baseline_share = baseline_count / baseline_total if baseline_total else 0.0
        # Half-observation smoothing keeps unique low-count families below
        # genuinely dominant scene-specific families while still ranking them.
        enrichment = (comparison_share + 0.5 / comparison_total) / (
            baseline_share + (0.5 / baseline_total if baseline_total else 0.5)
        )
        family = metadata.get(pair[0], {})
        rows.append(
            {
                "vertex_shader": pair[0],
                "pixel_shader": pair[1],
                "comparison_count": comparison_count,
                "baseline_count": baseline_count,
                "comparison_share": f"{comparison_share:.9f}",
                "baseline_share": f"{baseline_share:.9f}",
                "share_delta": f"{comparison_share - baseline_share:.9f}",
                "enrichment": f"{enrichment:.4f}",
                "cbuffers": family.get("cbuffers", ""),
                "interface": family.get("interface", ""),
                "cbuffer_load_shape": family.get("cbuffer_load_shape", ""),
            }
        )

    rows.sort(
        key=lambda row: (
            float(row["share_delta"]),
            int(row["comparison_count"]),
            float(row["enrichment"]),
        ),
        reverse=True,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    label = "classified" if args.include_all_classified else "billboard"
    print(
        f"baseline_{label}_rows={baseline_total} "
        f"comparison_{label}_rows={comparison_total} "
        f"families={len(rows)} output={args.output}"
    )
    for row in rows[:12]:
        print(
            "candidate="
            f"{row['vertex_shader']}/{row['pixel_shader']} "
            f"comparison={row['comparison_count']} baseline={row['baseline_count']} "
            f"delta={row['share_delta']} enrichment={row['enrichment']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
