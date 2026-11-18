"""Verify provenance and ordinary-map restrictions for bundled item artwork."""
import base64
import json
import unittest
from pathlib import Path

from update_map_item_art import catalogue, check, validate_url

ROOT = Path(__file__).resolve().parents[1]


class MapItemArtTests(unittest.TestCase):
    def test_bundled_images_are_complete_and_verified_offline(self):
        check()
        manifest = json.loads((ROOT / "src/Assets/MapCrafting/items.json").read_text())
        self.assertEqual(16, len(manifest["images"]))

    def test_rejects_unpinned_catalogues_and_special_map_art(self):
        with self.assertRaisesRegex(ValueError, "pinned source"):
            catalogue(b"{}")
        item = {"f": "2DItems/Maps/Atlas2Maps/New/MapNumbers16", "mn": 24, "mb": True}
        token = base64.urlsafe_b64encode(json.dumps([31, 14, item]).encode()).decode().rstrip("=")
        with self.assertRaises(AssertionError):
            validate_url(f"/gen/image/{token}/deadbeef/MapNumbers16.png", 16)
        with self.assertRaises(ValueError):
            validate_url("/gen/image/../../other.png", 16)


if __name__ == "__main__":
    unittest.main()
