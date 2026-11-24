from contextlib import redirect_stderr, redirect_stdout
from email.message import Message
from io import BytesIO, StringIO
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import MagicMock, Mock, patch
from urllib.error import HTTPError

import collect_public_stash_capture as collector
from build_public_stash_capture import build_capture, encode_response, publish_capture


def page(next_cursor, *stashes):
    return encode_response({"next_change_id": next_cursor, "stashes": list(stashes)})


def stash(number, **extra):
    return {"id": f"{number:064x}", "public": True, "league": "Covens", "items": [], **extra}


class CollectorTest(unittest.TestCase):
    def test_collected_capture_resumes_from_published_cursor(self):
        fetch = Mock(side_effect=[(page("next", stash(1)), 0), (page("next"), 0)])
        pause = Mock()
        body, report = collector.collect("Covens", "start", 8, fetch, pause)
        self.assertEqual([call.args[0] for call in fetch.call_args_list], ["start", "next"])
        pause.assert_called_once_with(1)
        self.assertEqual(report, {"pages": 2, "nextCursor": "next", "stoppedBy": "end_of_stream",
                                  "retryAfterSeconds": 0})
        with TemporaryDirectory() as directory:
            file = Path(directory, "capture.json")
            publish_capture(file, body)
            self.assertEqual(collector.capture_start(file, "Covens"), "next")
            with self.assertRaisesRegex(ValueError, "same league"):
                collector.capture_start(file, "Standard")
            with self.assertRaises(FileExistsError):
                publish_capture(file, b"replacement")
            self.assertEqual(file.read_bytes(), body)
            self.assertEqual(list(Path(directory).iterdir()), [file])

    def test_stops_on_provider_cooldown(self):
        fetch = Mock(return_value=(page("next", stash(1)), 71))
        body, report = collector.collect("Covens", "start", 8, fetch)
        fetch.assert_called_once_with("start")
        self.assertEqual(report["stoppedBy"], "provider_cooldown")
        self.assertEqual(report["retryAfterSeconds"], 71)
        self.assertEqual(json.loads(body)["pages"][0]["response"]["next_change_id"], "next")

    def test_preserves_unread_cursor_at_size_limit(self):
        first, second = page("next", stash(1)), page("later", stash(2))
        fetch = Mock(side_effect=[(first, 0), (second, 0)])
        with patch.object(collector, "CAPTURE_LIMIT", 64 * 1024 + len(first) + 1):
            body, report = collector.collect("Covens", "start", 8, fetch, Mock())
        self.assertEqual(report["stoppedBy"], "size_limit")
        self.assertEqual(report["nextCursor"], "next")
        self.assertEqual(len(json.loads(body)["pages"]), 1)

    def test_rejects_incomplete_stream_evidence(self):
        for response in (page("start", stash(1)), page("next", {"id": "missing"}),
                         page("next", stash(1, items={"bad": True}))):
            with self.subTest(response=response):
                with self.assertRaises(ValueError):
                    collector.collect("Covens", "start", 1, Mock(return_value=(response, 0)))

    def test_request_uses_only_official_endpoint_and_identity(self):
        opener = MagicMock()
        response = opener.open.return_value.__enter__.return_value
        response.status = 200
        response.read.return_value = b'{}'
        response.headers = Message()
        response.headers["X-Rate-Limit-Rules"] = "Account, Client"
        response.headers["X-Rate-Limit-Account"] = "7:8:10,20:60:90"
        response.headers["X-Rate-Limit-Account-State"] = "1:8:0,20:60:0"
        response.headers["X-Rate-Limit-Client-State"] = "1:60:71"
        agent = collector.identification("fixture-app", "ops@example.com")
        body, wait = collector.fetch_page(opener, "one/two", "fixture-token", agent)
        self.assertEqual((body, wait), (b"{}", 71))
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.pathofexile.com/public-stash-tabs?id=one%2Ftwo")
        self.assertEqual(request.get_header("Authorization"), "Bearer fixture-token")
        self.assertEqual(request.get_header("User-agent"), agent)
        self.assertEqual(opener.open.call_args.kwargs["timeout"], 15)
        self.assertIsNone(collector.RejectRedirects().redirect_request(
            request, None, 302, "", response.headers, "https://example.com/redirect"
        ))

    def test_response_size_and_truncation_are_rejected(self):
        opener = MagicMock()
        response = opener.open.return_value.__enter__.return_value
        response.status = 200
        response.headers = {"Content-Length": str(collector.PAGE_LIMIT + 1)}
        with self.assertRaisesRegex(collector.CaptureRequestError, "4 MiB"):
            collector.fetch_page(opener, "cursor", "fixture-token", "fixture")
        response.read.assert_not_called()
        response.headers = {"Content-Length": "10"}
        response.read.return_value = b"{}"
        with self.assertRaisesRegex(collector.CaptureRequestError, "incomplete"):
            collector.fetch_page(opener, "cursor", "fixture-token", "fixture")

    def test_http_status_failure_is_safe_and_cooldown_is_reported(self):
        headers = Message()
        headers["Retry-After"] = "73"
        for status, delay in ((429, 73), (503, 73), (401, None), (403, None), (302, None)):
            with self.subTest(status=status):
                opener = Mock()
                opener.open.side_effect = HTTPError("https://example.com/", status, "fixture-token", headers, BytesIO())
                with self.assertRaises(collector.CaptureRequestError) as failure:
                    collector.fetch_page(opener, "cursor", "fixture-token", "fixture")
                self.assertEqual(failure.exception.retry_after, delay)
                self.assertNotIn("fixture-token", str(failure.exception))

    def test_cli_denial_does_not_publish_or_leak_token(self):
        with TemporaryDirectory() as directory:
            output = Path(directory, "capture.json")
            args = ["collect", "--league", "Covens", "--client-id", "fixture-app", "--contact",
                    "ops@example.com", "--cursor", "start", str(output)]
            stdout, stderr = StringIO(), StringIO()
            with patch("sys.argv", args), patch.dict("os.environ", {collector.TOKEN_VARIABLE: "fixture-token"}):
                with redirect_stdout(stdout), redirect_stderr(stderr), patch.object(
                    collector, "fetch_page", side_effect=collector.CaptureRequestError("GGG HTTP 429", 23)
                ):
                    self.assertEqual(collector.main(), 75)
            self.assertFalse(output.exists())
            self.assertEqual(stdout.getvalue(), "")
            self.assertEqual(json.loads(stderr.getvalue())["retryAfterSeconds"], 23)
            self.assertNotIn("fixture-token", stderr.getvalue())

    def test_manual_bundler_still_reads_recorded_pages(self):
        with TemporaryDirectory() as directory:
            response = Path(directory, "page.json")
            response.write_bytes(page("next", stash(1)))
            body = build_capture("Covens", 1700000000, [("start", response)])
            self.assertEqual(json.loads(body)["pages"][0]["response"]["next_change_id"], "next")


if __name__ == "__main__":
    unittest.main()
