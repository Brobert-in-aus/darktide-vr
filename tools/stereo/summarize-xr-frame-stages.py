"""Summarize CPU-observed viewer stages; no GPU or display-latency attribution."""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path

STAGES = ("active_loop", "pair_wait", "wait_frame", "begin_frame", "tracking",
          "swapchain_acquire_wait", "gpu_fence", "end_frame")


def fields(line):
    result = {}
    for field in line.split()[1:]:
        if "=" in field:
            key, value = field.split("=", 1)
            if key in result:
                raise ValueError("duplicate_field")
            result[key] = value
    return result


def number(value):
    result = float(value)
    if not math.isfinite(result) or result < 0:
        raise ValueError("invalid_number")
    return result


def parse(line):
    data = fields(line)
    if any(data.get(k) != v for k, v in
           (("clock", "steady"), ("units", "ms"), ("scope", "cpu_wall"))):
        raise ValueError("unknown_scope")
    if int(data["invalid_samples"]) != 0:
        raise ValueError("invalid_samples")
    row = {"window_end_frame": int(data["window_end_frame"]),
           "last_display_period_ms": number(data["last_display_period_ms"]), "stages": {}}
    for stage in STAGES:
        count = int(data[stage + "_samples"])
        if count < 0:
            raise ValueError("invalid_count")
        sample = {"count": count}
        if count:
            sample.update(mean_ms=number(data[stage + "_mean"]),
                          maximum_ms=number(data[stage + "_max"]))
            if sample["mean_ms"] > sample["maximum_ms"] + 1e-6:
                raise ValueError("invalid_maximum")
        elif stage + "_mean" in data or stage + "_max" in data:
            raise ValueError("duration_without_samples")
        row["stages"][stage] = sample
    count = row["stages"]["active_loop"]["count"]
    if count <= 0 or row["window_end_frame"] < count:
        raise ValueError("invalid_window")
    for stage in ("pair_wait", "wait_frame", "begin_frame", "tracking", "end_frame"):
        if row["stages"][stage]["count"] != count:
            raise ValueError("incomplete_stage")
    if row["stages"]["gpu_fence"]["count"] > count or \
            row["stages"]["swapchain_acquire_wait"]["count"] > count * 3:
        raise ValueError("invalid_render_count")
    return row


def aggregate(rows):
    result = {"windows": len(rows), "stages": {}}
    for stage in STAGES:
        samples = [row["stages"][stage] for row in rows if row["stages"][stage]["count"]]
        count = sum(sample["count"] for sample in samples)
        output = {"count": count}
        if count:
            output.update(mean_call_ms=sum(s["count"] * s["mean_ms"] for s in samples) / count,
                          maximum_observed_call_ms=max(s["maximum_ms"] for s in samples))
        result["stages"][stage] = output
    return result


def summarize(lines):
    context = None
    contexts = set()
    previous_frame = None
    epoch = 0
    excluded = Counter()
    rows = []
    total = 0
    for line in lines:
        if line.startswith("openxr.presentation "):
            try:
                data = fields(line)
                context = tuple(data[k] for k in ("mode", "generation", "source", "crop"))
            except (KeyError, ValueError):
                context = None
            contexts.add(context)
        elif line.startswith("openxr.frame_stage_timing "):
            total += 1
            try:
                row = parse(line)
                frame = row["window_end_frame"]
                expected = (previous_frame or 0) + row["stages"]["active_loop"]["count"]
                if previous_frame is not None and frame <= previous_frame:
                    epoch += 1
                previous_frame = frame
                if frame != expected:
                    raise ValueError("frame_discontinuity")
                if len(contexts) != 1 or context is None:
                    raise ValueError("unknown_or_mixed_presentation")
                row["presentation"] = dict(zip(("mode", "generation", "source", "crop"), context))
                row["epoch"] = epoch
                rows.append(row)
            except (KeyError, ValueError) as error:
                # A malformed row cannot establish frame continuity.
                if str(error) not in ("frame_discontinuity", "unknown_or_mixed_presentation"):
                    previous_frame = None
                excluded[str(error)] += 1
            contexts = {context}
    groups = defaultdict(list)
    for row in rows:
        key = (row["epoch"], *row["presentation"].values())
        groups[key].append(row)
    summaries = []
    for key, group in sorted(groups.items()):
        summaries.append({"epoch": key[0],
                          "presentation": dict(zip(("mode", "generation", "source", "crop"), key[1:])),
                          "all": aggregate(group), "first_60_windows": aggregate(group[:60]),
                          "last_60_windows": aggregate(group[-60:])})
    return {"status": "observational_only", "timing_rows": total,
            "excluded_windows": dict(excluded), "groups": summaries, "windows": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = summarize(args.log.read_text(encoding="utf-8").splitlines())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "windows"}, indent=2))


if __name__ == "__main__":
    main()
