#!/usr/bin/env python3
"""Reproduce Discord's persistent stream alongside a Firefox video."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "home/media-idle-inhibit.sh"


def stream(title, state="running", app="Firefox", role=None):
    return {
        "type": "PipeWire:Interface:Node",
        "info": {
            "state": state,
            "props": {
                "application.name": app,
                "media.name": title,
                "media.class": "Stream/Output/Audio",
                "media.role": role,
            },
        },
    }


class MediaIdleInhibitTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.events = self.directory / "events"
        self.events.touch()
        self.snapshot = self.directory / "snapshot"
        self.discord = stream("(82) Discord | #general | Server")
        self.publish(self.discord)
        helper = self.directory / "helper"
        helper.write_text(f"#!{sys.executable}\n" + '''
import json, os, pathlib, signal, sys, time
if pathlib.Path(sys.argv[0]).name == "pw-dump":
    snapshot = pathlib.Path(os.environ["TEST_SNAPSHOT"]).read_text()
    if snapshot == "failure":
        sys.exit(1)
    print(snapshot)
else:
    def event(value):
        with open(os.environ["TEST_EVENTS"], "a") as output:
            output.write(value + "\\n")
    def stop(*args):
        event("stopped")
        sys.exit(0)
    signal.signal(signal.SIGTERM, stop)
    event("started")
    while True:
        time.sleep(1)
''')
        helper.chmod(0o755)
        for name in ("pw-dump", "wayland-pipewire-idle-inhibit"):
            (self.directory / name).symlink_to(helper)
        self.log = (self.directory / "log").open("w+")
        self.addCleanup(self.log.close)
        self.process = subprocess.Popen(
            ["bash", "-euo", "pipefail", str(SCRIPT)],
            env=dict(os.environ, PATH=f"{self.directory}:{os.environ['PATH']}",
                     TEST_SNAPSHOT=str(self.snapshot), TEST_EVENTS=str(self.events)),
            stdout=self.log, stderr=subprocess.STDOUT, start_new_session=True,
        )
        self.addCleanup(self.stop)

    def stop(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait()

    def publish(self, *nodes):
        temporary = self.directory / "next"
        temporary.write_text(json.dumps(list(nodes)))
        temporary.replace(self.snapshot)

    def expect_events(self, expected):
        deadline = time.monotonic() + 5
        while self.events.read_text().splitlines() != expected:
            if time.monotonic() >= deadline:
                self.fail(f"Expected {expected}, saw {self.events.read_text()!r}")
            time.sleep(0.05)

    def test_chat_alone_does_not_inhibit_but_video_does(self):
        self.publish(self.discord, stream("Video", state="idle"),
                     stream("AudioStream", app="Discord"),
                     stream("Call", role="Communication"),
                     stream("Notification", role="Notification"))
        time.sleep(2.5)
        self.assertEqual(self.events.read_text(), "")
        self.assertIsNone(self.process.poll())

        self.publish(self.discord, stream("Video"))
        self.expect_events(["started"])
        self.publish(self.discord, stream("Video", state="idle"))
        self.expect_events(["started", "stopped"])
        time.sleep(2.5)
        self.assertEqual(self.events.read_text().splitlines(), ["started", "stopped"])

    def test_pipewire_failure_releases_inhibitor(self):
        self.publish(self.discord, stream("Video"))
        self.expect_events(["started"])
        self.snapshot.write_text("failure")
        self.assertNotEqual(self.process.wait(timeout=5), 0)
        self.expect_events(["started", "stopped"])

    def test_service_stop_releases_inhibitor(self):
        self.publish(stream("Video"))
        self.expect_events(["started"])
        self.stop()
        self.expect_events(["started", "stopped"])


if __name__ == "__main__":
    unittest.main()
