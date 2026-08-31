#!/usr/bin/env python3
"""Compare native draws by the named completed eye they actually feed.

Focused draw records are emitted while a command list is being recorded, before
the final eye resource is known. OUTPUT_IDENTITY is emitted later at queue
submission and binds that command list to the named left/right final resource.
This analyzer performs that late join instead of trusting viewport-derived
``eye=-1``/SBS labels.
"""

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


def signature(record: dict[str, str]) -> tuple[str, ...]:
    return tuple(
        record.get(field, "")
        for field in ("vs", "ps", "blend", "depth", "topo", "kind")
    )


def read_trace(path: Path) -> tuple[list[dict[str, str]], dict[str, Any]]:
    identities: dict[tuple[str, str, str], str] = {}
    draws: list[dict[str, str]] = []
    conflicts: list[dict[str, str]] = []
    with path.open("r", encoding="utf-8", errors="replace") as stream:
        for line in stream:
            if ("\tOUTPUT_IDENTITY\t" in line or
                    "\tOUTPUT_BATCH_IDENTITY\t" in line):
                record = parse_record(line)
                # The production DLSS path completes both sequential renders
                # into alternating FSR replacement backbuffers, so those
                # resources do not have a permanent left/right name. The
                # render-arm tag is matched to this completion in the native
                # queue hook and is the authoritative eye owner. Preserve
                # compatibility with the first diagnostic build as well.
                eye = record.get("render_eye", record.get("armed_eye"))
                if eye not in {"0", "1"}:
                    continue
                key = (record.get("frame", ""), record.get("CL", ""),
                       record.get("gen", ""))
                previous = identities.get(key)
                if previous is not None and previous != eye:
                    conflicts.append(
                        {"frame": key[0], "command_list": key[1],
                         "recording_generation": key[2],
                         "first_eye": previous, "second_eye": eye}
                    )
                identities[key] = eye
            elif "\tDRAW\t" in line:
                draws.append(parse_record(line))

    attributed: list[dict[str, str]] = []
    for draw in draws:
        key = (draw.get("frame", ""), draw.get("CL", ""),
               draw.get("gen", ""))
        output_eye = identities.get(key)
        if output_eye is None:
            continue
        enriched = dict(draw)
        enriched["output_eye"] = output_eye
        attributed.append(enriched)
    diagnostics = {
        "draw_records": len(draws),
        "identity_records": len(identities),
        "attributed_draw_records": len(attributed),
        "unattributed_draw_records": len(draws) - len(attributed),
        "identity_conflicts": conflicts,
    }
    return attributed, diagnostics


def compare(draws: list[dict[str, str]]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    groups = {eye: [draw for draw in draws if draw["output_eye"] == eye]
              for eye in ("0", "1")}
    list_counts = {
        eye: len({(draw.get("frame", ""), draw.get("CL", ""),
                  draw.get("gen", "")) for draw in group})
        for eye, group in groups.items()
    }
    frame_counts = {
        eye: max(1, len({draw.get("frame", "") for draw in group}))
        for eye, group in groups.items()
    }
    counters = {
        eye: collections.Counter(signature(draw) for draw in group)
        for eye, group in groups.items()
    }
    examples: dict[tuple[str, ...], dict[str, str]] = {}
    for draw in draws:
        examples.setdefault(signature(draw), draw)

    rows: list[dict[str, Any]] = []
    for key in counters["0"].keys() | counters["1"].keys():
        left_rate = counters["0"][key] / frame_counts["0"]
        right_rate = counters["1"][key] / frame_counts["1"]
        delta = right_rate - left_rate
        if abs(delta) < 1e-9:
            continue
        rows.append(
            {
                "vs": key[0],
                "ps": key[1],
                "blend": key[2],
                "depth": key[3],
                "topology": key[4],
                "draw_kind": key[5],
                "left_draws_per_eye_frame": left_rate,
                "right_draws_per_eye_frame": right_rate,
                "right_minus_left": delta,
                "example": {
                    field: examples[key].get(field, "")
                    for field in ("frame", "CL", "pso", "coarse", "exact",
                                  "a", "rtv", "dsv", "bind", "s4", "s7")
                },
            }
        )
    rows.sort(key=lambda row: (-abs(row["right_minus_left"]), row["ps"], row["vs"]))
    summary = {
        "left": {
            "draws": len(groups["0"]),
            "output_lists": list_counts["0"],
            "frames": frame_counts["0"],
        },
        "right": {
            "draws": len(groups["1"]),
            "output_lists": list_counts["1"],
            "frames": frame_counts["1"],
        },
    }
    return rows, summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace", type=Path)
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--top", type=int, default=80)
    args = parser.parse_args()

    draws, diagnostics = read_trace(args.trace)
    ranked, summary = compare(draws)
    report = {
        "trace": str(args.trace),
        "diagnostics": diagnostics,
        "summary": summary,
        "asymmetric_signatures": ranked[: args.top],
    }
    args.output_directory.mkdir(parents=True, exist_ok=True)
    (args.output_directory / "output-attributed-trace.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    lines = [
        "# Completed-output-attributed draw comparison",
        "",
        f"Trace: `{args.trace}`",
        "",
        f"Attributed {diagnostics['attributed_draw_records']} of "
        f"{diagnostics['draw_records']} draw records using "
        f"{diagnostics['identity_records']} named-output identities.",
        "",
        "| Rank | VS | PS | Blend | Depth | Left/frame | Right/frame | R-L |",
        "|---:|---|---|:---:|:---:|---:|---:|---:|",
    ]
    for index, row in enumerate(ranked[: args.top], 1):
        lines.append(
            f"| {index} | `{row['vs']}` | `{row['ps']}` | {row['blend']} | "
            f"{row['depth']} | {row['left_draws_per_eye_frame']:.3f} | "
            f"{row['right_draws_per_eye_frame']:.3f} | "
            f"{row['right_minus_left']:+.3f} |"
        )
    (args.output_directory / "output-attributed-trace.md").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
