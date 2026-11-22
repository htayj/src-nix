{ config, lib, pkgs, nix-channel, ... }:
{
  home.packages = [
    nix-channel.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-desktop
  ];
  xdg.mimeApps.defaultApplications."x-scheme-handler/openclaw" = [ "OpenClaw.desktop" ];

  # Fixed personal Firefox source; the existing node publishes only this narrow
  # stdio MCP server. Its mutable node config retains credentials outside Nix.
  home.file.".local/share/openclaw-node/firefox-personal-export.py".source =
    pkgs.replaceVars ./firefox-personal-export.py {
      gitleaks = lib.getExe pkgs.gitleaks;
      gitleaksConfig = pkgs.writeText "firefox-export-gitleaks.toml" ''
        [extend]
        useDefault = true
      '';
    };

  programs.bash.shellAliases.claw = builtins.concatStringsSep " " [
    "${pkgs.tmux}/bin/tmux new-session -A -s openclaw"
    "${config.home.homeDirectory}/.local/bin/openclaw tui"
    "--session agent:ceo_chryso:main"
  ];

  # Use the existing cluster Gateway over SSH. Only loopback is exposed locally;
  # Gateway credentials and device pairing remain required by OpenClaw.
  systemd.user.services.openclaw-cluster-tunnel = {
    Unit = {
      Description = "OpenClaw cluster Gateway SSH tunnel";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      StartLimitIntervalSec = 0;
    };
    Service = {
      ExecStart = builtins.concatStringsSep " " [
        "${pkgs.openssh}/bin/ssh -N -T"
        "-L 127.0.0.1:18789:192.168.7.131:18789"
        "-o BatchMode=yes -o StrictHostKeyChecking=yes"
        "-o ExitOnForwardFailure=yes -o ConnectTimeout=10"
        "-o ServerAliveInterval=15 -o ServerAliveCountMax=3"
        "-o ControlMaster=no -o ControlPath=none -o ControlPersist=no"
        "tay@basedserv"
      ];
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
