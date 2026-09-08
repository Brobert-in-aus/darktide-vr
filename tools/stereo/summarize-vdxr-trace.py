"""Summarize VDXR TraceLogging activities from tracerpt XML without restarting XR.

Durations are CPU-observed wall time, including waits. Nested and concurrent
activities must not be added together. A circular ETL may retain only a suffix
even when the header reports zero lost events.
"""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import statistics
import xml.etree.ElementTree as ET

NS = {"e": "http://schemas.microsoft.com/win/2004/08/events/event"}
PROVIDER = "{cbf3adcd-42b1-4c38-930b-91980af201f6}"
ZERO_ACTIVITY = "{00000000-0000-0000-0000-000000000000}"


def events(source):
    stream = ET.iterparse(source, events=("start", "end"))
    _, root = next(stream)
    for action, element in stream:
        if action == "end" and element.tag == "{" + NS["e"] + "}Event":
            yield element
            root.remove(element)


def stats(values):
    ordered = sorted(values)
    return {"samples": len(values), "mean_ms": statistics.mean(values),
            "p50_ms": statistics.median(values),
            "p95_ms": ordered[(len(values)-1)*95//100], "maximum_ms": ordered[-1]}


def summarize(source, process_id):
    starts = {}
    durations = defaultdict(list)
    groups = defaultdict(list)
    counts, excluded = Counter(), Counter()
    header = {}
    first = last = None
    for element in events(source):
        provider = element.find("e:System/e:Provider", NS)
        data = {item.get("Name"): item.text for item in element.findall("e:EventData/e:Data", NS)}
        if "EventsLost" in data and "StartTime" in data and "BufferSize" in data:
            for key in ("EventsLost", "BuffersLost", "BuffersWritten", "BufferSize", "MaxFileSize",
                        "LogFileMode", "StartTime", "EndTime", "PerfFreq", "ReservedFlags"):
                if key in data:
                    value = data[key].strip()
                    header[key] = int(value, 16 if value.startswith("0x") else 10)
        if provider is None or provider.get("Guid", "").lower() != PROVIDER:
            continue
        execution = element.find("e:System/e:Execution", NS)
        if execution is None or execution.get("ProcessID") != str(process_id):
            continue
        # This Windows tracerpt version emits inconsistent +09:59/+10:00
        # offsets in one capture. Never derive durations from its formatted
        # SystemTime: require raw QPC ticks and the trace header's frequency.
        created = element.find("e:System/e:TimeCreated", NS)
        if created is None or created.get("RawTime") is None:
            raise ValueError("Raw timestamps required: regenerate XML with tracerpt -rts")
        if header.get("ReservedFlags") != 1 or header.get("PerfFreq", 0) <= 0:
            raise ValueError("Raw timestamps require a QPC trace header and positive PerfFreq")
        try:
            name = element.findtext("e:RenderingInfo/e:Task", namespaces=NS)
            if not name:
                raise ValueError("missing_activity_name")
            ticks = int(created.get("RawTime"))
            if ticks < 0:
                raise ValueError("invalid_timestamp")
            when = ticks * 10**9 // header["PerfFreq"]
            first = min(first, when) if first is not None else when
            last = max(last, when) if last is not None else when
            counts[name] += 1
            opcode = element.findtext("e:System/e:Opcode", namespaces=NS)
            if opcode not in ("1", "2"):
                continue
            activity = element.find("e:System/e:Correlation", NS).get("ActivityID", "").lower()
            if not activity or activity == ZERO_ACTIVITY:
                raise ValueError("missing_activity_identity")
            key = (name, activity)
            thread = execution.get("ThreadID", "unknown")
            if opcode == "1":
                if key in starts:
                    excluded["duplicate_start"] += 1
                starts[key] = (when, thread, data.get("DoRunningStart", "unreported"))
            else:
                began = starts.pop(key, None)
                if began is None:
                    excluded["stop_without_start"] += 1
                elif when < began[0]:
                    excluded["negative_duration"] += 1
                else:
                    duration = (when-began[0])/1e6
                    durations[name].append(duration)
                    groups[(name, began[1], thread, began[2])].append(duration)
        except (AttributeError, TypeError, ValueError) as error:
            excluded[str(error)] += 1
    excluded["start_without_stop"] += len(starts)
    circular = bool(header.get("LogFileMode", 0) & 2)
    overwritten = circular and header.get("MaxFileSize", 0) > 0 and (
        header.get("BuffersWritten", 0)*header.get("BufferSize", 0) > header["MaxFileSize"]*1024**2)
    return {"scope": "CPU-observed wall time; do not sum nested/concurrent activities",
            "process_id": process_id, "trace_header": header,
            "circular_file": circular, "circular_overwrite_indicated": overwritten,
            "retained_event_span_seconds": (last-first)/1e9 if first is not None else None,
            "excluded_activities": dict(excluded), "event_counts": dict(counts),
            "activities": {key: stats(value) for key, value in sorted(durations.items())},
            "activity_groups": [dict(zip(("name", "start_thread", "end_thread", "running_start"), key),
                                     **stats(value)) for key, value in sorted(groups.items())]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xml", type=Path)
    parser.add_argument("--process-id", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.process_id <= 0:
        parser.error("process ID must be positive")
    try:
        result = summarize(args.xml, args.process_id)
    except ValueError as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key != "event_counts"}, indent=2))


if __name__ == "__main__":
    main()
