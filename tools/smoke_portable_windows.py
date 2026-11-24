#!/usr/bin/env python3
# cspell:ignore WINFUNCTYPE STARTUPINFO STARTF USESHOWWINDOW startupinfo
"""Smoke-test a freshly extracted AI Edition portable package on Windows."""
import argparse
import ctypes
from ctypes import wintypes
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
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
    parser.add_argument("--loot-filter", type=Path, help="Copy this fixed baseline and run one live Windows sync")
    parser.add_argument("--league", help="PC trade league ID for the live sync")
    parser.add_argument("--protected-checks", type=int, default=600, help="Minimum protected samples expected from this baseline")
    args = parser.parse_args()
    if bool(args.loot_filter) != bool(args.league):
        parser.error("--loot-filter and --league must be supplied together")
    if args.protected_checks < 1:
        parser.error("--protected-checks must be positive")
    directory = args.directory.resolve(strict=True)
    baseline = args.loot_filter.resolve(strict=True) if args.loot_filter else None
    if baseline and (not baseline.is_file() or baseline.suffix.lower() != ".filter" or directory in baseline.parents):
        parser.error("Use a .filter baseline located outside the fresh extraction")
    result = smoke(directory)
    if baseline:
        result["lootSync"] = smoke_loot_sync(directory, baseline, args.league, args.protected_checks)
    print(json.dumps(result, indent=2))


def smoke_loot_sync(directory, source, league, minimum_checks):
    tools = Path(__file__).resolve().parent
    baseline, target = (directory / name for name in ("smoke-baseline.filter", "smoke-output.filter"))
    config = directory / "LootFilterDailySync.json"
    reviews = directory / "LootFilterDailySync-Reviews.json"
    if any(path.exists() or path.is_symlink() for path in (baseline, target, config, reviews)):
        raise ValueError("Use a fresh extraction without existing loot sync state")
    source_bytes = source.read_bytes()
    for path in (baseline, target):
        with path.open("xb") as destination:
            destination.write(source_bytes)

    def native_config(action):
        output = subprocess.check_output(
            [sys.executable, str(tools / "run_headless_lupa.py"), "--filesystem", "--portable", str(directory),
             str(tools / "smoke_portable_loot_sync.lua"), action, str(directory), league],
            encoding="utf-8", timeout=30,
        )
        return json.loads(output) if output.strip() else None

    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE

    def invoke_worker():
        return subprocess.run([str(directory / "Path of Building.exe"), "--loot-filter-sync-scheduled"],
                              cwd=directory, startupinfo=startup, timeout=160, check=False).returncode

    native_config("prepare")
    scheduled_date = date.today()
    first_exit = invoke_worker()
    evidence = native_config("report")
    status = evidence["status"]
    if first_exit or status["state"] != "enabled" or status["league"] != league or not status.get("lastSuccess"):
        raise RuntimeError(f"Scheduled Windows worker failed ({first_exit}): {status}")
    review = evidence.get("lastReview") or {}
    if not review.get("verifiedProtection") or (review.get("protectedChecks") or 0) < minimum_checks:
        raise RuntimeError("The scheduled refresh did not verify the required protected samples")
    if baseline.read_bytes() != source_bytes or source.read_bytes() != source_bytes:
        raise RuntimeError("The fixed filter baseline changed")

    def checksums():
        return [hashlib.sha256(path.read_bytes()).hexdigest() for path in (target, baseline, config, reviews)]

    if date.today() != scheduled_date:
        raise RuntimeError("The live refresh crossed midnight before the same-day rerun")
    original = checksums()
    if invoke_worker() or checksums() != original or date.today() != scheduled_date:
        raise RuntimeError("Could not verify a byte-identical same-day worker rerun")
    return {"league": league, "lastSuccess": status["lastSuccess"], "feeds": review["feeds"],
            "protectedChecks": review["protectedChecks"], "priceDecisions": review["changeCount"],
            "fixedBaselinePreserved": True, "sameDayRerunIdentical": True, "outputSha256": original[0]}


if __name__ == "__main__":
    main()
