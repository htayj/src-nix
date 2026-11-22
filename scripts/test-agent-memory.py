#!/usr/bin/env python3
"""Check job routing, instruction preservation, and isolated OOM failure."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


hook = load("agent_hook", "agent-job-hook.py")
installer = load("policy_installer", "install-agent-resource-policy.py")
LAUNCHER = [sys.executable, str(Path(__file__).with_name("agent-job.py"))]


class PolicyTests(unittest.TestCase):
    def test_known_heavy_commands_need_a_job_scope(self):
        for command in ["cargo test", "npm run test:unit", "pnpm build", "pytest tests",
                        "cmake --build build", "make -j2", "nix flake check path:.",
                        "python3 -m unittest", "agent-browser open https://example.org"]:
            with self.subTest(command=command):
                self.assertTrue(hook.is_job(command))

    def test_agents_servers_and_read_commands_are_untouched(self):
        for command in ["codex resume", "claude", "autolith-dev", "node mcp-server.js",
                        "rg needle src", "git status", "agent-job -- cargo test",
                        "npx codex", "python3 server.py"]:
            with self.subTest(command=command):
                self.assertFalse(hook.is_job(command))

    def test_complex_shell_needs_an_explicit_boundary(self):
        for command in ["make && codex", "cargo test | tee log", "make > log",
                        "make $(codex)", "cd repo; pytest", "npm test\nclaude"]:
            with self.subTest(command=command):
                self.assertFalse(hook.is_job(command))

    def test_guard_never_grants_approval_or_rewrites_input(self):
        event = {"tool_input": {"cmd": "cargo test", "workdir": "/repo"}}
        original = json.dumps(event)
        reply = hook.hook_response(event, "/bin/agent-job")["hookSpecificOutput"]
        self.assertEqual(reply["permissionDecision"], "deny")
        self.assertNotIn("updatedInput", reply)
        self.assertIn("agent-job", reply["permissionDecisionReason"])
        self.assertEqual(json.dumps(event), original)

    def test_claude_existing_guards_and_instructions_survive_repeated_install(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            guard = {"matcher": "Bash", "hooks": [{"type": "command", "command": "existing-guard"}]}
            (root / "settings.json").write_text(json.dumps({"permissions": {"deny": ["original"]},
                                                          "hooks": {"PreToolUse": [guard]}}))
            (root / "CLAUDE.md").write_text("Existing personal instructions.\n")
            installer.install(root, "First resource policy", "job-guard")
            # A user's hook added to our matcher group must also survive.
            settings = json.loads((root / "settings.json").read_text())
            extra = {"type": "command", "command": "user-added-guard"}
            settings["hooks"]["PreToolUse"][-1]["hooks"].append(extra)
            (root / "settings.json").write_text(json.dumps(settings))
            installer.install(root, "Updated resource policy", "job-guard-new")
            settings = json.loads((root / "settings.json").read_text())
            self.assertEqual(settings["permissions"], {"deny": ["original"]})
            self.assertEqual(settings["hooks"]["PreToolUse"][0], guard)
            self.assertEqual(len(settings["hooks"]["PreToolUse"]), 3)
            self.assertEqual(settings["hooks"]["PreToolUse"][1]["hooks"], [extra])
            text = (root / "CLAUDE.md").read_text()
            self.assertIn("Existing personal instructions.", text)
            self.assertIn("Updated resource policy", text)
            self.assertNotIn("First resource policy", text)
            self.assertEqual(text.count(installer.BEGIN), 1)

    def test_direct_agent_launch_is_rejected_before_systemd(self):
        result = subprocess.run([*LAUNCHER, "--", "codex"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("agent-session", result.stderr)


@unittest.skipUnless(os.environ.get("AGENT_MEMORY_INTEGRATION") == "1",
                     "requires installed agents.slice and agentjobs.slice")
class ScopeTests(unittest.TestCase):
    def test_job_has_separate_scope_limits_and_oom_priority(self):
        command = """import json,os
from pathlib import Path
group=Path('/proc/self/cgroup').read_text().strip()[3:]
p=Path('/sys/fs/cgroup')/group.lstrip('/')
print(json.dumps({'group':group,'high':(p/'memory.high').read_text().strip(),
'max':(p/'memory.max').read_text().strip(),'swap':(p/'memory.swap.max').read_text().strip(),
'oom_group':(p/'memory.oom.group').read_text().strip(),
'priority':Path('/proc/self/oom_score_adj').read_text().strip(),'cwd':os.getcwd()}))
"""
        result = subprocess.run([*LAUNCHER, "--", sys.executable, "-c", command],
                                capture_output=True, text=True, check=True, timeout=15)
        info = json.loads(result.stdout)
        self.assertIn("/agentjobs.slice/", info["group"])
        self.assertNotEqual(Path("/proc/self/cgroup").read_text().strip()[3:], info["group"])
        self.assertEqual(info["high"], str(3 * 1024**3))
        self.assertEqual(info["max"], str(6 * 1024**3))
        self.assertEqual(info["swap"], str(1024**3))
        self.assertEqual(info["oom_group"], "1")
        self.assertEqual(info["priority"], "200")
        self.assertEqual(info["cwd"], os.getcwd())

    def test_job_oom_does_not_kill_parent_agent_scope(self):
        group = Path("/proc/self/cgroup").read_text().strip()[3:]
        self.assertIn("/agents.slice/", group, "run this integration test through agent-session")
        events = Path("/sys/fs/cgroup") / group.lstrip("/") / "memory.events"
        before = events.read_text()
        result = subprocess.run([*LAUNCHER, "--memory-high=infinity", "--memory-max=64M", "--swap-max=0",
                                 "--", sys.executable, "-c", "buffer=bytearray(256*1024*1024)"],
                                capture_output=True, text=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(Path("/proc/self/cgroup").read_text().strip()[3:], group)
        self.assertEqual(events.read_text(), before)
        self.assertTrue(Path(f"/proc/{os.getpid()}").exists())


if __name__ == "__main__":
    unittest.main()
