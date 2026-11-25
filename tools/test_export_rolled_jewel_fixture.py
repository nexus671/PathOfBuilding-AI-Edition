"""Check the rolled-jewel fixture against the native listing matcher."""

from copy import deepcopy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

from build_public_stash_capture import encode_response
from collect_public_stash_capture import read_capture
from export_rolled_jewel_fixture import export_fixture


def sample_capture():
    timestamp = int(time.time()) - 20
    current = []
    first = []
    bases = (
        ("Small Cluster Jewel", 2, 0, "4% increased maximum Life"),
        ("Medium Cluster Jewel", 4, 1, "12% increased Burning Damage"),
        ("Large Cluster Jewel", 8, 2, "12% increased Axe and Sword Damage"),
        ("Mycelium Core", 0, 0, ""),
    )
    for number, (base, passives, sockets, bonus) in enumerate(bases, 1):
        enchants = [f"Adds {passives} Passive Skills", f"Added Small Passive Skills grant: {bonus}"]
        if sockets == 1:
            enchants.append("1 Added Passive Skill is a Jewel Socket")
        elif sockets == 2:
            enchants.append("2 Added Passive Skills are Jewel Sockets")
        item = {
            "baseType": base, "rarity": "Rare", "identified": True, "ilvl": 84,
            "name": "private generated title", "forum_note": "private forum note",
            "enchantMods": enchants, "explicitMods": [{"description": "+3 to maximum Life"}],
        }
        if base == "Mycelium Core":
            item.update(
                name="Putrid Seed", typeLine=base, rarity="Unique",
                enchantMods=["1 Added Passive Skill is Atrophy", "1 Added Passive Skill is Corruption"],
                explicitMods=[
                    {"description": "Grows four random Passive Skills when Anointed"},
                    {"description": "Passive Skills grown are influenced by Oils used when Anointing"},
                ],
                properties=[{"name": "Limited to", "displayMode": 0, "values": [["1", 0]], "icon": "private property URL"}],
            )
        for seller, price in enumerate((12, 20, 30, 45, 99), 1):
            row = deepcopy(item)
            row["id"] = f"{number * 10 + seller:064x}".replace("0", "b", 4)
            row["note"] = f" ~price {price} chaos "
            if seller == 4:
                row["note"] = "private item note overrides tab price"
            if seller == 5:
                row["ilvl"] = 85
            tab = {
                "id": f"{number * 10 + seller:064x}".replace("0", "a", 4),
                "public": True, "league": "Source", "accountName": f"private account {seller}",
                "stash": "~b/o 90 chaos", "items": [row],
            }
            current.append(tab)
            if seller == 1:
                old = deepcopy(tab)
                old["items"][0]["note"] = "~price 1 chaos"
                first.append(old)
                second_tab = deepcopy(tab)
                second_tab["id"] = f"{number + 100:064x}"
                second_tab["accountName"] = tab["accountName"].upper()
                second_tab["items"][0]["id"] = f"{number + 200:064x}"
                second_tab["items"][0]["note"] = ""
                second_tab["stash"] = "~b/o 35 chaos"
                current.append(second_tab)
                divine = deepcopy(second_tab)
                divine["id"] = f"{number + 1000:064x}"
                divine["items"][0]["id"] = f"{number + 1100:064x}"
                divine["items"][0]["note"] = "~price 1.5 divine"
                current.append(divine)
                withdrawn = deepcopy(second_tab)
                withdrawn["id"] = f"{number + 300:064x}"
                withdrawn["items"][0]["id"] = f"{number + 400:064x}"
                first.append(withdrawn)
                current.append({"id": withdrawn["id"].upper(), "public": False})
                duplicate = deepcopy(second_tab)
                duplicate["id"] = f"{number + 500:064x}"
                duplicate["items"][0]["id"] = f"{number + 600:064X}"
                current.append(duplicate)
                conflict = deepcopy(duplicate)
                conflict["id"] = f"{number + 700:064x}"
                conflict["items"][0]["id"] = duplicate["items"][0]["id"].lower()
                current.append(conflict)
                changed = deepcopy(tab)
                changed["id"] = f"{number + 800:064x}"
                changed["items"][0]["id"] = f"{number + 900:064x}"
                if base == "Mycelium Core":
                    changed["items"][0]["enchantMods"].reverse()
                else:
                    changed["items"][0]["explicitMods"][0]["flags"] = {"fractured": True}
                current.append(changed)
    return {
        "format": "pob-public-stash-capture-v1", "realm": "pc", "league": "Source",
        "capturedAt": timestamp,
        "pages": [
            {"requestCursor": "private-cursor-first", "collectedAt": timestamp,
             "response": {"stashes": first, "next_change_id": "private-cursor-second"}},
            {"requestCursor": "private-cursor-second", "collectedAt": timestamp + 10,
             "response": {"stashes": current, "next_change_id": "private-cursor-third"}},
        ],
    }


class RolledJewelFixtureTest(unittest.TestCase):
    def test_fixture_preserves_native_results_without_private_fields(self):
        source = sample_capture()
        fixture, count = export_fixture(source)
        self.assertGreater(count, 12)
        for secret in (b"private", b"Source", b"aaaa0000", b"bbbb0000", str(source["capturedAt"]).encode()):
            self.assertNotIn(secret, fixture)
        result = json.loads(fixture)
        self.assertEqual(result["fixture"], "rolled-jewels-v1")
        with tempfile.TemporaryDirectory() as folder:
            raw_path = Path(folder, "raw.json")
            raw_path.write_bytes(encode_response(source))
            fixture_path = Path(folder, "fixture.json")
            subprocess.run(
                [sys.executable, "tools/export_rolled_jewel_fixture.py", "--league", "Source", raw_path, fixture_path],
                check=True,
            )
            self.assertEqual(fixture_path.read_bytes(), fixture)
            with self.assertRaisesRegex(ValueError, "cannot resume"):
                read_capture(fixture_path, result["league"])
            subprocess.run(
                [sys.executable, "tools/run_headless_lupa.py", "tools/test_rolled_jewel_fixture.lua",
                 raw_path, fixture_path],
                check=True,
            )

    def test_rejects_capture_with_no_target_rows(self):
        capture = sample_capture()
        for entry in capture["pages"]:
            for stash in entry["response"]["stashes"]:
                for item in stash.get("items", []):
                    item["baseType"] = "Cobalt Jewel"
        with self.assertRaisesRegex(ValueError, "no Cluster Jewel"):
            export_fixture(capture)


if __name__ == "__main__":
    unittest.main()
