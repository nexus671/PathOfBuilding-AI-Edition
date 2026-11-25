"""Generate a small Soul Core reference from the pinned 3.30 gem export."""
# cspell:ignore disempower diminishment destitution encumbrance impotence lethargy mediocrity nullification taxation
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/Data/Crafting/GemSoulCores330.json"
COMMIT = "c97553d1fc14a134dd6813e672d2b45fddf5b42d"
GEMS_SHA256 = "140da08739137ad6d21ffa77002dd059fafb288be79b1e67f87d3a446b0ef253"
IDS = ("SupportConstriction", "SupportDisempower", "SupportDiminishment", "SupportDestitution", "SupportEncumbrance", "SupportImpotence", "SupportLethargy", "SupportMediocrity", "SupportNullification", "SupportPoverty", "SupportPenance", "SupportTaxation")
CORE_NAMES = ("Soul Core of Intellect", "Soul Core of Might", "Soul Core of Finesse", "Soul Core of Instability")


def build(gems, currencies, digest):
    if digest != GEMS_SHA256:
        raise ValueError("The gem export does not match the pinned 3.30.0.4 source")
    cores = []
    for name in CORE_NAMES:
        matches = [v for v in currencies.values() if v.get("name") == name]
        if len(matches) != 1 or not matches[0].get("description"):
            raise ValueError(f"Expected one description for {name}")
        cores.append({"name": name, "description": matches[0]["description"]})
    outcomes = []
    for key in IDS:
        gem = gems[key]
        if not gem.get("is_support") or not gem.get("display_name") or gem["base_item"]["max_level"] != 1:
            raise ValueError(f"Unexpected support definition: {key}")
        static = gem["static"]
        effects = [value for _, value in sorted((static.get("stat_text") or {}).items())]
        multiplier = static.get("cost_multiplier")
        if multiplier is not None and multiplier != 100:
            effects.insert(0, f"Cost multiplier: {multiplier}%")
        if not effects:
            raise ValueError(f"Missing effect for {key}")
        outcomes.append({"id": key, "name": gem["display_name"], "effects": effects, "supportText": gem["support_gem"]["support_text"]})
    return {"_comment": "Generated GGG game data from RePoE. cspell:disable", "patch": "3.30.0.4", "sourceCommit": COMMIT, "gemsSha256": digest, "cores": cores, "downsides": outcomes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gems", type=Path, help="Pinned 3.30.0.4 gems.json")
    parser.add_argument("--check", action="store_true", help="Compare without writing")
    args = parser.parse_args()
    raw = args.gems.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    currencies = json.loads((ROOT / "src/Data/Crafting/3.30.json").read_text(encoding="utf8"))["currencies"]
    output = json.dumps(build(json.loads(raw), currencies, digest), ensure_ascii=False, separators=(",", ":")) + "\n"
    if args.check:
        if OUTPUT.read_text(encoding="utf8") != output:
            raise SystemExit("Soul Core reference differs")
        print("Soul Core reference matches pinned source")
    else:
        OUTPUT.write_text(output, encoding="utf8", newline="\n")
        print("Generated Soul Core reference")


if __name__ == "__main__":
    main()
