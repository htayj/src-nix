#!/usr/bin/env python3
"""Isolate browser content/search workers and protect coding-agent processes."""

import argparse
import asyncio
from dataclasses import dataclass
import logging
import os
from pathlib import Path
import time

from dbus_next import BusType, Message, MessageType, Variant
from dbus_next.aio import MessageBus


LOG = logging.getLogger("webkit-renderer-cgroups")
SLICE = "webkit.slice"
GIB = 1024**3
PROFILES = {
    "webkit": ("webkit.slice", 4 * GIB, 6 * GIB, GIB),
    "firefox": ("firefox.slice", 4 * GIB, 6 * GIB, GIB),
    "search": ("agenthelpers.slice", 2 * GIB, 4 * GIB, GIB),
}


@dataclass(frozen=True)
class Renderer:
    pid: int
    start_time: int
    cgroup: str
    kind: str = "webkit"

    @property
    def slice_name(self):
        return PROFILES[self.kind][0]

    @property
    def scope(self):
        prefix = {"webkit": "webkit-renderer", "firefox": "firefox-content",
                  "search": "autolith-search"}[self.kind]
        return f"{prefix}-{self.pid}-{self.start_time}.scope"


def process_kind(exe, argv):
    name = Path(exe).name
    if exe.endswith("/WebKitWebProcess") and "/webkit2gtk-" in exe:
        return "webkit"
    # Firefox rewrites argv into a single space-delimited process title.
    if "/lib/firefox/" in exe and name == "firefox":
        title = " ".join(argv).split()
        if "-contentproc" in title and title[-1:] == ["tab"]:
            return "firefox"
    if name == "sbcl":
        if any(arg.endswith("/bin/autolith-search-worker") for arg in argv):
            return "search"
        if any(arg.endswith(("/bin/autolith-active", "/autolith-active.core")) for arg in argv):
            return "agent"
    if name == "codex" and exe.startswith("/nix/store/"):
        return "agent"
    if "/.local/share/claude/versions/" in exe or any(
            "/@anthropic-ai/claude-code/" in arg and arg.endswith("/claude.exe") for arg in argv):
        return "agent"
    return None


def identify_renderer(pid, uid, proc_root=Path("/proc")):
    """Match the executable and owner, not a forgeable command line or comm."""
    proc = proc_root / str(pid)
    try:
        exe = str((proc / "exe").readlink())
        name = Path(exe).name
        if name not in {"WebKitWebProcess", "firefox", "sbcl", "codex", "ld-linux-x86-64.so.2"} and "/.local/share/claude/versions/" not in exe:
            return None
        status = dict(line.split(":", 1) for line in (proc / "status").read_text().splitlines())
        if any(int(owner) != uid for owner in status["Uid"].split()):
            return None
        argv = [arg.decode(errors="replace") for arg in (proc / "cmdline").read_bytes().split(b"\0") if arg]
        kind = process_kind(exe, argv)
        if kind is None:
            return None
        if kind == "firefox" and status.get("Name") == "WebExtensions":
            return None
        # The comm field in stat may contain spaces and parentheses.
        start_time = int((proc / "stat").read_text().rsplit(")", 1)[1].split()[19])
        cgroup = next(line[3:] for line in (proc / "cgroup").read_text().splitlines()
                      if line.startswith("0::"))
        return Renderer(pid, start_time, cgroup, kind)
    except (OSError, ValueError, KeyError, IndexError, StopIteration):
        # Processes can disappear or exec while /proc is being scanned.
        return None


def discover_renderers(uid, proc_root=Path("/proc"), slice_name=SLICE):
    for proc in proc_root.iterdir():
        if not proc.name.isdigit():
            continue
        renderer = identify_renderer(int(proc.name), uid, proc_root)
        if renderer is not None and (renderer.kind == "agent" or
                                     not renderer.cgroup.startswith(f"/{renderer.slice_name}/")):
            yield renderer


def scope_message(renderer, pidfd, slice_name=None):
    target, high, maximum, swap = PROFILES[renderer.kind]
    return Message(
        destination="org.freedesktop.systemd1",
        path="/org/freedesktop/systemd1",
        interface="org.freedesktop.systemd1.Manager",
        member="StartTransientUnit",
        signature="ssa(sv)a(sa(sv))",
        unix_fds=[pidfd],
        body=[renderer.scope, "fail", [
            ["Description", Variant("s", f"{renderer.kind} workload {renderer.pid}")],
            ["Slice", Variant("s", slice_name or target)],
            # Pass a pidfd rather than a recyclable numeric process ID.
            ["PIDFDs", Variant("ah", [0])],
            ["MemoryAccounting", Variant("b", True)],
            ["MemoryHigh", Variant("t", high)],
            ["MemoryMax", Variant("t", maximum)],
            ["MemorySwapMax", Variant("t", swap)],
            ["OOMPolicy", Variant("s", "kill")],
            ["CollectMode", Variant("s", "inactive-or-failed")],
        ], []],
    )


async def start_scope(bus, renderer, pidfd, slice_name=None):
    reply = await bus.call(scope_message(renderer, pidfd, slice_name))
    if reply.message_type == MessageType.ERROR:
        raise RuntimeError(f"{reply.error_name}: {reply.body}")


async def protect_renderer(bus, renderer, uid):
    with os.fdopen(os.pidfd_open(renderer.pid), "rb", closefd=True) as pidfd:
        # Recheck identity after opening the pidfd. Never move a reused PID.
        current = identify_renderer(renderer.pid, uid)
        if current is None or current.start_time != renderer.start_time:
            return
        if renderer.kind == "agent":
            # The open proc directory pins this task's procfs identity, so a
            # recycled numeric PID cannot receive the priority adjustment.
            procfd = os.open(f"/proc/{renderer.pid}", os.O_RDONLY | os.O_DIRECTORY)
            try:
                stat = os.open("stat", os.O_RDONLY, dir_fd=procfd)
                with os.fdopen(stat) as stream:
                    start = int(stream.read().rsplit(")", 1)[1].split()[19])
                if start != renderer.start_time:
                    return
                fd = os.open("oom_score_adj", os.O_RDWR, dir_fd=procfd)
                with os.fdopen(fd, "r+") as stream:
                    if int(stream.read()) > -500:
                        stream.seek(0)
                        stream.write("-500")
                        LOG.info("Protected coding-agent process %s", renderer.pid)
            finally:
                os.close(procfd)
            return
        if current.cgroup.startswith(f"/{renderer.slice_name}/"):
            return
        await start_scope(bus, renderer, pidfd.fileno())
        # StartTransientUnit queues a job; verify that the move actually ran.
        for _ in range(20):
            current = identify_renderer(renderer.pid, uid)
            if current is None or current.start_time != renderer.start_time:
                return
            if current.cgroup == f"/{renderer.slice_name}/{renderer.scope}":
                LOG.info("Grouped %s process %s in %s", renderer.kind, renderer.pid, renderer.scope)
                return
            await asyncio.sleep(0.05)
        raise RuntimeError("systemd did not move the renderer into its scope")


async def monitor(uid, once=False):
    bus = await MessageBus(bus_type=BusType.SYSTEM, negotiate_unix_fd=True).connect()
    retry_after = {}
    try:
        while True:
            if not bus.connected:
                raise ConnectionError("Disconnected from the system bus")
            pending = list(discover_renderers(uid))
            live_keys = {(r.pid, r.start_time) for r in pending}
            retry_after = {k: v for k, v in retry_after.items() if k in live_keys}
            failures = 0
            for renderer in pending:
                key = (renderer.pid, renderer.start_time)
                if time.monotonic() < retry_after.get(key, 0):
                    continue
                try:
                    await protect_renderer(bus, renderer, uid)
                except ProcessLookupError:
                    pass
                except (OSError, RuntimeError) as error:
                    failures += 1
                    LOG.warning("Could not group renderer %s: %s", renderer.pid, error)
                    retry_after[key] = time.monotonic() + 30
            if once:
                return int(failures > 0)
            await asyncio.sleep(2)
    finally:
        bus.disconnect()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uid", type=int, required=True, help="browser owner's host UID")
    parser.add_argument("--once", action="store_true", help="group current renderers and exit")
    parser.add_argument("--dry-run", action="store_true", help="list matching renderers without changes")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    if args.dry_run:
        for renderer in discover_renderers(args.uid):
            if renderer.kind == "agent":
                print(f"{renderer.pid}: protected coding agent (OOM score adjustment -500)")
            else:
                print(f"{renderer.pid}: {renderer.cgroup} -> /{renderer.slice_name}/{renderer.scope}")
        return 0
    if os.geteuid() != 0:
        parser.error("grouping session processes requires root; use --dry-run to inspect")
    return asyncio.run(monitor(args.uid, args.once))


if __name__ == "__main__":
    raise SystemExit(main())
