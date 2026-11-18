"""Check listed updater files against the content available in this checkout.

Like the updater, accept either the exact content hash or its LF-to-CRLF form.
For source text, also check the form produced by a Windows CRLF checkout.
This does not check whether every required file is listed or a URL is reachable.
"""
import hashlib
from pathlib import Path, PurePosixPath
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PARTS = {"default": "", "runtime": "runtime", "program": "src", "tree": "src"}
SOURCE_TEXT_SUFFIXES = {".lua", ".js", ".cjs", ".json", ".xml", ".txt", ".md"}


def check(root):
    manifest = ET.parse(root / "manifest.xml").getroot()
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
        source = root / PARTS[part] / name
        try:
            content = source.read_bytes()
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


if __name__ == "__main__":
    count, errors = check(ROOT)
    for error in errors:
        print(error, file=sys.stderr)
    print(f"Checked {count} manifest entries; {len(errors)} errors")
    sys.exit(bool(errors))
