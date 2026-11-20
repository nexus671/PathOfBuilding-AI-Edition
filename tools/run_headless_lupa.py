#!/usr/bin/env python3
# cspell:ignore lupa
"""Run a repository Lua script using Python's optional LuaJIT-backed Lupa."""

import os
import sys
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
    arguments = sys.argv[1:]
    filesystem = bool(arguments and arguments[0] == "--filesystem")
    if filesystem:
        arguments = arguments[1:]
    if not arguments:
        raise SystemExit("Usage: python tools/run_headless_lupa.py [--filesystem] SCRIPT [ARGS...]")
    try:
        from lupa.luajit21 import LuaRuntime
    except ImportError as exc:
        raise SystemExit("Install Python's Lupa package with LuaJIT 2.1 support first.") from exc

    root = Path(__file__).resolve().parent.parent
    script = Path(arguments[0]).resolve()
    if not script.is_file():
        raise SystemExit(f"Lua script not found: {script}")
    runtime = root / "runtime"
    dll_directory = None
    if os.name == "nt":
        dll_directory = os.add_dll_directory(str(runtime))
    os.environ["PATH"] = str(runtime) + os.pathsep + os.environ.get("PATH", "")
    os.environ.setdefault("CI", "1")
    os.chdir(root / "src")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('package.path="?.lua;?/init.lua;../runtime/lua/?.lua;../runtime/lua/?/init.lua;"..package.path')
    lua.execute('package.cpath="../runtime/?.dll;../runtime/?.so;"..package.cpath')
    if filesystem:
        install_filesystem(lua)
    args = lua.table()
    args[0] = str(script)
    for index, value in enumerate(arguments[1:], 1):
        args[index] = value
    lua.globals().arg = args
    lua.execute("dofile(...)", str(script))
    if dll_directory is not None:
        dll_directory.close()


if __name__ == "__main__":
    main()
