import unittest

from update_atlas_filter_supplies import build, select_items


class AtlasFilterSuppliesTest(unittest.TestCase):
    def test_filters_legacy_unreleased_and_removed_items(self):
        def entry(name, item_class="StackableCurrency", release="released"):
            return {"name": name, "item_class": item_class, "release_state": release}

        items = {
            "Metadata/Items/MapFragments/New": entry("Allflame Ember of Flesh"),
            "Metadata/Items/NecropolisPacks/Old": entry("Allflame Ember of Rats", "NecropolisPack"),
            "Metadata/Items/Currency/Old": entry("Fruiting Astrolabe"),
            "Metadata/Items/Currency/New": entry("Feral Astrolabe"),
            "Metadata/Items/Currency/Hidden": entry("Hidden Astrolabe", release="unreleased"),
            "Metadata/Items/Currency/Orb": entry("Threaded Delirium Orb"),
            "Metadata/Items/Currency/Chisel": entry("Maven's Chisel of Divination"),
            "Metadata/Items/Currency/Other": entry("Divine Orb"),
        }
        self.assertEqual(["Allflame Ember of Flesh", "Feral Astrolabe", "Maven's Chisel of Divination", "Threaded Delirium Orb"],
                         select_items(items, {"Fruiting Astrolabe"}))

    def test_rejects_unreviewed_source(self):
        with self.assertRaisesRegex(ValueError, "does not match"):
            build(b"{}", b'{"removed":[]}')


if __name__ == "__main__":
    unittest.main()
