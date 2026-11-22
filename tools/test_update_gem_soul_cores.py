# cspell:ignore encumbrance
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).with_name("update_gem_soul_cores.py")
spec = importlib.util.spec_from_file_location("gem_soul_cores", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SoulCoreDataTest(unittest.TestCase):
    def fixtures(self):
        gems = {key: {"is_support": True, "display_name": key, "base_item": {"max_level": 1},
                      "static": {"stat_text": {"effect": "Sample effect"}, "cost_multiplier": 100},
                      "support_gem": {"support_text": "Supports a skill."}} for key in module.IDS}
        cores = {str(index): {"name": name, "description": "Corrupts a level 20 Skill Gem"}
                 for index, name in enumerate(module.CORE_NAMES)}
        return gems, cores

    def test_extracts_all_named_effects_and_cost_multiplier(self):
        gems, cores = self.fixtures()
        gems["SupportEncumbrance"]["static"] = {"stat_text": None, "cost_multiplier": 200}
        result = module.build(gems, cores, module.GEMS_SHA256)
        self.assertEqual(4, len(result["cores"]))
        self.assertEqual(12, len(result["downsides"]))
        self.assertEqual(["Cost multiplier: 200%"], next(entry for entry in result["downsides"] if entry["id"] == "SupportEncumbrance")["effects"])

    def test_rejects_unpinned_or_missing_data(self):
        gems, cores = self.fixtures()
        with self.assertRaisesRegex(ValueError, "pinned"):
            module.build(gems, cores, "wrong")
        del cores["0"]
        with self.assertRaisesRegex(ValueError, "Expected one description"):
            module.build(gems, cores, module.GEMS_SHA256)


if __name__ == "__main__":
    unittest.main()
