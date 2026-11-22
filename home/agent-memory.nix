{ config, lib, pkgs, ... }:
let
  job = pkgs.writeShellScriptBin "agent-job" ''
    export AGENT_SYSTEMD_RUN=${pkgs.systemd}/bin/systemd-run
    exec ${pkgs.python3}/bin/python3 ${../scripts/agent-job.py} "$@"
  '';
  session = pkgs.writeShellApplication {
    name = "agent-session";
    text = ''
      exec ${pkgs.systemd}/bin/systemd-run --user --scope --quiet --collect \
        --slice=agents.slice --property=OOMPolicy=continue \
        --property=ManagedOOMPreference=omit --working-directory="$PWD" -- "$@"
    '';
  };
  instructions = pkgs.writeText "agent-resource-policy.md" ''
    # Local resource policy

    Run builds, test suites, benchmarks, temporary dev servers, and disposable
    browser automation through `agent-job -- COMMAND ...`. For a compound shell
    job, use `agent-job -- bash -c '...'` around only the disposable work.
    Keep coding agents, subagents, and essential MCP/tool servers outside job
    limits; launch them with `agent-session COMMAND ...` when needed.
    If a job is killed for memory, report its failure and retry with less
    concurrency or an explicit larger per-job limit. Do not disable the shared
    jobs slice limits or put the parent agent under a memory ceiling.
    Nix builders have separate daemon-side limits; wrapping the client alone
    does not contain its builders.
  '';
  hookCommand = "${pkgs.python3}/bin/python3 ${../scripts/agent-job-hook.py} --launcher ${lib.getExe job}";
in
{
  home.packages = [ job session ];
  systemd.user.slices.agents = {
    Unit = {
      Description = "Protected coding agents and essential tool servers";
      X-RestartIfChanged = false;
      X-StopIfChanged = false;
      RefuseManualStop = true;
    };
    Slice = {
      MemoryAccounting = true;
      MemoryLow = "2G";
      IOWeight = 25;
      ManagedOOMPreference = "omit";
    };
  };
  systemd.user.slices.agentjobs = {
    Unit = {
      Description = "Disposable coding-agent builds and tests";
      X-RestartIfChanged = false;
      X-StopIfChanged = false;
    };
    Slice = {
      MemoryAccounting = true;
      MemoryHigh = "6G";
      MemoryMax = "10G";
      MemorySwapMax = "2G";
      IOWeight = 25;
      ManagedOOMSwap = "kill";
      ManagedOOMMemoryPressure = "kill";
      ManagedOOMMemoryPressureLimit = "40%";
      ManagedOOMMemoryPressureDurationSec = "10s";
    };
    Install.WantedBy = [ "default.target" ];
  };
  # Dash-prefix drop-ins cover current and future transient tmux pane scopes.
  xdg.configFile."systemd/user/tmux-spawn-.scope.d/50-memory-protection.conf".text = ''
    [Scope]
    OOMPolicy=continue
    ManagedOOMPreference=omit
    MemoryLow=256M
  '';
  home.file.".codex/AGENTS.md".source = instructions;
  programs.bash.shellAliases = {
    autolith = "agent-session autolith";
    autolith-dev = "agent-session autolith-dev";
  };
  home.activation.agentMemory = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    run ${pkgs.python3}/bin/python3 ${../scripts/install-agent-resource-policy.py} \
      ${lib.escapeShellArg "${config.home.homeDirectory}/.claude"} ${instructions} \
      ${lib.escapeShellArg hookCommand}
    if ${pkgs.systemd}/bin/systemctl --user is-system-running >/dev/null 2>&1 ||
       ${pkgs.systemd}/bin/systemctl --user is-active default.target >/dev/null 2>&1; then
      run ${pkgs.systemd}/bin/systemctl --user daemon-reload
      run ${pkgs.systemd}/bin/systemctl --user start agentjobs.slice agents.slice
    fi
  '';
}
