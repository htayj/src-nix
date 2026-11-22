#!/usr/bin/env python3
"""Offline checks: protocol, partial saves and credential boundaries."""
import importlib.util
import io
import json
import sys
from pathlib import Path
import unittest
from unittest.mock import patch
import urllib.error

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location(
    "karakeep", Path(__file__).resolve().parents[1] / "home/nyxt-karakeep.py")
k = importlib.util.module_from_spec(spec)
spec.loader.exec_module(k)

BOOKMARK = {"id": "test-id", "title": "Article", "content": {
    "type": "link", "url": "https://example.org/article"}, "tags": []}
LISTS = [
    {"id": "parent", "name": "Projects", "type": "manual", "userRole": "owner"},
    {"id": "stars", "name": "GitHub Stars", "parentId": "parent", "type": "manual", "userRole": "editor"},
    {"id": "smart", "name": "Automatic", "type": "smart", "userRole": "owner"},
    {"id": "readonly", "name": "Shared", "type": "manual", "userRole": "viewer"},
]


class FakeClient:
    def __init__(self, fail_tags=False, fail_list=False):
        self.calls = []
        self.methods = []
        self.fail_tags = fail_tags
        self.fail_list = fail_list

    def request(self, path, data=None, *, method=None):
        self.calls.append((path, data))
        self.methods.append(method)
        if path == "/lists":
            return {"lists": LISTS}
        if method == "PUT":
            if self.fail_list:
                raise k.IntegrationError("Unavailable")
            return None
        if path.endswith("/tags"):
            if self.fail_tags:
                raise k.IntegrationError("Unavailable")
            return {"attached": []}
        if data is None:
            return {"bookmarks": [BOOKMARK], "nextCursor": "next-page"}
        return BOOKMARK


class Tests(unittest.TestCase):
    def test_picker_only_offers_writable_manual_lists_with_parent_names(self):
        result = k.execute({"action": "lists"}, FakeClient())
        self.assertEqual([item["id"] for item in result["lists"]], ["parent", "stars"])
        self.assertEqual(result["lists"][1]["path"], "Projects / GitHub Stars")

    def test_save_to_list_uses_idempotent_put(self):
        client = FakeClient()
        result = k.execute({"action": "save", "url": "https://example.org", "listId": "stars"}, client)
        self.assertEqual(client.calls[-1], ("/lists/stars/bookmarks/test-id", None))
        self.assertEqual(client.methods[-1], "PUT")
        self.assertEqual(result["list"], "Projects / GitHub Stars")

    def test_invalid_list_is_rejected_before_saving(self):
        for identifier in ["deleted", "smart", "readonly"]:
            client = FakeClient()
            with self.assertRaises(k.IntegrationError):
                k.execute({"action": "save", "url": "https://example.org", "listId": identifier}, client)
            self.assertEqual(client.calls, [("/lists", None)])

    def test_partial_failures_do_not_hide_success_or_skip_other_operations(self):
        client = FakeClient(fail_tags=True)
        result = k.execute({"action": "save", "url": "https://example.org", "listId": "stars", "tags": ["tag"]}, client)
        self.assertIn("tags failed", result["warning"])
        self.assertEqual(result["list"], "Projects / GitHub Stars")
        result = k.execute({"action": "save", "url": "https://example.org", "listId": "stars", "tags": ["tag"]},
                           FakeClient(fail_tags=True, fail_list=True))
        self.assertIn("tags failed", result["warning"])
        self.assertIn("list failed", result["warning"])
        self.assertNotIn("list", result)

    def test_put_accepts_no_content_response(self):
        client = k.Client("fixture-credential")
        with patch.object(client.opener, "open") as request:
            response = io.StringIO("")
            response.status = 204
            request.return_value.__enter__.return_value = response
            self.assertIsNone(client.request("/lists/stars/bookmarks/test-id", method="PUT"))
            self.assertEqual(request.call_args.args[0].method, "PUT")

    def test_save_then_attach_tags_without_replacing_existing_tags(self):
        client = FakeClient()
        result = k.execute({"action": "save", "url": "https://example.org/article",
                            "title": "Article", "tags": [" Lisp ", "Lisp", "reading", ""]}, client)
        self.assertEqual(result["reader"], k.ORIGIN + "/reader/test-id")
        self.assertEqual(client.calls[1], ("/bookmarks/test-id/tags", {
            "tags": [{"tagName": "Lisp"}, {"tagName": "reading"}]}))

    def test_partial_save_is_reported_truthfully(self):
        result = k.execute({"action": "save", "url": "https://example.org",
                            "tags": ["reading"]}, FakeClient(fail_tags=True))
        self.assertIn("Bookmark saved, but tags failed", result["warning"])

    def test_search_escapes_query_and_reports_more_results(self):
        client = FakeClient()
        result = k.execute({"action": "search", "query": "lisp & nyxt"}, client)
        self.assertIn("q=lisp+%26+nyxt", client.calls[0][0])
        self.assertTrue(result["more"])

    def test_unsafe_urls_rejected_before_vault_access(self):
        for url in ["javascript:alert(1)", "file:///etc/passwd", "https://user:pass@example.org", ""]:
            with self.subTest(url=url), patch.object(k, "api_token") as vault:
                output = io.StringIO()
                with patch("sys.stdin", io.StringIO(json.dumps({"action": "save", "url": url}))), patch("sys.stdout", output):
                    self.assertEqual(k.main(), 1)
                vault.assert_not_called()

    def test_remote_url_cannot_execute_code(self):
        bookmark = dict(BOOKMARK, content={"url": "javascript:alert(1)"})
        self.assertEqual(k.bookmark_result(bookmark)["url"], "")

    def test_authentication_is_header_only_and_origin_is_fixed(self):
        client = k.Client("fixture-credential")
        with patch.object(client.opener, "open") as request:
            response = io.StringIO("{}")
            response.status = 200
            request.return_value.__enter__.return_value = response
            client.request("/bookmarks")
            req = request.call_args.args[0]
            self.assertEqual(req.full_url, k.ORIGIN + "/api/v1/bookmarks")
            self.assertEqual(req.get_header("Authorization"), "Bearer fixture-credential")
            self.assertIsNone(req.data)

    def test_redirects_refused(self):
        with self.assertRaises(k.IntegrationError):
            k.NoRedirect().redirect_request(None, None, 302, "", {}, "https://other.invalid")

    def test_http_error_body_is_never_reported(self):
        client = k.Client("fixture-credential")
        error = urllib.error.HTTPError(k.ORIGIN, 500, "fixture-sensitive-body", {}, None)
        with patch.object(client.opener, "open", side_effect=error):
            with self.assertRaises(k.IntegrationError) as caught:
                client.request("/bookmarks")
        self.assertNotIn("fixture-sensitive-body", str(caught.exception))
        self.assertNotIn("fixture-credential", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
