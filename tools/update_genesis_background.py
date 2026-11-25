"""Regenerate the pinned Genesis background from an extracted game DDS."""
# cspell:ignore LANCZOS tobytes
import argparse
import hashlib
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "src/Assets/Genesis/Background.png"
SOURCE_SHA256 = "60b518341495c5b1fbf677f0a9e8d9a7bf82a245c5c361ac643314a944e793bb"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Extracted 3.30.0.4 Genesis background DDS")
    parser.add_argument("--check", action="store_true", help="Compare decoded pixels without writing")
    args = parser.parse_args()
    raw = args.source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError("The source DDS does not match the pinned 3.30.0.4 asset")
    with Image.open(args.source) as image:
        if image.size != (7576, 6640):
            raise ValueError("Unexpected source dimensions")
        image.thumbnail((2048, 2048), Image.Resampling.LANCZOS)
        if args.check:
            with Image.open(DESTINATION) as existing:
                if existing.size != image.size or existing.mode != image.mode or existing.tobytes() != image.tobytes():
                    raise ValueError("Bundled Genesis background differs from the pinned source")
            print("Genesis background matches the pinned source")
        else:
            image.save(DESTINATION, optimize=True)
            print(f"Wrote {DESTINATION}; update its manifest hashes if it changed")


if __name__ == "__main__":
    main()
