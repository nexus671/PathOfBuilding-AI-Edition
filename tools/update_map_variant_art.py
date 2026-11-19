"""Bundle and verify pinned official artwork for Blight map variants."""
# cspell:ignore getbbox lipuller
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
from pathlib import Path
import re
import urllib.request

from PIL import Image
from update_map_item_art import CDN, SOURCE, SOURCE_SHA256

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "src/Assets/MapCrafting"
MANIFEST = ASSETS / "variants.json"
EXPECTED = {("blighted", tier) for tier in range(1, 17)} | {("ravaged", tier) for tier in range(14, 17)}


def validate_url(path, tier, variant):
    if variant not in {"blighted", "ravaged"} or not re.fullmatch(r"/gen/image/[A-Za-z0-9_-]+/[0-9a-f]+/MapNumbers" + str(tier) + r"\.png", path):
        raise ValueError("Unexpected map variant image path")
    token = path.split("/")[3]
    payload = json.loads(base64.urlsafe_b64decode(token + "=" * (-len(token) % 4)))
    assert isinstance(payload, list) and len(payload) == 3 and isinstance(payload[2], dict)
    item = payload[2]
    assert item.get("f") == f"2DItems/Maps/Atlas2Maps/New/MapNumbers{tier}"
    assert item.get("mn") == 24 and item.get("mb") is (variant == "blighted")
    assert item.get("mub") is (variant == "ravaged") and not item.get("mm")
    return CDN + path


def catalogue(raw):
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError("Static map catalogue does not match its pinned source")
    result = {}
    for group in json.loads(raw)["result"]:
        for entry in group.get("entries", []):
            match = re.fullmatch(r"(blighted|blight-ravaged)-map-tier-(\d+)", entry.get("id", ""))
            if not match:
                continue
            variant = "blighted" if match[1] == "blighted" else "ravaged"
            tier = int(match[2]); key = (variant, tier)
            assert key in EXPECTED and key not in result and entry["text"] == f"Map (Tier {tier})"
            result[key] = validate_url(entry["image"], tier, variant)
    assert set(result) == EXPECTED, "Incomplete Blight map catalogue"
    return result


def check():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert manifest["source"] == SOURCE and manifest["sourceSha256"] == SOURCE_SHA256
    assert set(manifest["images"]) == {f"{v}:{t}" for v, t in EXPECTED}
    for key, entry in manifest["images"].items():
        variant, value = key.split(":"); tier = int(value)
        assert entry["url"] == validate_url(entry["url"].removeprefix(CDN), tier, variant)
        assert entry["path"] == f"Assets/MapCrafting/Items/{variant.title()}Tier{tier}.png"
        content = (ROOT / "src" / entry["path"]).read_bytes()
        assert hashlib.sha256(content).hexdigest() == entry["sha256"]
        with Image.open(io.BytesIO(content)) as image:
            assert image.format == "PNG" and list(image.size) == [entry["width"], entry["height"]]
            assert list(image.convert("RGBA").getbbox()) == entry["bounds"]
    print(f"Verified {len(EXPECTED)} Blight map images")


def update(source):
    urls = catalogue(source.read_bytes())
    def download(entry):
        (variant, tier), url = entry
        with urllib.request.urlopen(url, timeout=30) as response:
            content = response.read()
        with Image.open(io.BytesIO(content)) as image:
            assert image.format == "PNG" and image.width <= 256 and image.height <= 256
            bounds = image.convert("RGBA").getbbox(); assert bounds
            width, height = image.size
        path = f"Assets/MapCrafting/Items/{variant.title()}Tier{tier}.png"
        return f"{variant}:{tier}", content, {"url": url, "path": path, "width": width, "height": height,
                "bounds": list(bounds), "sha256": hashlib.sha256(content).hexdigest()}
    with ThreadPoolExecutor(max_workers=6) as pool:
        downloaded = list(pool.map(download, sorted(urls.items())))
    images = {}
    for key, content, info in downloaded:
        (ROOT / "src" / info["path"]).write_bytes(content); images[key] = info
    MANIFEST.write_text(json.dumps({"source": SOURCE, "sourceSha256": SOURCE_SHA256, "images": images}, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    check()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, nargs="?", help="Pinned static catalogue; omit to verify offline")
    args = parser.parse_args()
    update(args.source) if args.source else check()
