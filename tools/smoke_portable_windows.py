#!/usr/bin/env python3
# cspell:ignore WINFUNCTYPE STARTUPINFO STARTF USESHOWWINDOW startupinfo
"""Smoke-test a freshly extracted AI Edition portable package on Windows."""
import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import subprocess
import time
import xml.etree.ElementTree as ET


def smoke(directory, timeout=90):
    if os.name != "nt":
        raise RuntimeError("The native portable smoke test requires Windows")
    directory = Path(directory).resolve(strict=True)
    for name in ("PACKAGE-INFO.txt", "Launch.cfg", "manifest.xml", "Path of Building.exe"):
        if not (directory / name).is_file():
            raise ValueError(f"Not an extracted portable package: missing {name}")
    if (directory / "Settings.xml").exists() or (directory / "Builds").exists():
        raise ValueError("Use a fresh extraction without existing settings or builds")
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows.argtypes = (callback_type, wintypes.LPARAM)
    user32.EnumWindows.restype = wintypes.BOOL
    user32.GetWindowThreadProcessId.argtypes = (wintypes.HWND, ctypes.POINTER(wintypes.DWORD))
    user32.GetWindowTextLengthW.argtypes = (wintypes.HWND,)
    user32.GetWindowTextW.argtypes = (wintypes.HWND, wintypes.LPWSTR, ctypes.c_int)
    user32.IsHungAppWindow.argtypes = (wintypes.HWND,)
    user32.IsHungAppWindow.restype = wintypes.BOOL
    user32.PostMessageW.argtypes = (wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM)
    user32.PostMessageW.restype = wintypes.BOOL
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    process = subprocess.Popen([str(directory / "Path of Building.exe")], cwd=directory, startupinfo=startup)
    window = None
    title = None
    try:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError(f"Application exited before becoming ready: {process.returncode}")
            found = []
            @callback_type
            def inspect(hwnd, _):
                pid = wintypes.DWORD()
                user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
                if pid.value == process.pid:
                    length = user32.GetWindowTextLengthW(hwnd)
                    text = ctypes.create_unicode_buffer(length + 1)
                    user32.GetWindowTextW(hwnd, text, len(text))
                    if " - Path of Building AI Edition" in text.value:
                        found.append((hwnd, text.value))
                return True
            if not user32.EnumWindows(inspect, 0):
                raise ctypes.WinError(ctypes.get_last_error())
            if found and not user32.IsHungAppWindow(found[0][0]) and (directory / "Builds").is_dir():
                window, title = found[0]
                break
            time.sleep(0.5)
        if window is None:
            raise TimeoutError(f"Application did not become ready within {timeout} seconds")
        if not user32.PostMessageW(window, 0x0010, 0, 0):  # WM_CLOSE
            raise ctypes.WinError(ctypes.get_last_error())
        process.wait(timeout=15)
        if process.returncode != 0:
            raise RuntimeError(f"Application exited with code {process.returncode}")
        settings = directory / "Settings.xml"
        if not settings.is_file() or ET.parse(settings).getroot().tag != "PathOfBuilding":
            raise RuntimeError("Portable settings were not saved in the extraction directory")
        return {"windowTitle": title, "exitCode": process.returncode, "settings": str(settings), "builds": str(directory / "Builds")}
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Freshly extracted and source-verified portable package")
    args = parser.parse_args()
    print(json.dumps(smoke(args.directory), indent=2))


if __name__ == "__main__":
    main()
