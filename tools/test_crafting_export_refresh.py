"""Check the reviewed same-version modifier-export correction."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CraftingExportRefreshTest(unittest.TestCase):
    def test_reviewed_jewel_domains_preserve_other_modifier_data(self):
        data = json.loads((ROOT / "src/Data/Crafting/3.30.json").read_text(encoding="utf-8"))
        self.assertEqual("585b4b8433079e514bbd6095c7a5af0480c9d824", data["source"]["commit"])
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
        encoded = json.dumps(other_fields, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
        self.assertEqual("f165e1926173a5258a0506c507abbd129d2aac8802c4d24bbed0660abe38bebb",
                         hashlib.sha256(encoded).hexdigest())


if __name__ == "__main__":
    unittest.main()
