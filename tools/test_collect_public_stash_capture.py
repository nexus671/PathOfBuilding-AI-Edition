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
        response.headers = {"Content-Length": "10", "Retry-After": "89"}
        response.read.return_value = b"{}"
        with self.assertRaisesRegex(collector.CaptureRequestError, "incomplete") as failure:
            collector.fetch_page(opener, "cursor", "fixture-token", "fixture")
        self.assertEqual(failure.exception.retry_after, 89)

    def test_http_status_failure_is_safe_and_cooldown_is_reported(self):
        for status, header, delay in ((429, "73", 73), (503, "73", 73), (429, None, 60),
                                      (403, "76", 76), (401, None, None), (302, None, None)):
            with self.subTest(status=status, header=header):
                headers = {"Retry-After": header} if header else {}
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


class RollingCaptureTest(unittest.TestCase):
    now = 1795545600

    def setUp(self):
        directory = self.enterContext(TemporaryDirectory())
        self.output = Path(directory, "pinned.json")
        self.clock = self.enterContext(patch.object(collector.time, "time", return_value=self.now))
        initial, _ = collector.collect("Covens", "a", 2, Mock(side_effect=[
            (page("b", stash(1)), 0), (page("b"), 0),
        ]), Mock())
        publish_capture(self.output, initial)
        self.initial = initial

    def refresh(self, *responses):
        return collector.refresh_capture(self.output, "Covens", len(responses), Mock(side_effect=responses), Mock())

    def test_retains_listing_changes_and_original_timestamp(self):
        self.clock.return_value += 900
        withdrawn = {"id": stash(1)["id"], "public": False}
        report = self.refresh((page("c", withdrawn, stash(2)), 0), (page("c"), 0))
        self.assertEqual(report, {"pages": 2, "nextCursor": "c", "stoppedBy": "end_of_stream",
                                  "retryAfterSeconds": 0, "published": True, "capturePages": 3})
        updated = collector.read_capture(self.output, "Covens")
        self.assertEqual(updated["capturedAt"], self.now)
        self.assertEqual([entry["requestCursor"] for entry in updated["pages"]], ["a", "b", "c"])
        self.assertEqual([entry["collectedAt"] for entry in updated["pages"]], [self.now, self.now + 900, self.now + 900])
        self.assertEqual(updated["pages"][1]["response"]["stashes"], [withdrawn, stash(2)])
        self.assertEqual(collector.capture_start(self.output, "Covens"), "c")
        raw = self.output.read_bytes()
        self.clock.return_value += 100
        report = self.refresh((page("c"), 30))
        self.assertFalse(report["published"])
        self.assertEqual(report["retryAfterSeconds"], 30)
        self.assertEqual(self.output.read_bytes(), raw)

    def test_expires_old_pages_and_moves_capture_timestamp(self):
        self.clock.return_value += collector.WINDOW_SECONDS + 1
        self.refresh((page("c", stash(2)), 0))
        updated = collector.read_capture(self.output, "Covens")
        self.assertEqual(updated["capturedAt"], self.clock.return_value)
        self.assertEqual([entry["requestCursor"] for entry in updated["pages"]], ["b"])

    def test_advancing_empty_page_resumes_at_new_cursor(self):
        first = self.refresh((page("c"), 0))
        self.assertTrue(first["published"])
        self.assertEqual(collector.capture_start(self.output, "Covens"), "c")
        fetch = Mock(return_value=(page("d", stash(2)), 0))
        collector.refresh_capture(self.output, "Covens", 1, fetch, Mock())
        fetch.assert_called_once_with("c")
        updated = collector.read_capture(self.output, "Covens")
        self.assertEqual([entry["requestCursor"] for entry in updated["pages"]], ["c"])

    def test_retains_a_consecutive_suffix_at_both_size_limits(self):
        for number in range(35):
            self.refresh((page(f"cursor{number}", stash(2)), 0))
        updated = collector.read_capture(self.output, "Covens")
        self.assertEqual(len(updated["pages"]), 32)
        self.assertEqual(updated["pages"][0]["requestCursor"], "cursor2")

        limit = 70 * 1024
        with patch.object(collector, "CAPTURE_LIMIT", limit):
            self.refresh((page("large1", stash(3, note="x" * 36_000)), 0))
            self.refresh((page("large2", stash(4, note="x" * 36_000)), 0))
            updated = collector.read_capture(self.output, "Covens")
            self.assertEqual([entry["requestCursor"] for entry in updated["pages"]], ["large1"])
            self.assertLess(self.output.stat().st_size, limit)

    def test_cycle_cooldown_and_failed_replacement_keep_last_good_file(self):
        for failure in (
            (ValueError, lambda: self.refresh((page("a", stash(2)), 0))),
            (collector.CaptureRequestError, lambda: self.refresh(
                (page("c", stash(2)), 0), collector.CaptureRequestError("GGG HTTP 429", 41)
            )),
        ):
            with self.assertRaises(failure[0]):
                failure[1]()
            self.assertEqual(self.output.read_bytes(), self.initial)
        with patch("build_public_stash_capture.os.replace", side_effect=PermissionError("fixture")):
            with self.assertRaises(PermissionError):
                self.refresh((page("c", stash(2)), 0))
        self.assertEqual(self.output.read_bytes(), self.initial)
        self.assertFalse(list(self.output.parent.glob(".pob-stash-*")))

    def test_refuses_concurrent_refresh_before_network_and_releases_lock(self):
        fetch = Mock(return_value=(page("c", stash(2)), 0))
        with collector.refresh_lock(self.output):
            with self.assertRaisesRegex(ValueError, "lock"):
                collector.refresh_capture(self.output, "Covens", 1, fetch, Mock())
        fetch.assert_not_called()
        self.assertEqual(self.output.read_bytes(), self.initial)
        self.assertTrue(collector.refresh_capture(self.output, "Covens", 1, fetch, Mock())["published"])

    def test_cli_refresh_uses_same_file_and_prints_publish_status(self):
        args = ["collect", "--league", "Covens", "--client-id", "fixture-app", "--contact",
                "ops@example.com", "--max-pages", "1", "--refresh", str(self.output)]
        stdout = StringIO()
        with patch("sys.argv", args), patch.dict("os.environ", {collector.TOKEN_VARIABLE: "fixture-token"}):
            with redirect_stdout(stdout), patch.object(collector, "fetch_page",
                                                       return_value=(page("c", stash(2)), 0)):
                self.assertEqual(collector.main(), 0)
        self.assertTrue(json.loads(stdout.getvalue())["published"])
        self.assertEqual(collector.capture_start(self.output, "Covens"), "c")


class CollectorCooldownTest(unittest.TestCase):
    def setUp(self):
        self.directory = Path(self.enterContext(TemporaryDirectory()))
        self.clock = self.enterContext(patch.object(collector.time, "time", return_value=1795545600))
        self.enterContext(patch.dict("os.environ", {collector.TOKEN_VARIABLE: "fixture-token"}))

    def invoke(self, output, fetch, *options, client="fixture-app"):
        args = ["collect", "--league", "Covens", "--client-id", client, "--contact", "ops@example.com",
                "--max-pages", "1", *options, str(output)]
        stdout, stderr = StringIO(), StringIO()
        with patch("sys.argv", args), patch.object(collector, "fetch_page", fetch):
            with redirect_stdout(stdout), redirect_stderr(stderr):
                code = collector.main()
        return code, json.loads(stdout.getvalue() or stderr.getvalue())

    def test_reuses_retry_deadline_across_capture_paths_then_resumes(self):
        pinned = self.directory / "pinned.json"
        original, _ = collector.collect("Covens", "a", 1, Mock(return_value=(page("b", stash(1)), 0)))
        publish_capture(pinned, original)
        fetch = Mock(side_effect=collector.CaptureRequestError("GGG returned HTTP 429", 300))
        self.assertEqual(self.invoke(pinned, fetch, "--refresh")[0], 75)
        fetch.assert_called_once()
        self.assertEqual(pinned.read_bytes(), original)
        self.clock.return_value += 20
        fetch = Mock(return_value=(page("c", stash(2)), 0))
        next_file = self.directory / "next.json"
        code, report = self.invoke(next_file, fetch, "--resume-from", str(pinned))
        self.assertEqual((code, report["retryAfterSeconds"]), (75, 280))
        fetch.assert_not_called()
        self.assertFalse(next_file.exists())
        self.clock.return_value += 280
        code, report = self.invoke(next_file, fetch, "--resume-from", str(pinned))
        self.assertEqual((code, report["nextCursor"]), (0, "c"))
        self.assertEqual(fetch.call_args.args[1], "b")
        state = next(self.directory.glob("*.cooldown.json"))
        self.assertNotIn("fixture-token", state.read_text())
        self.assertEqual(json.loads(state.read_bytes())["notBefore"], 0)

    def test_successful_reply_persists_cooldown_before_page_validation(self):
        output = self.directory / "capture.json"
        code, report = self.invoke(output, Mock(return_value=(b"invalid JSON", 90)), "--cursor", "start")
        self.assertEqual(code, 1)
        self.assertFalse(output.exists())
        request = Mock()
        code, report = self.invoke(output, request, "--cursor", "start")
        self.assertEqual((code, report["retryAfterSeconds"]), (75, 90))
        request.assert_not_called()

    def test_successful_idle_refresh_preserves_capture_and_persists_wait(self):
        output = self.directory / "pinned.json"
        before, _ = collector.collect("Covens", "a", 1, Mock(return_value=(page("b", stash(1)), 0)))
        publish_capture(output, before)
        code, report = self.invoke(output, Mock(return_value=(page("b"), 75)), "--refresh")
        self.assertEqual((code, report["published"], report["retryAfterSeconds"]), (0, False, 75))
        request = Mock()
        self.assertEqual(self.invoke(output, request, "--refresh")[0], 75)
        request.assert_not_called()
        self.assertEqual(output.read_bytes(), before)

    def test_explicit_file_shares_across_directories_and_binds_client(self):
        a, b = self.directory / "a", self.directory / "b"
        a.mkdir()
        b.mkdir()
        state = self.directory / "rates.json"
        options = ("--cursor", "start", "--cooldown-file", str(state))
        self.assertEqual(self.invoke(a / "a.json", Mock(return_value=(page("next"), 45)), *options)[0], 0)
        request = Mock()
        self.assertEqual(self.invoke(b / "b.json", request, *options)[0], 75)
        self.assertEqual(self.invoke(b / "b.json", request, *options, client="other-app")[0], 1)
        request.assert_not_called()

    def test_bad_state_storage_and_lock_contention_stop_before_fetch(self):
        output = self.directory / "capture.json"
        state = self.directory / "rates.json"
        options = ("--cursor", "start", "--cooldown-file", str(state))
        request = Mock()
        with collector.refresh_lock(state):
            self.assertEqual(self.invoke(output, request, *options)[0], 1)
        state.write_text("bad state")
        self.assertEqual(self.invoke(output, request, *options)[0], 1)
        self.assertEqual(self.invoke(output, request, "--cursor", "start", "--cooldown-file", str(output))[0], 1)
        with patch("collect_public_stash_capture.publish_capture", side_effect=PermissionError("fixture")):
            self.assertEqual(self.invoke(output, request, "--cursor", "start")[0], 1)
        request.assert_not_called()
        self.assertFalse(output.exists())

    def test_interruption_leaves_a_short_hold(self):
        state = self.directory / "rates.json"
        request = Mock(side_effect=KeyboardInterrupt)
        with self.assertRaises(KeyboardInterrupt):
            collector.fetch_with_cooldown(state, "fixture", request, "cursor")
        hold = collector.read_cooldown(state, "fixture")
        self.assertEqual(hold - self.clock.return_value, 60)
        with self.assertRaisesRegex(collector.CaptureRequestError, "still active"):
            collector.fetch_with_cooldown(state, "fixture", request, "cursor")
        request.assert_called_once()

    def test_records_header_before_interrupted_body_read(self):
        state = self.directory / "rates.json"
        opener = MagicMock()
        response = opener.open.return_value.__enter__.return_value
        response.status = 200
        response.headers = {"Retry-After": "300"}
        response.read.side_effect = KeyboardInterrupt

        def request(cursor, remember):
            return collector.fetch_page(opener, cursor, "fixture-token", "fixture", on_cooldown=remember)

        with self.assertRaises(KeyboardInterrupt):
            collector.fetch_with_cooldown(state, "fixture", request, "cursor")
        self.assertEqual(collector.read_cooldown(state, "fixture") - self.clock.return_value, 300)


if __name__ == "__main__":
    unittest.main()
