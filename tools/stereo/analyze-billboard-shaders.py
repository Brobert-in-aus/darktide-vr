#!/usr/bin/env python3
"""Build an evidence-based census of Darktide's live billboard shader families.

The native capture log records PSOs that matched the renderer's billboard
classification.  This tool joins that runtime evidence to captured vertex
shader DXIL, uses DXC reflection/disassembly, and groups shaders by executable
interface.  It deliberately does not claim that every classified shader is a
spherical particle: ribbon/tangent families remain separate and need their own
orientation proof.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import re
import subprocess
from collections import Counter, defaultdict
from pathlib import Path


HASH_RE = re.compile(r"^[0-9a-f]{16}$")
CBUFFER_RE = re.compile(r"^;\s+cbuffer (\S+)")
CBUFFER_SIZE_RE = re.compile(r"^;\s+\}.*Size:\s+(\d+)")
SIGNATURE_ROW_RE = re.compile(
    r"^;\s+(\S+)\s+(\d+)\s+([xyzw ]+)\s+(\d+)\s+(\S+)\s+(\S+)\s+([xyzw ]*)$"
)
LOAD_RE = re.compile(r"cbufferLoadLegacy\.\w+.*?i32 (\d+)\)\s+; CBufferLoadLegacy")


def parse_identity(
    path: Path, include_all_classified: bool
) -> tuple[Counter[str], dict[str, Counter[str]]]:
    vertex_counts: Counter[str] = Counter()
    pixel_counts: dict[str, Counter[str]] = defaultdict(Counter)
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        fields = dict(part.split("=", 1) for part in line.split("\t") if "=" in part)
        vertex = fields.get("vs", "").lower()
        pixel = fields.get("ps", "").lower()
        classified = (
            HASH_RE.fullmatch(vertex) is not None
            and HASH_RE.fullmatch(pixel) is not None
            and vertex != "0000000000000000"
            and pixel != "0000000000000000"
        )
        if not classified or (
            not include_all_classified and fields.get("billboard") != "1"
        ):
            continue
        vertex_counts[vertex] += 1
        if HASH_RE.fullmatch(pixel):
            pixel_counts[vertex][pixel] += 1
    return vertex_counts, pixel_counts


def signature_rows(text: str, heading: str) -> list[str]:
    rows: list[str] = []
    active = False
    saw_rows = False
    for line in text.splitlines():
        if line.startswith(f"; {heading} signature:"):
            active = True
            continue
        if not active:
            continue
        match = SIGNATURE_ROW_RE.match(line.rstrip())
        if match:
            rows.append(":".join("".join(part.split()) for part in match.groups()))
            saw_rows = True
        elif saw_rows and line.strip() == ";":
            break
    return rows


def reflect(dxc: Path, shader: Path) -> dict[str, object]:
    result = subprocess.run(
        [str(dxc), "-dumpbin", str(shader)],
        check=True,
        capture_output=True,
        text=True,
        errors="replace",
    )
    text = result.stdout
    cbuffers: list[str] = []
    current_cbuffer: str | None = None
    for line in text.splitlines():
        match = CBUFFER_RE.match(line)
        if match:
            current_cbuffer = match.group(1)
            continue
        match = CBUFFER_SIZE_RE.match(line)
        if match and current_cbuffer:
            cbuffers.append(f"{current_cbuffer}:{match.group(1)}")
            current_cbuffer = None

    resources: list[str] = []
    in_resources = False
    for line in text.splitlines():
        if line.startswith("; Resource Bindings:"):
            in_resources = True
            continue
        if in_resources and line.startswith("; ViewId state:"):
            break
        if in_resources and line.startswith(";"):
            columns = line[1:].split()
            if len(columns) >= 7 and columns[1] in {"cbuffer", "sampler", "texture", "UAV"}:
                resources.append(":".join((columns[0], columns[1], columns[-2], columns[-1])))

    inputs = signature_rows(text, "Input")
    outputs = signature_rows(text, "Output")
    loads = Counter(int(match.group(1)) for match in LOAD_RE.finditer(text))
    load_shape = ",".join(f"{register}:{count}" for register, count in sorted(loads.items()))
    interface = "|".join((",".join(inputs), ",".join(outputs), ",".join(resources)))
    return {
        "cbuffers": ",".join(cbuffers),
        "resources": ",".join(resources),
        "input_signature": ",".join(inputs),
        "output_signature": ",".join(outputs),
        "interface": hashlib.sha256(interface.encode()).hexdigest()[:16],
        "cbuffer_load_shape": load_shape,
        "instruction_lines": sum(1 for line in text.splitlines() if line.startswith("  %")),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("identity_log", type=Path)
    parser.add_argument("shader_directory", type=Path)
    parser.add_argument("--dxc", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--include-all-classified",
        action="store_true",
        help=(
            "Reflect every row with nonzero VS/PS identities. Use this for "
            "scene-delta captures whose target is missed by the billboard "
            "heuristic."
        ),
    )
    args = parser.parse_args()

    vertex_counts, pixel_counts = parse_identity(
        args.identity_log, args.include_all_classified
    )
    rows: list[dict[str, object]] = []
    missing: list[str] = []
    for vertex, count in vertex_counts.most_common():
        shader = args.shader_directory / f"vs-{vertex}.bin"
        if not shader.exists():
            missing.append(vertex)
            continue
        metadata = reflect(args.dxc, shader)
        pixels = pixel_counts[vertex]
        rows.append({
            "vertex_shader": vertex,
            "observed_pso_rows": count,
            "pixel_shader_count": len(pixels),
            "pixel_shaders": ",".join(f"{key}:{value}" for key, value in pixels.most_common()),
            **metadata,
        })

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        raise SystemExit("identity log contains no reflected shader identities")
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    interfaces = Counter(str(row["interface"]) for row in rows)
    label = "classified" if args.include_all_classified else "billboard"
    print(
        f"{label}_vertex_shaders={len(vertex_counts)} "
        f"reflected={len(rows)} missing={len(missing)}"
    )
    print(f"interface_families={len(interfaces)} output={args.output}")
    for interface, members in interfaces.most_common(12):
        observations = sum(int(row["observed_pso_rows"]) for row in rows if row["interface"] == interface)
        examples = ",".join(str(row["vertex_shader"]) for row in rows if row["interface"] == interface)[:101]
        print(f"interface={interface} shaders={members} observations={observations} examples={examples}")
    if missing:
        print("missing_hashes=" + ",".join(missing))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
