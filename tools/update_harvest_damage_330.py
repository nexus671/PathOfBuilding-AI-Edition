"""Extract the 3.30 Harvest damage-conversion eligibility and costs."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_HASH = "65c690ba4e90dbafb0f3ff5c433e72fd4dc363f5a43880a5a8b201f682ea109d"
ELEMENTS = ("fire", "cold", "lightning")
LIFEFORCE = {1: "wild_lifeforce", 2: "vivid_lifeforce", 3: "primal_lifeforce", 5: "crystallised_rancour"}


def build(raw):
    if hashlib.sha256(raw).hexdigest() != SOURCE_HASH:
        raise ValueError("Harvest export differs from the reviewed 3.30 client data")
    rows = {row["Id"]: row for row in json.loads(raw)}
    groups, recipes = {}, {}
    for source in ELEMENTS:
        for target in ELEMENTS:
            if source == target:
                continue
            row = rows[f"Change{source.title()}To{target.title()}Damage"]
            tokens = row["Parameters"].split()
            if row["Command"] != "convert_mod" or tokens[-3:] != ["CONVERT", source, target]:
                raise ValueError("Unexpected Harvest conversion command")
            eligible = tokens[:-3]
            if not eligible or len(eligible) != len(set(eligible)):
                raise ValueError("Invalid Harvest modifier groups")
            if source in groups and groups[source] != eligible:
                raise ValueError("Inconsistent Harvest modifier groups")
            groups[source] = eligible
            types, costs = row["LifeforceTypes"], row["LifeforceCosts"]
            if len(types) != 3 or len(costs) != 3 or len(set(types)) != 3:
                raise ValueError("Unexpected Harvest conversion costs")
            recipes[f"{source}:{target}"] = {LIFEFORCE[k]: v for k, v in zip(types, costs)}
    return {"schemaVersion": 1, "clientVersion": "3.30.0.2", "sourceSha256": SOURCE_HASH,
            "groups": groups, "costs": recipes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path, help="Reviewed harvest_costs.json client export")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    output = ROOT / "src/Data/Crafting/3.30-harvest-damage.json"
    encoded = json.dumps(build(args.export.read_bytes()), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if output.read_text(encoding="utf-8") != encoded:
            raise ValueError("Harvest conversion data differs from reviewed export")
    else:
        output.write_text(encoded, encoding="utf-8", newline="\n")
    print("Harvest damage-conversion data verified" if args.check else "Harvest damage-conversion data generated")


if __name__ == "__main__":
    main()
