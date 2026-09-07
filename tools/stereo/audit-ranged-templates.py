"""Inventory direct ranged template routes/inputs in a local stock snapshot.

Lexical source evidence, not ownership, runtime inheritance or weapon acceptance.
Output is JSON on stdout; callers may save it under ignored artifacts.
"""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("bindings", type=Path)
args = parser.parse_args()
root = args.source / "scripts/settings/equipment/weapon_templates"
routes = {"shoot_hit_scan", "shoot_pellets", "shoot_projectile", "spawn_projectile",
          "flamer_gas", "flamer_gas_burst", "chain_lightning"}
bindings = set(re.findall(r'"([a-z_0-9]+)"', args.bindings.read_text(encoding="utf-8")))
rows = []
for path in sorted(root.glob("*/*.lua")):
    if path.parent.name in {"bot_weapons", "weapon_trait_templates"}:
        continue
    source = path.read_text(encoding="utf-8")
    kinds = set(re.findall(r'\bkind\s*=\s*"([a-z_]+)"', source)) & routes
    if not kinds:
        continue
    # action_inputs precedes action_input_hierarchy/actions in stock templates.
    # Restrict input literals to that table region; later tables include names
    # of internal action chains, which are not controller input columns.
    start = source.find("weapon_template.action_inputs =")
    end_match = re.search(r"\nweapon_template\.[a-z_]+\s*=", source[start + 1:]) if start >= 0 else None
    inputs_source = source[start:start + 1 + end_match.start()] if end_match else ""
    inputs = sorted(set(re.findall(r'\binput\s*=\s*"([a-z_0-9]+)"', inputs_source)))
    rows.append({"template": path.stem, "family": path.parent.name,
                 "path": path.relative_to(args.source).as_posix(),
                 "scope": "auxiliary" if path.parent.name in {"grenades", "weapon_template_generators"} else "player_ranged",
                 "routes": sorted(kinds), "inputs": inputs,
                 "unmapped_literal_inputs": sorted(set(inputs) - bindings),
                 "has_literal_input_table": bool(inputs_source),
                 "skip_aiming_literals": len(re.findall(r"\bskip_aiming\s*=\s*true", source))})
families = {}
for row in rows:
    family = families.setdefault(row["family"], {"templates": 0, "routes": set(), "unmapped": set()})
    family["templates"] += 1
    family["routes"].update(row["routes"])
    family["unmapped"].update(row["unmapped_literal_inputs"])
for family in families.values():
    family["routes"] = sorted(family["routes"])
    family["unmapped"] = sorted(family["unmapped"])
print(json.dumps({"scope": "direct top-level stock ranged template literals; no runtime availability/ownership claim",
                  "player_ranged_count": sum(row["scope"] == "player_ranged" for row in rows),
                  "template_count": len(rows), "families": families, "templates": rows}, indent=2))
