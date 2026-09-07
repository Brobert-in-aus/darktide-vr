"""Summarize generated-stereo health windows without inferring graphics settings.

These are observational window averages, not frame-time percentiles or a
controlled FG on/off comparison. Groups separate focus, observed generation
progress and clock precision. Slow windows remain included.
"""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import statistics

COUNTERS = ("evaluations", "complete", "paired", "published")
METRICS = ("engine_fps", "legacy_publish_fps", "original_ring_fps", "present_mean_ms")


def parse(line):
    fields = dict(field.split("=", 1) for field in line.split()[1:] if "=" in field)
    row = {name: float(fields[name]) for name in METRICS}
    row.update({name: int(fields[name]) for name in COUNTERS})
    row["foreground"] = int(fields["foreground"])
    row["original_failed"] = int(fields["original_failed"])
    row["clock"] = fields.get("present_clock", "coarse_legacy")
    row["focus_changes"] = int(fields["focus_changes"]) if "focus_changes" in fields else None
    row["focus_tracking"] = "per_present" if row["focus_changes"] is not None else "endpoint_only"
    if row["focus_changes"] is not None and row["focus_changes"] < 0:
        raise ValueError("Invalid within-window focus count")
    if any(not math.isfinite(row[key]) or row[key] < 0 for key in METRICS + COUNTERS):
        raise ValueError("Invalid metric or cumulative counter")
    if row["foreground"] not in (0, 1) or row["original_failed"] not in (0, 1):
        raise ValueError("Invalid health flag")
    if row["clock"] not in ("coarse_legacy", "steady"):
        raise ValueError("Unknown clock precision")
    return row


def summarize(lines):
    previous = None
    groups = defaultdict(list)
    excluded = Counter()
    total = 0
    timing_counter_boundaries = 0
    for line in lines:
        if line.strip() in ("enabled", "disabled"):
            previous = None
        if line.startswith("health_boundary "):
            previous = None
            timing_counter_boundaries += 1
        if not line.startswith("health "):
            continue
        total += 1
        try:
            row = parse(line)
        except (ValueError, KeyError, OverflowError):
            excluded["invalid_health_row"] += 1
            previous = None  # Never bridge an unknown interval.
            continue
        baseline = previous
        previous = row
        if baseline is None:
            excluded["counter_baseline"] += 1
            continue
        delta = {key: row[key] - baseline[key] for key in COUNTERS}
        if any(value < 0 for value in delta.values()):
            excluded["counter_reset"] += 1
            continue
        if (row["foreground"] != baseline["foreground"] or row["clock"] != baseline["clock"] or
                row["focus_tracking"] != baseline["focus_tracking"]):
            excluded["focus_or_clock_transition"] += 1
            continue
        if row["focus_changes"]:
            excluded["within_window_focus_transition"] += 1
            continue
        if row["original_failed"]:
            excluded["original_failure"] += 1
            continue
        if row["engine_fps"] <= 0 or max(row["legacy_publish_fps"], row["original_ring_fps"]) <= 0:
            excluded["no_observed_original_output"] += 1
            continue
        if delta["published"] > 0:
            progress = "generated_publication_progress"
        elif delta["evaluations"] > 0:
            progress = "evaluation_without_publication_progress"
        else:
            progress = "no_evaluation_or_publication_progress"
        # Completion can occur after the last evaluation; publication progress
        # therefore takes precedence. Lack of progress does not mean FG disabled.
        key = ("foreground" if row["foreground"] else "background", progress,
               row["clock"], row["focus_tracking"])
        groups[key].append(row)
    result = {"comparison_status": "observational_only", "health_rows": total,
              "timing_counter_boundaries": timing_counter_boundaries,
              "excluded_windows": dict(excluded), "groups": []}
    for (focus, progress, clock, focus_tracking), rows in sorted(groups.items()):
        metrics = {}
        for metric in METRICS:
            values = [row[metric] for row in rows]
            metrics[metric] = {"median_window_value": statistics.median(values),
                               "minimum_window_value": min(values), "maximum_window_value": max(values)}
        result["groups"].append({"focus": focus, "generation_progress": progress,
                                 "focus_tracking": focus_tracking,
                                 "present_clock": clock, "windows": len(rows), "metrics": metrics})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = summarize(args.log.read_text(encoding="utf-8").splitlines())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
