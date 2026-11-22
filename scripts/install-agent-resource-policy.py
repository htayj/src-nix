#!/usr/bin/env python3
"""Maintain only this policy's section/hook in otherwise user-owned Claude files."""

import argparse
import json
from pathlib import Path


BEGIN = "<!-- BEGIN agent resource policy -->"
END = "<!-- END agent resource policy -->"


def install(root, instructions, command):
    root.mkdir(parents=True, exist_ok=True)
    path = root / "CLAUDE.md"
    text = path.read_text() if path.exists() else ""
    if BEGIN in text and END in text:
        start = text.index(BEGIN)
        finish = text.index(END, start) + len(END)
        text = text[:start] + text[finish:]
    text = text.rstrip() + "\n\n" + BEGIN + "\n" + instructions.strip() + "\n" + END + "\n"
    path.write_text(text)
    path = root / "settings.json"
    settings = json.loads(path.read_text()) if path.exists() else {}
    groups = settings.setdefault("hooks", {}).setdefault("PreToolUse", [])
    # Only replace this exact managed entry; preserve all existing guards.
    preserved = []
    for group in groups:
        remaining = [hook for hook in group.get("hooks", [])
                     if hook.get("statusMessage") != "Coding-agent job memory policy"]
        if remaining:
            preserved.append({**group, "hooks": remaining})
    groups[:] = preserved
    groups.append({"matcher": "Bash", "hooks": [{"type": "command", "command": command,
                   "timeout": 5, "statusMessage": "Coding-agent job memory policy"}]})
    path.write_text(json.dumps(settings, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("instructions", type=Path)
    parser.add_argument("command")
    args = parser.parse_args()
    install(args.directory, args.instructions.read_text(), args.command)
