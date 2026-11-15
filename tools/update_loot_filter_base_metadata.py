"""Generate conservative filter-example base properties from a pinned client export."""
import argparse
import hashlib
import json
from pathlib import Path

SOURCE_SHA256 = "bcf0743a00d8db0f3ffb1dc8a15dad47d6469c884bee18bc6029494a8c81400b"
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/Data/LootFilters/base-metadata.json"
FIELDS = {"drop_level": "DropLevel", "inventory_width": "Width", "inventory_height": "Height"}


def build(raw):
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError("Client base-item export does not match the reviewed 3.30.0.1.4 data")
    groups = {}
    for item in json.loads(raw).values():
        name = item.get("name")
        if isinstance(name, str) and name:
            groups.setdefault(name, []).append(item)
    bases = {}
    for name, items in groups.items():
        properties = {}
        for source, target in FIELDS.items():
            values = {item.get(source) for item in items}
            if len(values) == 1:
                value = next(iter(values))
                if isinstance(value, int) and not isinstance(value, bool) and value > 0:
                    properties[target] = value
        if properties:
            bases[name] = properties
    return {"clientVersion": "3.30.0.1.4", "sourceSha256": SOURCE_SHA256, "bases": bases}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Pinned base_items.min.json export")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    content = json.dumps(build(args.source.read_bytes()), ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    if args.check:
        if OUTPUT.read_text(encoding="utf-8") != content:
            raise SystemExit("Filter base metadata differs from the pinned export")
    else:
        OUTPUT.write_text(content, encoding="utf-8", newline="\n")
    print(f"Verified {len(json.loads(content)['bases'])} filter base names")


if __name__ == "__main__":
    main()
