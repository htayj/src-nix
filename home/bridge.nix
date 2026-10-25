{ config, lib, pkgs, ... }:
let
  source = "${config.home.homeDirectory}/projects/bridge";
  bridge = pkgs.writeShellApplication {
    name = "bridge";
    text = ''
      exec ${lib.getExe pkgs.nodejs_22} --experimental-strip-types ${source}/bin/bridge.ts "$@"
    '';
  };
in
{
  home.packages = [ bridge ];
  systemd.user.services.bridge = {
    Unit = {
      Description = "Bridge loopback model gateway";
      ConditionPathExists = "${source}/bin/bridge.ts";
    };
    Service = {
      Type = "simple";
      ExecStart = lib.getExe bridge;
      WorkingDirectory = source;
      Environment = [ "BRIDGE_FALLBACK=0" ];
      Restart = "on-failure";
      RestartSec = 2;
      TimeoutStopSec = 15;
      NoNewPrivileges = true;
      PrivateTmp = true;
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
