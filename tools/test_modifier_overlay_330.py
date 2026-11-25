import hashlib
import json
import unittest
from unittest.mock import patch

import update_modifier_overlay_330 as overlay


class ModifierOverlayTest(unittest.TestCase):
    def setUp(self):
        self.old = {field: [] for field in overlay.FIELDS}
        self.old.update(domain="item", generation_type="corrupted", required_level=40,
                        is_essence_only=False,
                        stats=[{"id": "local_display_support_level", "min": 10, "max": 10}])
        self.baseline = {"patch": "3.29.3.6", "source": {"commit": overlay.BASE_COMMIT},
                         "mods": {"support": self.old}}
        self.mod = dict(self.old, stats=[{"id": "local_display_support_level", "min": 0, "max": 0}],
                        grants_effects=[{"level": 15}])

    def run_build(self):
        raw = json.dumps({"support": self.mod}).encode()
        normalized = json.dumps(self.baseline, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        with patch.object(overlay, "SOURCE_HASH", hashlib.sha256(raw).hexdigest()), \
             patch.object(overlay, "BASE_HASH", hashlib.sha256(normalized).hexdigest()), \
             patch.object(overlay, "RECONSTRUCTED_LEVELS", 1), patch.object(overlay, "CHANGED_RECORDS", 1), \
             patch.object(overlay, "NEW_IDS", ()):
            return overlay.build(self.baseline, raw)

    def test_reconstructs_current_granted_level_without_mutating_the_baseline(self):
        result = self.run_build()
        self.assertEqual(15, result["mods"]["support"]["stats"][0]["min"])
        self.assertEqual(10, self.baseline["mods"]["support"]["stats"][0]["min"])

    def test_rejects_ambiguous_granted_levels_and_wrong_sources(self):
        self.mod["grants_effects"].append({"level": 20})
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            self.run_build()
        with patch.object(overlay, "BASE_HASH", hashlib.sha256(json.dumps(self.baseline, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()):
            with self.assertRaisesRegex(ValueError, "does not match"):
                overlay.build(self.baseline, b"{}")
        self.baseline["patch"] = "3.28"
        with self.assertRaisesRegex(ValueError, "baseline"):
            overlay.build(self.baseline, b"{}")
        self.baseline["patch"] = "3.29.3.6"
        self.baseline["mods"]["support"]["stats"][0]["min"] = 9
        with self.assertRaisesRegex(ValueError, "baseline does not match"):
            overlay.build(self.baseline, b"{}")


if __name__ == "__main__":
    unittest.main()
