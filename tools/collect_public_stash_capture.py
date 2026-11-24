"""Collect a bounded PC listing capture from GGG on an authorized backend."""
# cspell:ignore lexists newurl urlencode

import argparse
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from http.client import HTTPException
import json
import math
import os
from pathlib import Path
import re
import sys
import time
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener

from build_public_stash_capture import (
    CAPTURE_LIMIT, CURSOR, PAGE_LIMIT, assemble_capture, encode_response, parse_page,
    publish_capture, validate_capture_settings,
)


ENDPOINT = "https://api.pathofexile.com/public-stash-tabs"
TOKEN_VARIABLE = "POB_GGG_PUBLIC_STASH_TOKEN"


class CaptureRequestError(Exception):
    def __init__(self, message, retry_after=None):
        super().__init__(message)
        self.retry_after = retry_after


class RejectRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def identification(client_id, contact):
    if not re.fullmatch(r"[a-zA-Z0-9_.-]{1,100}", client_id):
        raise ValueError("Use the registered GGG client ID")
    if not re.fullmatch(r"[a-zA-Z0-9_.+%-]+@[a-zA-Z0-9.-]+", contact) or len(contact) > 160:
        raise ValueError("Use the registered public contact email")
    return f"OAuth {client_id}/1.0 (contact: {contact}) PoB-AI-Stash-Capture"


def retry_after(value):
    if not value:
        return 0
    if re.fullmatch(r"[0-9]{1,10}", value):
        return int(value)
    try:
        when = parsedate_to_datetime(value)
        if when.tzinfo is not None:
            return max(0, math.ceil((when - datetime.now(timezone.utc)).total_seconds()))
    except (TypeError, ValueError, OverflowError):
        pass
    return 0


def rate_limit_wait(headers):
    wait = retry_after(headers.get("Retry-After"))
    for rule in headers.get("X-Rate-Limit-Rules", "").split(","):
        rule = rule.strip()
        if not re.fullmatch(r"[A-Za-z-]{1,32}", rule):
            continue
        fields = f"X-Rate-Limit-{rule}"
        limits = list(triples(headers.get(fields, "")))
        for hits, window, active in triples(headers.get(f"{fields}-State", "")):
            wait = max(wait, active)
            for maximum, period, _ in limits:
                if window == period and 0 < maximum <= hits:
                    wait = max(wait, period)
    return wait


def triples(value):
    for entry in value.split(","):
        fields = entry.strip().split(":")
        if len(fields) == 3 and all(re.fullmatch(r"[0-9]{1,9}", field) for field in fields):
            yield tuple(map(int, fields))


def fetch_page(opener, cursor, token, agent):
    query = urlencode({"id": cursor})
    request = Request(f"{ENDPOINT}?{query}", headers={
        "Authorization": f"Bearer {token}", "User-Agent": agent,
        "Accept": "application/json", "Accept-Encoding": "identity",
    })
    try:
        with opener.open(request, timeout=15) as response:
            if response.status != 200:
                raise CaptureRequestError(f"Unexpected GGG HTTP status {response.status}")
            header = response.headers.get("Content-Length", "")
            length = int(header) if re.fullmatch(r"[0-9]{1,10}", header) else None
            if length is not None and length > PAGE_LIMIT:
                raise CaptureRequestError("The GGG page exceeds the 4 MiB capture page limit")
            body = response.read(PAGE_LIMIT + 1)
            if len(body) > PAGE_LIMIT:
                raise CaptureRequestError("The GGG page exceeds the 4 MiB capture page limit")
            if length is not None and len(body) != length:
                raise CaptureRequestError("GGG returned an incomplete capture page")
            return body, rate_limit_wait(response.headers)
    except HTTPError as error:
        try:
            if error.code in (429, 503):
                delay = rate_limit_wait(error.headers) or 60
                raise CaptureRequestError(f"GGG returned HTTP {error.code}", delay) from None
            raise CaptureRequestError(f"GGG returned HTTP {error.code}") from None
        finally:
            error.close()
    except (OSError, HTTPException):
        raise CaptureRequestError("Could not read a complete HTTPS response from GGG") from None


def capture_start(path, league):
    with path.open("rb") as source:
        raw = source.read(CAPTURE_LIMIT + 1)
    if len(raw) > CAPTURE_LIMIT:
        raise ValueError("The previous capture exceeds 16 MiB")
    previous = json.loads(raw)
    if (not isinstance(previous, dict) or previous.get("format") != "pob-public-stash-capture-v1"
            or previous.get("realm") != "pc" or previous.get("league") != league):
        raise ValueError("Resume from a PC capture of the same league")
    pages = previous.get("pages")
    if not isinstance(pages, list) or not all(
        isinstance(entry, dict) and "requestCursor" in entry and "response" in entry for entry in pages
    ):
        raise ValueError("The previous capture is missing its pages")
    inputs = ((entry["requestCursor"], encode_response(entry["response"])) for entry in pages)
    assemble_capture(league, previous.get("capturedAt"), inputs, len(pages))
    return pages[-1]["response"]["next_change_id"]


def collect(league, cursor, page_limit, fetch, pause=time.sleep):
    captured_at = int(time.time())
    validate_capture_settings(league, captured_at, page_limit)
    if not CURSOR.fullmatch(cursor):
        raise ValueError("Use a recorded stream cursor")
    inputs, visited = [], set()
    total = 0
    delay = 0
    stop = "page_limit"
    for index in range(1, page_limit + 1):
        body, delay = fetch(cursor)
        page = parse_page(body, index, league)
        next_cursor = page["next_change_id"]
        if next_cursor in visited or next_cursor == cursor and page["stashes"]:
            raise ValueError("GGG returned a repeated stream cursor")
        # Leave room for the capture header and cursor fields. The next invocation
        # starts at the cursor of the page that did not fit.
        if inputs and total + len(body) > CAPTURE_LIMIT - 64 * 1024:
            stop = "size_limit"
            break
        inputs.append((cursor, body))
        visited.add(cursor)
        total += len(body)
        cursor = next_cursor
        if not page["stashes"]:
            stop = "end_of_stream"
            break
        if delay:
            stop = "provider_cooldown"
            break
        if index < page_limit:
            pause(1)
    capture = assemble_capture(league, captured_at, inputs, len(inputs))
    return capture, {"pages": len(inputs), "nextCursor": cursor, "stoppedBy": stop,
                     "retryAfterSeconds": delay}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--league", required=True)
    parser.add_argument("--client-id", required=True)
    parser.add_argument("--contact", required=True)
    parser.add_argument("--max-pages", type=int, default=8)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--cursor", help="A known cursor from the authorized PC stream")
    source.add_argument("--resume-from", type=Path, help="The preceding capture in the same league")
    parser.add_argument("output", type=Path, help="A new capture path on the backend")
    args = parser.parse_args()
    try:
        token = os.environ.get(TOKEN_VARIABLE, "")
        if not re.fullmatch(r"[A-Za-z0-9._~+/=-]{1,4096}", token):
            raise ValueError(f"Set {TOKEN_VARIABLE} from the authorized server secret store")
        if os.path.lexists(args.output):
            raise ValueError("The capture output already exists")
        if not args.output.parent.is_dir():
            raise ValueError("The capture output folder does not exist")
        agent = identification(args.client_id, args.contact)
        cursor = args.cursor if args.cursor is not None else capture_start(args.resume_from, args.league)
        opener = build_opener(RejectRedirects())
        capture, report = collect(args.league, cursor, args.max_pages,
                                  lambda value: fetch_page(opener, value, token, agent))
        publish_capture(args.output, capture)
    except CaptureRequestError as error:
        print(json.dumps({"error": str(error), "retryAfterSeconds": error.retry_after}), file=sys.stderr)
        return 75 if error.retry_after else 1
    except (OSError, ValueError, RecursionError) as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 1
    print(json.dumps(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
