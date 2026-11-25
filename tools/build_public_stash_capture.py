"""Bundle locally recorded GGG Public Stashes responses for PoB."""

import argparse
from pathlib import Path
import json
import os
import re
import tempfile
import time


PAGE_LIMIT = 4 * 1024 * 1024
CAPTURE_LIMIT = 16 * 1024 * 1024
CURSOR = re.compile(r"[^\s\x00-\x1f\x7f]{1,512}")


def parse_page(body, index, league):
    if len(body) > PAGE_LIMIT:
        raise ValueError(f"Page {index} exceeds 4 MiB")
    response = json.loads(body)
    next_cursor = response.get("next_change_id") if isinstance(response, dict) else None
    if not isinstance(next_cursor, str) or not CURSOR.fullmatch(next_cursor):
        raise ValueError(f"Page {index} has an invalid next cursor")
    stashes = response.get("stashes")
    if not isinstance(stashes, list) or not all(isinstance(stash, dict) for stash in stashes):
        raise ValueError(f"Page {index} does not contain a stash array")
    for stash in stashes:
        stash_id = stash.get("id")
        if not isinstance(stash_id, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", stash_id) or type(stash.get("public")) is not bool:
            raise ValueError(f"Page {index} contains an invalid stash change")
        if stash["public"] and stash.get("league") == league:
            items = stash.get("items")
            if not isinstance(items, list) or not all(isinstance(item, dict) for item in items):
                raise ValueError(f"Page {index} contains a public stash without an item array")
    return response


def encode_response(response):
    return json.dumps(response, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")


def validate_capture_settings(league, captured_at, count):
    if not re.fullmatch(r"(?=.*[a-zA-Z0-9])[a-zA-Z0-9 _-]{1,80}", league):
        raise ValueError("Enter the exact trade league ID")
    if type(captured_at) is not int or not 1577836800 <= captured_at <= time.time():
        raise ValueError("Enter the recorded UTC capture time as Unix seconds")
    if not 1 <= count <= 32:
        raise ValueError("Provide 1 to 32 ordered stash pages")


def assemble_capture(league, captured_at, inputs, count):
    validate_capture_settings(league, captured_at, count)
    pages, visited, expected = [], set(), None
    total = 0
    for index, (request, body) in enumerate(inputs, 1):
        if not isinstance(request, str) or not CURSOR.fullmatch(request) or request in visited or expected and request != expected:
            raise ValueError(f"Page {index} has a missing or unexpected request cursor")
        visited.add(request)
        total += len(body)
        if total > CAPTURE_LIMIT:
            raise ValueError("The bundle may be at most 16 MiB")
        response = parse_page(body, index, league)
        next_cursor = response["next_change_id"]
        stashes = response["stashes"]
        terminal = not stashes and index == count
        if not stashes and not terminal or next_cursor in visited and not (terminal and next_cursor == request):
            raise ValueError(f"Page {index} stops the stream or repeats a cursor")
        pages.append({"requestCursor": request, "response": response})
        expected = next_cursor
    capture = {"format": "pob-public-stash-capture-v1", "realm": "pc", "league": league,
               "capturedAt": captured_at, "pages": pages}
    output = encode_response(capture)
    if len(output) > CAPTURE_LIMIT:
        raise ValueError("The output capture exceeds 16 MiB")
    return output


def build_capture(league, captured_at, inputs):
    def read_pages():
        for request, path in inputs:
            with Path(path).open("rb") as source:
                yield request, source.read(PAGE_LIMIT + 1)

    return assemble_capture(league, captured_at, read_pages(), len(inputs))


def publish_capture(path, body, *, replace=False):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".pob-stash-", delete=False) as output:
            temporary = Path(output.name)
            output.write(body)
            output.flush()
            os.fsync(output.fileno())
        if replace:
            os.replace(temporary, path)
        else:
            os.link(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--league", required=True)
    parser.add_argument("--captured-at", type=int, required=True, help="Recorded capture time as UTC Unix seconds")
    parser.add_argument("--page", nargs=2, action="append", metavar=("REQUEST_CURSOR", "FILE"), required=True)
    parser.add_argument("output", type=Path, help="A new JSON file")
    args = parser.parse_args()
    try:
        body = build_capture(args.league, args.captured_at, args.page)
        publish_capture(args.output, body)
    except (OSError, RecursionError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    print(f"Wrote {len(args.page)} stash pages for {args.league} to {args.output}")


if __name__ == "__main__":
    main()
