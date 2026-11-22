#!/usr/bin/env python3
"""Exercise WAL consistency, source boundaries and Firefox-only export semantics."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import stat
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "home/firefox-personal-export.py"
spec = importlib.util.spec_from_file_location("firefox_export", SCRIPT)
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class FirefoxExportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.profile = self.base / exporter.PROFILE_ID
        self.profile.mkdir()
        self.ini = self.base / "profiles.ini"
        self.ini.write_text(f"[Profile0]\nName=default\nPath={exporter.PROFILE_ID}\nIsRelative=1\n")
        scanner_config = self.base / "gitleaks.toml"
        scanner_config.write_text("[extend]\nuseDefault = true\n")
        for name, value in (("PROFILE", self.profile), ("PROFILES_INI", self.ini),
                            ("EXPORT_ROOT", self.base / "export"),
                            ("OWNER_UID", os.geteuid()), ("BACKUP_SECONDS", 0.1),
                            ("GITLEAKS", str((SCRIPT.parents[1] / ".git/gitleaks-bin").resolve())),
                            ("GITLEAKS_CONFIG", str(scanner_config))):
            changing = patch.object(exporter, name, value)
            changing.start()
            self.addCleanup(changing.stop)
        hostname = patch.object(exporter.socket, "gethostname", return_value="nixos")
        hostname.start()
        self.addCleanup(hostname.stop)
        self.db = sqlite3.connect(self.profile / "places.sqlite")
        self.addCleanup(self.db.close)
        self.db.executescript("""
            PRAGMA journal_mode=WAL;
            PRAGMA wal_autocheckpoint=0;
            CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT, title TEXT);
            CREATE TABLE moz_historyvisits(id INTEGER PRIMARY KEY, place_id INTEGER, visit_date INTEGER);
            CREATE TABLE moz_bookmarks(id INTEGER PRIMARY KEY, parent INTEGER, guid TEXT, title TEXT, type INTEGER, fk INTEGER);
            INSERT INTO moz_places VALUES (1, 'https://example.test/a%20b?q=hello', 'An untrusted title');
            INSERT INTO moz_places VALUES (2, 'https://example.test/second', NULL);
            INSERT INTO moz_historyvisits VALUES (1, 1, 1700000000000001), (2, 1, 1700000000000002), (3, 1, 1700000000000001);
            INSERT INTO moz_bookmarks VALUES (1, 0, 'root________', '', 2, NULL),
                (2, 1, 'toolbar_____', 'Toolbar', 2, NULL),
                (3, 2, 'folder______', 'Research', 2, NULL),
                (4, 3, 'bookmark____', 'Saved page', 1, 1);
            CREATE TABLE unrelated_credentials(secret TEXT);
            INSERT INTO unrelated_credentials VALUES ('excluded-fixture-value');
        """)
        self.db.commit()

    def records(self, manifest, dataset="history"):
        path = Path(manifest["export_path"]) / f"{dataset}.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()]

    def test_wal_repeat_visits_exact_timestamps_and_idempotent_reimport(self):
        # This visit exists only in the uncheckpointed live WAL.
        self.db.execute("INSERT INTO moz_historyvisits VALUES (4, 2, 1700000000000003)")
        self.db.commit()
        first = exporter.export_snapshot()
        records = self.records(first)
        self.assertEqual(len(records), 3)
        self.assertEqual(records[0]["url"], "https://example.test/a%20b?q=hello")
        self.assertEqual(records[0]["visit_time_us"], 1700000000000001)
        self.assertTrue(records[0]["visit_time_utc"].endswith(".000001Z"))
        identity = lambda rows: {(r["url"], r["visit_time_us"]) for r in rows}
        baseline = identity(records)
        second = exporter.export_snapshot()
        self.assertEqual(identity(self.records(second)) - baseline, set())
        self.db.execute("INSERT INTO moz_historyvisits VALUES (5, 1, 1700000000000004)")
        self.db.commit()
        third = exporter.export_snapshot()
        self.assertEqual(len(identity(self.records(third)) - baseline), 1)
        self.assertEqual(self.records(third)[-2]["title"], None)

    def test_exclusive_firefox_lock_includes_committed_wal_without_source_writes(self):
        self.db.execute("PRAGMA locking_mode=EXCLUSIVE")
        self.db.execute("INSERT INTO moz_historyvisits VALUES (4, 2, 1700000000000003)")
        self.db.commit()
        self.db.execute("INSERT INTO moz_historyvisits VALUES (5, 2, 1700000000000004)")
        # The uncommitted visit must not appear, even with an exclusive writer.
        paths = [self.profile / ("places.sqlite" + suffix) for suffix in ("", "-wal", "-shm")]
        def source_state():
            return [(p.stat().st_size, p.stat().st_mtime_ns, p.stat().st_ctime_ns,
                     hashlib.sha256(p.read_bytes()).hexdigest()) for p in paths]
        before = source_state()
        manifest = exporter.export_snapshot()
        self.assertEqual([r["visit_time_us"] for r in self.records(manifest)],
                         [1700000000000001, 1700000000000002, 1700000000000003])
        self.assertEqual(manifest["backup_method"], "sqlite-online-backup-stable-wal-copy")
        self.assertEqual(source_state(), before)
        self.assertFalse(list(exporter.EXPORT_ROOT.glob(".sqlite-backup-*")))

    def test_clean_database_without_wal_captures_current_main_file(self):
        self.db.execute("PRAGMA journal_mode=DELETE")
        self.db.execute("INSERT INTO moz_historyvisits VALUES (4, 2, 1700000000000003)")
        self.db.commit()
        self.assertFalse((self.profile / "places.sqlite-wal").exists())
        exporter.prepare_root()
        with exporter.stable_places_copy() as path:
            with exporter.contextlib.closing(exporter.checked_backup(path)) as snapshot:
                self.assertEqual(len(list(exporter.history_records(snapshot))), 3)

    def test_active_rollback_journal_fails_closed(self):
        self.db.execute("PRAGMA journal_mode=DELETE")
        self.db.execute("PRAGMA locking_mode=EXCLUSIVE")
        self.db.execute("INSERT INTO moz_historyvisits VALUES (4, 2, 1700000000000003)")
        self.db.commit()
        self.db.execute("INSERT INTO moz_historyvisits VALUES (5, 2, 1700000000000004)")
        self.assertTrue((self.profile / "places.sqlite-journal").exists())
        with self.assertRaisesRegex(exporter.ExportError, "busy or unavailable"):
            exporter.export_snapshot()
        self.assertFalse((exporter.EXPORT_ROOT / "latest.json").exists())
        self.assertFalse(list(exporter.EXPORT_ROOT.glob(".sqlite-backup-*")))

    def test_changing_wal_retries_with_a_fresh_coherent_capture(self):
        self.db.execute("PRAGMA locking_mode=EXCLUSIVE")
        self.db.execute("INSERT INTO moz_historyvisits VALUES (4, 2, 1700000000000003)")
        self.db.commit()
        original = exporter.copy_places_file
        changes = []

        def change_once(source, destination, deadline):
            original(source, destination, deadline)
            if destination.name == "places.sqlite" and not changes:
                self.db.execute("INSERT INTO moz_historyvisits VALUES (5, 2, 1700000000000004)")
                self.db.commit()
                changes.append(True)

        with patch.object(exporter, "copy_places_file", side_effect=change_once):
            manifest = exporter.export_snapshot()
        self.assertEqual(manifest["history"]["records"], 4)
        self.assertEqual(self.records(manifest)[-1]["visit_time_us"], 1700000000000004)
        self.assertFalse(list(exporter.EXPORT_ROOT.glob(".sqlite-backup-*")))

    def test_continuously_changing_wal_fails_closed_with_bounded_retries(self):
        self.db.execute("PRAGMA locking_mode=EXCLUSIVE")
        self.db.execute("INSERT INTO moz_historyvisits VALUES (4, 2, 1700000000000003)")
        self.db.commit()
        original = exporter.copy_places_file
        changes = []

        def always_change(source, destination, deadline):
            original(source, destination, deadline)
            if destination.name == "places.sqlite":
                self.db.execute("UPDATE moz_historyvisits SET visit_date=visit_date+1 WHERE id=4")
                self.db.commit()
                changes.append(True)

        with patch.object(exporter, "copy_places_file", side_effect=always_change):
            with self.assertRaisesRegex(exporter.ExportError, "busy or unavailable"):
                exporter.export_snapshot()
        self.assertEqual(len(changes), exporter.BACKUP_ATTEMPTS)
        self.assertFalse((exporter.EXPORT_ROOT / "latest.json").exists())
        self.assertFalse(list(exporter.EXPORT_ROOT.glob(".staging-*")))
        self.assertFalse(list(exporter.EXPORT_ROOT.glob(".sqlite-backup-*")))

    def test_replaced_wal_is_rejected_even_with_identical_contents(self):
        exporter.prepare_root()
        original = exporter.copy_places_file
        wal = self.profile / "places.sqlite-wal"

        def replace_wal(source, destination, deadline):
            original(source, destination, deadline)
            if destination.name == "places.sqlite-wal":
                replacement = self.profile / "replacement-wal"
                replacement.write_bytes(wal.read_bytes())
                replacement.replace(wal)

        with patch.object(exporter, "copy_places_file", side_effect=replace_wal):
            with self.assertRaises(TimeoutError):
                with exporter.stable_places_copy():
                    self.fail("A replaced WAL must not be accepted")
        self.assertFalse(list(exporter.EXPORT_ROOT.glob(".sqlite-backup-*")))

    def test_stable_copy_timeout_cleans_up_without_publishing(self):
        exporter.prepare_root()
        with patch.object(exporter, "BACKUP_SECONDS", 0):
            with self.assertRaises(TimeoutError):
                with exporter.stable_places_copy():
                    self.fail("An expired capture must not be accepted")
        self.assertFalse(list(exporter.EXPORT_ROOT.glob(".sqlite-backup-*")))

    def test_wal_symlink_rejected_by_fallback(self):
        exporter.prepare_root()
        wal = self.profile / "places.sqlite-wal"
        moved = self.profile / "moved-wal"
        wal.replace(moved)
        wal.symlink_to(moved)
        with self.assertRaises(exporter.ExportError):
            with exporter.stable_places_copy():
                self.fail("A WAL symlink must not be followed")
        self.assertFalse((exporter.EXPORT_ROOT / "latest.json").exists())
        self.assertFalse(list(exporter.EXPORT_ROOT.glob(".sqlite-backup-*")))

    def test_bookmark_ancestry_current_state_and_removed_bookmark(self):
        first = exporter.export_snapshot()
        bookmarks = self.records(first, "bookmarks")
        self.assertEqual([f["title"] for f in bookmarks[0]["folders"]], ["", "Toolbar", "Research"])
        self.assertEqual(bookmarks[0]["guid"], "bookmark____")
        self.db.execute("DELETE FROM moz_bookmarks WHERE type=1")
        self.db.commit()
        second = exporter.export_snapshot()
        self.assertEqual(self.records(second, "bookmarks"), [])
        self.assertEqual(len(self.records(first, "bookmarks")), 1)

    def test_no_profile_databases_credentials_or_extra_columns_exported(self):
        forbidden = ["file:///home/taylor/private", "about:config", "https://u:pass@example.test/",
                     "https://example.test/?access_token=excluded", "https://example.test/#id_token=excluded"]
        for number, url in enumerate(forbidden, 10):
            self.db.execute("INSERT INTO moz_places VALUES (?, ?, 'Excluded')", (number, url))
            self.db.execute("INSERT INTO moz_historyvisits VALUES (?, ?, ?)",
                            (number, number, 1700000000000000 + number))
        self.db.commit()
        manifest = exporter.export_snapshot()
        directory = Path(manifest["export_path"])
        self.assertEqual({p.name for p in directory.iterdir()}, {"history.jsonl", "bookmarks.jsonl", "manifest.json"})
        self.assertEqual(manifest["history"]["excluded_url_or_size"], len(forbidden))
        self.assertNotIn("excluded-fixture-value", "".join(p.read_text() for p in directory.iterdir()))
        self.assertEqual(set(self.records(manifest)[0]),
                         {"source_id", "url", "title", "visit_time_us", "visit_time_utc"})

    def test_modes_hashes_and_manifest_provenance(self):
        manifest = exporter.export_snapshot()
        for directory in [exporter.EXPORT_ROOT, Path(manifest["export_path"])]:
            self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
        for path in Path(manifest["export_path"]).iterdir():
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        for dataset in ("history", "bookmarks"):
            raw = (Path(manifest["export_path"]) / manifest[dataset]["file"]).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), manifest[dataset]["sha256"])
        self.assertEqual(manifest["source"]["origin_device"], "unknown")
        self.assertEqual(exporter.current_manifest(), manifest)

    def test_credential_findings_remove_whole_records_and_rescan_before_publish(self):
        original = exporter.credential_findings
        scans = []

        def flagged_once(directory):
            scans.append(directory)
            if len(scans) == 1:
                return [{"File": str(directory / "history.jsonl"), "StartLine": 2, "EndLine": 2}]
            return original(directory)

        with patch.object(exporter, "credential_findings", side_effect=flagged_once):
            manifest = exporter.export_snapshot()
        self.assertEqual(len(scans), 2)
        self.assertEqual(manifest["history"]["records"], 1)
        self.assertEqual(manifest["history"]["excluded_credential_scan"], 1)
        self.assertIn("final scan passed", manifest["credential_scan"])

    def test_credential_scanner_failure_prevents_publication(self):
        with patch.object(exporter, "GITLEAKS", "/nonexistent-scanner"):
            with self.assertRaisesRegex(exporter.ExportError, "Credential check unavailable"):
                exporter.export_snapshot()
        self.assertFalse((exporter.EXPORT_ROOT / "latest.json").exists())

    def test_unscanned_snapshot_cannot_be_read(self):
        manifest = exporter.export_snapshot()
        path = Path(manifest["export_path"]) / "manifest.json"
        manifest.pop("credential_scan")
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(exporter.ExportError, "credential-check approval"):
            exporter.current_manifest()

    def test_work_host_symlinks_and_changed_profile_rejected(self):
        with patch.object(exporter.socket, "gethostname", return_value="work"):
            with self.assertRaises(exporter.ExportError):
                exporter.export_snapshot()
        alias = self.base / "alias"
        alias.symlink_to(self.profile, target_is_directory=True)
        with patch.object(exporter, "PROFILE", alias):
            with self.assertRaises(exporter.ExportError):
                exporter.export_snapshot()
        self.ini.write_text("[Profile0]\nName=work\nPath=other-profile\nIsRelative=1\n")
        with self.assertRaises(exporter.ExportError):
            exporter.export_snapshot()

    def test_mcp_only_accepts_allowlisted_data_and_pinned_generations(self):
        manifest = exporter.export_snapshot()
        arguments = {"snapshot": manifest["snapshot"], "dataset": "history", "limit": 1}
        first = exporter.call_tool("read_records", arguments)
        self.assertEqual(len(first["records"]), 1)
        self.assertEqual(first["next_offset"], 1)
        second = exporter.call_tool("read_records", dict(arguments, offset=1))
        self.assertIsNone(second["next_offset"])
        for bad in [dict(arguments, path="/home/taylor/.ssh/id_ed25519"),
                    dict(arguments, dataset="../../cookies.sqlite"),
                    dict(arguments, snapshot="../../private"),
                    dict(arguments, offset=-1), dict(arguments, limit=101)]:
            with self.assertRaises(exporter.ExportError):
                exporter.call_tool("read_records", bad)
        for name in ("refresh", "manifest"):
            with self.assertRaises(exporter.ExportError):
                exporter.call_tool(name, {"source": "/home/taylor/.config/other"})
        path = Path(manifest["export_path"]) / "history.jsonl"
        path.unlink()
        path.symlink_to(self.ini)
        with self.assertRaises(exporter.ExportError):
            exporter.call_tool("read_records", arguments)

    def test_oversized_rows_omitted_without_stalling_pagination(self):
        self.db.execute("UPDATE moz_places SET title=? WHERE id=1", ("x" * exporter.MAX_RECORD_BYTES,))
        self.db.commit()
        manifest = exporter.export_snapshot()
        self.assertEqual(manifest["history"]["records"], 0)
        result = exporter.read_records({"snapshot": manifest["snapshot"], "dataset": "history"})
        self.assertEqual(result["records"], [])
        self.assertIsNone(result["next_offset"])


if __name__ == "__main__":
    unittest.main()
