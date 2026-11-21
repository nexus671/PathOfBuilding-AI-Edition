"""Verify the Genesis icons referenced by the pinned tree."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "src/Assets/Genesis"
manifest = json.loads((ASSETS / "manifest.json").read_text(encoding="utf-8"))
graph = json.loads((ROOT / "src/Data/Genesis/3.30.0d.json").read_text(encoding="utf-8"))
icons = manifest["icons"]
expected = {"KeepersCurrencyNode", "KeepersCurrencyNotable", "KeepersEquipmentNode", "KeepersEquipmentNotable",
            "KeepersMiscellaneousNode", "KeepersMiscellaneousNotable", "KeepersSelectionNotable", "KeepersUniqueNode", "KeepersUniqueNotable", "MasteryBlank"}
assert set(icons) == expected, "Unexpected Genesis icon catalogue"
for name, entry in icons.items():
    assert entry["file"] == f"Assets/Genesis/{name}.png", name
    raw = (ASSETS / f"{name}.png").read_bytes()
    assert raw.startswith(b"\x89PNG\r\n\x1a\n"), name
    assert hashlib.sha256(raw).hexdigest() == entry["sha256"], name
used = {node["icon"].rsplit("/", 1)[-1].removesuffix(".dds") for node in graph["nodes"].values() if node.get("icon")}
missing = used - set(icons)
assert not missing, f"Missing Genesis icons: {missing}"
print(f"Genesis icons: {len(icons)} verified; all pinned node icons are present")
