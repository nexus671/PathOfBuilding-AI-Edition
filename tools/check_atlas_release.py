"""Compare a GGG Atlas tag with the source snapshots recorded in this checkout.

This compares source files, not the generated graph or the live game's tree.
"""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import quote
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parents[1]
SOURCES = (
    ("3.30.0-preview", "data.json", "sha256"),
    ("3.30.0-preview", "league.json", "leagueSha256"),
    ("3.30.0-preview-ruthless", "ruthless.json", "sha256"),
    ("3.30.0-preview-ruthless", "ruthless-league.json", "leagueSha256"),
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default="3.30.0", help="GGG Atlas export tag or commit")
    args = parser.parse_args()
    ref = quote(args.ref, safe="")
    failed = False
    for version, filename, field in SOURCES:
        graph = json.loads((ROOT / "src" / "Data" / "Atlas" / (version + ".json")).read_text(encoding="utf-8"))
        url = f"https://raw.githubusercontent.com/grindinggear/atlastree-export/{ref}/{filename}"
        with urlopen(url, timeout=30) as response:
            digest = hashlib.sha256(response.read()).hexdigest()
        matches = digest == graph[field]
        failed |= not matches
        print(f"{filename}: {'matches' if matches else 'DIFFERS'} {version} ({digest})")
    if failed:
        raise SystemExit("Atlas export differs; inspect and regenerate the affected graphs before updating plans.")
    print("Source files match. This does not verify generated nodes or the live game.")


if __name__ == "__main__":
    main()
