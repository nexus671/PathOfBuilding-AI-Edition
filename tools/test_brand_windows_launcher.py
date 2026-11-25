import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from brand_windows_launcher import brand, version_resource

ROOT = Path(__file__).resolve().parent.parent


class BrandingTest(unittest.TestCase):
    def test_invalid_versions_are_rejected(self):
        for value in ("1.2", "1.2.3.4", "1.bad.3", "65536.1.1"):
            with self.assertRaises(ValueError):
                version_resource(value)

    @unittest.skipUnless(os.name == "nt", "Windows resources require Windows")
    def test_launcher_identity_and_bad_input(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "launcher.exe"
            shutil.copyfile(ROOT / "runtime/Path{space}of{space}Building.exe", executable)
            before = hashlib.sha256(executable.read_bytes()).digest()
            with self.assertRaises(ValueError):
                brand(executable, ROOT / "src/Assets/AI-Edition.ico", "invalid")
            self.assertEqual(before, hashlib.sha256(executable.read_bytes()).digest())
            brand(executable, ROOT / "src/Assets/AI-Edition.ico", "1.0.1")
            output = subprocess.check_output([
                "powershell.exe", "-NoProfile", "-Command",
                "(Get-Item -LiteralPath $env:POB_BRANDING_TEST_EXE).VersionInfo | "
                "Select-Object ProductName,FileDescription,ProductVersion | ConvertTo-Json -Compress",
            ], text=True, env={**os.environ, "POB_BRANDING_TEST_EXE": str(executable)})
            info = json.loads(output)
            self.assertEqual(info["ProductName"], "Path of Building AI Edition")
            self.assertEqual(info["FileDescription"], "Path of Building AI Edition")
            self.assertEqual(info["ProductVersion"], "1.0.1")


if __name__ == "__main__":
    unittest.main()
