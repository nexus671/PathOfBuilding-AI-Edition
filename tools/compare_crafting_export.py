"""Compare a local RePoE modifier export with the current crafting supplement.

This reports differences only; matching identifiers do not establish that an
export or its schema is correct for a game version.
"""
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ("groups", "stats", "domain", "implicit_tags", "adds_tags",
          "generation_weights", "spawn_weights", "is_essence_only",
          "required_level", "generation_type")


def compare(previous, exported):
    old = previous["mods"]
    shared = old.keys() & exported.keys()
    changed = {field: sorted(key for key in shared
                             if old[key].get(field) != exported[key].get(field))
               for field in FIELDS}
    display_changes = []
    for key in sorted(shared):
        current = exported[key]
        effects = current.get("grants_effects") or []
        if not effects:
            continue
        old_stats = {stat["id"]: stat for stat in old[key].get("stats", [])}
        for stat in current.get("stats", []):
            prior = old_stats.get(stat["id"])
            if (prior and stat["id"].startswith("local_display_")
                    and (prior["min"], prior["max"]) != (0, 0)
                    and (stat["min"], stat["max"]) == (0, 0)):
                display_changes.append({"modifier": key, "stat": stat["id"],
                                        "previous_min": prior["min"], "previous_max": prior["max"],
                                        "granted_effects": effects})
    return {
        "previous_patch": previous["patch"],
        "previous_count": len(old),
        "export_count": len(exported),
        "shared_count": len(shared),
        "missing_ids": sorted(old.keys() - exported.keys()),
        "additional_count_by_domain": dict(sorted(Counter(
            mod.get("domain", "<missing>") for key, mod in exported.items()
            if key not in old).items())),
        "changed_ids_by_field": changed,
        "zeroed_display_stats_with_granted_effects": display_changes,
    }


def compare_records(previous, exported):
    """Report identity and field changes without treating a match as validation."""
    if not isinstance(previous, dict) or not isinstance(exported, dict):
        raise ValueError("Expected objects indexed by record ID")
    shared = previous.keys() & exported.keys()
    if any(not isinstance(row, dict) for row in list(previous.values()) + list(exported.values())):
        raise ValueError("Expected record objects")
    return {
        "previous_count": len(previous), "export_count": len(exported),
        "added_ids": sorted(exported.keys() - previous.keys()),
        "missing_ids": sorted(previous.keys() - exported.keys()),
        "changed_fields_by_id": {
            key: sorted(field for field in previous[key].keys() | exported[key].keys()
                        if field not in previous[key] or field not in exported[key]
                        or previous[key][field] != exported[key][field])
            for key in sorted(shared) if previous[key] != exported[key]
        },
    }


def currency_records(bases):
    if not isinstance(bases, dict):
        raise ValueError("Expected base items indexed by record ID")
    return {key: {"name": value["name"], "description": value.get("properties", {}).get("description"),
                  "release": value["release_state"]}
            for key, value in bases.items()
            if value["item_class"] in ("StackableCurrency", "DeepwaterCurrency") or "/Deepwater/" in key}


def read_candidate(path):
    raw = path.read_bytes()
    return json.loads(raw), hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mods", type=Path, help="Path to the candidate mods.json")
    parser.add_argument("--previous", type=Path, default=ROOT / "src/Data/Crafting/3.29.json")
    parser.add_argument("--fossils", type=Path, help="Optional candidate fossils.json")
    parser.add_argument("--base-items", type=Path, help="Optional candidate base_items.json for currency metadata")
    args = parser.parse_args()
    with args.previous.open(encoding="utf-8") as source:
        previous = json.load(source)
    with args.mods.open(encoding="utf-8") as source:
        exported = json.load(source)
    result = compare(previous, exported)
    for path, name, convert in ((args.fossils, "fossils", lambda value: value),
                                (args.base_items, "currencies", currency_records)):
        if path:
            candidate, digest = read_candidate(path)
            result[name] = compare_records(previous[name], convert(candidate))
            result[name]["candidate_sha256"] = digest
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
