{ config, pkgs, ... }:
let
  python = pkgs.python3.withPackages (ps: [ ps.dbus-next ]);
in
{
  systemd.oomd.enable = true;

  # Monitor only renderer scopes, never the graphical session containing Nyxt.
  systemd.slices.webkit = {
    description = "WebKitGTK browser renderers";
    sliceConfig = {
      MemoryAccounting = true;
      ManagedOOMSwap = "kill";
      ManagedOOMMemoryPressure = "kill";
      ManagedOOMMemoryPressureLimit = "40%";
      ManagedOOMMemoryPressureDurationSec = "10s";
    };
  };

  systemd.services.webkit-renderer-cgroups = {
    description = "Isolate browser content and search workers; protect coding agents";
    wantedBy = [ "multi-user.target" ];
    requires = [ "webkit.slice" "firefox.slice" "agenthelpers.slice" ];
    after = [ "dbus.service" "systemd-oomd.service" "webkit.slice" "firefox.slice" "agenthelpers.slice" ];
    serviceConfig = {
      ExecStart = "${python}/bin/python3 ${../scripts/webkit-renderer-cgroups.py} --uid ${toString config.users.users.tay.uid}";
      Restart = "on-failure";
      RestartSec = "5s";
      # The system manager performs the cgroup writes over D-Bus. This process
      # identifies processes, opens pidfds, and lowers agents' OOM scores.
      User = "root";
      CapabilityBoundingSet = [ "CAP_SYS_PTRACE" "CAP_SYS_RESOURCE" "CAP_DAC_OVERRIDE" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ProtectControlGroups = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      PrivateDevices = true;
      PrivateTmp = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
    };
  };
}
