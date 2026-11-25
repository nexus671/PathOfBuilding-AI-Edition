"""Offline regression tests for the official announcement extractor."""
import hashlib
import json
import unittest
from unittest.mock import patch

from update_loot_filter_data import Post
import update_loot_filter_base_metadata as base_metadata
import update_loot_filter_base_classes as base_classes


class PostTests(unittest.TestCase):
    def test_reads_only_the_news_post_content(self):
        html = '''<div class="content"><div>Site navigation</div>
        <table><tr class="newsPost"><td><div class="content">
        <h3>Removed Items</h3><div class="spoiler"><ul><li>Orb of Binding</li></ul></div>
        </div></td></tr><tr><td><div class="content">A reply</div></td></tr></table>
        <div>Report Forum Post 12345Next</div></div>'''
        post = Post()
        post.feed(html)
        text = "".join(post.parts)
        self.assertIn("Removed Items", text)
        self.assertIn("Orb of Binding", text)
        self.assertNotIn("Site navigation", text)
        self.assertNotIn("A reply", text)
        self.assertNotIn("Report Forum Post", text)

    def test_base_metadata_omits_ambiguous_and_missing_properties(self):
        records = {
            "one": {"name": "Repeated", "drop_level": 10, "inventory_width": 2, "inventory_height": 3},
            "two": {"name": "Repeated", "drop_level": 20, "inventory_width": 2, "inventory_height": 3},
            "three": {"name": "Incomplete", "drop_level": 0, "inventory_width": 1},
        }
        raw = json.dumps(records).encode()
        with patch.object(base_metadata, "SOURCE_SHA256", hashlib.sha256(raw).hexdigest()):
            bases = base_metadata.build(raw)["bases"]
        self.assertEqual({"Width": 2, "Height": 3}, bases["Repeated"])
        self.assertEqual({"Width": 1}, bases["Incomplete"])
        with self.assertRaises(ValueError):
            base_metadata.build(raw)

    def test_base_classes_preserve_ambiguity_and_reject_unreviewed_sources(self):
        records = {
            "a": {"name": "Known", "item_class": "one"},
            "b": {"name": "Known", "item_class": "alias"},
            "c": {"name": "Ambiguous", "item_class": "one"},
            "d": {"name": "Ambiguous", "item_class": "two"},
            "e": {"name": "Unknown", "item_class": "missing"},
            "f": {"name": "Incomplete", "item_class": "one"},
            "g": {"name": "Incomplete"},
            "h": {"name": "Trade proxy", "item_class": "InstanceLocalItem"},
        }
        classes = {"one": {"name": "Class A"}, "alias": {"name": "Class A"}, "two": {"name": "Class B"}, "InstanceLocalItem": {"name": "Instance Local Items"}}
        base_raw, class_raw = json.dumps(records).encode(), json.dumps(classes).encode()
        with patch.object(base_classes, "BASE_SHA256", hashlib.sha256(base_raw).hexdigest()), patch.object(base_classes, "CLASS_SHA256", hashlib.sha256(class_raw).hexdigest()):
            data = base_classes.build(base_raw, class_raw)
            self.assertEqual({"Known": "Class A"}, data["classes"])
            self.assertEqual({"Ambiguous", "Unknown", "Incomplete", "Trade proxy"}, set(data["ambiguous"]))
            with self.assertRaises(ValueError):
                base_classes.build(base_raw, class_raw + b" ")


if __name__ == "__main__":
    unittest.main()
