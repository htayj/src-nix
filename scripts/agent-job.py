#!/usr/bin/env python3
"""Run a disposable command in a bounded cgroup, separate from its agent."""

import argparse
import os
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--memory-high", default="3G")
    parser.add_argument("--memory-max", default="6G")
    parser.add_argument("--swap-max", default="1G")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("a command is required after --")
    if Path(command[0]).name in {"codex", "claude", "autolith", "autolith-dev", "agent-session"}:
        parser.error("launch coding agents with agent-session, outside disposable job limits")
    # Set this in the job process only; never change the parent agent's score.
    child = "from pathlib import Path; import os,sys; Path('/proc/self/oom_score_adj').write_text('200'); os.execvpe(sys.argv[1],sys.argv[1:],os.environ)"
    run = [os.environ.get("AGENT_SYSTEMD_RUN", "systemd-run"), "--user", "--scope",
           "--quiet", "--collect", "--slice=agentjobs.slice",
           "--description=Disposable coding-agent job",
           f"--working-directory={os.getcwd()}", "--property=OOMPolicy=kill",
           f"--property=MemoryHigh={args.memory_high}",
           f"--property=MemoryMax={args.memory_max}",
           f"--property=MemorySwapMax={args.swap_max}",
           "--", sys.executable, "-c", child, *command]
    os.execvpe(run[0], run, os.environ)


if __name__ == "__main__":
    main()
