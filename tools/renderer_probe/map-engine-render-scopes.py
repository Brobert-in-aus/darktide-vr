"""Read-only mapping of engine profiling strings to x64 unwind ranges.

Install pefile==2024.8.26 and capstone==5.0.9 in an isolated Python environment.
No game process is opened. Output is build-specific evidence, not hook addresses.
"""
from __future__ import annotations

import argparse
import bisect
import hashlib
import json
import re
from pathlib import Path

import capstone
import pefile

LABELS = re.compile(
    r"^(?:RI::render_world|render_culled_scene|render_kernel_culled|"
    r"prepare rendering work|prepare render shadows|light culling and sort|"
    r"kick sphere culling.*|wait.*culling.*|reset_dlss|render_world|"
    r"stingray::RenderInterface::(?:.*render_world.*|update_world))$"
)
RIP = re.compile(r"\[rip ([+-]) (0x[0-9a-f]+)\]")


def analyze(path: Path, expected_hash: str) -> dict:
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != expected_hash.lower():
        raise ValueError("Executable hash mismatch; do not mix build addresses")
    pe = pefile.PE(data=data)
    if pe.FILE_HEADER.Machine != 0x8664:
        raise ValueError("Only Windows x64 executables are supported")
    base = pe.OPTIONAL_HEADER.ImageBase
    labels = {}
    for match in re.finditer(rb"[ -~]{5,}\x00", data):
        value = match.group()[:-1].decode("ascii")
        if LABELS.fullmatch(value):
            labels[base + pe.get_rva_from_offset(match.start())] = value
    ranges = sorted((entry.struct.BeginAddress, entry.struct.EndAddress)
                    for entry in pe.DIRECTORY_ENTRY_EXCEPTION)
    starts = [start for start, _ in ranges]
    decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    decoder.skipdata = True
    refs, calls = [], []
    for section in pe.sections:
        if not section.Characteristics & 0x20000000:
            continue
        for address, size, mnemonic, operands in decoder.disasm_lite(
                section.get_data(), base + section.VirtualAddress):
            rva = address - base
            if mnemonic == "call" and re.fullmatch(r"0x[0-9a-f]+", operands):
                calls.append((rva, int(operands, 16) - base))
            match = RIP.search(operands)
            if not match:
                continue
            target = address + size + int(match[2], 16) * (1 if match[1] == "+" else -1)
            if target not in labels:
                continue
            index = bisect.bisect_right(starts, rva) - 1
            owner = ranges[index] if index >= 0 and rva < ranges[index][1] else None
            refs.append({"label": labels[target], "string_rva": target - base,
                         "instruction_rva": rva, "unwind_range": owner})
    scopes = sorted({tuple(ref["unwind_range"]) for ref in refs if ref["unwind_range"]})
    return {
        "schema": 1, "sha256": digest, "image_base": base,
        "method": "linear x64 decode, RIP-relative string references, PE unwind ranges",
        "limitations": [
            "An unwind range may be a chained function fragment, not an entry point.",
            "Linear decoding can encounter embedded data; manually inspect candidates.",
            "Labels and direct calls do not prove live execution, cost or reusable work.",
            "Indirect calls and dynamically hashed labels are not resolved.",
        ],
        "references": refs,
        "scopes": [{"begin_rva": begin, "end_rva": end,
                    "labels": sorted({ref["label"] for ref in refs
                                      if ref["unwind_range"] == (begin, end)}),
                    "direct_calls": [{"instruction_rva": source, "target_rva": target}
                                     for source, target in calls if begin <= source < end]}
                   for begin, end in scopes],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-fA-F]{64}", args.expected_sha256):
        parser.error("Expected SHA-256 must contain 64 hexadecimal characters")
    if args.output.resolve() == args.executable.resolve() or (
            args.output.exists() and args.output.samefile(args.executable)):
        parser.error("Output must not overwrite the executable")
    report = analyze(args.executable, args.expected_sha256)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Mapped {len(report['references'])} references in {len(report['scopes'])} unwind ranges")


if __name__ == "__main__":
    main()
