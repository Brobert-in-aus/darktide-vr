"""Map debugger residency samples; percentages are not sampled CPU time."""
from __future__ import annotations
import argparse
import bisect
import collections
import csv
import hashlib
import importlib.util
import json
import math
import re
import statistics
import struct
from pathlib import Path
import pefile

KNOWN_ENGINE = "6fce8db87a77a412b22ef9f33f74fa16ef85126cc0fbb24187d78b85fc7a19d3"

def kernel_route(flags, kernel_flags):
    if kernel_flags is None:
        return "unknown"
    if kernel_flags & 1 or (flags & 0x20 and not kernel_flags & 4):
        return "compute_async_queue_candidate" if kernel_flags & 2 else "compute_graphics_queue_candidate"
    if flags & 0x20:
        return "ray_dispatch_candidate"
    return "instancer_candidate" if flags & 0x80000000 else "direct_draw_candidate"

def read_bundle_samples(row, count):
    attempted = int(row.get("bundle_attempted", 0))
    if attempted == 0:
        return 0, []
    if not 1 <= count <= 10000000 or attempted != min(count, 8):
        raise ValueError("Invalid bounded bundle sample count")
    result = []
    for i in range(attempted):
        valid = row[f"bundle{i}_valid"]
        index, flags, opcode = (int(row[f"bundle{i}_{key}"]) for key in ("index", "flags", "opcode"))
        expected = i * (count - 1) // (attempted - 1) if attempted > 1 else 0
        if valid not in ("0", "1") or index != expected or not 0 <= flags <= 0xffffffff or not 0 <= opcode <= 0xffff:
            raise ValueError("Invalid bundle position, flags or opcode")
        if valid == "0":
            if flags or opcode or row.get(f"bundle{i}_kernel_valid", "0") != "0" or int(row.get(f"bundle{i}_kernel_flags", "0")):
                raise ValueError("Unreadable bundle contains command metadata")
            continue
        category = 3 if flags & 0x80000000 else 2 if flags & 0x20 else 1 if flags & 4 else 0
        kernel_valid = row.get(f"bundle{i}_kernel_valid", "0")
        kernel_flags = int(row.get(f"bundle{i}_kernel_flags", "0"))
        if kernel_valid not in ("0", "1") or not 0 <= kernel_flags <= 0xffffffff:
            raise ValueError("Invalid kernel flags")
        if (kernel_valid == "1" and opcode != 0x23) or (kernel_valid == "0" and kernel_flags):
            raise ValueError("Kernel flags lack an eligible command")
        kernel_flags = kernel_flags if kernel_valid == "1" else None
        result.append((category, flags, opcode, kernel_flags, kernel_route(flags, kernel_flags)))
    return attempted, result

def analyze(directory: Path) -> dict:
    receipt = json.loads((directory / "receipt.json").read_text(encoding="utf-8-sig"))
    modules = json.loads((directory / "modules.json").read_text(encoding="utf-8-sig"))
    lines = (directory / "samples.csv").read_text(encoding="utf-8-sig").splitlines()
    header = dict(re.findall(r"(\w+)=(\d+)", lines[0]))
    if not lines[0].startswith("RESIDENCY_BEGIN ") or receipt["exit_code"] != 0:
        raise ValueError("Incomplete residency capture")
    for key in ("pid", "thread"):
        if int(header[key]) != receipt[key]:
            raise ValueError("Capture identity mismatch")
    rows = list(csv.DictReader(lines[1:]))
    if int(header["failure"]) or len(rows) != int(header["samples"]) or len(rows) != int(header["requested"]) or not 1 <= len(rows) <= 2000 or int(header["frequency"]) <= 0:
        raise ValueError("Incomplete sample window")
    modules.sort(key=lambda m: m["base_address"])
    for left, right in zip(modules, modules[1:]):
        if left["base_address"] + left["size"] > right["base_address"]:
            raise ValueError("Overlapping module map")
    bases = [m["base_address"] for m in modules]
    engines = [m for m in modules if m["name"].lower() == "darktide.exe"]
    if len(engines) != 1:
        raise ValueError("Expected one engine module")
    engine = engines[0]
    data = Path(engine["path"]).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != receipt["game_sha256"].lower():
        raise ValueError("Recorded engine hash differs from local file")
    pe = pefile.PE(data=data)
    if pe.FILE_HEADER.Machine != 0x8664:
        raise ValueError("Only x64 captures are supported")
    entries = sorted((e.struct.BeginAddress, e.struct.EndAddress, e.struct.UnwindData)
                     for e in pe.DIRECTORY_ENTRY_EXCEPTION)
    unwind_starts = [e[0] for e in entries]
    spec = importlib.util.spec_from_file_location("engine_mapper", Path(__file__).with_name("map-engine-render-scopes.py"))
    mapper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mapper)
    def owner(rva: int) -> str:
        i = bisect.bisect_right(unwind_starts, rva) - 1
        if i < 0 or rva >= entries[i][1]:
            return "unmapped"
        return hex(mapper.unwind_chain(pe, entries[i])[-1]["begin_rva"])
    counts, owners, locations, callers = (collections.Counter() for _ in range(4))
    module_locations = collections.Counter()
    parents = collections.Counter()
    layouts = []
    categories = []
    queues = []
    chunks = []
    bundle_attempted = 0
    bundle_observations = collections.Counter()
    peer_locations, dispatch_peer_locations = collections.Counter(), collections.Counter()
    peer_thread = receipt.get("peer_thread", 0)
    def peer_location(row):
        if not peer_thread:
            return None
        if int(row.get("peer_thread", 0)) != peer_thread or row.get("peer_read") != "1":
            raise ValueError("Peer identity or context missing")
        ip = int(row["peer_rip"], 16)
        i = bisect.bisect_right(bases, ip) - 1
        if i < 0 or ip >= bases[i] + modules[i]["size"]:
            return ("unmapped", hex(ip), "unmapped")
        module = modules[i]
        rva = ip - module["base_address"]
        return (module["name"], hex(rva), owner(rva) if module is engine else "unresolved")
    pauses, qpcs = [], []
    wait_samples = stack_samples = rejected_callers = 0
    known_wait = digest == KNOWN_ENGINE and pe.get_data(0x6F7760, 4) == bytes.fromhex("4883ec28")
    known_parent = known_wait and pe.get_data(0x6F94D9, 11) == bytes.fromhex("488bc4415441574883ec78")
    for row in rows:
        peer = peer_location(row)
        if peer is not None:
            peer_locations[peer] += 1
        ip, qpc, pause = int(row["rip"], 16), int(row["qpc"]), float(row["pause_us"])
        if not math.isfinite(pause) or pause < 0 or (qpcs and qpc <= qpcs[-1]):
            raise ValueError("Invalid sample timing")
        pauses.append(pause)
        qpcs.append(qpc)
        i = bisect.bisect_right(bases, ip) - 1
        if i < 0 or ip >= bases[i] + modules[i]["size"]:
            counts["unmapped"] += 1
            continue
        module = modules[i]
        counts[module["name"]] += 1
        module_locations[(module["name"], hex(ip - module["base_address"]))] += 1
        if module is not engine:
            continue
        rva = ip - module["base_address"]
        owners[owner(rva)] += 1
        locations[hex(rva)] += 1
        # This exact body has sub rsp,0x28 and no intervening stack adjustment.
        # Interpret s5 only in its verified wait loop, not as a general unwind.
        if known_wait and 0x6F77C4 <= rva < 0x6F77DF:
            wait_samples += 1
            if row.get("stack_read") != "1":
                continue
            stack_samples += 1
            caller_return = int(row["s5"], 16) - engine["base_address"]
            instruction = pe.get_data(caller_return - 5, 5) if 5 <= caller_return < engine["size"] else b""
            if len(instruction) == 5 and instruction[0] == 0xE8 and caller_return + struct.unpack("<i", instruction[1:])[0] == 0x6F7760:
                callers[(hex(caller_return - 5), owner(caller_return - 5))] += 1
                # The list-wait caller pushes 16 bytes and subtracts 0x78.
                # Its return slot is leaf RSP + 0x30 + 0x88 = 0xb8 (s23).
                if known_parent and caller_return == 0x6F9542 and "s23" in row:
                    parent_return = int(row["s23"], 16) - engine["base_address"]
                    parent_call = pe.get_data(parent_return - 5, 5) if 5 <= parent_return < engine["size"] else b""
                    if len(parent_call) == 5 and parent_call[0] == 0xE8 and parent_return + struct.unpack("<i", parent_call[1:])[0] == 0x6F94D0:
                        parents[(hex(parent_return - 5), owner(parent_return - 5))] += 1
                        if parent_return == 0x7AC4AA and row.get("layout_read") == "1" and receipt.get("observe_dispatch_layout"):
                            layout = {key: int(row[key]) for key in ("workers", "commands", "weighted_commands", "history_commands", "weighted_enabled")}
                            layout["history_cost_raw"] = float(row["history_cost"])
                            if not 0 <= layout["workers"] <= 64 or layout["weighted_enabled"] not in (0, 1) or any(not 0 <= layout[key] <= 10000000 for key in ("commands", "weighted_commands", "history_commands")) or not math.isfinite(layout["history_cost_raw"]):
                                raise ValueError("Implausible dispatcher layout; do not interpret field offsets")
                            layouts.append(layout)
                            attempted, observed = read_bundle_samples(row, layout["weighted_commands"])
                            bundle_attempted += attempted
                            bundle_observations.update(observed)
                            if row.get("chunks_read") == "1":
                                count = int(row["chunk_count"])
                                if not 1 <= count <= 32 or int(row["boundary_count"]) != count:
                                    raise ValueError("Implausible chunk count")
                                chunk_starts = [int(row[f"chunk_start{i}"]) for i in range(count)]
                                end = layout["weighted_commands"]
                                if chunk_starts[0] != 0 or any(a >= b for a, b in zip(chunk_starts, chunk_starts[1:])) or chunk_starts[-1] >= end:
                                    raise ValueError("Invalid weighted chunk boundaries")
                                sizes = [b - a for a, b in zip(chunk_starts, chunk_starts[1:] + [end])]
                                chunks.append({"count": count, "sizes": sizes})
                            if peer is not None:
                                dispatch_peer_locations[peer] += 1
                            if row.get("queues_read") == "1":
                                depths = (int(row["queue_a"]), int(row["queue_b"]))
                                if any(not 0 <= x <= 1000000 for x in depths):
                                    raise ValueError("Implausible queue depth")
                                queues.append(depths)
                            if row.get("categories_read") == "1":
                                values = [{"cost_raw": float(row[f"category{i}_cost"]),
                                           "records": int(row.get(f"category{i}_records", row.get(f"category{i}_commands")))} for i in range(4)]
                                if any(not math.isfinite(x["cost_raw"]) or x["cost_raw"] < 0 or
                                       not 0 <= x["records"] <= 10000000 for x in values):
                                    raise ValueError("Implausible category history; do not interpret field offsets")
                                categories.append(values)
                    else:
                        parents[("unverified", "unverified")] += 1
            else:
                rejected_callers += 1
    return {
        "scope": "instruction-pointer residency including waits; not CPU-time shares",
        "samples": len(rows), "sample_span_seconds": (qpcs[-1] - qpcs[0]) / int(header["frequency"]),
        "modules": dict(counts.most_common()), "engine_primary_owners": dict(owners.most_common()),
        "top_module_rvas": [{"module": name, "rva": rva, "samples": n}
                            for (name, rva), n in module_locations.most_common(30)],
        "top_engine_rvas": dict(locations.most_common(30)), "wait_loop_samples": wait_samples,
        "wait_stack_samples": stack_samples, "rejected_wait_callers": rejected_callers,
        "wait_callers": [{"call_rva": call, "primary_rva": primary, "samples": n}
                         for (call, primary), n in callers.most_common()],
        "list_wait_parents": [{"call_rva": call, "primary_rva": primary, "samples": n}
                              for (call, primary), n in parents.most_common()],
        "dispatch_layout": {
            "samples": len(layouts),
            "workers": dict(collections.Counter(x["workers"] for x in layouts)),
            "weighted_enabled": dict(collections.Counter(x["weighted_enabled"] for x in layouts)),
            "ranges": {key: [min(x[key] for x in layouts), max(x[key] for x in layouts)]
                       for key in ("commands", "weighted_commands", "history_commands", "history_cost_raw")} if layouts else {},
        },
        "pause_mean_us": statistics.mean(pauses),
        "dispatch_chunks": {
            "samples": len(chunks),
            "scope": "repeated weighted bundle partitions at waits; bundle count is not CPU cost",
            "counts": dict(collections.Counter(x["count"] for x in chunks)),
            "bundle_size_range": [min(min(x["sizes"]) for x in chunks), max(max(x["sizes"]) for x in chunks)] if chunks else None,
            "observed_partitions": [{"bundle_sizes": list(sizes), "samples": n}
                                    for sizes, n in collections.Counter(tuple(x["sizes"]) for x in chunks).most_common(20)],
        },
        "dispatch_bundle_commands": {
            "scope": "eight evenly spaced sorted bundles per wait; first opcode only; repeated observations, not workload or CPU shares",
            "attempted": bundle_attempted,
            "valid": sum(bundle_observations.values()),
            "observed": [{"category": category, "flags": hex(flags), "first_opcode": hex(opcode),
                          "kernel_flags": hex(kernel) if kernel is not None else None, "candidate_route": route, "samples": n}
                         for (category, flags, opcode, kernel, route), n in bundle_observations.most_common()],
        },
        "paired_residency": {
            "thread": peer_thread or None,
            "scope": "peer paused after primary; perturbed overlap, not atomic running-state or CPU-time shares",
            "all_samples": sum(peer_locations.values()),
            "dispatch_wait_samples": sum(dispatch_peer_locations.values()),
            "all_locations": [{"module": m, "rva": r, "primary_rva": p, "samples": n}
                              for (m, r, p), n in peer_locations.most_common(30)],
            "during_dispatch_wait": [{"module": m, "rva": r, "primary_rva": p, "samples": n}
                                     for (m, r, p), n in dispatch_peer_locations.most_common(30)],
        },
        "dispatch_queues": {
            "samples": len(queues),
            "scope": "sequential reads while workers run; zero depths do not imply all jobs complete",
            "observed_pairs": [{"queue_a": a, "queue_b": b, "samples": n}
                               for (a, b), n in collections.Counter(queues).most_common()],
        },
        "dispatch_category_history": {
            "samples": len(categories),
            "scope": "existing aggregate history at sampled waits; repeated snapshots, not per-frame timings",
            "categories": [{"index": i,
                            "cost_raw_range": [min(x[i]["cost_raw"] for x in categories), max(x[i]["cost_raw"] for x in categories)],
                            "records_range": [min(x[i]["records"] for x in categories), max(x[i]["records"] for x in categories)]}
                           for i in range(4)] if categories else [],
        },
        "pause_p95_us": sorted(pauses)[math.ceil(len(pauses) * .95) - 1], "pause_max_us": max(pauses),
        "source_sha256": {name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
                          for name in ("receipt.json", "modules.json", "samples.csv")},
        "engine_sha256": digest,
    }

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    result = analyze(args.directory)
    (args.directory / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
