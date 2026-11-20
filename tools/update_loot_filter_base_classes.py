"""Build conservative item-filter class identities from a reviewed RePoE export."""
# cspell:ignore repoe
import argparse
import hashlib
import json
from pathlib import Path

COMMIT = "c97553d1fc14a134dd6813e672d2b45fddf5b42d"
BASE_SHA256 = "b16dc6c967b7e70ee369fba80506cdf08a1fa5bc5dd5c4f07aaddead97c98b2f"
CLASS_SHA256 = "58c679523f4c45ab7a70ec9db9c0405b1ff37633e9083fa4ca860bfb42c9c380"
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/Data/LootFilters/base-classes.json"
# Trade proxies and hidden client records are not reliable ground-drop examples.
NON_DROP_CLASSES = {"InstanceLocalItem", "HiddenItem"}


def build(base_raw, class_raw):
    if hashlib.sha256(base_raw).hexdigest() != BASE_SHA256 or hashlib.sha256(class_raw).hexdigest() != CLASS_SHA256:
        raise ValueError("Filter class source does not match the reviewed 3.30.0.4 export")
    bases = json.loads(base_raw)
    class_data = json.loads(class_raw)
    groups = {}
    for item in bases.values():
        name = item.get("name")
        if isinstance(name, str) and name:
            identifier = item.get("item_class")
            info = class_data.get(identifier) if isinstance(identifier, str) and identifier not in NON_DROP_CLASSES else None
            label = info.get("name") if isinstance(info, dict) else None
            groups.setdefault(name, set()).add(label if isinstance(label, str) and label else None)
    resolved, ambiguous = {}, {}
    for name, values in groups.items():
        if len(values) == 1 and None not in values:
            resolved[name] = next(iter(values))
        else:
            ambiguous[name] = True
    return {"_comment": "Generated game data; cspell:disable", "clientVersion": "3.30.0.4", "sourceCommit": COMMIT,
            "baseSha256": BASE_SHA256, "classSha256": CLASS_SHA256,
            "classes": resolved, "ambiguous": ambiguous}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bases", type=Path)
    parser.add_argument("classes", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = build(args.bases.read_bytes(), args.classes.read_bytes())
    content = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    if args.check:
        if OUTPUT.read_text(encoding="utf-8") != content:
            raise SystemExit("Filter class data differs from the reviewed export")
    else:
        OUTPUT.write_text(content, encoding="utf-8")
    print(f"Verified {len(data['classes'])} class identities; {len(data['ambiguous'])} names remain ambiguous")


if __name__ == "__main__":
    main()
