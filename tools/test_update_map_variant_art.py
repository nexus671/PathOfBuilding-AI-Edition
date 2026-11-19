"""Validate bundled Blight-map artwork and its source constraints."""
import base64
import json
import unittest

from update_map_variant_art import catalogue, check, validate_url


class MapVariantArtTests(unittest.TestCase):
    def test_bundled_art_is_complete_and_verified_offline(self):
        check()

    def test_rejects_unpinned_data_and_mismatched_variants(self):
        with self.assertRaisesRegex(ValueError, "pinned source"):
            catalogue(b"{}")
        item = {"f": "2DItems/Maps/Atlas2Maps/New/MapNumbers16", "mn": 24,
                "mb": True, "mub": False, "mm": False}
        token = base64.urlsafe_b64encode(json.dumps([31, 14, item]).encode()).decode().rstrip("=")
        path = f"/gen/image/{token}/deadbeef/MapNumbers16.png"
        self.assertTrue(validate_url(path, 16, "blighted").startswith("https://web.poecdn.com/"))
        with self.assertRaises(AssertionError):
            validate_url(path, 16, "ravaged")
        with self.assertRaises(ValueError):
            validate_url("/gen/image/../../other.png", 16, "blighted")


if __name__ == "__main__":
    unittest.main()
