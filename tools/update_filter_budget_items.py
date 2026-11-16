"""Generate exact budget-item names from the reviewed 3.30 client export."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_SHA256 = "336cbd6c463249c862b8e47ab78392f7fbe03864044d5d8fcf5a7f3433de2ae4"
OUTPUT = ROOT / "src/Data/LootFilters/budget-items-3.30.json"
EXACT = {
    "Metadata/Items/Currency/CurrencyGemQuality",
    "Metadata/Items/Currency/CurrencyMapQuality",
    "Metadata/Items/Currency/CurrencyRerollUnique",
}


def build(raw):
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError("Base-item export does not match the reviewed 3.30.0.2 source")
    names = set()
    for path, item in json.loads(raw).items():
        name = item.get("name") or ""
        if item.get("release_state") != "released" or item.get("item_class") != "StackableCurrency":
            continue
        family = (re.fullmatch(r"Metadata/Items/Currency/Mushrune\d+", path)
                  or re.fullmatch(r"Metadata/Items/Currency/(?:Ancestral|Honoured|Forbidden)Tattoo\w+", path)
                  or re.fullmatch(r"Metadata/Items/Currency/Currency\w+Shard", path) and name.endswith(" Shard"))
        if (path in EXACT or family) and name and not re.search(r'["\[\]\r\n]', name):
            names.add(name)
    return {"_comment": "Generated GGG data; cspell:disable", "clientVersion": "3.30.0.2",
            "sourceSha256": SOURCE_SHA256, "names": sorted(names)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = build(args.source.read_bytes())
    content = json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    if args.check:
        if OUTPUT.read_text(encoding="utf-8") != content:
            raise SystemExit("Budget-item data differs from the reviewed source")
    else:
        OUTPUT.write_text(content, encoding="utf-8", newline="\n")
    print(f"Verified {len(result['names'])} exact budget-item names")


if __name__ == "__main__":
    main()
