"""Build the Katakohi modifier catalogue from an immutable game-data export."""
# cspell:ignore Katakohi repoe
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "ae6d85a5c36857e08819852ab8732239294aba59"
URL = f"https://raw.githubusercontent.com/repoe-fork/repoe-fork.github.io/{COMMIT}/data/mods.json"
EXPECTED_SHA256 = "8ffecc59131a5456f9d40316e81e527c560f055da1ea85c32e8d300135b6a2c4"
with urlopen(URL, timeout=90) as response:
    raw = response.read()
assert hashlib.sha256(raw).hexdigest() == EXPECTED_SHA256, "Unexpected upstream modifier export"
mods = json.loads(raw)
selected = {key: value for key, value in mods.items() if key.startswith("DeepwaterTattooEnchant")}
assert len(selected) == 24, "Unexpected Katakohi modifier count"
result = {"_comment": "Generated game data. cspell:disable", "source": URL, "sha256": EXPECTED_SHA256, "patch": "3.29.3.6", "mods": {}}
for key, value in sorted(selected.items()):
    assert value["domain"] == "ducat_crafted" and value["generation_type"] == "unique"
    assert value["text"].startswith("-1 to maximum Sockets\n")
    result["mods"][key] = {name: value[name] for name in ("text", "groups", "spawn_weights", "stats", "required_level")}
path = ROOT / "src/Data/Crafting/Katakohi.json"
path.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
print(f"Wrote {len(selected)} Katakohi modifiers to {path}")
