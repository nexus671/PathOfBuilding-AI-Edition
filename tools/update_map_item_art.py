"""Bundle and verify official generated images for ordinary tier-map items."""
# cspell:ignore getbbox lipuller poecdn
import argparse
import base64
import hashlib
import io
import json
import re
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "src/Assets/MapCrafting"
MANIFEST = ASSETS / "items.json"
SOURCE = "https://raw.githubusercontent.com/zalepy/lipuller/051fb15d855e2b31b76b43f82f7c039f0464b265/static.json"
SOURCE_SHA256 = "ba1bd88ae4a3499b8b3a7065d2d952c22ad5aa9fdc16d6f95c15bc2dbb020f8e"
CDN = "https://web.poecdn.com"


def validate_url(path, tier):
    if not re.fullmatch(r"/gen/image/[A-Za-z0-9_-]+/[0-9a-f]+/MapNumbers" + str(tier) + r"\.png", path):
        raise ValueError("Unexpected generated map image path")
    token = path.split("/")[3]
    payload = json.loads(base64.urlsafe_b64decode(token + "=" * (-len(token) % 4)))
    assert isinstance(payload, list) and len(payload) == 3 and isinstance(payload[2], dict)
    item = payload[2]
    assert item.get("f") == f"2DItems/Maps/Atlas2Maps/New/MapNumbers{tier}"
    assert item.get("mn") == 24 and not any(item.get(key) for key in ("mub", "mb", "mm"))
    return CDN + path


def catalogue(raw):
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError("Static map catalogue does not match its pinned source")
    data = json.loads(raw)
    entries = {}
    for group in data["result"]:
        for entry in group.get("entries", []):
            match = re.fullmatch(r"map-tier-([1-9]|1[0-6])", entry.get("id", ""))
            if match:
                tier = int(match[1])
                assert tier not in entries and entry["text"] == f"Map (Tier {tier})"
                entries[tier] = validate_url(entry["image"], tier)
    assert set(entries) == set(range(1, 17)), "Incomplete ordinary map catalogue"
    return entries


def check():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert manifest["source"] == SOURCE and manifest["sourceSha256"] == SOURCE_SHA256
    data = json.loads((ROOT / "src/Data/Crafting/Map330.json").read_text(encoding="utf-8"))
    assert set(manifest["images"]) == {f"Metadata/Items/Maps/MapKeyTier{n}" for n in range(1, 17)}
    for tier in range(1, 17):
        base_id = f"Metadata/Items/Maps/MapKeyTier{tier}"
        entry = manifest["images"][base_id]
        assert data["bases"][base_id]["name"] == f"Map (Tier {tier})"
        assert data["bases"][base_id]["visual_identity"]["dds_file"] == f"Art/2DItems/Maps/Atlas2Maps/New/MapNumbers{tier}.dds"
        assert entry["url"] == validate_url(entry["url"].removeprefix(CDN), tier)
        assert entry["path"] == f"Assets/MapCrafting/Items/MapTier{tier}.png"
        content = (ROOT / "src" / entry["path"]).read_bytes()
        assert hashlib.sha256(content).hexdigest() == entry["sha256"]
        with Image.open(io.BytesIO(content)) as image:
            assert image.format == "PNG" and list(image.size) == [entry["width"], entry["height"]]
            assert list(image.convert("RGBA").getbbox()) == entry["bounds"]
    print("Verified 16 complete ordinary map item images")


def update(static_file):
    urls = catalogue(static_file.read_bytes())
    images = {}
    for tier, url in sorted(urls.items()):
        with urllib.request.urlopen(url, timeout=30) as response:
            content = response.read()
        with Image.open(io.BytesIO(content)) as image:
            assert image.format == "PNG" and image.width <= 256 and image.height <= 256
            bounds = image.convert("RGBA").getbbox()
            assert bounds, "Empty map item image"
            width, height = image.size
        path = f"Assets/MapCrafting/Items/MapTier{tier}.png"
        (ROOT / "src" / path).write_bytes(content)
        images[f"Metadata/Items/Maps/MapKeyTier{tier}"] = {
            "path": path, "url": url, "sha256": hashlib.sha256(content).hexdigest(),
            "width": width, "height": height, "bounds": bounds,
        }
    MANIFEST.write_text(json.dumps({"_comment": "GGG generated item artwork; cspell:disable",
                                    "source": SOURCE, "sourceSha256": SOURCE_SHA256,
                                    "images": images}, sort_keys=True, separators=(",", ":")) + "\n",
                        encoding="utf-8")
    check()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static", type=Path, help="Pinned static item catalogue; omit with --check")
    parser.add_argument("--check", action="store_true", help="Verify bundled images without network access")
    args = parser.parse_args()
    if args.check:
        check()
    elif args.static:
        update(args.static)
    else:
        parser.error("Supply --static or --check")


if __name__ == "__main__":
    main()
