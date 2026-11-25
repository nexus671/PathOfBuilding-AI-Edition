#!/usr/bin/env python3
# cspell:ignore compresslevel
"""Build a fork-owned Windows portable ZIP from a clean, committed checkout."""
import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PARTS = {"default": "", "runtime": "runtime", "program": "src", "tree": "src"}
SHA1 = re.compile(r"[0-9a-f]{40}\Z")
WINDOWS_DEVICES = {"CON", "PRN", "AUX", "NUL"} | {f"{prefix}{number}" for prefix in ("COM", "LPT") for number in range(1, 10)}


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def safe_name(name):
    name = name.replace("{space}", " ")
    path = PurePosixPath(name)
    if (not name or "\\" in name or path.is_absolute() or any(p in {".", ".."} for p in name.split("/"))
            or any(not part or part.endswith((".", " ")) or part.split(".", 1)[0].upper() in WINDOWS_DEVICES
                   or any(ord(char) < 32 or char in '<>:"|?*' for char in part) for part in name.split("/"))):
        raise ValueError(f"Unsafe manifest path: {name!r}")
    return path


def payload(root, part, manifest_name, digest):
    if part not in PARTS or not SHA1.fullmatch(digest or ""):
        raise ValueError(f"Invalid manifest entry: {part}/{manifest_name}")
    # Files are named with {space} in the source tree but decoded by the updater.
    destination = safe_name(manifest_name)
    source_name = PurePosixPath(manifest_name)
    safe_name(str(source_name))
    base = (root / PARTS[part]).resolve()
    source = base.joinpath(*source_name.parts)
    if not source.resolve().is_relative_to(base) or not source.is_file():
        raise ValueError(f"Missing or unsafe source: {part}/{manifest_name}")
    data = source.read_bytes()
    if hashlib.sha1(data).hexdigest() != digest:
        windows = data.replace(b"\n", b"\r\n")
        if hashlib.sha1(windows).hexdigest() != digest:
            raise ValueError(f"Manifest hash mismatch: {part}/{manifest_name}")
        data = windows
    return str(destination), data


def build(root, output, branch, commit, check_source=None, *, local_updates=False):
    if branch not in {"dev", "main"} or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("A full commit ID and dev or main branch are required")
    root, output = Path(root), Path(output)
    if output.exists():
        raise FileExistsError(f"Output already exists: {output}")
    manifest = ET.parse(root / "manifest.xml").getroot()
    version = manifest.find("Version")
    if manifest.tag != "PoBVersion" or version is None or not version.get("number"):
        raise ValueError("Invalid updater manifest")
    entries = manifest.findall("File")
    if not entries:
        raise ValueError("Updater manifest has no files")
    version.set("branch", branch)
    version.set("platform", "win32")
    if version.get("updates") is not None:
        raise ValueError("App update mode belongs in the portable package")
    if local_updates:
        version.set("updates", "local")
    local_manifest = ET.tostring(manifest, encoding="utf-8", xml_declaration=True)
    info = ("Path of Building AI Edition portable build\r\n"
            f"Version: {version.get('number')}\r\nCommit: {commit}\r\nUpdate branch: {branch}\r\n\r\n"
            "Extract to a writable folder and run Path of Building.exe.\r\n"
            "Builds and settings are stored in that folder. This package does not import existing builds.\r\n"
            + ("App updates use local packages. Daily market refreshes can still use the configured price source.\r\n"
               if local_updates else "The updater follows the stated branch; back up your builds before updating.\r\n")).encode("utf-8")
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".pob-package-", suffix=".tmp", dir=output.parent, delete=False) as handle:
            temp = Path(handle.name)
        names = {"manifest.xml", "package-info.txt", "launch.cfg"}
        with zipfile.ZipFile(temp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
            def add(name, content):
                entry = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o100644 << 16
                archive.writestr(entry, content)
            for entry in entries:
                platform = entry.get("platform")
                if platform not in (None, "win32"):
                    continue
                name, data = payload(root, entry.get("part"), entry.get("name", ""), entry.get("sha1"))
                if name.casefold() in names:
                    raise ValueError(f"Duplicate package path: {name}")
                names.add(name.casefold())
                add(name, data)
            if "path of building.exe" not in names or "launch.lua" not in names:
                raise ValueError("Manifest is missing the launcher or program entry point")
            add("manifest.xml", local_manifest)
            add("PACKAGE-INFO.txt", info)
            add("Launch.cfg", b"")
        # Recheck the source immediately before exposing the finished archive.
        if check_source is not None:
            check_source()
        # A hard link creates the final path only if it does not already exist.
        os.link(temp, output)
        temp.unlink()
        temp = None
    finally:
        if temp is not None:
            temp.unlink(missing_ok=True)
    return len(names), version.get("number")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New ZIP path; existing files are never replaced")
    parser.add_argument("--local-updates", action="store_true", help="Disable in-app updates from GitHub for this package")
    args = parser.parse_args()
    checkout_branch, commit = git("branch", "--show-current"), git("rev-parse", "HEAD")
    branch = "dev" if args.local_updates and checkout_branch not in {"dev", "main"} else checkout_branch
    def check_source():
        if (git("rev-parse", "HEAD") != commit or git("branch", "--show-current") != checkout_branch
                or subprocess.run(["git", "diff-index", "--quiet", "HEAD", "--"], cwd=ROOT).returncode):
            raise ValueError("The checkout changed or has tracked changes; commit them before packaging")
    check_source()
    count, version = build(ROOT, args.output, branch, commit, check_source, local_updates=args.local_updates)
    print(f"Built {args.output}: {version}, {branch}, {commit}, {count} files")


if __name__ == "__main__":
    main()
