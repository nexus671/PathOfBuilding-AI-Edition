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
assert classes["clientVersion"] == "3.30.0.4" and len(classes["classes"]) == 4384
assert classes["sourceCommit"] == "c97553d1fc14a134dd6813e672d2b45fddf5b42d"
assert classes["baseSha256"] == "b16dc6c967b7e70ee369fba80506cdf08a1fa5bc5dd5c4f07aaddead97c98b2f"
assert classes["classSha256"] == "58c679523f4c45ab7a70ec9db9c0405b1ff37633e9083fa4ca860bfb42c9c380"
metadata = json.loads((root / "base-metadata.json").read_text(encoding="utf-8"))
assert metadata["clientVersion"] == "3.30.0.4" and metadata["sourceSha256"] == "b16dc6c967b7e70ee369fba80506cdf08a1fa5bc5dd5c4f07aaddead97c98b2f"
for name, level in [("Originator's Exalted Orb", 78), ("Primordial Exalted Orb", 81), ("Foulborn Regal Orb", 75), ("Foulborn Orb of Augmentation", 75)]:
    assert classes["classes"][name] == "Stackable Currency"
    assert metadata["bases"][name] == {"DropLevel": level, "Width": 1, "Height": 1}
assert classes["classes"]["Gold"] == "Gold" and classes["classes"]["Expedition Logbook"] == "Expedition Logbooks"
assert classes["ambiguous"]["Primitive Chaotic Resonator"] and "Primitive Chaotic Resonator" not in classes["classes"]
print("Loot filter data: 7 pinned hashes, MIT notice and 3.30 snapshot verified")
