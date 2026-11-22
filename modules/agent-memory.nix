{ config, pkgs, ... }:
let
  job = pkgs.writeShellScript "agent-job" ''
    export AGENT_SYSTEMD_RUN=${pkgs.systemd}/bin/systemd-run
    exec ${pkgs.python3}/bin/python3 ${../scripts/agent-job.py} "$@"
  '';
  monitored = {
    MemoryAccounting = true;
    ManagedOOMSwap = "kill";
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "40%";
    ManagedOOMMemoryPressureDurationSec = "10s";
  };
in
{
  nix.settings = {
    max-jobs = 2;
    cores = 2;
    use-cgroups = true;
    experimental-features = [ "cgroups" ];
  };
  assertions = [
    {
      assertion = !config.nix.settings.use-cgroups
        || builtins.elem "cgroups" config.nix.settings.experimental-features;
      message = "Nix build cgroups require experimental-features to include cgroups; otherwise nix-daemon cannot start.";
    }
  ];
  # Builders live below the daemon, not below the agent running `nix build`.
  systemd.services.nix-daemon.serviceConfig = {
    MemoryAccounting = true;
    MemoryHigh = "8G";
    MemoryMax = "12G";
    MemorySwapMax = "2G";
    OOMPolicy = "continue";
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "40%";
    ManagedOOMMemoryPressureDurationSec = "10s";
  };
  systemd.services."user@".serviceConfig = {
    MemoryLow = "4G";
    ManagedOOMPreference = "omit";
  };
  systemd.slices.firefox = {
    description = "Firefox content processes";
    sliceConfig = monitored;
  };
  systemd.slices.agenthelpers = {
    description = "Restartable coding-agent search helpers";
    sliceConfig = monitored // {
      MemoryHigh = "4G";
      MemoryMax = "6G";
      MemorySwapMax = "2G";
      IOWeight = 25;
    };
  };
  # This hook asks the agent to retry through the launcher. It never returns
  # "allow", which could change the command's normal approval behavior.
  environment.etc."codex/hooks/agent-job.py".source = ../scripts/agent-job-hook.py;
  environment.etc."codex/requirements.toml".text = ''
    [hooks]
    managed_dir = "/etc/codex/hooks"

    [[hooks.PreToolUse]]
    matcher = "^(Bash|exec_command|shell_command)$"

    [[hooks.PreToolUse.hooks]]
    type = "command"
    command = "${pkgs.python3}/bin/python3 /etc/codex/hooks/agent-job.py --launcher ${job}"
    timeout = 5
  '';
}
