{ ... }:
let
  desktopShare = device: {
    inherit device;
    fsType = "nfs";
    options = [
      "nfsvers=4"
      "proto=tcp"
      "nosuid"
      "nodev"

      # Only connect when accessed; NAS availability must not gate boot.
      "_netdev"
      "nofail"
      "x-systemd.automount"
      "x-systemd.idle-timeout=1min"
      "x-systemd.mount-timeout=10s"

      # Return ETIMEDOUT during an outage instead of retrying forever.
      # Applications must handle failed/incomplete writes (see README).
      "softerr"
      "timeo=50"
      "retrans=2"
      "retry=0"
    ];
  };
in
{
  # These are the existing exports, rather than the TrueNAS pool roots.
  # QNAP's NFSv4 pseudo-root exposes /share/Public as /Public.
  fileSystems = {
    "/mnt/qnap" = desktopShare "192.168.7.69:/Public";
    "/mnt/sas-main" = desktopShare "192.168.1.242:/mnt/sas-main/main";
    "/mnt/ssd" = desktopShare "192.168.1.242:/mnt/ssd/main";
  };

  # systemd creates root-owned mountpoints with its default mode 0755.
  # Do not chmod them with tmpfiles: later runs could touch a mounted NAS.
}
