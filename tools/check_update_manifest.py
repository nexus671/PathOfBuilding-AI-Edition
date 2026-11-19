"""Check listed updater files against the content available in this checkout.

Like the updater, accept either the exact content hash or its LF-to-CRLF form.
For source text, also check the form produced by a Windows CRLF checkout.
This does not check whether every required file is listed or a URL is reachable.
"""
import argparse
import hashlib
import subprocess
from pathlib import Path, PurePosixPath
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PARTS = {"default": "", "runtime": "runtime", "program": "src", "tree": "src"}
SOURCE_TEXT_SUFFIXES = {".lua", ".js", ".cjs", ".json", ".xml", ".txt", ".md"}


def check(root, read_bytes=None):
    read_bytes = read_bytes or (lambda path: (root / path).read_bytes())
    manifest = ET.fromstring(read_bytes("manifest.xml"))
    errors, seen = [], set()
    entries = manifest.findall("File")
    if not entries:
        errors.append("The manifest contains no files")
    for entry in entries:
        part, name, expected = (entry.get(key, "") for key in ("part", "name", "sha1"))
        path = PurePosixPath(name)
        key = (part, name, entry.get("platform", ""))
        if key in seen:
            errors.append(f"Duplicate entry: {part}/{name}")
        seen.add(key)
        if (part not in PARTS or not name or path.is_absolute() or ".." in path.parts
                or "\\" in name or not re.fullmatch(r"[0-9a-f]{40}", expected)):
            errors.append(f"Invalid entry: {part}/{name}")
            continue
        source = PurePosixPath(PARTS[part]) / name
        try:
            content = read_bytes(str(source))
        except OSError:
            errors.append(f"Missing or unreadable file: {part}/{name}")
            continue
        digest = hashlib.sha1(content).hexdigest()
        if digest != expected and hashlib.sha1(content.replace(b"\n", b"\r\n")).hexdigest() != expected:
            errors.append(f"Hash mismatch: {part}/{name}")
        elif part in {"program", "tree"} and path.suffix.lower() in SOURCE_TEXT_SUFFIXES and b"\0" not in content:
            windows_content = content.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            if hashlib.sha1(windows_content).hexdigest() != expected:
                errors.append(f"Windows newline mismatch: {part}/{name}")
    return len(entries), errors


class GitIndexReader:
    """Read the staged tree without relying on the possibly different working copy."""
    def __init__(self, root):
        self.process = subprocess.Popen(
            ["git", "cat-file", "--batch"], cwd=root,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        )

    def read(self, path):
        if "\n" in path or "\r" in path:
            raise OSError("Invalid index path")
        self.process.stdin.write((":" + path + "\n").encode("utf-8"))
        self.process.stdin.flush()
        header = self.process.stdout.readline().split()
        if len(header) != 3 or header[1] != b"blob":
            raise OSError("File missing from Git index")
        length = int(header[2])
        content = self.process.stdout.read(length)
        if len(content) != length or self.process.stdout.read(1) != b"\n":
            raise OSError("Incomplete Git index response")
        return content

    def close(self):
        self.process.stdin.close()
        self.process.stdout.close()
        self.process.wait()


def check_index(root):
    reader = GitIndexReader(root)
    try:
        return check(root, reader.read)
    finally:
        reader.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--git-index", action="store_true", help="check staged Git content instead of the working tree")
    args = parser.parse_args()
    count, errors = check_index(ROOT) if args.git_index else check(ROOT)
    for error in errors:
        print(error, file=sys.stderr)
    print(f"Checked {count} manifest entries; {len(errors)} errors")
    sys.exit(bool(errors))
