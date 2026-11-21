"""Extract the 3.30 utility-flask enchantment pool from pinned RePoE data."""
import argparse
import hashlib
import json
import os
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "c97553d1fc14a134dd6813e672d2b45fddf5b42d"
SHA256 = "8549a332c5de55ba5b3a7208adf2fca321ccce3ba50698200a78e867cba1f4e4"
URL = f"https://raw.githubusercontent.com/repoe-fork/repoe-fork.github.io/{COMMIT}/data/mods.json"
DEST = ROOT / "src/Data/Crafting/FlaskEnchants330.json"
# Indices correspond to the native EnchantmentFlask.lua lists; unknown additions
# must be reviewed and mapped rather than silently omitted.
IDS = {
    "ENKINDLING": [
        "FlaskEnchantmentSealIncreasedEffect_", "FlaskEnchantmentSealIncreasedDuration",
        "FlaskEnchantmentSealIncreasedChargesGained", "FlaskEnchantmentSealReducedChargesUsed",
        "FlaskEnchantmentSealMaximumCharges____",
    ],
    "INSTILLING": [
        "FlaskEnchantmentInjectorAdjacentFlasks___", "FlaskEnchantmentInjectorFlaskEffectEnd",
        "FlaskEnchantmentInjectorOnFullCharges__", "FlaskEnchantmentInjectorOnGuardSkillUsed",
        "FlaskEnchantmentInjectorOnTravelSkillUsed", "FlaskEnchantmentInjectorOnGuardSkillExpired",
        "FlaskEnchantmentInjectorOnHittingRareOrUnique_", "FlaskEnchantmentInjectorOnAffectedByFreeze__",
        "FlaskEnchantmentInjectorOnAffectedByChill", "FlaskEnchantmentInjectorOnAffectedByShock_",
        "FlaskEnchantmentInjectorOnAffectedByIgnite", "FlaskEnchantmentInjectorOnAffectedByBleed",
        "FlaskEnchantmentInjectorOnAffectedByPoison_", "FlaskEnchantmentInjectorOnDamageBlocked",
        "FlaskEnchantmentInjectorOnTakingSavageHit_", "FlaskEnchantmentInjectorOnUsingLifeFlask",
    ],
}


def generate(raw):
    if hashlib.sha256(raw).hexdigest() != SHA256:
        raise ValueError("Unexpected flask enchantment source hash")
    mods = json.loads(raw)
    known = {item for group in IDS.values() for item in group}
    actual = {key for key, value in mods.items() if value["generation_type"] in
              ("flask_enchantment_instilling", "flask_enchantment_enkindling")}
    if actual != known:
        raise ValueError("The flask enchantment pool requires review")
    pools = {}
    for group, ids in IDS.items():
        entries = []
        for index, item in enumerate(ids, 1):
            mod = mods[item]
            assert mod["generation_type"] == "flask_enchantment_" + group.lower()
            assert mod["spawn_weights"][1:] == [{"tag": "default", "weight": 0}]
            assert mod["spawn_weights"][0]["tag"] == "flask"
            entries.append({"id": item, "index": index, "weight": mod["spawn_weights"][0]["weight"], "stats": mod["stats"]})
        pools[group] = entries
    return (json.dumps({"source": {"commit": COMMIT, "sha256": SHA256}, "pools": pools}, indent=2) + "\n").encode()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-file", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.source_file:
        raw = args.source_file.read_bytes()
    else:
        with urlopen(URL, timeout=60) as response:
            raw = response.read()
    generated = generate(raw)
    if args.check:
        if DEST.read_bytes().replace(b"\r\n", b"\n") != generated:
            raise SystemExit("Flask enchantment data differs from the pinned source")
        print("Flask enchantment data verified: 5 Enkindling and 16 Instilling modifiers")
    else:
        DEST.write_bytes(generated.replace(b"\n", b"\r\n") if os.name == "nt" else generated)
        print(f"Wrote {DEST}")


if __name__ == "__main__":
    main()
