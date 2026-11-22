#!/usr/bin/env python3
"""Require a job boundary for simple build/test commands without granting permissions."""

import argparse
import json
from pathlib import Path
import re
import shlex
import sys


def is_job(command):
    # Complex shell programs need an explicit boundary chosen by the agent.
    # Do not rewrite pipelines, redirections, substitutions or control flow.
    if any(char in command for char in "\n;|&<>()`$"):
        return False
    try:
        args = shlex.split(command)
    except ValueError:
        return False
    while args and re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*=.*", args[0]):
        args.pop(0)
    if not args:
        return False
    program = Path(args[0]).name
    if program in {"make", "gmake", "ninja", "ctest", "pytest", "pytest-3", "vitest", "jest",
                   "playwright", "agent-browser", "gradle", "mvn"}:
        return True
    if program in {"cargo", "go", "nix", "npm", "pnpm", "yarn", "bun", "cmake", "python", "python3"}:
        rest = args[1:]
        if program in {"python", "python3"}:
            return rest[:2] in [["-m", "pytest"], ["-m", "unittest"]]
        if program == "cmake":
            return rest[:1] == ["--build"]
        if not rest:
            return False
        subcommand = rest[0]
        if program == "nix":
            return subcommand in {"build", "develop"} or rest[:2] == ["flake", "check"]
        if program in {"npm", "pnpm", "yarn", "bun"}:
            if subcommand == "run":
                rest = rest[1:]
            return bool(rest) and rest[0].split(":", 1)[0] in {"build", "test", "check", "lint", "dev", "start"}
        return subcommand in {"build", "test", "check", "clippy", "bench"}
    return False


def hook_response(event, launcher):
    tool_input = event.get("tool_input")
    if not isinstance(tool_input, dict):
        return None
    field = "command" if "command" in tool_input else "cmd"
    command = tool_input.get(field)
    if not isinstance(command, str) or not is_job(command):
        return None
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                    "permissionDecision": "deny",
                                    "permissionDecisionReason":
                                    f"Run this disposable build/test through {launcher} -- COMMAND, "
                                    "then retry the tool call. Keep coding agents, subagents and "
                                    "essential tool servers outside the job scope. This requires no "
                                    "new user approval; normal command approval rules still apply."}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--launcher", required=True)
    args = parser.parse_args()
    result = hook_response(json.load(sys.stdin), args.launcher)
    if result:
        print(json.dumps(result))


if __name__ == "__main__":
    main()
