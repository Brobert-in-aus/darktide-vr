"""Inventory stock hint construction without loading game code or sending input.

This is a review queue, not proof of controller functionality or visual coverage.
Dynamic expressions remain unresolved instead of being guessed from label text.
"""
import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path


CALL = re.compile(r"\b(input_text_for_current_input_device|localize_with_button_hint|"
                  r"get_input_alias_key|_get_view_input_text|_get_ingame_input_text)\s*\(")
LUA_TOKEN = re.compile(r"--\[(=*)\[.*?\]\1\]|--[^\n]*|"
                       r"\[(=*)\[.*?\]\2\]|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'",
                       re.DOTALL)


def masked(source):
    return LUA_TOKEN.sub(lambda match: re.sub(r"[^\n]", " ", match.group()), source)


def arguments(source, mask, opening):
    depth = 0
    start = opening + 1
    values = []
    for index in range(opening + 1, len(mask)):
        char = mask[index]
        if char in "([{":
            depth += 1
        elif char in ")]}":
            if char == ")" and depth == 0:
                values.append(source[start:index].strip())
                return values, index + 1
            depth -= 1
        elif char == "," and depth == 0:
            values.append(source[start:index].strip())
            start = index + 1
    raise ValueError("Unclosed hint call")


def literal(expression):
    match = re.fullmatch(r'''["']([A-Za-z0-9_]+)["']''', expression)
    return match.group(1) if match else None


def scan(source, path):
    mask = masked(source)
    records = []
    for match in CALL.finditer(mask):
        # The two local helpers are also declarations; report calls only.
        prefix = mask[max(0, match.start()-12):match.start()]
        if re.search(r"\bfunction\s+$", prefix):
            continue
        args, end = arguments(source, mask, match.end()-1)
        api = match.group(1)
        index = 1 if api == "input_text_for_current_input_device" else 0
        expression = args[index] if len(args) > index else ""
        # Conditional mouse/gamepad expressions expose multiple candidates.
        # Listing them does not establish which device branch will be active.
        candidates = re.findall(r'''["']([A-Za-z0-9_]+)["']''', expression)
        records.append({
            "path": path, "line": source.count("\n", 0, match.start())+1,
            "api": api, "arguments": args, "action_expression": expression,
            "literal_action": literal(expression), "action_candidates": candidates,
            "resolution": "literal" if literal(expression) else "dynamic_review_required",
            "controller_status": "route_and_live_check_required",
            "source_excerpt": source[match.start():end],
        })
    return records


def inventory(root):
    records, files = [], []
    for path in sorted((root / "scripts" / "ui").rglob("*.lua")):
        data = path.read_bytes()
        relative = path.relative_to(root).as_posix()
        found = scan(data.decode("utf-8-sig"), relative)
        if found:
            records.extend(found)
            files.append({"path": relative, "sha256": hashlib.sha256(data).hexdigest()})
    if not files:
        raise ValueError("No UI hint sources found under source-root/scripts/ui")
    # These user-reported cases must remain visible in the full inventory.
    # Missing source is an audit coverage failure, never a resolved UI bug.
    talent = [r for r in records if "talent_builder_view/" in r["path"] and
              "right_pressed" in r["action_candidates"] and
              "remove_level" in r["source_excerpt"]]
    onboarding = [r for r in records if "onboarding_templates.lua" in r["path"] and
                  r["literal_action"] == "hotkey_inventory"]
    checks = {
        "talent_deactivation_right_click": {
            "found": bool(talent), "status": "unfixed_acceptance_case",
            "sites": [{"path": r["path"], "line": r["line"]} for r in talent]},
        "onboarding_inventory_shortcut": {
            "found": bool(onboarding), "status": "unfixed_acceptance_case",
            "sites": [{"path": r["path"], "line": r["line"]} for r in onboarding]},
    }
    return {"kind": "source_inventory_not_visual_acceptance", "files": files,
            "summary": {"files": len(files), "calls": len(records),
                        "by_api": dict(Counter(r["api"] for r in records)),
                        "dynamic": sum(r["literal_action"] is None for r in records)},
            "user_acceptance_cases": checks, "calls": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = inventory(args.source_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"summary": report["summary"],
                      "user_acceptance_cases": report["user_acceptance_cases"]}))
    if not all(case["found"] for case in report["user_acceptance_cases"].values()):
        raise SystemExit("Audit coverage failure: a user-reported source case is missing")


if __name__ == "__main__":
    main()
