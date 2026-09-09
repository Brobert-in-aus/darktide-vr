"""Summarize bounded marker input diagnostics, without claiming raster equality."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re

PREFIX = "DARKTIDEVR_MARKER_METRICS "
KINDS = {"markers", "interaction", "tag"}
DIFFERENCES = ("shape", "font", "scale", "alpha", "color_alpha", "text_layout",
               "layer", "start_layer", "offset_depth")
MAXIMA = ("max_anchor_delta", "max_layer_delta", "max_offset_depth_delta")
COUNTS = ("left", "right", "matched", "kind_mismatch", "text_measured") + DIFFERENCES


def fields(message):
    result = {}
    for token in message.split():
        if "=" not in token:
            raise ValueError("invalid diagnostic token")
        key, value = token.split("=", 1)
        if key in result or not re.fullmatch(r"[a-z_]+", key) or not value:
            raise ValueError("duplicate or invalid diagnostic field")
        result[key] = value
    return result


def integer(value):
    if not re.fullmatch(r"[0-9]{1,12}", value):
        raise ValueError("invalid nonnegative counter")
    return int(value)


def boolean(value):
    if value not in {"true", "false"}:
        raise ValueError("invalid boolean")
    return value == "true"


def pair(row):
    expected = set(COUNTS + MAXIMA) | {"kind", "incomplete", "input_geometry_only"}
    if set(row) != expected:
        raise ValueError("unsupported or incomplete pair format")
    parsed = {name: integer(row[name]) for name in COUNTS}
    parsed["incomplete"] = boolean(row["incomplete"])
    if not boolean(row["input_geometry_only"]):
        raise ValueError("missing input-only evidence marker")
    for name in MAXIMA:
        parsed[name] = float(row[name])
        if not math.isfinite(parsed[name]) or parsed[name] < 0:
            raise ValueError("invalid maximum delta")
    matched = parsed["matched"]
    if matched + parsed["kind_mismatch"] > min(parsed["left"], parsed["right"], 128):
        raise ValueError("impossible matched-call counts")
    if any(parsed[name] > matched for name in DIFFERENCES + ("text_measured",)):
        raise ValueError("difference count exceeds matched calls")
    if parsed["text_layout"] > parsed["text_measured"]:
        raise ValueError("text differences exceed measured text")
    if not parsed["incomplete"] and (matched != parsed["left"] or matched != parsed["right"]):
        raise ValueError("complete pair has missing or mismatched calls")
    return parsed


def group():
    return dict(pairs=0, nonempty_pairs=0, empty_pairs=0, incomplete_pairs=0,
                matching_input_pairs=0, unmatched_scopes=0,
                counters={name: 0 for name in COUNTS},
                maximum_deltas={name: 0.0 for name in MAXIMA})


def summarize(lines):
    sessions = []
    current = None

    def begin(line, observed, budget=None):
        item = dict(start_line=line, start_observed=observed, pass_budget=budget,
                    end_line=None, termination="log_end", minimum_observed_scopes=0, kinds={})
        sessions.append(item)
        return item

    for number, line in enumerate(lines, 1):
        if PREFIX not in line:
            continue
        try:
            row = fields(line.split(PREFIX, 1)[1])
            if "started" in row:
                if set(row) != {"started", "pass_budget"} or not boolean(row["started"]):
                    raise ValueError("invalid start record")
                budget = integer(row["pass_budget"])
                if not 2 <= budget <= 240:
                    raise ValueError("invalid pass budget")
                if current is not None:
                    current.update(end_line=number-1, termination="new_start")
                current = begin(number, True, budget)
                continue
            if current is None:
                current = begin(number, False)
            if "complete" in row:
                if set(row) != {"complete"} or not boolean(row["complete"]):
                    raise ValueError("invalid completion record")
                current.update(end_line=number, termination="budget_complete")
                current = None
                continue
            kind = row.get("kind")
            if kind not in KINDS:
                raise ValueError("unknown marker kind")
            item = current["kinds"].setdefault(kind, group())
            if "unmatched" in row:
                if set(row) != {"kind", "unmatched", "input_geometry_only"} or \
                        not boolean(row["unmatched"]) or not boolean(row["input_geometry_only"]):
                    raise ValueError("invalid unmatched record")
                item["unmatched_scopes"] += 1
                current["minimum_observed_scopes"] += 1
            else:
                parsed = pair(row)
                item["pairs"] += 1
                nonempty = bool(parsed["left"] or parsed["right"])
                item["nonempty_pairs"] += int(nonempty)
                item["empty_pairs"] += int(not nonempty)
                item["incomplete_pairs"] += int(parsed["incomplete"])
                item["matching_input_pairs"] += int(nonempty and not parsed["incomplete"] and
                    not any(parsed[name] for name in DIFFERENCES))
                for name in COUNTS:
                    item["counters"][name] += parsed[name]
                for name in MAXIMA:
                    item["maximum_deltas"][name] = max(item["maximum_deltas"][name], parsed[name])
                current["minimum_observed_scopes"] += 2
            budget = current["pass_budget"]
            if budget is not None and current["minimum_observed_scopes"] > budget:
                raise ValueError("records exceed the declared pass budget")
            current["end_line"] = number
        except (ValueError, KeyError, OverflowError) as error:
            raise ValueError(f"Marker diagnostic line {number}: {error}") from error
    if not sessions:
        raise ValueError("No marker diagnostic records found")
    return dict(schema_version=1, evidence="observed_gui_inputs_only",
                visual_acceptance="unverified", raster_bounds_verified=False,
                per_frame_identity_available=False, sessions=sessions)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        if args.output and (args.output.resolve() == args.log.resolve() or
                            (args.output.exists() and args.output.samefile(args.log))):
            raise ValueError("Output must not replace the input log")
        data = args.log.read_bytes()
        report = summarize(data.decode("utf-8-sig").splitlines())
        report["input_sha256"] = hashlib.sha256(data).hexdigest()
        report["input_bytes"] = len(data)
        result = json.dumps(report, indent=2, allow_nan=False) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(result, encoding="utf-8")
        else:
            print(result, end="")
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(2, f"{error}\n")


if __name__ == "__main__":
    main()
