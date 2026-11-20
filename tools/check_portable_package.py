#!/usr/bin/env python3
"""Verify a portable ZIP against the manifest inside it without extracting it."""
import argparse
import hashlib
from pathlib import Path
import re
import stat
import xml.etree.ElementTree as ET
import zipfile

from build_portable_package import safe_name, SHA1


def verify(path):
    with zipfile.ZipFile(path) as archive:
        entries = {}
        for info in archive.infolist():
            name = str(safe_name(info.filename))
            key = name.casefold()
            mode = info.external_attr >> 16
            if key in entries or info.is_dir() or stat.S_ISLNK(mode):
                raise ValueError(f"Unsafe or duplicate archive entry: {name}")
            entries[key] = info
        local = ET.fromstring(archive.read(entries["manifest.xml"]))
        version = local.find("Version")
        if local.tag != "PoBVersion" or version is None or version.get("platform") != "win32" or version.get("branch") not in {"dev", "main"}:
            raise ValueError("Invalid local update identity")
        expected = {"manifest.xml", "package-info.txt", "launch.cfg"}
        manifest_entries = local.findall("File")
        if not manifest_entries:
            raise ValueError("Manifest has no files")
        for item in manifest_entries:
            if item.get("platform") not in (None, "win32"):
                continue
            name = str(safe_name(item.get("name", "")))
            key, digest = name.casefold(), item.get("sha1", "")
            if key in expected or key not in entries or not SHA1.fullmatch(digest):
                raise ValueError(f"Missing, duplicate or invalid manifest entry: {name}")
            expected.add(key)
            actual = hashlib.sha1()
            with archive.open(entries[key]) as contents:
                for chunk in iter(lambda: contents.read(1024 * 1024), b""):
                    actual.update(chunk)
            if actual.hexdigest() != digest:
                raise ValueError(f"Package hash mismatch: {name}")
        if set(entries) != expected or not {"path of building.exe", "launch.lua"} <= expected:
            raise ValueError("Package has unlisted files or is missing a launcher")
        if archive.read(entries["launch.cfg"]) != b"":
            raise ValueError("Unexpected launcher configuration")
        info = archive.read(entries["package-info.txt"]).decode("utf-8")
        commit = re.search(r"(?m)^Commit: ([0-9a-f]{40})\r?$", info)
        if not commit or f"Version: {version.get('number')}\r\n" not in info or f"Update branch: {version.get('branch')}\r\n" not in info:
            raise ValueError("Package identity does not match its manifest")
        return len(entries), version.get("number"), version.get("branch"), commit.group(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    args = parser.parse_args()
    count, version, branch, commit = verify(args.package)
    print(f"Verified {count} files: {version}, {branch}, {commit}")


if __name__ == "__main__":
    main()
