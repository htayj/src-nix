#!/usr/bin/env python3
"""Identity regression checks and an opt-in, harmless systemd integration test."""

import asyncio
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from dbus_next import BusType, Message, MessageType, Variant
from dbus_next.aio import MessageBus


spec = importlib.util.spec_from_file_location(
    "webkit_cgroups", Path(__file__).with_name("webkit-renderer-cgroups.py"))
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.proc = Path(self.temp.name)

    def process(self, pid=123, uid=1000, name="WebKitWebProcess", cgroup="/session.scope"):
        proc = self.proc / str(pid)
        proc.mkdir()
        (proc / "exe").symlink_to(
            f"/nix/store/hash-webkitgtk-2.54/libexec/webkit2gtk-4.1/{name}")
        (proc / "status").write_text(f"Name:\t{name}\nUid:\t{uid}\t{uid}\t{uid}\t{uid}\n")
        (proc / "cmdline").write_bytes(name.encode() + b"\0")
        fields = ["S"] + ["0"] * 18 + ["456"]
        (proc / "stat").write_text(f"{pid} (comm (with) spaces) {' '.join(fields)}")
        (proc / "cgroup").write_text(f"0::{cgroup}\n")
        return proc

    def test_renderer_identity_and_stat_parsing(self):
        self.process()
        self.assertEqual(list(module.discover_renderers(1000, self.proc)),
                         [module.Renderer(123, 456, "/session.scope")])

    def test_other_owner_is_excluded(self):
        self.process(uid=1001)
        self.assertEqual(list(module.discover_renderers(1000, self.proc)), [])

    def test_browser_ui_and_network_process_are_excluded(self):
        self.process(123, name=".nyxt-wrapped")
        self.process(124, name="WebKitNetworkProcess")
        self.assertEqual(list(module.discover_renderers(1000, self.proc)), [])

    def test_command_name_alone_does_not_match(self):
        proc = self.process()
        (proc / "exe").unlink()
        (proc / "exe").symlink_to("/usr/bin/WebKitWebProcess")
        self.assertEqual(list(module.discover_renderers(1000, self.proc)), [])

    def test_already_grouped_process_is_skipped(self):
        self.process(cgroup="/webkit.slice/webkit-renderer-123-456.scope")
        self.assertEqual(list(module.discover_renderers(1000, self.proc)), [])

    def test_disappearing_process_is_skipped(self):
        proc = self.process()
        (proc / "stat").unlink()
        self.assertEqual(list(module.discover_renderers(1000, self.proc)), [])

    def test_firefox_content_title_matches_but_main_and_extensions_do_not(self):
        exe = "/nix/store/hash-firefox-158/lib/firefox/firefox"
        self.assertEqual(module.process_kind(exe, [exe + " -contentproc -parentPid 42 3 tab"]), "firefox")
        self.assertIsNone(module.process_kind(exe, [exe]))
        self.assertIsNone(module.process_kind(exe, [exe + " -contentproc 3 utility"]))

    def test_search_worker_is_expendable_but_active_image_is_protected(self):
        exe = "/nix/store/hash-sbcl/bin/sbcl"
        self.assertEqual(module.process_kind(exe, ["--script", "/home/taylor/projects/autolith/bin/autolith-search-worker"]), "search")
        self.assertEqual(module.process_kind(exe, ["--core", "/state/autolith-active.core"]), "agent")
        self.assertIsNone(module.process_kind(exe, ["--script", "/repo/test.lisp"]))

    def test_agent_executables_and_subagents_are_protected(self):
        self.assertEqual(module.process_kind("/nix/store/hash-codex/bin/codex", ["codex"]), "agent")
        self.assertEqual(module.process_kind("/home/taylor/.local/share/claude/versions/2.1.316", []), "agent")


@unittest.skipUnless(os.environ.get("WEBKIT_OOM_INTEGRATION") == "1",
                     "set WEBKIT_OOM_INTEGRATION=1 to test the systemd user manager")
class SystemdIntegrationTests(unittest.TestCase):
    def test_pidfd_move_limits_and_oomd_registration(self):
        asyncio.run(self.run_scope_test())

    async def run_scope_test(self):
        bus = await MessageBus(bus_type=BusType.SESSION, negotiate_unix_fd=True).connect()
        slice_name = "webkit_oom_test.slice"
        sleeper = None
        try:
            reply = await bus.call(Message(
                destination="org.freedesktop.systemd1",
                path="/org/freedesktop/systemd1",
                interface="org.freedesktop.systemd1.Manager",
                member="StartTransientUnit",
                signature="ssa(sv)a(sa(sv))",
                body=[slice_name, "fail", [
                    ["MemoryAccounting", Variant("b", True)],
                    ["ManagedOOMSwap", Variant("s", "kill")],
                    ["ManagedOOMMemoryPressure", Variant("s", "kill")],
                    ["ManagedOOMMemoryPressureLimit", Variant("u", int(0.4 * (2**32 - 1)))],
                    ["ManagedOOMMemoryPressureDurationUSec", Variant("t", 10_000_000)],
                ], []]))
            self.assertNotEqual(reply.message_type, MessageType.ERROR, reply.body)
            # Only this harmless child is moved. No browser or desktop is touched.
            sleeper = subprocess.Popen(["sleep", "60"])
            proc = Path("/proc") / str(sleeper.pid)
            start_time = int((proc / "stat").read_text().rsplit(")", 1)[1].split()[19])
            renderer = module.Renderer(sleeper.pid, start_time, "")
            pidfd = os.pidfd_open(sleeper.pid)
            try:
                await module.start_scope(bus, renderer, pidfd, slice_name)
            finally:
                os.close(pidfd)
            for _ in range(40):
                group = (proc / "cgroup").read_text().strip()[3:]
                if group.endswith(f"/{slice_name}/{renderer.scope}"):
                    break
                await asyncio.sleep(0.05)
            self.assertTrue(group.endswith(f"/{slice_name}/{renderer.scope}"), group)
            cgroup = Path("/sys/fs/cgroup") / group.lstrip("/")
            for file, expected in [("memory.high", 4 * module.GIB),
                                   ("memory.max", 6 * module.GIB),
                                   ("memory.swap.max", module.GIB),
                                   ("memory.oom.group", 1)]:
                self.assertEqual((cgroup / file).read_text().strip(), str(expected))
            for _ in range(30):
                oomctl = subprocess.run(["oomctl", "dump", "--no-pager"],
                                        capture_output=True, text=True, check=True).stdout
                if f"/{slice_name}" in oomctl:
                    break
                await asyncio.sleep(0.1)
            self.assertIn(f"/{slice_name}", oomctl)
        finally:
            if sleeper is not None:
                if sleeper.poll() is None:
                    sleeper.terminate()
                sleeper.wait(timeout=5)
            await bus.call(Message(
                destination="org.freedesktop.systemd1",
                path="/org/freedesktop/systemd1",
                interface="org.freedesktop.systemd1.Manager",
                member="StopUnit", signature="ss", body=[slice_name, "replace"]))
            bus.disconnect()


if __name__ == "__main__":
    unittest.main()
