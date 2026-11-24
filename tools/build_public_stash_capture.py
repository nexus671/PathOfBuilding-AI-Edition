"""Bundle locally recorded GGG Public Stashes responses for PoB."""

import argparse
from pathlib import Path
import json
import re
import time


PAGE_LIMIT = 4 * 1024 * 1024
CAPTURE_LIMIT = 16 * 1024 * 1024
CURSOR = re.compile(r"[^\s\x00-\x1f\x7f]{1,512}")


def build_capture(league, captured_at, inputs):
    if not re.fullmatch(r"(?=.*[a-zA-Z0-9])[a-zA-Z0-9 _-]{1,80}", league):
        raise ValueError("Enter the exact trade league ID")
    if not 1577836800 <= captured_at <= time.time():
        raise ValueError("Enter the recorded UTC capture time as Unix seconds")
    if not 1 <= len(inputs) <= 32:
        raise ValueError("Provide 1 to 32 ordered stash pages")
    pages, visited, expected = [], set(), None
    total = 0
    for index, (request, path) in enumerate(inputs, 1):
        if not CURSOR.fullmatch(request) or request in visited or expected and request != expected:
            raise ValueError(f"Page {index} has a missing or unexpected request cursor")
        visited.add(request)
        with Path(path).open("rb") as source:
            body = source.read(PAGE_LIMIT + 1)
        total += len(body)
        if len(body) > PAGE_LIMIT or total > CAPTURE_LIMIT:
            raise ValueError("Each input page may be at most 4 MiB and the bundle at most 16 MiB")
        response = json.loads(body)
        next_cursor = response.get("next_change_id") if isinstance(response, dict) else None
        if not isinstance(next_cursor, str) or not CURSOR.fullmatch(next_cursor):
            raise ValueError(f"Page {index} has an invalid next cursor")
        stashes = response.get("stashes")
        if not isinstance(stashes, list) or not all(isinstance(stash, dict) for stash in stashes):
            raise ValueError(f"Page {index} does not contain a stash array")
        terminal = not stashes and index == len(inputs)
        if not stashes and not terminal or next_cursor in visited and not (terminal and next_cursor == request):
            raise ValueError(f"Page {index} stops the stream or repeats a cursor")
        pages.append({"requestCursor": request, "response": response})
        expected = next_cursor
    capture = {"format": "pob-public-stash-capture-v1", "realm": "pc", "league": league,
               "capturedAt": captured_at, "pages": pages}
    output = json.dumps(capture, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    if len(output) > CAPTURE_LIMIT:
        raise ValueError("The output capture exceeds 16 MiB")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--league", required=True)
    parser.add_argument("--captured-at", type=int, required=True, help="Recorded capture time as UTC Unix seconds")
    parser.add_argument("--page", nargs=2, action="append", metavar=("REQUEST_CURSOR", "FILE"), required=True)
    parser.add_argument("output", type=Path, help="A new JSON file")
    args = parser.parse_args()
    try:
        body = build_capture(args.league, args.captured_at, args.page)
        with args.output.open("xb") as output:
            output.write(body)
    except (OSError, RecursionError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    print(f"Wrote {len(args.page)} stash pages for {args.league} to {args.output}")


if __name__ == "__main__":
    main()
