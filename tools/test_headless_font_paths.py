"""Exercise the real headless font loader from source and portable layouts."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / "runtime/SimpleGraphic/Fonts/Liberation Sans.tgf"
MODULE = ROOT / "src/Modules/HeadlessUI.lua"
RUNNER = '''
launch={headless=true};main={}
local ui=assert(loadfile(arg[1]))().install(arg[2] and {fontRoot=arg[2]} or {})
assert(DrawStringWidth(14,"VAR","Portable font")>0)
print("HEADLESS_FONT_OK")
'''


class HeadlessFontPaths(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.runner = self.root / "font.lua"
        self.runner.write_text(RUNNER, encoding="utf-8")
        self.lua = shutil.which("luajit")
        if not self.lua:
            try:
                import lupa.luajit21  # noqa: F401
            except ImportError:
                self.skipTest("LuaJIT or Lupa is required")

    def tearDown(self):
        self.temp.cleanup()

    def run_font(self, cwd, explicit=None):
        args = [str(self.runner), str(MODULE)] + ([str(explicit)] if explicit else [])
        if self.lua:
            command = [self.lua, *args]
        else:
            command = [sys.executable, "-c", (
                "import sys; from lupa.luajit21 import LuaRuntime; "
                "lua=LuaRuntime(); a=lua.table(); "
                "[a.__setitem__(i,x) for i,x in enumerate(sys.argv[2:],1)]; "
                "lua.globals().arg=a; lua.execute(open(sys.argv[1],encoding='utf-8').read())"
            ), *args]
        return subprocess.run(command, cwd=cwd, text=True, capture_output=True, env=os.environ.copy())

    def copy_font(self, directory):
        directory.mkdir(parents=True)
        shutil.copy2(FONT, directory / FONT.name)

    def test_source_and_portable_layouts(self):
        source = self.root / "checkout/src"
        source.mkdir(parents=True)
        self.copy_font(self.root / "checkout/runtime/SimpleGraphic/Fonts")
        portable = self.root / "portable"
        self.copy_font(portable / "SimpleGraphic/Fonts")
        for cwd in (source, portable):
            with self.subTest(cwd=cwd):
                result = self.run_font(cwd)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("HEADLESS_FONT_OK", result.stdout)

    def test_explicit_font_root_is_honored(self):
        custom = self.root / "custom"
        self.copy_font(custom)
        result = self.run_font(self.root, custom)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotEqual(self.run_font(self.root, self.root / "missing").returncode, 0)


if __name__ == "__main__":
    unittest.main()
