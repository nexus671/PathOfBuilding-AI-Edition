import hashlib
from pathlib import Path
import tempfile
import unittest

from check_update_manifest import check


class ManifestCheckTest(unittest.TestCase):
    def test_accepts_updater_newlines_and_reports_real_problems(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "src").mkdir()
            (root / "src" / "ok.lua").write_bytes(b"one\ntwo\n")
            expected = hashlib.sha1(b"one\r\ntwo\r\n").hexdigest()
            (root / "manifest.xml").write_text(
                '<PoBVersion><File part="program" name="ok.lua" sha1="' + expected + '"/>'
                '<File part="program" name="missing.lua" sha1="' + expected + '"/>'
                '<File part="program" name="../escape" sha1="' + expected + '"/>'
                '</PoBVersion>', encoding="utf-8")
            count, errors = check(root)
            self.assertEqual(3, count)
            self.assertEqual(2, len(errors))
            self.assertTrue(any("Missing" in error for error in errors))
            self.assertTrue(any("Invalid" in error for error in errors))
            (root / "src" / "ok.lua").write_bytes(b"changed")
            self.assertTrue(any("Hash mismatch" in error for error in check(root)[1]))

    def test_rejects_empty_and_duplicate_manifests(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "manifest.xml").write_text("<PoBVersion/>", encoding="utf-8")
            self.assertTrue(check(root)[1])
            (root / "file").write_bytes(b"x")
            digest = hashlib.sha1(b"x").hexdigest()
            entry = '<File part="default" name="file" sha1="' + digest + '"/>'
            (root / "manifest.xml").write_text("<PoBVersion>" + entry + entry + "</PoBVersion>", encoding="utf-8")
            self.assertTrue(any("Duplicate" in error for error in check(root)[1]))


if __name__ == "__main__":
    unittest.main()
