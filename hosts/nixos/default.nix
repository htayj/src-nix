{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core.nix
    ../../modules/desktop.nix
    ../../modules/manna-cadet.nix
  ];

  networking.hostName = "nixos";
  time.timeZone = "America/New_York";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Never change this just because nixpkgs is upgraded. It records the first
  # NixOS release installed on this machine.
  system.stateVersion = "26.05";
}
