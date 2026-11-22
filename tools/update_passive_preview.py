"""Generate the opt-in 3.30 passive preview from a pinned official GGG export."""
import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import re
import tempfile
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "550fb34ae7fca9ec4d760a2ac845bb2ba1032ec3"
SOURCE = f"https://raw.githubusercontent.com/grindinggear/skilltree-export/{COMMIT}/data.json"
DESTINATION = ROOT / "src/TreeData/3_30_preview"


def lua(value, depth=0):
    indent = "\t" * depth
    if isinstance(value, dict):
        entries = value.items()
    elif isinstance(value, list):
        entries = enumerate(value, 1)
    elif value is None:
        return "nil"
    elif isinstance(value, bool):
        return "true" if value else "false"
    else:
        return json.dumps(value, ensure_ascii=False)
    lines = []
    for key, entry in entries:
        if isinstance(key, str) and re.fullmatch(r"[0-9]+", key):
            key = int(key)
        lines.append(indent + "\t[" + json.dumps(key, ensure_ascii=False) + "] = " + lua(entry, depth + 1) + ",")
    return "{\n" + "\n".join(lines) + "\n" + indent + "}"


def generate(destination):
    with urlopen(SOURCE, timeout=30) as response:
        raw = response.read()
    original = json.loads(raw)
    assert original["tree"] == "Default"
    module_spec = importlib.util.spec_from_file_location("fix_ascendancy_positions", ROOT / "fix_ascendancy_positions.py")
    fixer = importlib.util.module_from_spec(module_spec)
    import sys
    sys.modules[module_spec.name] = fixer
    module_spec.loader.exec_module(fixer)
    with tempfile.TemporaryDirectory(prefix="pob-passive-preview-") as directory:
        path = Path(directory) / "data.json"
        path.write_bytes(raw)
        fixer.fix_ascendancy_positions(path)
        data = json.loads(path.read_text(encoding="utf-8"))
        sprites = json.loads(path.with_name("sprites.json").read_text(encoding="utf-8"))
    destination.mkdir(parents=True, exist_ok=True)
    header = "-- Generated official GGG preview data. cspell:disable\nreturn "
    (destination / "tree.lua").write_text(header + lua(data) + "\n", encoding="utf-8")
    (destination / "sprites.lua").write_text(header + lua(sprites) + "\n", encoding="utf-8")
    names = sorted({Path(urlsplit(sheet["filename"]).path).name for sheet in sprites["sprites"].values()})

    def asset(name):
        assert re.fullmatch(r"[a-zA-Z0-9_.-]+", name)
        source = f"https://raw.githubusercontent.com/grindinggear/skilltree-export/{COMMIT}/assets/{name}"
        with urlopen(source, timeout=60) as response:
            content = response.read()
        (destination / name).write_bytes(content)
        return name, {"source": source, "sha256": hashlib.sha256(content).hexdigest()}

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        assets = dict(pool.map(asset, names))
    provenance = {"_comment": "Generated official GGG data. cspell:disable", "preview": True,
                  "source": SOURCE, "commit": COMMIT, "sha256": hashlib.sha256(raw).hexdigest(),
                  "preprocessor": "fix_ascendancy_positions.py", "assets": assets}
    (destination / "source.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    return len(data["nodes"]), len(assets), provenance["sha256"]


def differences(generated, existing):
    """Compare generated files, tolerating checkout line endings for text."""
    result = []
    for path in sorted(generated.iterdir()):
        target = existing / path.name
        if not target.is_file():
            result.append(f"Missing: {path.name}")
            continue
        expected, actual = path.read_bytes(), target.read_bytes()
        if path.suffix in {".lua", ".json"}:
            expected = expected.replace(b"\r\n", b"\n")
            actual = actual.replace(b"\r\n", b"\n")
        if expected != actual:
            result.append(f"Different: {path.name}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Compare generated data and assets without modifying the checkout")
    args = parser.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="pob-passive-check-") as directory:
            generated = Path(directory)
            count, sheets, digest = generate(generated)
            errors = differences(generated, DESTINATION)
        if errors:
            raise SystemExit("Passive preview differs:\n" + "\n".join(errors))
        print(f"Verified 3.30 preview: {count} nodes, {sheets} sprite sheets, source {digest}")
    else:
        count, sheets, digest = generate(DESTINATION)
        print(f"3.30 preview: {count} nodes, {sheets} sprite sheets, source {digest}")


if __name__ == "__main__":
    main()
