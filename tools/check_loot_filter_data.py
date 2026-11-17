"""Verify bundled third-party templates without network access."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "src/Data/LootFilters"
source = json.loads((root / "source.json").read_text())
assert source["license"] == "MIT"
assert source.get("nativePatch") == "3.30"
assert set(source["files"]) == {f"{index}.filter" for index in range(7)}
for filename, record in source["files"].items():
    raw = (root / filename).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == record["sha256"], filename
    assert source["commit"] in record["source"], filename
license_text = (root / "LICENSE-NeverSink.txt").read_text()
assert "Copyright (c) 2026 NeverSink" in license_text and "Permission is hereby granted" in license_text
patch = json.loads((root / "patch-3.30.json").read_text())
assert patch["version"] == "3.30" and patch["keywords"]["UnidentifiedItemTier"] == [0, 5]
assert patch["sha256Kind"] == "extracted-news-text"
assert "Fated" in patch["keywords"]
assert "Frayed Thread" in patch["added"]["Stackable Currency"]
assert "Enshrouded Quiver" in patch["added"]["Enshrouded Items"]
assert patch["renamed"]["Maven's Chisel of Scarabs"] == "Maven's Chisel of Threads"
assert "Orb of Binding" in patch["removed"]
assert len(patch["removed"]) == 171 and len(set(patch["removed"])) == 171
assert "Report Forum Post" not in patch["removed"]
classes = json.loads((root / "base-classes.json").read_text(encoding="utf-8"))
assert classes["clientVersion"] == "3.30.0.2.2" and len(classes["classes"]) == 4382
assert classes["sourceCommit"] == "f49a9a43f5b06cac7f7125093cfd7ef2f0137650"
assert classes["baseSha256"] == "336cbd6c463249c862b8e47ab78392f7fbe03864044d5d8fcf5a7f3433de2ae4"
assert classes["classSha256"] == "58c679523f4c45ab7a70ec9db9c0405b1ff37633e9083fa4ca860bfb42c9c380"
assert classes["classes"]["Gold"] == "Gold" and classes["classes"]["Expedition Logbook"] == "Expedition Logbooks"
assert classes["ambiguous"]["Primitive Chaotic Resonator"] and "Primitive Chaotic Resonator" not in classes["classes"]
print("Loot filter data: 7 pinned hashes, MIT notice and 3.30 snapshot verified")
