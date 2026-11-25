import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("update_passive_preview.py")
spec = importlib.util.spec_from_file_location("passive_preview", SCRIPT)
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


class PassivePreviewCheckTest(unittest.TestCase):
    def test_differences_reports_missing_and_changed_without_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            generated, existing = root / "generated", root / "existing"
            generated.mkdir()
            existing.mkdir()
            (generated / "tree.lua").write_bytes(b"a\nb\n")
            (existing / "tree.lua").write_bytes(b"a\r\nb\r\n")
            (generated / "sprites.png").write_bytes(b"first")
            (existing / "sprites.png").write_bytes(b"second")
            (generated / "source.json").write_text("{}", encoding="utf8")
            self.assertEqual(["Missing: source.json", "Different: sprites.png"], preview.differences(generated, existing))
            self.assertEqual(b"second", (existing / "sprites.png").read_bytes())
            self.assertFalse((existing / "source.json").exists())

    def test_check_reports_changes_without_modifying_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            (destination / "tree.lua").write_bytes(b"original")
            def generate(target):
                (target / "tree.lua").write_bytes(b"different")
                return 1, 0, "source"
            with patch.object(preview, "DESTINATION", destination), patch.object(preview, "generate", generate), patch.object(sys, "argv", [str(SCRIPT), "--check"]):
                with self.assertRaisesRegex(SystemExit, "Different: tree.lua"):
                    preview.main()
            self.assertEqual(b"original", (destination / "tree.lua").read_bytes())

    def test_help_is_read_only(self):
        output = io.StringIO()
        with patch.object(preview, "generate") as generate, patch.object(sys, "argv", [str(SCRIPT), "--help"]), contextlib.redirect_stdout(output):
            with self.assertRaises(SystemExit) as result:
                preview.main()
        self.assertEqual(0, result.exception.code)
        generate.assert_not_called()
        self.assertIn("--check", output.getvalue())


if __name__ == "__main__":
    unittest.main()
