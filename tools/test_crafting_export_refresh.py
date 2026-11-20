"""Check the reviewed 3.30 crafting export changes."""
import hashlib
import json
from pathlib import Path
import unittest
from crafting_data_status import single_base_implicit_ids

ROOT = Path(__file__).resolve().parents[1]


class CraftingExportRefreshTest(unittest.TestCase):
    def test_single_implicit_grouping_is_conservative(self):
        values = {
            "one": {"name": "same", "implicits": ["ModA"]},
            "duplicate": {"name": "same", "implicits": ["ModA"]},
            "ambiguous1": {"name": "ambiguous", "implicits": ["ModA"]},
            "ambiguous2": {"name": "ambiguous", "implicits": ["ModB"]},
            "several": {"name": "several", "implicits": ["ModA", "ModB"]},
            "absent": {"name": "absent", "implicits": []},
            "invalid": {"name": "invalid", "implicits": [None]},
        }
        self.assertEqual({"same": "ModA"}, single_base_implicit_ids(values))
        data = json.loads((ROOT / "src/Data/Crafting/3.30.json").read_text(encoding="utf-8"))
        self.assertEqual("LifeAndManaOnHitSeparatedImplicitMarakethClaw3", data["singleBaseImplicits"]["Gemini Claw"])
        self.assertEqual("SocketedActiveGemLevelSupportGemPenaltyImplicitR1", data["singleBaseImplicits"]["Imp Crown"])
        self.assertNotIn("Two-Toned Boots", data["singleBaseImplicits"])

    def test_reviewed_jewel_domains_preserve_other_modifier_data(self):
        data = json.loads((ROOT / "src/Data/Crafting/3.30.json").read_text(encoding="utf-8"))
        self.assertEqual("c97553d1fc14a134dd6813e672d2b45fddf5b42d", data["source"]["commit"])
        jewels = sorted(key for key, mod in data["mods"].items() if mod["domain"] == "jewel")
        self.assertEqual(253, len(jewels))
        self.assertEqual("67ed0db78edab50282c1d8ae105b026d3d51deae99f79e3b2b76c9227dd85a9c",
                         hashlib.sha256(("\n".join(jewels) + "\n").encode()).hexdigest())
        # Vendor outcomes were added separately from the jewel-domain refresh.
        vendor_ids = {identifier for fossil in data["fossils"].values()
                      for identifier in fossil.get("sell_price_mods", [])}
        self.assertEqual(9, len(vendor_ids))
        self.assertTrue(vendor_ids <= data["mods"].keys())
        other_fields = {key: {field: value for field, value in mod.items() if field != "domain"}
                        for key, mod in data["mods"].items() if key not in vendor_ids}
        updated = [key for key in other_fields if key.startswith(("JunMasterVeiledJewel", "JunMasterVeiledAbyss"))]
        self.assertEqual(53, len(updated))
        for key in updated:
            self.assertIn("unveiled_mod", other_fields[key]["implicit_tags"])
            other_fields[key]["implicit_tags"] = [tag for tag in other_fields[key]["implicit_tags"] if tag != "unveiled_mod"]
        encoded = json.dumps(other_fields, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
        self.assertEqual("f165e1926173a5258a0506c507abbd129d2aac8802c4d24bbed0660abe38bebb",
                         hashlib.sha256(encoded).hexdigest())


if __name__ == "__main__":
    unittest.main()
