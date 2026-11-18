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
    # GGG's Base26 image supplies the frame beneath the five transparent
    # Nightmare symbols. It is bundled unchanged for offline use.
    frame = (ROOT / "src/Assets/MapCrafting/Items/NightmareFrame.png").read_bytes()
    assert hashlib.sha256(frame).hexdigest() == "238bf2bf059d0d2cdcdf453e6c2689a463092d47b87b407d5a0feab904c9dae0"
    with Image.open(io.BytesIO(frame)) as decoded:
        assert decoded.format == "PNG" and decoded.size == (78, 78)
    for name in ("UberMalformation", "UberPrimordialBlocks", "UberSilo", "UberRelicChambers", "UberMausoleum"):
        assert f"Art/2DItems/Maps/Atlas2Maps/New/{name}.dds" in art["images"]
    print(f"Verified {len(expected)} map images")


if __name__ == "__main__":
    main()
