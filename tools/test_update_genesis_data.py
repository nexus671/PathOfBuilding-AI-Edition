"""Check the bundled Genesis export's core invariants and patch-specific data."""
import json
from pathlib import Path
import unittest

from update_genesis_data import DESTINATION, HASHES, TREE, read_source, translate


class GenesisDataTests(unittest.TestCase):
    def test_graph_is_partitioned_and_bidirectional(self):
        data = json.loads(DESTINATION.read_text(encoding="utf-8"))
        nodes = data["nodes"]
        self.assertEqual(133, len(nodes))
        self.assertEqual(4, len(data["roots"]))
        self.assertEqual(6, sum(node["choice"] for node in nodes.values()))
        self.assertEqual(28, sum(node["choiceOption"] for node in nodes.values()))
        for node in nodes.values():
            self.assertIn(node["root"], data["roots"])
            for target in node["links"]:
                other = nodes[str(target)]
                self.assertIn(node["id"], other["links"])
                self.assertEqual(node["root"], other["root"])
        for root in data["roots"]:
            self.assertEqual(root, nodes[str(root)]["root"])

    def test_current_currency_patch_and_source_provenance(self):
        data = json.loads(DESTINATION.read_text(encoding="utf-8"))
        node = next(node for node in data["nodes"].values() if node["name"] == "Mutation Cultivation")
        self.assertEqual(["6% chance to Birth an additional Foulborn Currency (level 75+)"], node["stats"])
        self.assertFalse(any(node["name"] == "Flawed Seeds" for node in data["nodes"].values()))
        self.assertEqual(HASHES[TREE], data["treeSha256"])

    def test_unknown_stat_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Expected one translation"):
            translate("unknown", 5, {})

    def test_modified_source_is_rejected(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "BrequelTree.json").write_text("{}", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Unexpected source hash"):
                read_source(TREE, Path(directory))


if __name__ == "__main__":
    unittest.main()
