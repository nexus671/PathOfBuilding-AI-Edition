"""Verify the bundled map images against their recorded source and hashes."""
# cspell:ignore getbbox
import hashlib
import io
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    data = json.loads((ROOT / "src/Data/Crafting/Map330.json").read_text(encoding="utf-8"))
    art = json.loads((ROOT / "src/Assets/MapCrafting/art.json").read_text(encoding="utf-8"))
    assert art["source"] == data["source"] and art["basesSha256"] == data["basesSha256"]
    expected = {base["visual_identity"]["dds_file"] for base in data["bases"].values()
                if base.get("visual_identity") and base["visual_identity"].get("dds_file")}
    assert set(art["images"]) == expected
    for identity, entry in art["images"].items():
        expected_name = hashlib.sha256(identity.encode()).hexdigest()[:20] + ".png"
        assert entry["path"] == "Assets/MapCrafting/Items/" + expected_name
        image = ROOT / "src" / entry["path"]
        content = image.read_bytes()
        assert hashlib.sha256(content).hexdigest() == entry["sha256"]
        with Image.open(io.BytesIO(content)) as decoded:
            assert list(decoded.size) == [entry["width"], entry["height"]]
            assert list(decoded.convert("RGBA").getbbox() or (0, 0, *decoded.size)) == entry["bounds"]
        left, top, right, bottom = entry["bounds"]
        assert 0 <= left < right <= entry["width"] and 0 <= top < bottom <= entry["height"]
    print(f"Verified {len(expected)} map images")


if __name__ == "__main__":
    main()
