"""Coverage checks for pinned flask enchantment metadata and PoB text."""
import json
import unittest
from pathlib import Path

from update_flask_enchant_data import DEST, IDS


class FlaskEnchantDataTests(unittest.TestCase):
    def test_pool_weights_and_native_text_counts(self):
        data = json.loads(DEST.read_text(encoding="utf-8"))["pools"]
        self.assertEqual({"INSTILLING", "ENKINDLING"}, set(data))
        self.assertEqual(5, len(data["ENKINDLING"]))
        self.assertEqual(16, len(data["INSTILLING"]))
        self.assertEqual(1500, sum(item["weight"] for item in data["INSTILLING"]))
        self.assertEqual(650, sum(item["weight"] for item in data["ENKINDLING"]))
        self.assertEqual(["FlaskEnchantmentInjectorOnGuardSkillExpired"], [item["id"] for item in data["INSTILLING"] if item["weight"] == 0])
        for group, entries in data.items():
            self.assertEqual(IDS[group], [item["id"] for item in entries])
            self.assertEqual(list(range(1, len(entries) + 1)), [item["index"] for item in entries])


if __name__ == "__main__":
    unittest.main()
