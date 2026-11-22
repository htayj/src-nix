{ ... }:
let
  desktopAudio = {
    MemoryLow = "128M";
    IOWeight = 1000;
  };
in
{
  # Compressed RAM swap takes pages before the NVMe partition, which shares the
  # disk with agent builds and scans. Swapping to zram is cheap, so keep the
  # kernel's anon/file balance neutral instead of dropping file cache first.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };
  boot.kernel.sysctl."vm.swappiness" = 100;

  # IOWeight is only enforced by an IO scheduler with cgroup support.
  boot.kernelModules = [ "bfq" ];
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="nvme[0-9]*n[0-9]*", ENV{DEVTYPE}=="disk", ATTR{queue/scheduler}="bfq"
  '';

  # memory.low only takes effect when every ancestor also carries protection;
  # these parents make the desktop and the existing user@ / agent lows real.
  systemd.slices.user.sliceConfig.MemoryLow = "6G";
  systemd.units."user-.slice" = {
    overrideStrategy = "asDropin";
    text = ''
      [Slice]
      MemoryLow=6G
    '';
  };
  # The compositor runs in the logind session scope.
  systemd.units."session-.scope" = {
    overrideStrategy = "asDropin";
    text = ''
      [Scope]
      MemoryLow=1536M
      IOWeight=10000
    '';
  };

  systemd.user.slices.session.sliceConfig = {
    MemoryLow = "512M";
    IOWeight = 10000;
  };
  systemd.user.services = {
    pipewire.serviceConfig = desktopAudio;
    pipewire-pulse.serviceConfig = desktopAudio;
    wireplumber.serviceConfig = desktopAudio;
  };

  systemd.services.nix-daemon.serviceConfig.IOWeight = 25;

  # Agent scratch trees are created and deleted constantly; keep that churn
  # off the SSD. Large Nix builds stay on disk instead of competing for RAM.
  boot.tmp = {
    useTmpfs = true;
    tmpfsSize = "8G";
  };
  nix.settings.build-dir = "/var/tmp";

  # The drive stalls for seconds during garbage collection when deleted space
  # has not been trimmed; weekly is too slow for this much churn.
  services.fstrim.interval = "daily";
}
