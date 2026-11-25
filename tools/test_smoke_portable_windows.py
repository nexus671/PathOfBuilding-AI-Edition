"""Safety checks for the Windows portable smoke test."""
import os
from pathlib import Path
import tempfile
import unittest

from smoke_portable_windows import smoke


@unittest.skipUnless(os.name == "nt", "native smoke test requires Windows")
class PortableSmokeSafety(unittest.TestCase):
    def test_rejects_missing_package_before_launch(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "missing PACKAGE-INFO"):
                smoke(folder)

    def test_rejects_existing_user_data_before_launch(self):
        for name in ("Settings.xml", "Builds"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                for required in ("PACKAGE-INFO.txt", "Launch.cfg", "manifest.xml", "Path of Building.exe"):
                    (root / required).touch()
                if name == "Builds":
                    (root / name).mkdir()
                else:
                    (root / name).write_text("keep", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "fresh extraction"):
                    smoke(root)
                self.assertTrue((root / name).exists())
                if name == "Settings.xml":
                    self.assertEqual("keep", (root / name).read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
