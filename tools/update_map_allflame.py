"""Build the pinned 3.30 map Allflame reference and its game artwork."""
import argparse, hashlib, json, struct, urllib.parse, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SHA = "b16dc6c967b7e70ee369fba80506cdf08a1fa5bc5dd5c4f07aaddead97c98b2f"
COMMIT = "c97553d1fc14a134dd6813e672d2b45fddf5b42d"
DATA = ROOT / "src/Data/Atlas/map-allflame-3.30.json"
ASSETS = ROOT / "src/Assets/MapCrafting/Allflame"

def check():
    result = json.loads(DATA.read_text(encoding="utf8"))
    assert result["baseItemsSha256"] == SHA and result["sourceCommit"] == COMMIT
    assert len(result["items"]) == 11
    paths = set()
    for item in result["items"]:
        path = (ROOT / "src" / item["icon"]).resolve()
        assert path.parent == ASSETS.resolve() and path.suffix == ".png"
        data = path.read_bytes(); assert data.startswith(b"\x89PNG\r\n\x1a\n")
        assert hashlib.sha256(data).hexdigest() == item["iconSha256"]
        assert struct.unpack(">II", data[16:24]) == (item["width"], item["height"])
        paths.add(path)
    assert paths == {p.resolve() for p in ASSETS.glob("*.png")}
    return len(result["items"])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-items", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        print(f"Verified {check()} map Allflame entries")
        return
    url = f"https://raw.githubusercontent.com/repoe-fork/repoe-fork.github.io/{COMMIT}/data/base_items.json"
    raw = args.base_items.read_bytes() if args.base_items else urllib.request.urlopen(url, timeout=30).read()
    assert hashlib.sha256(raw).hexdigest() == SHA
    bases = json.loads(raw); ASSETS.mkdir(parents=True, exist_ok=True); items = []
    for key, entry in sorted(bases.items()):
        if not (key.startswith("Metadata/Items/MapFragments/") and entry.get("name", "").startswith("Allflame Ember") and entry.get("item_class") == "StackableCurrency" and entry.get("release_state") == "released"):
            continue
        art = entry["visual_identity"]["dds_file"]; filename = hashlib.sha256(art.encode()).hexdigest()[:20] + ".png"
        path = ASSETS / filename
        if not path.exists():
            art_url = "https://web.poecdn.com/image/" + urllib.parse.quote(art.removesuffix(".dds") + ".png", safe="/")
            path.write_bytes(urllib.request.urlopen(art_url, timeout=30).read())
        content = path.read_bytes(); assert content.startswith(b"\x89PNG\r\n\x1a\n")
        width,height = struct.unpack(">II",content[16:24])
        items.append({"id":key,"name":entry["name"],"description":entry["properties"]["description"].strip(),"icon":"Assets/MapCrafting/Allflame/"+filename,"iconSha256":hashlib.sha256(content).hexdigest(),"width":width,"height":height})
    items.sort(key=lambda item:item["name"])
    assert len(items)==11
    DATA.write_text(json.dumps({"clientVersion":"3.30.0.4","sourceCommit":COMMIT,"baseItemsSha256":SHA,"items":items},ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    print(f"Generated {len(items)} map Allflame entries")

if __name__ == "__main__": main()
