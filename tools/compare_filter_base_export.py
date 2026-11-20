"""Compare filter-relevant fields in two client base-item exports."""
import argparse
import hashlib
import json
from pathlib import Path

FIELDS = ("name", "item_class", "drop_level", "inventory_width", "inventory_height")


def compare(old_raw, new_raw, old_classes=None, new_classes=None):
    old, new = json.loads(old_raw), json.loads(new_raw)
    if not isinstance(old, dict) or not isinstance(new, dict):
        raise ValueError("Expected base-item objects")
    shared = old.keys() & new.keys()
    result = {
        "oldSha256": hashlib.sha256(old_raw).hexdigest(),
        "newSha256": hashlib.sha256(new_raw).hexdigest(),
        "addedIds": sorted(new.keys() - old.keys()),
        "removedIds": sorted(old.keys() - new.keys()),
        "changedFields": {field: sorted(key for key in shared if old[key].get(field) != new[key].get(field)) for field in FIELDS},
        "note": "Field equality does not establish current drop availability or in-game filter behavior.",
    }
    if (old_classes is None) != (new_classes is None):
        raise ValueError("Supply both item-class exports or neither")
    if old_classes is not None:
        before, after = json.loads(old_classes), json.loads(new_classes)
        if not isinstance(before, dict) or not isinstance(after, dict):
            raise ValueError("Expected item-class objects")
        result["changedClassRecords"] = sorted(key for key in before.keys() | after.keys() if before.get(key) != after.get(key))
        result["classSha256"] = [hashlib.sha256(old_classes).hexdigest(), hashlib.sha256(new_classes).hexdigest()]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("previous", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--previous-classes", type=Path)
    parser.add_argument("--candidate-classes", type=Path)
    args = parser.parse_args()
    print(json.dumps(compare(args.previous.read_bytes(), args.candidate.read_bytes(),
                             args.previous_classes.read_bytes() if args.previous_classes else None,
                             args.candidate_classes.read_bytes() if args.candidate_classes else None), indent=2))


if __name__ == "__main__":
    main()
