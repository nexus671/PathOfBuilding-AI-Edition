"""Build the reviewed 3.30 modifier overlay from the pinned local client export."""
# cspell:ignore repoe
import argparse
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_HASH = "a6814fdd00755eca4208b2d5bae7877795e5c91a2d0935daa6748b49f26ec0ce"
BASE_COMMIT = "ae6d85a5c36857e08819852ab8732239294aba59"
BASE_HASH = "ff3119817742fcf26a3d96db21e276fb50eb158d23f287843a4a62978239b7a2"
RECONSTRUCTED_LEVELS = 368
CHANGED_RECORDS = 813
FIELDS = ("groups", "stats", "domain", "implicit_tags", "adds_tags", "generation_weights",
          "spawn_weights", "is_essence_only", "required_level", "generation_type")
NEW_IDS = ("PlayerIsDeliriousEssence1", "V2MinPowerChargesCorruptedNew")


def build(baseline, raw, jewel_rows=None):
    if baseline["patch"] != "3.29.3.6" or baseline["source"]["commit"] != BASE_COMMIT:
        raise ValueError("The modifier overlay requires the reviewed 3.29 baseline")
    normalized = json.dumps(baseline, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if hashlib.sha256(normalized).hexdigest() != BASE_HASH:
        raise ValueError("The crafting baseline does not match the reviewed data")
    if hashlib.sha256(raw).hexdigest() != SOURCE_HASH:
        raise ValueError("The client modifier export does not match the reviewed 3.30.0.1.4 source")
    client = json.loads(raw)
    previous = baseline["mods"]
    jewel_rows = jewel_rows or {}
    result = {}
    repaired = 0
    for ident in sorted(set(previous) | set(NEW_IDS) | set(jewel_rows)):
        mod = copy.deepcopy(client[ident])
        if ident in jewel_rows:
            jewel = jewel_rows[ident]
            if (jewel["group"] not in mod["groups"] or jewel["level"] != mod["required_level"]
                    or jewel["stats"] != mod["stats"] or jewel["weights"] != mod["spawn_weights"]
                    or jewel["type"] != mod["generation_type"]):
                raise ValueError(f"Unveiled jewel metadata differs from the client export: {ident}")
        old = previous.get(ident, {})
        for stat in mod["stats"]:
            prior = next((s for s in old.get("stats", []) if s["id"] == stat["id"]), None)
            if (prior and (prior["min"] or prior["max"]) and stat["id"].startswith("local_display_")
                    and stat["min"] == stat["max"] == 0 and mod.get("grants_effects")):
                levels = {effect["level"] for effect in mod["grants_effects"]}
                if len(levels) != 1 or next(iter(levels)) <= 0:
                    raise ValueError(f"Ambiguous granted effect level: {ident}")
                stat["min"] = stat["max"] = next(iter(levels))
                repaired += 1
        record = {key: mod[key] for key in FIELDS}
        if previous.get(ident) != record:
            result[ident] = record
    if repaired != RECONSTRUCTED_LEVELS:
        raise ValueError(f"Expected {RECONSTRUCTED_LEVELS} reviewed granted-effect levels, found {repaired}")
    if len(result) != CHANGED_RECORDS:
        raise ValueError(f"Expected {CHANGED_RECORDS} changed modifiers, found {len(result)}")
    return {"schemaVersion": 1, "basePatch": baseline["patch"], "baseCommit": BASE_COMMIT, "clientVersion": "3.30.0.1.4",
            "sourceSha256": SOURCE_HASH, "reconstructedLevels": repaired, "mods": result}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mods", type=Path, help="Pinned local 3.30.0.1.4 mods.json")
    parser.add_argument("--check", action="store_true", help="Verify the committed output without writing it")
    args = parser.parse_args()
    baseline = json.loads((ROOT / "src/Data/Crafting/3.29.json").read_text(encoding="utf-8"))
    jewels = json.loads((ROOT / "src/Data/Crafting/3.30-unveiled-jewels.json").read_text(encoding="utf-8"))
    if jewels["clientVersion"] != "3.30.0.1.4" or jewels["sourceSha256"] != SOURCE_HASH or len(jewels["mods"]) != 53:
        raise ValueError("The unveiled jewel fixture does not match the reviewed client export")
    output = ROOT / "src/Data/Crafting/3.30-modifier-overlay.json"
    encoded = json.dumps(build(baseline, args.mods.read_bytes(), jewels["mods"]), ensure_ascii=False, separators=(",", ":")) + "\n"
    if args.check:
        if output.read_text(encoding="utf-8") != encoded:
            raise ValueError("Modifier overlay differs from the reviewed sources")
    else:
        output.write_text(encoded, encoding="utf-8", newline="\n")
    print("3.30 modifier overlay verified" if args.check else "3.30 modifier overlay generated")


if __name__ == "__main__":
    main()
