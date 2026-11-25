#!/usr/bin/env python3
# cspell:ignore lupa
"""Run a repository Lua script using Python's optional LuaJIT-backed Lupa."""

import argparse
import os
from pathlib import Path


def install_filesystem(lua):
    """Offer the small LuaFileSystem subset used by headless recovery checks."""
    def mkdir(path):
        try:
            os.mkdir(path)
            return True
        except OSError as exc:
            return None, str(exc)

    def rmdir(path):
        try:
            os.rmdir(path)
            return True
        except OSError as exc:
            return None, str(exc)

    def listdir(path):
        return lua.table_from([".", "..", *os.listdir(path)])

    lua.globals().headless_fs_mkdir = mkdir
    lua.globals().headless_fs_rmdir = rmdir
    lua.globals().headless_fs_listdir = listdir
    lua.execute('''package.preload.lfs=function()
        return {mkdir=headless_fs_mkdir,rmdir=headless_fs_rmdir,dir=function(path)
            local entries=headless_fs_listdir(path);local i=0
            return function() i=i+1;return entries[i] end
        end}
    end''')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--filesystem", action="store_true", help="provide a limited LuaFileSystem adapter")
    parser.add_argument("--portable", type=Path, help="run against a freshly extracted portable package")
    parser.add_argument("script", type=Path)
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    try:
        from lupa.luajit21 import LuaRuntime
    except ImportError as exc:
        raise SystemExit("Install Python's Lupa package with LuaJIT 2.1 support first.") from exc

    root = Path(__file__).resolve().parent.parent
    script = options.script.resolve()
    if not script.is_file():
        raise SystemExit(f"Lua script not found: {script}")
    runtime = options.portable.resolve(strict=True) if options.portable else root / "runtime"
    if options.portable and not all((runtime / name).is_file() for name in ("HeadlessWrapper.lua", "Launch.lua", "manifest.xml")):
        raise SystemExit("The portable directory must contain HeadlessWrapper.lua, Launch.lua and manifest.xml.")
    dll_directory = None
    if os.name == "nt":
        dll_directory = os.add_dll_directory(str(runtime))
    os.environ["PATH"] = str(runtime) + os.pathsep + os.environ.get("PATH", "")
    os.environ.setdefault("CI", "1")
    os.chdir(runtime if options.portable else root / "src")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua_path = "lua/?.lua;lua/?/init.lua;" if options.portable else "../runtime/lua/?.lua;../runtime/lua/?/init.lua;"
    lua_cpath = "?.dll;?.so;" if options.portable else "../runtime/?.dll;../runtime/?.so;"
    lua.execute('package.path="?.lua;?/init.lua;"..' + repr(lua_path) + '..package.path')
    lua.execute('package.cpath=' + repr(lua_cpath) + '..package.cpath')
    if options.filesystem:
        install_filesystem(lua)
    args = lua.table()
    args[0] = str(script)
    for index, value in enumerate(options.arguments, 1):
        args[index] = value
    lua.globals().arg = args
    lua.execute("dofile(...)", str(script))
    if dll_directory is not None:
        dll_directory.close()


if __name__ == "__main__":
    main()
