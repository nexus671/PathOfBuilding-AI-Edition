"""Generate a reviewed Delirium Orb reference from the pinned client export."""
# cspell:ignore repoe
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_SHA256 = "b16dc6c967b7e70ee369fba80506cdf08a1fa5bc5dd5c4f07aaddead97c98b2f"
OUTPUT = ROOT / "src/Data/Atlas/delirium-orbs-3.30.json"


def build(raw):
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError("Base item export does not match the reviewed 3.30.0.4 data")
    choices = set()
    for path, item in json.loads(raw).items():
        if "/CurrencyAfflictionOrb" not in path or item.get("release_state") != "released":
            continue
        name = item.get("name")
        # 3.30 patch notes convert this legacy orb to the Threaded version.
        if not name or name == "Fragmented Delirium Orb":
            continue
        text = item.get("properties", {}).get("description", "")
        match = re.search(r"\[DeliriumRewardType\|Delirium Reward Type\]:\s*(.+)", text)
        if match:
            reward = re.sub(r"\[([^|\]]+)\|([^\]]+)\]", r"\2", match.group(1))
            choices.add((name, reward))
    return {"_comment": "Generated game data; cspell:disable", "clientVersion": "3.30.0.4", "sourceSha256": SOURCE_SHA256,
            "choices": [{"name": name, "reward": reward} for name, reward in sorted(choices)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = build(args.source.read_bytes())
    if args.check:
        assert json.loads(OUTPUT.read_text(encoding="utf8")) == data, "Delirium Orb reference differs"
        print(f"Verified {len(data['choices'])} Delirium Orb choices")
    else:
        OUTPUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
        print(f"Wrote {len(data['choices'])} Delirium Orb choices")


if __name__ == "__main__":
    main()
