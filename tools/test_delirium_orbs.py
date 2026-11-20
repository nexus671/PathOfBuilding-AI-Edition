import json
import unittest

from update_delirium_orbs import OUTPUT, SOURCE_SHA256, build


class DeliriumOrbReferenceTest(unittest.TestCase):
    def test_reference(self):
        data = json.loads(OUTPUT.read_text(encoding="utf8"))
        self.assertEqual(data["sourceSha256"], SOURCE_SHA256)
        choices = {entry["name"]: entry["reward"] for entry in data["choices"]}
        self.assertEqual(len(choices), 20)
        self.assertEqual(len(choices), len(data["choices"]))
        self.assertEqual(choices["Fine Delirium Orb"], "Currency Items")
        self.assertEqual(choices["Threaded Delirium Orb"], "Threads")
        self.assertNotIn("Fragmented Delirium Orb", choices)

    def test_rejects_unreviewed_export(self):
        with self.assertRaises(ValueError):
            build(b"{}")


if __name__ == "__main__":
    unittest.main()
