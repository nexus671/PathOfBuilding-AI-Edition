"""Bundle map base images from a local extracted GGG artwork directory."""
import argparse
import hashlib
import io
import json
import struct
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "src/Assets/MapCrafting"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("art_root", type=Path, help="Extracted client root containing Art/2DItems")
    args = parser.parse_args()
    data = json.loads((ROOT / "src/Data/Crafting/Map330.json").read_text(encoding="utf-8"))
    (ASSETS / "Items").mkdir(parents=True, exist_ok=True)
    images = {}
    for base in data["bases"].values():
        identity = base.get("visual_identity") or {}
        art = identity.get("dds_file")
        if not art or art in images:
            continue
        if not art.startswith("Art/2DItems/") or ".." in Path(art).parts or not art.endswith(".dds"):
            raise ValueError("Invalid artwork path")
        content = (args.art_root / (art[:-4] + ".png")).read_bytes()
        if not content.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"Invalid PNG for {art}")
        name = hashlib.sha256(art.encode()).hexdigest()[:20] + ".png"
        (ASSETS / "Items" / name).write_bytes(content)
        width, height = struct.unpack(">II", content[16:24])
        with Image.open(io.BytesIO(content)) as image:
            bounds = image.convert("RGBA").getbbox() or (0, 0, width, height)
        images[art] = {"path": "Assets/MapCrafting/Items/" + name, "width": width, "height": height,
                       "bounds": bounds, "sha256": hashlib.sha256(content).hexdigest()}
    manifest = {"_comment": "GGG artwork metadata; cspell:disable", "source": data["source"],
                "basesSha256": data["basesSha256"], "images": images}
    (ASSETS / "art.json").write_text(json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Bundled {len(images)} map images")


if __name__ == "__main__":
    main()
