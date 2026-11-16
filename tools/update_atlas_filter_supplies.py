"""Generate known Atlas supply names from the reviewed 3.30 client export."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_SHA256 = "bcf0743a00d8db0f3ffb1dc8a15dad47d6469c884bee18bc6029494a8c81400b"
PATCH = ROOT / "src/Data/LootFilters/patch-3.30.json"
OUTPUT = ROOT / "src/Data/LootFilters/atlas-supplies-3.30.json"


def select_items(items, removed):
    names = set()
    for path, item in items.items():
        name = item.get("name") or ""
        if item.get("release_state") != "released" or item.get("item_class") != "StackableCurrency" or name in removed:
            continue
        is_ember = path.startswith("Metadata/Items/MapFragments/") and name.startswith("Allflame Ember of ")
        is_astrolabe = path.startswith("Metadata/Items/Currency/") and name.endswith(" Astrolabe")
        is_chisel = name.startswith("Maven's Chisel of ")
        is_orb = name.endswith(" Delirium Orb")
        if is_ember or is_astrolabe or is_chisel or is_orb or name in {"Divine Vessel", "Royal Visage"}:
            names.add(name)
    return sorted(names)


def build(raw, patch_raw):
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError("Client base-item export does not match the reviewed 3.30.0.1.4 data")
    # Git checkouts may use CRLF on Windows and LF on CI.
    patch_raw = patch_raw.replace(b"\r\n", b"\n")
    removed = set(json.loads(patch_raw)["removed"])
    return {"_comment": "Generated client data; cspell:disable", "clientVersion": "3.30.0.1.4",
            "sourceSha256": SOURCE_SHA256, "patchSha256": hashlib.sha256(patch_raw).hexdigest(),
            "names": select_items(json.loads(raw), removed)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Pinned base_items.min.json export")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = build(args.source.read_bytes(), PATCH.read_bytes())
    content = json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    if args.check:
        if OUTPUT.read_text(encoding="utf-8") != content:
            raise SystemExit("Atlas supply data differs from the reviewed sources")
    else:
        OUTPUT.write_text(content, encoding="utf-8", newline="\n")
    print(f"Verified {len(result['names'])} Atlas supply names")


if __name__ == "__main__":
    main()
