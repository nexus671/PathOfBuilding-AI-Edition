"""Generate Atlas strategy map names from the reviewed local client export."""
import argparse
import hashlib
import json
from pathlib import Path

SOURCE_SHA256 = "bcf0743a00d8db0f3ffb1dc8a15dad47d6469c884bee18bc6029494a8c81400b"
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/Data/LootFilters/map-names.json"


def build(raw):
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError("Client base-item export does not match the reviewed 3.30.0.1.4 data")
    names = sorted({item["name"] for item in json.loads(raw).values()
                    if item.get("item_class") == "Map" and item.get("release_state") == "released"
                    and item.get("name") and not item["name"].startswith("[")})
    return {"_comment": "Generated client map names. cspell:disable", "clientVersion": "3.30.0.1.4",
            "sourceSha256": SOURCE_SHA256, "names": names}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    content = json.dumps(build(args.source.read_bytes()), ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    if args.check:
        if OUTPUT.read_text(encoding="utf-8") != content:
            raise SystemExit("Map names differ from the reviewed client export")
    else:
        OUTPUT.write_text(content, encoding="utf-8", newline="\n")
    print(f"Verified {len(json.loads(content)['names'])} map names")


if __name__ == "__main__":
    main()
