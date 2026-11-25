#!/usr/bin/env python3
"""Verify a portable ZIP against the manifest inside it without extracting it."""
import argparse
import hashlib
from pathlib import Path
import re
import stat
import subprocess
import xml.etree.ElementTree as ET
import zipfile

from build_portable_package import safe_name, SHA1, ROOT


def manifest_identity(root, local=False):
    if root.tag != "PoBVersion":
        raise ValueError("Invalid source manifest")
    children = []
    for child in root:
        if child.tag not in {"Version", "Source", "File"} or list(child) or (child.text or "").strip():
            raise ValueError("Unexpected source manifest content")
        attributes = dict(child.attrib)
        if local and child.tag == "Version":
            attributes.pop("branch", None)
            attributes.pop("platform", None)
            attributes.pop("updates", None)
        children.append((child.tag, tuple(sorted(attributes.items()))))
    return tuple(children)


def verify(path, source_manifest=None, expected_commit=None, expected_branch=None, *, require_local_updates=False):
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
        if version.get("updates") not in {None, "local"}:
            raise ValueError("Invalid app update mode")
        if require_local_updates and version.get("updates") != "local":
            raise ValueError("Package does not disable network app updates")
        if expected_branch is not None and (expected_branch not in {"dev", "main"} or version.get("branch") != expected_branch):
            raise ValueError("Package update branch does not match the expected branch")
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
        if (source_manifest is None) != (expected_commit is None):
            raise ValueError("Source manifest and expected commit must be supplied together")
        if source_manifest is not None:
            if not re.fullmatch(r"[0-9a-f]{40}", expected_commit) or commit.group(1) != expected_commit:
                raise ValueError("Package commit does not match the expected commit")
            if manifest_identity(local, local=True) != manifest_identity(ET.fromstring(source_manifest)):
                raise ValueError("Package manifest does not match the expected commit")
        return len(entries), version.get("number"), version.get("branch"), commit.group(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--expected-commit", help="Full commit ID whose tracked manifest is trusted")
    parser.add_argument("--expected-branch", choices=("dev", "main"), help="Expected update branch")
    parser.add_argument("--require-local-updates", action="store_true", help="Require app updates to be disabled in the package")
    args = parser.parse_args()
    source_manifest = None
    if args.expected_commit:
        if not re.fullmatch(r"[0-9a-f]{40}", args.expected_commit):
            parser.error("--expected-commit must be a full lowercase commit ID")
        source_manifest = subprocess.check_output(["git", "show", args.expected_commit + ":manifest.xml"], cwd=ROOT)
    count, version, branch, commit = verify(args.package, source_manifest, args.expected_commit, args.expected_branch, require_local_updates=args.require_local_updates)
    outcome = "Source verified" if source_manifest is not None else "Internally consistent; source commit not independently verified"
    print(f"{outcome}: {count} files, {version}, {branch}, {commit}")


if __name__ == "__main__":
    main()
