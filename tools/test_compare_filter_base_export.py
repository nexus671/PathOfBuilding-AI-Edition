"""Check filter source comparisons catch changed, added and removed records."""
import json
import unittest
from compare_filter_base_export import compare


def raw(value):
    return json.dumps(value, sort_keys=True).encode()


class FilterSourceComparisonTest(unittest.TestCase):
    def test_reports_relevant_fields_and_class_changes(self):
        old = {"kept": {"name": "Old", "item_class": "Ring", "drop_level": 1}, "removed": {}}
        new = {"kept": {"name": "New", "item_class": "Ring", "drop_level": 2}, "added": {}}
        result = compare(raw(old), raw(new), raw({"Ring": {"name": "Rings"}}), raw({"Ring": {"name": "Changed"}}))
        self.assertEqual(["added"], result["addedIds"])
        self.assertEqual(["removed"], result["removedIds"])
        self.assertEqual(["kept"], result["changedFields"]["name"])
        self.assertEqual(["kept"], result["changedFields"]["drop_level"])
        self.assertEqual([], result["changedFields"]["item_class"])
        self.assertEqual(["Ring"], result["changedClassRecords"])

    def test_requires_both_class_sources(self):
        with self.assertRaisesRegex(ValueError, "both item-class"):
            compare(raw({}), raw({}), raw({}), None)


if __name__ == "__main__":
    unittest.main()
