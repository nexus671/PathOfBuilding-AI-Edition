"""Regression tests for the fork's updater manifest generator."""
import os
from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import update_manifest


class ManifestGeneratorTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.previous = Path.cwd()
        os.chdir(self.temporary.name)
        Path("src/Export").mkdir(parents=True)
        Path("src/Assets/3.30.0").mkdir(parents=True)
        Path("src/Export/old.lua").write_text("old\n")
        Path("src/Assets/3.30.0/new.lua").write_text("new\n")
        Path("manifest.cfg").write_text("[program]\npath = src\nexclude-directories = src/Export\n")
        Path("manifest.xml").write_text(
            '<PoBVersion><Version number="1" />'
            '<Source part="program" url="https://example.com/fork/{branch}/src/" />'
            '<File name="Export/old.lua" part="program" sha1="outdated" />'
            '</PoBVersion>'
        )

    def tearDown(self):
        os.chdir(self.previous)
        self.temporary.cleanup()

    def test_preserves_sources_and_existing_excluded_files_and_adds_new_files(self):
        update_manifest.create_manifest("2")
        root = ET.parse("manifest-updated.xml").getroot()
        self.assertEqual("2", root.find("Version").get("number"))
        self.assertEqual("https://example.com/fork/{branch}/src/", root.find("Source").get("url"))
        files = {entry.get("name"): entry for entry in root.findall("File")}
        self.assertEqual({"Export/old.lua", "Assets/3.30.0/new.lua"}, set(files))
        self.assertNotEqual("outdated", files["Export/old.lua"].get("sha1"))

    def test_missing_existing_file_does_not_replace_manifest(self):
        original = Path("manifest.xml").read_bytes()
        Path("src/Export/old.lua").unlink()
        with self.assertRaisesRegex(ValueError, "Existing manifest file is missing"):
            update_manifest.create_manifest("2", replace=True)
        self.assertEqual(original, Path("manifest.xml").read_bytes())

    def test_rejects_existing_path_traversal(self):
        path = Path("manifest.xml")
        path.write_text(path.read_text().replace("Export/old.lua", "../old.lua"))
        with self.assertRaisesRegex(ValueError, "Invalid existing manifest path"):
            update_manifest.create_manifest()

    def test_runtime_files_keep_platform_scope(self):
        Path("runtime").mkdir()
        Path("runtime/font.tga").write_bytes(b"font")
        with Path("manifest.cfg").open("a") as config:
            config.write("\n[runtime]\npath = runtime\n")
        path = Path("manifest.xml")
        path.write_text(path.read_text().replace(
            "</PoBVersion>",
            '<Source part="runtime" platform="win32" url="https://example.com/fork/{branch}/runtime/" /></PoBVersion>',
        ))
        update_manifest.create_manifest()
        root = ET.parse("manifest-updated.xml").getroot()
        runtime = next(entry for entry in root.findall("File") if entry.get("part") == "runtime")
        self.assertEqual("win32", runtime.get("platform"))
        self.assertIsNone(runtime.get("runtime"))


if __name__ == "__main__":
    unittest.main()
