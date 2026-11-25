import hashlib
import json
import unittest
from pathlib import Path

from update_map_crafting_data import extract
from check_map_crafting_art import compatible_source


class MapDataExtractionTest(unittest.TestCase):
    def test_bundled_map_catalogue_matches_the_pinned_export(self):
        root = Path(__file__).resolve().parents[1]
        baseline = json.loads((root / "src/Data/Crafting/3.30.json").read_text(encoding="utf-8"))
        maps = json.loads((root / "src/Data/Crafting/Map330.json").read_text(encoding="utf-8"))
        self.assertEqual("3.30.0.4", maps["patch"])
        self.assertEqual(baseline["patch"], maps["patch"])
        self.assertEqual(baseline["source"], maps["source"])
        self.assertEqual(baseline["hashes"]["mods.json"], maps["modsSha256"])
        self.assertEqual(baseline["hashes"]["base_items.json"], maps["basesSha256"])
        for key in ("MapContainsBeyondDemonFactionWorlds", "MapContainsBeyondFleshFactionWorlds",
                    "MapContainsBeyondPaleFactionWorlds", "MapContainsDeliriumMirrorWorlds",
                    "MapContainsMirageWorlds", "MapContainsWildwoodWorlds", "MapContainsSentinelApexWorlds",
                    "MapContainsSentinelPandemoniumWorlds", "MapContainsSentinelStalkerWorlds"):
            self.assertEqual({"tag": "infected_map", "weight": 0}, maps["mods"][key]["spawn_weights"][0])
        self.assertIn("MapMonsterAreaOfEffectMapWorlds", maps["mods"])
        self.assertIn("35% more [Thread|Threads]", maps["mods"]["MapUberModCurses"]["text"])
        self.assertIn("47% more Currency", maps["mods"]["MapUberModJuggernaut"]["text"])
        self.assertIn("Metadata/Items/Maps/MapWorldsBeach", maps["bases"])
        self.assertEqual({"id": "MapVaalTempleContainsVaalVessels", "text": "Area contains 10 additional guarded Vaal Vessels", "source": "base"},
                         maps["baseImplicits"]["Metadata/Items/Maps/MapWorldsVaalTemple"])
        self.assertEqual("Nightmare Map", maps["bases"]["Metadata/Items/Maps/MapKeyNightmareBoss"]["name"])
        for tier in range(1, 17):
            self.assertEqual(f"Map (Tier {tier})", maps["bases"][f"Metadata/Items/Maps/MapKeyTier{tier}"]["name"])

    def test_prior_art_source_requires_reviewed_map_identity_projection(self):
        root = Path(__file__).resolve().parents[1]
        art = json.loads((root / "src/Assets/MapCrafting/art.json").read_text(encoding="utf-8"))
        data = json.loads((root / "src/Data/Crafting/Map330.json").read_text(encoding="utf-8"))
        self.assertTrue(compatible_source(art, data))
        data["bases"][next(iter(data["bases"]))]["visual_identity"] = {"dds_file": "changed"}
        self.assertFalse(compatible_source(art, data))
        data["source"]["commit"] = "unreviewed"
        self.assertFalse(compatible_source(art, data))

    def test_keeps_area_affixes_and_ordered_weights(self):
        mod = {field: [] for field in ("groups", "spawn_weights", "generation_weights", "adds_tags", "stats")}
        mod.update(name="Example", generation_type="prefix", required_level=1, text="Example",
                   domain="area", spawn_weights=[{"tag": "uber_tier_map", "weight": 0},
                                                 {"tag": "low_tier_map", "weight": 1000}])
        source = json.dumps({"map": mod, "item": {**mod, "domain": "item"},
                             "unique": {**mod, "generation_type": "unique"}}).encode()
        base = {"name": "Example Map", "tags": ["map", "default"], "release_state": "released",
                "drop_level": 1, "visual_identity": None, "item_class": "Map"}
        base_source = json.dumps({"base": base, "Metadata/Items/Maps/MapKeyTier1": {**base, "item_class": "MapKey"},
                                  "Metadata/Items/Maps/MapKeyNightmareBoss": {**base, "item_class": "MapKey"},
                                  "special": {**base, "item_class": "MapKey"},
                                  "not_map": {**base, "item_class": "Ring"}}).encode()
        args = (source, hashlib.sha256(source).hexdigest(), base_source,
                hashlib.sha256(base_source).hexdigest(), {"commit": "test"})
        result = extract(*args)
        self.assertEqual(["map"], list(result["mods"]))
        self.assertEqual(["base", "Metadata/Items/Maps/MapKeyTier1", "Metadata/Items/Maps/MapKeyNightmareBoss"], list(result["bases"]))
        self.assertEqual(mod["spawn_weights"], result["mods"]["map"]["spawn_weights"])
        with self.assertRaisesRegex(ValueError, "does not match"):
            extract(source, "0" * 64, *args[2:])
        with self.assertRaisesRegex(ValueError, "Base-item export"):
            extract(source, args[1], base_source, "0" * 64, {})

    def test_rejects_an_empty_area_catalogue(self):
        source = b"{}"
        with self.assertRaisesRegex(ValueError, "No area modifiers"):
            extract(source, hashlib.sha256(source).hexdigest(), source, hashlib.sha256(source).hexdigest(), {})

    def test_reviews_implicit_identity_before_exporting(self):
        base_id = "Metadata/Items/Maps/MapWorldsVaalTemple"
        mod_id = "MapVaalTempleContainsVaalVessels"
        affix = {field: [] for field in ("groups", "spawn_weights", "generation_weights", "adds_tags", "stats")}
        affix.update(name="Example", generation_type="prefix", required_level=1, text="Example", domain="area")
        mods = json.dumps({"example": affix, mod_id: {"domain": "area", "generation_type": "unique", "text": "Ten vessels"}}).encode()
        base = {"name": "Vaal Temple Map", "tags": ["map", "default"], "release_state": "released", "drop_level": 83,
                "visual_identity": None, "item_class": "Map", "implicits": [mod_id]}
        def run(value):
            bases = json.dumps({base_id: value}).encode()
            return extract(mods, hashlib.sha256(mods).hexdigest(), bases, hashlib.sha256(bases).hexdigest(), {})
        self.assertEqual("Ten vessels", run(base)["baseImplicits"][base_id]["text"])
        with self.assertRaisesRegex(ValueError, "Review changed map base implicit"):
            run({**base, "implicits": []})


if __name__ == "__main__":
    unittest.main()
