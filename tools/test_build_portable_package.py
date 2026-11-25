import hashlib
import sys
import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

spec = importlib.util.spec_from_file_location("portable", Path(__file__).with_name("build_portable_package.py"))
portable = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portable)
sys.path.insert(0, str(Path(__file__).parent))
import check_portable_package


class PortablePackageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "runtime").mkdir()
        (self.root / "src").mkdir()
        self.exe = b"launcher"
        self.lua = b"line 1\nline 2\n"
        (self.root / "runtime" / "Path{space}of{space}Building.exe").write_bytes(self.exe)
        (self.root / "src" / "Launch.lua").write_bytes(self.lua)
        (self.root / "src" / "Settings.xml").write_text("personal data")
        self.manifest = ET.Element("PoBVersion")
        ET.SubElement(self.manifest, "Version", number="test-preview")
        ET.SubElement(self.manifest, "File", part="runtime", name="Path{space}of{space}Building.exe", sha1=hashlib.sha1(self.exe).hexdigest(), platform="win32")
        ET.SubElement(self.manifest, "File", part="program", name="Launch.lua", sha1=hashlib.sha1(self.lua.replace(b"\n", b"\r\n")).hexdigest())
        self.save_manifest()
        self.output = self.root / "output.zip"

    def tearDown(self):
        self.tmp.cleanup()

    def save_manifest(self):
        ET.ElementTree(self.manifest).write(self.root / "manifest.xml", encoding="utf-8", xml_declaration=True)

    def build(self):
        return portable.build(self.root, self.output, "dev", "a" * 40)

    def test_package_contains_only_manifest_files_with_local_update_identity(self):
        count, version = self.build()
        self.assertEqual((count, version), (5, "test-preview"))
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(set(archive.namelist()), {"Path of Building.exe", "Launch.lua", "manifest.xml", "PACKAGE-INFO.txt", "Launch.cfg"})
            self.assertEqual(archive.read("Launch.lua"), self.lua.replace(b"\n", b"\r\n"))
            version = ET.fromstring(archive.read("manifest.xml")).find("Version")
            self.assertEqual((version.get("branch"), version.get("platform")), ("dev", "win32"))
            self.assertIn(b"a" * 40, archive.read("PACKAGE-INFO.txt"))
        self.assertEqual(check_portable_package.verify(self.output), (5, "test-preview", "dev", "a" * 40))
        with self.assertRaises(FileExistsError):
            self.build()

    def test_local_updates_must_be_recorded_in_the_manifest(self):
        portable.build(self.root, self.output, "dev", "a" * 40, local_updates=True)
        trusted = (self.root / "manifest.xml").read_bytes()
        result = check_portable_package.verify(self.output, trusted, "a" * 40, require_local_updates=True)
        self.assertEqual(result, (5, "test-preview", "dev", "a" * 40))
        with zipfile.ZipFile(self.output) as source:
            version = ET.fromstring(source.read("manifest.xml")).find("Version")
            self.assertEqual(version.get("updates"), "local")
            self.assertIn(b"App updates use local packages", source.read("PACKAGE-INFO.txt"))
        online = self.root / "online.zip"
        portable.build(self.root, online, "dev", "a" * 40)
        with self.assertRaisesRegex(ValueError, "does not disable"):
            check_portable_package.verify(online, require_local_updates=True)

    def test_verifier_rejects_unlisted_and_modified_content(self):
        self.build()
        with zipfile.ZipFile(self.output, "a") as archive:
            archive.writestr("unexpected.txt", "extra")
        with self.assertRaises(ValueError):
            check_portable_package.verify(self.output)
        self.output.unlink()
        self.build()
        rewritten = self.root / "rewritten.zip"
        with zipfile.ZipFile(self.output) as source, zipfile.ZipFile(rewritten, "w") as target:
            for entry in source.infolist():
                target.writestr(entry, b"changed" if entry.filename == "Launch.lua" else source.read(entry))
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            check_portable_package.verify(rewritten)

    def test_expected_commit_requires_the_tracked_manifest(self):
        self.build()
        trusted = (self.root / "manifest.xml").read_bytes()
        self.assertEqual(check_portable_package.verify(self.output, trusted, "a" * 40)[3], "a" * 40)
        with self.assertRaisesRegex(ValueError, "commit does not match"):
            check_portable_package.verify(self.output, trusted, "b" * 40)
        with self.assertRaisesRegex(ValueError, "update branch does not match"):
            check_portable_package.verify(self.output, trusted, "a" * 40, "main")
        forged = self.root / "forged.zip"
        with zipfile.ZipFile(self.output) as source, zipfile.ZipFile(forged, "w") as target:
            for entry in source.infolist():
                data = source.read(entry)
                if entry.filename == "Launch.lua":
                    data = b"forged program"
                elif entry.filename == "manifest.xml":
                    manifest = ET.fromstring(data)
                    next(item for item in manifest.findall("File") if item.get("name") == "Launch.lua").set("sha1", hashlib.sha1(b"forged program").hexdigest())
                    data = ET.tostring(manifest, encoding="utf-8", xml_declaration=True)
                target.writestr(entry, data)
        # A self-consistent archive is not evidence of source authenticity.
        self.assertEqual(check_portable_package.verify(forged)[3], "a" * 40)
        with self.assertRaisesRegex(ValueError, "manifest does not match"):
            check_portable_package.verify(forged, trusted, "a" * 40)

    def test_bad_hash_and_unsafe_or_duplicate_paths_do_not_leave_output(self):
        for name, part, digest in [("../outside", "program", "0" * 40), ("Launch.lua", "program", "0" * 40), ("launch.lua", "program", hashlib.sha1(self.lua.replace(b"\n", b"\r\n")).hexdigest())]:
            added = ET.SubElement(self.manifest, "File", name=name, part=part, sha1=digest)
            if name == "launch.lua":
                (self.root / "src" / name).write_bytes(self.lua)
            self.save_manifest()
            with self.assertRaises(ValueError):
                self.build()
            self.assertFalse(self.output.exists())
            self.manifest.remove(added)
        self.save_manifest()

    def test_changed_source_does_not_publish_archive(self):
        def changed():
            raise ValueError("source changed")
        with self.assertRaisesRegex(ValueError, "source changed"):
            portable.build(self.root, self.output, "dev", "a" * 40, changed)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob(".pob-package-*.tmp")))

    def test_rejects_windows_device_and_invalid_file_names(self):
        for name in ("NUL.txt", "folder/COM1.json", "folder/Lpt9", "bad?.lua", "trailing.", "file\x01.lua"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                portable.safe_name(name)
        self.assertEqual(str(portable.safe_name("data/COM10.lua")), "data/COM10.lua")

    def test_rejects_unknown_branch_or_short_commit(self):
        with self.assertRaises(ValueError):
            portable.build(self.root, self.output, "feature", "a" * 40)
        with self.assertRaises(ValueError):
            portable.build(self.root, self.output, "dev", "abc")


if __name__ == "__main__":
    unittest.main()
