"""Measure temporal overlap of runtime waits and OVR_BeginFrame; not causation."""
import argparse
from collections import defaultdict
import importlib.util
import json
from pathlib import Path

path = Path(__file__).with_name("summarize-vdxr-trace.py")
spec = importlib.util.spec_from_file_location("vdxr_trace", path)
trace = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trace)


def union(intervals):
    result = []
    for begin, end in sorted(intervals):
        if end < begin:
            raise ValueError("negative interval")
        if end == begin:
            continue
        if result and begin <= result[-1][1]:
            result[-1] = (result[-1][0], max(result[-1][1], end))
        else:
            result.append((begin, end))
    return result


def intersection_size(left, right):
    a = b = total = 0
    while a < len(left) and b < len(right):
        total += max(0, min(left[a][1], right[b][1]) - max(left[a][0], right[b][0]))
        if left[a][1] < right[b][1]:
            a += 1
        else:
            b += 1
    return total


def correlate(spans):
    begins = union((span[0], span[1]) for span in spans["OVR_BeginFrame"])
    if not begins:
        return {"status": "no_complete_begin_frame_spans", "groups": []}
    lower, upper = begins[0][0], begins[-1][1]
    groups = defaultdict(list)
    excluded = defaultdict(int)
    for name in ("WaitForAsyncSubmissionIdle", "xrEndFrame"):
        for begin, end, start_thread, end_thread, running_start in spans[name]:
            key = (name, start_thread, end_thread, running_start)
            # Drop complete waits crossing the retained complete-begin envelope.
            # Incomplete begin activities at capture edges cannot cover them.
            if begin < lower or end > upper:
                excluded[key] += 1
                continue
            groups[key].append((begin, end))
    output = []
    for key in sorted(groups.keys() | excluded.keys()):
        waits = union(groups[key])
        duration = sum(end - begin for begin, end in waits)
        overlap = intersection_size(waits, begins)
        output.append(dict(zip(("name", "start_thread", "end_thread", "running_start"), key),
                           spans=len(groups[key]), boundary_excluded=excluded[key],
                           wait_union_ms=duration / 1e6,
                           begin_frame_overlap_ms=overlap / 1e6,
                           overlap_fraction=overlap / duration if duration else None))
    return {"status": "temporal_overlap_only", "analysis_start_ns": lower,
            "analysis_end_ns": upper, "begin_frame_spans": len(spans["OVR_BeginFrame"]),
            "begin_frame_threads": sorted({(s[2], s[3]) for s in spans["OVR_BeginFrame"]}),
            "groups": output}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xml", type=Path)
    parser.add_argument("--process-id", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.process_id <= 0:
        parser.error("process ID must be positive")
    if args.output.resolve() == args.xml.resolve() or \
            (args.output.exists() and args.output.samefile(args.xml)):
        parser.error("Output must not replace the input trace")
    spans = {name: [] for name in ("OVR_BeginFrame", "WaitForAsyncSubmissionIdle", "xrEndFrame")}
    summary = trace.summarize(args.xml, args.process_id, spans)
    result = correlate(spans)
    result.update(process_id=args.process_id, trace_header=summary["trace_header"],
                  excluded_activities=summary["excluded_activities"],
                  circular_overwrite_indicated=summary["circular_overwrite_indicated"],
                  note="CPU-observed intervals; union avoids double counting. Overlap does not identify a backend cause.")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
