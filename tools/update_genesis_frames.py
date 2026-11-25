"""Regenerate Genesis frames from the pinned extracted game texture sheets."""
# cspell:ignore tobytes
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "src/Assets/Genesis"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path, help="Directory containing extracted 4k-3.dds, 4k-4.dds and 4k-5.dds")
    parser.add_argument("--check", action="store_true", help="Compare decoded pixels without writing")
    args = parser.parse_args()
    frames = json.loads((ASSETS / "manifest.json").read_text(encoding="utf-8"))["frames"]
    checked = set()
    for name, entry in frames.items():
        sheet = args.source_dir / ("4k-" + Path(entry["sourcePath"]).name)
        if sheet not in checked:
            if hashlib.sha256(sheet.read_bytes()).hexdigest() != entry["sourceSha256"]:
                raise ValueError(f"{sheet.name} does not match the pinned game data")
            checked.add(sheet)
        with Image.open(sheet) as source:
            crop = source.crop(tuple(entry["crop"]))
            destination = ASSETS / f"{name}.png"
            if args.check:
                with Image.open(destination) as existing:
                    if existing.size != crop.size or existing.mode != crop.mode or existing.tobytes() != crop.tobytes():
                        raise ValueError(f"{name} differs from its pinned source")
            else:
                crop.save(destination, optimize=True)
    print(f"Genesis frames {'match the pinned sources' if args.check else 'written; update manifest hashes if changed'}")


if __name__ == "__main__":
    main()
