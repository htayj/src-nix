{ config, lib, pkgs, ... }:
let
  source = "${config.home.homeDirectory}/projects/bridge";
  bridge = pkgs.writeShellApplication {
    name = "bridge";
    text = ''
      exec ${lib.getExe pkgs.nodejs_22} --experimental-strip-types ${source}/bin/bridge.ts "$@"
    '';
  };
  bridgeUsage = pkgs.writeShellApplication {
    name = "bridge-usage-mcp";
    text = ''
      export BRIDGE_LOGS_URL=http://127.0.0.1:8788
      exec ${lib.getExe pkgs.nodejs_22} --experimental-strip-types --no-warnings ${source}/src/mcp/main.ts "$@"
    '';
  };
in
{
  home.packages = [ bridge bridgeUsage ];
  # Share the imported skill without copying its source into the Nix store.
  home.file.".agents/skills/usage-review".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.claude/skills/usage-review";
  systemd.user.services.bridge = {
    Unit = {
      Description = "Bridge loopback model gateway";
      ConditionPathExists = "${source}/bin/bridge.ts";
      StartLimitIntervalSec = 0;
    };
    Service = {
      Type = "simple";
      ExecStart = lib.getExe bridge;
      WorkingDirectory = source;
      Environment = [ "BRIDGE_FALLBACK=0" ];
      Restart = "always";
      RestartSec = 5;
      TimeoutStopSec = 15;
      NoNewPrivileges = true;
      PrivateTmp = true;
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
