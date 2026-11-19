#!/usr/bin/env python3
# cspell:ignore lupa
"""Run a repository Lua script using Python's optional LuaJIT-backed Lupa."""

import os
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 2:
        raise SystemExit("Usage: python tools/run_headless_lupa.py SCRIPT [ARGS...]")
    try:
        from lupa.luajit21 import LuaRuntime
    except ImportError as exc:
        raise SystemExit("Install Python's Lupa package with LuaJIT 2.1 support first.") from exc

    root = Path(__file__).resolve().parent.parent
    script = Path(sys.argv[1]).resolve()
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
    args = lua.table()
    args[0] = str(script)
    for index, value in enumerate(sys.argv[2:], 1):
        args[index] = value
    lua.globals().arg = args
    lua.execute("dofile(...)", str(script))
    if dll_directory is not None:
        dll_directory.close()


if __name__ == "__main__":
    main()
