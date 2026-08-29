#!/usr/bin/env python3
"""Rank draw signatures enriched in one focused Darktide trace state.

This compares two independently captured focused traces.  Counts are normalized
per eye/frame so a longer capture cannot masquerade as an application-state
difference.
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


def read_draws(path: Path) -> list[dict[str, str]]:
    draws: list[dict[str, str]] = []
    with path.open("r", encoding="utf-8", errors="replace") as trace:
        for line in trace:
            if "\tDRAW\t" not in line:
                continue
            record = parse_record(line)
            if "frame" in record and record.get("eye") in {"0", "1"}:
                draws.append(record)
    return draws


def frame_keys(draws: list[dict[str, str]]) -> set[tuple[str, str]]:
    return {(draw["frame"], draw["eye"]) for draw in draws}


def signature(draw: dict[str, str]) -> tuple[str, ...]:
    return (
        draw.get("vs", ""),
        draw.get("ps", ""),
        draw.get("blend", ""),
        draw.get("depth", ""),
        draw.get("topo", ""),
        draw.get("kind", ""),
    )


def build_stats(draws: list[dict[str, str]]) -> dict[tuple[str, ...], dict[str, Any]]:
    stats: dict[tuple[str, ...], dict[str, Any]] = {}
    for draw in draws:
        key = signature(draw)
        row = stats.setdefault(
            key,
            {
                "draws": 0,
                "frames": set(),
                "psos": set(),
                "coarse": set(),
                "example": {},
            },
        )
        row["draws"] += 1
        row["frames"].add((draw["frame"], draw["eye"]))
        row["psos"].add(draw.get("pso", ""))
        row["coarse"].add(draw.get("coarse", ""))
        if not row["example"]:
            row["example"] = {
                field: draw.get(field, "")
                for field in (
                    "frame", "eye", "pso", "a", "vpx", "vpy", "vpw", "vph",
                    "sc", "rtv", "dsv", "bind", "constants", "s4", "s7"
                )
            }
    return stats


def compare(
    baseline: list[dict[str, str]], active: list[dict[str, str]]
) -> list[dict[str, Any]]:
    baseline_frames = max(1, len(frame_keys(baseline)))
    active_frames = max(1, len(frame_keys(active)))
    baseline_stats = build_stats(baseline)
    active_stats = build_stats(active)
    rows: list[dict[str, Any]] = []
    for key in set(baseline_stats) | set(active_stats):
        base = baseline_stats.get(key)
        live = active_stats.get(key)
        base_draws = base["draws"] if base else 0
        live_draws = live["draws"] if live else 0
        base_rate = base_draws / baseline_frames
        live_rate = live_draws / active_frames
        delta = live_rate - base_rate
        if delta <= 0:
            continue
        live_presence = len(live["frames"]) / active_frames if live else 0.0
        base_presence = len(base["frames"]) / baseline_frames if base else 0.0
        # D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST is 4.  Darktide's immediate UI
        # uses non-indexed triangle lists with blending and depth disabled.
        ui_shape = (
            key[2] == "1"
            and key[3] == "0"
            and key[4] == "4"
            and key[5] == "0"
        )
        score = delta * (1.0 + live_presence) * (2.0 if ui_shape else 1.0)
        rows.append(
            {
                "vs": key[0],
                "ps": key[1],
                "blend": key[2],
                "depth": key[3],
                "topology": key[4],
                "draw_kind": key[5],
                "ui_shape": ui_shape,
                "score": score,
                "baseline_draws_per_eye_frame": base_rate,
                "active_draws_per_eye_frame": live_rate,
                "delta_draws_per_eye_frame": delta,
                "baseline_frame_presence": base_presence,
                "active_frame_presence": live_presence,
                "baseline_distinct_coarse": len(base["coarse"]) if base else 0,
                "active_distinct_coarse": len(live["coarse"]) if live else 0,
                "active_psos": sorted(live["psos"]) if live else [],
                "example": live["example"] if live else {},
            }
        )
    rows.sort(key=lambda row: (-row["score"], row["ps"], row["vs"]))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("active", type=Path)
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--top", type=int, default=40)
    args = parser.parse_args()

    baseline = read_draws(args.baseline)
    active = read_draws(args.active)
    ranked = compare(baseline, active)
    report = {
        "baseline": str(args.baseline),
        "active": str(args.active),
        "baseline_draw_records": len(baseline),
        "active_draw_records": len(active),
        "baseline_eye_frames": len(frame_keys(baseline)),
        "active_eye_frames": len(frame_keys(active)),
        "enriched_signatures": ranked[: args.top],
    }
    args.output_directory.mkdir(parents=True, exist_ok=True)
    (args.output_directory / "focused-state-diff.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )

    lines = [
        "# Focused application-state draw comparison",
        "",
        f"Baseline: `{args.baseline}`",
        f"Active: `{args.active}`",
        "",
        f"Baseline: {len(baseline)} draws across {len(frame_keys(baseline))} eye-frames.",
        f"Active: {len(active)} draws across {len(frame_keys(active))} eye-frames.",
        "",
        "Rates below are draws per captured eye-frame. UI-shaped means blended, "
        "depth-disabled triangle geometry.",
        "",
        "| Rank | VS | PS | UI-shaped | Baseline | Active | Delta | Presence |",
        "|---:|---|---|:---:|---:|---:|---:|---:|",
    ]
    for index, row in enumerate(ranked[: args.top], 1):
        lines.append(
            f"| {index} | `{row['vs']}` | `{row['ps']}` | "
            f"{'yes' if row['ui_shape'] else 'no'} | "
            f"{row['baseline_draws_per_eye_frame']:.3f} | "
            f"{row['active_draws_per_eye_frame']:.3f} | "
            f"{row['delta_draws_per_eye_frame']:.3f} | "
            f"{row['active_frame_presence']:.1%} |"
        )
    (args.output_directory / "focused-state-diff.md").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
