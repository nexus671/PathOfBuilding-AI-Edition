"""Extract area modifiers for future map crafting from the pinned game export."""
# cspell:ignore repoe
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "src/Data/Crafting/Map330.json"
FIELDS = ("name", "generation_type", "required_level", "groups", "spawn_weights",
          "generation_weights", "adds_tags", "stats", "text")


def extract(raw, expected_hash, base_raw, expected_base_hash, source):
    actual = hashlib.sha256(raw).hexdigest()
    if actual != expected_hash:
        raise ValueError("Modifier export does not match the pinned crafting data")
    base_hash = hashlib.sha256(base_raw).hexdigest()
    if base_hash != expected_base_hash:
        raise ValueError("Base-item export does not match the pinned crafting data")
    mods = json.loads(raw)
    bases = json.loads(base_raw)
    selected = {key: {field: value[field] for field in FIELDS}
                for key, value in mods.items()
                if value.get("domain") == "area" and value.get("generation_type") in ("prefix", "suffix")}
    if not selected:
        raise ValueError("No area modifiers found")
    map_bases = {key: {field: value[field] for field in
                       ("name", "tags", "release_state", "drop_level", "visual_identity")}
                 for key, value in bases.items() if value.get("item_class") == "Map"}
    if not map_bases:
        raise ValueError("No map bases found")
    return {"_comment": "Generated GGG game data from RePoE; cspell:disable",
            "patch": "3.30.0.2.2", "source": source, "modsSha256": actual,
            "basesSha256": base_hash, "bases": map_bases, "mods": selected}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mods", type=Path, help="Pinned RePoE mods.json")
    parser.add_argument("bases", type=Path, help="Pinned RePoE base_items.json")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    existing = json.loads((ROOT / "src/Data/Crafting/3.30.json").read_text(encoding="utf-8"))
    data = extract(args.mods.read_bytes(), existing["hashes"]["mods.json"],
                   args.bases.read_bytes(), existing["hashes"]["base_items.json"], existing["source"])
    encoded = json.dumps(data, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n"
    if args.check:
        if DESTINATION.read_text(encoding="utf-8") != encoded:
            raise ValueError("Map modifier data differs from the pinned export")
    else:
        DESTINATION.write_text(encoded, encoding="utf-8")
    print(f"Verified {len(data['mods'])} area modifier records and {len(data['bases'])} map bases")


if __name__ == "__main__":
    main()
