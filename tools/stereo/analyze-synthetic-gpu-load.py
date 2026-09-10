"""Summarize board telemetry inside an explicitly timed simulator workload."""
import argparse
import csv
import hashlib
from datetime import datetime, timedelta, timezone
import io
import json
import math
from pathlib import Path
import re

METRICS = {"utilization.gpu [%]": "%", "power.draw [W]": "W",
           "clocks.current.graphics [MHz]": "MHz", "clocks.current.memory [MHz]": "MHz"}


def reading(value, unit):
    value = value.strip()
    if value in ("N/A", "[N/A]"): return None
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?) " + re.escape(unit), value)
    if not match: raise ValueError("invalid telemetry value")
    result = float(match[1])
    if not math.isfinite(result) or (unit == "%" and result > 100):
        raise ValueError("telemetry value outside range")
    return result


def summarize(text, start, end, offset_hours, gpu=0):
    if end <= start or not -14 <= offset_hours <= 14: raise ValueError("invalid measurement window")
    local_zone = timezone(timedelta(hours=offset_hours))
    totals = {name: {"weighted_sum": 0, "known_seconds": 0, "samples": 0} for name in METRICS}
    previous = None
    intervals = 0
    reader = csv.DictReader(io.StringIO(text), skipinitialspace=True)
    if not reader.fieldnames or not {"timestamp", "index", *METRICS}.issubset(reader.fieldnames):
        raise ValueError("missing telemetry columns")
    for row in reader:
        if int(row["index"]) != gpu: continue
        stamp = datetime.strptime(row["timestamp"], "%Y/%m/%d %H:%M:%S.%f").replace(tzinfo=local_zone).astimezone(timezone.utc)
        values = {name: reading(row[name], unit) for name, unit in METRICS.items()}
        if previous is not None:
            if stamp <= previous: raise ValueError("non-increasing telemetry time")
            # Do not smear one reading across a missing stretch of samples.
            seconds = max(0, (min(stamp, end)-max(previous, start)).total_seconds())
            if 0 < seconds and (stamp-previous).total_seconds() <= 3:
                intervals += 1
                for name, value in values.items():
                    if value is not None:
                        totals[name]["weighted_sum"] += value * seconds
                        totals[name]["known_seconds"] += seconds
                        totals[name]["samples"] += 1
        previous = stamp
    duration = (end-start).total_seconds()
    return {"window_seconds": duration, "intervals": intervals, "gpu_index": gpu,
            "board_level_not_process_exclusive": True,
            "metrics": {name: {"time_weighted_sample_mean": data["weighted_sum"]/data["known_seconds"] if data["known_seconds"] else None,
                               "known_seconds": data["known_seconds"], "samples": data["samples"],
                               "coverage_fraction": data["known_seconds"]/duration}
                        for name, data in totals.items()}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("telemetry", type=Path)
    parser.add_argument("run", type=Path)
    parser.add_argument("--utc-offset-hours", type=float, required=True)
    parser.add_argument("--warmup-seconds", type=float, default=10)
    args = parser.parse_args()
    launch = (args.run/"launch.log").read_text(encoding="utf-8-sig")
    stamps = re.findall(r"(?m)^offline_benchmark.started_utc=([^\r\n]+)", launch)
    if len(stamps) != 1: raise ValueError("missing or ambiguous workload start")
    beginning = datetime.fromisoformat(stamps[0].replace("Z", "+00:00"))
    duration = json.loads((args.run/"configuration.json").read_text(encoding="utf-8-sig"))["duration_seconds"]
    if not 0 <= args.warmup_seconds < duration: raise ValueError("invalid warm-up")
    report = summarize(args.telemetry.read_text(encoding="utf-8-sig"),
                       beginning+timedelta(seconds=args.warmup_seconds),
                       beginning+timedelta(seconds=duration), args.utc_offset_hours)
    report["workload_start_utc"] = beginning.isoformat()
    report["source_sha256"] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                               for path in (args.telemetry, args.run/"launch.log", args.run/"configuration.json")}
    print(json.dumps(report, indent=2))


if __name__ == "__main__": main()
