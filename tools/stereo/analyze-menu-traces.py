#!/usr/bin/env python3
"""Rank draw signatures that are enriched in a stock-menu trace.

The focused native logs can contain different frame counts, so this compares
per-frame rates and frame-presence fractions rather than raw draw totals.
"""

from __future__ import annotations

import argparse
import collections
from pathlib import Path


def parse_record(line: str) -> dict[str, str]:
    record: dict[str, str] = {}
    for field in line.rstrip("\r\n").split("\t"):
        if "=" in field:
            key, value = field.split("=", 1)
            record[key] = value
        elif field:
            record.setdefault("event", field)
    return record


def load(
    path: Path, phase: int | None = None
) -> tuple[set[int], dict[tuple[str, ...], dict[int, int]], dict[tuple[str, ...], str]]:
    frames: set[int] = set()
    counts: dict[tuple[str, ...], dict[int, int]] = collections.defaultdict(
        lambda: collections.defaultdict(int)
    )
    examples: dict[tuple[str, ...], str] = {}
    with path.open("r", encoding="utf-8", errors="replace") as trace:
        for line in trace:
            if "\tDRAW\t" not in line:
                continue
            record = parse_record(line)
            if phase is not None and int(record.get("phase", "-1")) != phase:
                continue
            frame = int(record["frame"])
            frames.add(frame)
            args = record.get("a", "").split(",", 1)[0]
            signature = (
                record.get("vs", ""),
                record.get("ps", ""),
                record.get("blend", ""),
                record.get("depth", ""),
                record.get("topo", ""),
                record.get("kind", ""),
                args,
                record.get("vpw", ""),
                record.get("vph", ""),
            )
            counts[signature][frame] += 1
            examples.setdefault(signature, line.rstrip())
    return frames, counts, examples


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("menu", type=Path)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("--menu-phase", type=int)
    parser.add_argument("--baseline-phase", type=int)
    parser.add_argument("--limit", type=int, default=60)
    args = parser.parse_args()

    menu_frames, menu, menu_examples = load(args.menu, args.menu_phase)
    base_frames, baseline, base_examples = load(args.baseline, args.baseline_phase)
    rows = []
    for signature in set(menu) | set(baseline):
        menu_total = sum(menu.get(signature, {}).values())
        base_total = sum(baseline.get(signature, {}).values())
        menu_rate = menu_total / len(menu_frames) if menu_frames else 0.0
        base_rate = base_total / len(base_frames) if base_frames else 0.0
        menu_presence = len(menu.get(signature, {})) / len(menu_frames) if menu_frames else 0.0
        base_presence = len(baseline.get(signature, {})) / len(base_frames) if base_frames else 0.0
        score = (menu_rate - base_rate) + 4.0 * (menu_presence - base_presence)
        if score <= 0.0:
            continue
        rows.append((score, menu_rate, base_rate, menu_presence, base_presence, signature))
    rows.sort(reverse=True)

    print(f"menu_frames={len(menu_frames)} baseline_frames={len(base_frames)}")
    print("score menu/f base/f menu% base% vs ps blend depth topo kind verts vpw vph")
    for score, menu_rate, base_rate, menu_presence, base_presence, signature in rows[: args.limit]:
        print(
            f"{score:8.3f} {menu_rate:7.2f} {base_rate:7.2f} "
            f"{menu_presence:5.1%} {base_presence:5.1%} " + " ".join(signature)
        )
        print("  " + (menu_examples.get(signature) or base_examples[signature]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
